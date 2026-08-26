import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/features/file_manager/file_upload_service.dart';

import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/models/storage_contract.dart';
import 'package:deltanium_app/services/request_signer.dart';

/// Chat service – handles offline (file-based) messaging
/// Reuses existing Store infrastructure for message storage
class ChatService {
  static final String _apiBase = AppConstants.apiBaseUrl;

  // Cache of active contractId per conversation to avoid frequent popups
  // Key: conversationId, Value: last used contractId
  static final Map<String, String> _conversationContracts = {};
  
  // Default bundle size (5MB) for chat messages
  static const int _chatBundleSize = 5 * 1024 * 1024;
  // Threshold for auto-approval (0.1 DLT)
  static const double _autoApprovalThreshold = 0.1;

  // ========== AUTH HELPERS ==========

  static Future<Map<String, String>?> _getAuth() async {
    return await AuthService().getCurrentAuthInfo();
  }

  static Future<Map<String, String>> _signedHeaders({
    required String method,
    required String path,
    required String pubKey,
    required String mnemonic,
    String? body,
  }) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    var bodyHash = '';
    if (method == 'POST' && body != null) {
      final bytes = utf8.encode(body);
      bodyHash = sha256.convert(bytes).toString();
    }
    final dataToSign = '$method$path$timestamp$bodyHash';
    final signature = await CryptoService.sign(dataToSign, mnemonic);
    return {
      'Content-Type': 'application/json',
      'X-User-PubKey': CryptoService.normalizePublicKey(pubKey),
      'X-Timestamp': timestamp,
      'X-Signature': signature,
    };
  }

  // ========== CONVERSATION ==========

  /// Create or get conversation with another user
  static Future<Map<String, dynamic>?> createOrGetConversation({
    required String recipientPubKey,
  }) async {
    try {
      final auth = await _getAuth();
      if (auth == null) return null;

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;
      final bodyJson = jsonEncode({'recipientPubKey': recipientPubKey});
      const path = '/chat/conversation';
      final headers = await _signedHeaders(
        method: 'POST',
        path: '/api$path',
        pubKey: pubKey,
        mnemonic: mnemonic,
        body: bodyJson,
      );

      final resp = await http.post(
        Uri.parse('$_apiBase$path'),
        headers: headers,
        body: bodyJson,
      );

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      AppLogger.log('ChatService: createOrGetConversation failed: ${resp.statusCode} ${resp.body}');
      return null;
    } catch (e) {
      AppLogger.log('ChatService: createOrGetConversation error: $e');
      return null;
    }
  }

  /// Get all conversations for current user
  static Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final auth = await _getAuth();
      if (auth == null) return [];

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;
      const path = '/chat/conversations';
      final headers = await _signedHeaders(
        method: 'GET',
        path: '/api$path',
        pubKey: pubKey,
        mnemonic: mnemonic,
      );

      final resp = await http.get(
        Uri.parse('$_apiBase$path'),
        headers: headers,
      );

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      }
      AppLogger.log('ChatService: getConversations failed: ${resp.statusCode}');
      return [];
    } catch (e) {
      AppLogger.log('ChatService: getConversations error: $e');
      return [];
    }
  }

  // ========== SEND MESSAGE (File-based) ==========

  /// Send a chat message using file-based approach
  /// Each message = 1 file (metadata + block) on Store
  static Future<bool> sendMessage({
    required String conversationId,
    required String recipientPubKey,
    required String text,
    String? clientMessageId,
    Future<bool> Function(Map<String, dynamic> storageInfo)? onConfirmFee,
  }) async {
    try {
      final auth = await _getAuth();
      if (auth == null) return false;

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;

      AppLogger.log('ChatService: Sending message to $recipientPubKey');

      // 1. Create message payload
      final payload = jsonEncode({
        'text': text,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'senderPubKey': pubKey,
        'conversationId': conversationId,
      });
      final fileData = Uint8List.fromList(utf8.encode(payload));

      // 2. Get a store node
      final nodeResp = await http.get(Uri.parse('$_apiBase/storenode/list'));
      if (nodeResp.statusCode != 200) {
        AppLogger.log('ChatService: Failed to get store nodes');
        return false;
      }
      final nodes = jsonDecode(nodeResp.body) as List<dynamic>;
      if (nodes.isEmpty) {
        AppLogger.log('ChatService: No store nodes available');
        return false;
      }
      final selectedNode = nodes.first as Map<String, dynamic>;
      final nodeEndpoint = (selectedNode['endpoint'] ?? selectedNode['Endpoint'] ?? '').toString();

      // 3. Negotiate/Reuse Storage Contract (Chat Bundle)
      String? contractId = _conversationContracts[conversationId];
      
      // If we don't have a cached contract, try to find an active one on the store
      final signer = RequestSigner(
        publicKey: pubKey,
        mnemonic: mnemonic,
      );
      final contractService = StorageContractService(
        storeBaseUrl: nodeEndpoint,
        signer: signer,
      );

      if (contractId == null) {
        AppLogger.log('ChatService: No cached contract for $conversationId, checking store...');
        final activeContracts = await contractService.listActiveContracts(userPublicKey: pubKey);
        
        // Find a valid contract with enough space (simplified)
        final validContract = activeContracts.where((c) => 
          c.isValidNow() && 
          (c.fileIds.isEmpty || c.fileIds.contains('any')) && // Store supports empty fileIds for bundles
          c.totalFileSize >= _chatBundleSize // Just a heuristic
        ).firstOrNull;

        if (validContract != null) {
          contractId = validContract.contractId;
          _conversationContracts[conversationId] = contractId;
          AppLogger.log('ChatService: Reusing existing contract $contractId');
        }
      }

      // If still no contract, create a new "Chat Bundle"
      if (contractId == null) {
        AppLogger.log('ChatService: Negotiating new Chat Bundle contract');
        final proposal = await contractService.createContract(
          contractType: 'OpenEnded',
          startDate: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          totalFileSize: _chatBundleSize,
          fileIds: [], // Empty means covers any file
          appPublicKey: pubKey,
          storageNodePublicKey: selectedNode['publicKey']?.toString() ?? selectedNode['PublicKey']?.toString() ?? '',
        );

        if (proposal == null) {
          AppLogger.log('ChatService: Failed to create contract proposal');
          return false;
        }

        // Auto-approve if fee is low, else trigger confirmation popup
        if (proposal.totalFee <= _autoApprovalThreshold) {
          AppLogger.log('ChatService: Auto-approving low fee: ${proposal.totalFee}');
          final signed = await contractService.approveAndSignContract(
            contract: proposal,
            appPrivateKey: mnemonic,
          );
          if (signed != null) {
            contractId = signed.contractId;
            _conversationContracts[conversationId] = contractId;
          }
        } else {
          // Trigger user confirmation popup
          AppLogger.log('ChatService: Fee requires manual approval: ${proposal.totalFee}');
          
          bool confirmed = false;
          if (onConfirmFee != null) {
            final storageInfo = {
              'totalFee': proposal.totalFee,
              'durationDays': 365, // ChatBundle is OpenEnded but we show 1 year cost
              'estimatedCostPerDay': proposal.totalFee / 365,
              'estimatedSize': _chatBundleSize,
              'feeBasis': 'Estimated 1 year storage for Chat Bundle (5MB)',
            };
            confirmed = await onConfirmFee(storageInfo);
          } else {
            AppLogger.log('ChatService: No onConfirmFee callback provided.');
            confirmed = false;
          }

          if (confirmed) {
            AppLogger.log('ChatService: User confirmed storage cost. Signing contract...');
            final signed = await contractService.approveAndSignContract(
              contract: proposal,
              appPrivateKey: mnemonic,
            );
            if (signed != null) {
              contractId = signed.contractId;
              _conversationContracts[conversationId] = contractId;
            }
          } else {
            AppLogger.log('ChatService: Storage cost not confirmed by user.');
            return false;
          }
        }
      }

      if (contractId == null) {
        AppLogger.log('ChatService: Could not obtain a valid contractId');
        return false;
      }

      // 4. Encrypt and upload using FileUploadService
      final uploader = FileUploadService();
      final result = await uploader.uploadEncryptedFile(
        fileData: fileData,
        fileName: 'chat_msg_${DateTime.now().millisecondsSinceEpoch}',
        publicKey: pubKey,
        mnemonic: mnemonic,
        sharedWithUsers: [recipientPubKey],
        selectedNode: selectedNode,
        fileType: 'chat_message',
        shareType: 'me',
        contractId: contractId, // Pass the Bundle ID
        onProgress: (msg) => AppLogger.log('ChatService upload: $msg'),
      );

      final fileId = result['fileId'] as String? ?? '';
      final firstBlockId = result['firstBlockId'] as String? ?? '';
      final recipientFileIds = result['recipientFileIds'] as Map<String, String>? ?? {};

      // Find recipient's fileId from the map
      final normalizedRecipient = CryptoService.normalizePublicKey(recipientPubKey);
      final recipientFileId = recipientFileIds[normalizedRecipient] ?? '';

      AppLogger.log('ChatService: Message uploaded, fileId=$fileId firstBlockId=$firstBlockId recipientFileId=$recipientFileId');

      if (fileId.isEmpty) {
        AppLogger.log('ChatService: Upload returned empty fileId');
        return false;
      }

      // 5. Register message metadata with Central API
      final storeNodeId = selectedNode['id']?.toString() ?? selectedNode['Id']?.toString() ?? '';
      final msgBody = jsonEncode({
        'conversationId': conversationId,
        'recipientPubKey': recipientPubKey,
        'storeNodeId': storeNodeId,
        'blockId': firstBlockId,
        'fileId': fileId,
        'recipientFileId': recipientFileId,
        if (clientMessageId != null && clientMessageId.isNotEmpty)
          'clientMessageId': clientMessageId,
      });

      const msgPath = '/chat/message';
      final msgHeaders = await _signedHeaders(
        method: 'POST',
        path: '/api$msgPath',
        pubKey: pubKey,
        mnemonic: mnemonic,
        body: msgBody,
      );

      final msgResp = await http.post(
        Uri.parse('$_apiBase$msgPath'),
        headers: msgHeaders,
        body: msgBody,
      );

      if (msgResp.statusCode == 200) {
        AppLogger.log('ChatService: Message registered successfully');
        return true;
      }

      AppLogger.log('ChatService: Failed to register message: ${msgResp.statusCode} ${msgResp.body}');
      return false;
    } catch (e) {
      AppLogger.log('ChatService: sendMessage error: $e');
      return false;
    }
  }

  // ========== RECEIVE MESSAGES ==========

  /// Get message metadata for a conversation
  static Future<List<Map<String, dynamic>>> getMessages({
    required String conversationId,
    int page = 0,
    int pageSize = 50,
  }) async {
    try {
      final auth = await _getAuth();
      if (auth == null) return [];

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;
      final path = '/chat/messages/$conversationId?page=$page&pageSize=$pageSize';
      final headers = await _signedHeaders(
        method: 'GET',
        path: '/api$path',
        pubKey: pubKey,
        mnemonic: mnemonic,
      );

      final resp = await http.get(
        Uri.parse('$_apiBase$path'),
        headers: headers,
      );

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      AppLogger.log('ChatService: getMessages error: $e');
      return [];
    }
  }

  /// Decrypt a chat message content from Store
  /// Uses the same flow as post decryption:
  /// 1. GET /api/file/download/{fileId} to get file metadata
  /// 2. GET /api/file/block/{firstBlockId} to get encrypted metadata block
  /// 3. decryptMetadataBlock to get symmetric key + content block IDs
  /// 4. GET /api/file/block/{contentBlockId} to get encrypted content
  /// 5. decryptRawBlockWithKey to get plaintext
  static Future<Map<String, dynamic>?> decryptMessageFromStore({
    required String blockId,
    required String fileId,
    required String storeNodeId,
  }) async {
    try {
      final auth = await _getAuth();
      if (auth == null) return null;

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;

      AppLogger.log('ChatService.decrypt: fileId=$fileId, blockId=$blockId, storeNodeId=$storeNodeId');

      // 1. Get store node endpoint
      final nodeResp = await http.get(Uri.parse('$_apiBase/storenode/list'));
      if (nodeResp.statusCode != 200) return null;

      final nodes = jsonDecode(nodeResp.body) as List<dynamic>;
      final node = nodes.firstWhere(
        (n) => (n['id']?.toString() ?? n['Id']?.toString() ?? '') == storeNodeId,
        orElse: () => nodes.isNotEmpty ? nodes.first : null,
      );
      if (node == null) return null;

      final endpoint = (node['endpoint'] ?? node['Endpoint'] ?? '').toString().replaceAll(RegExp(r'/\$'), '');

      // 2. Get file metadata from Store using /api/file/download/{fileId}
      //    (Same endpoint as existing post download flow)
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final metaPath = '/api/file/download/$fileId';
      final metaDataToSign = 'GET$metaPath$timestamp';
      final metaSig = await CryptoService.sign(metaDataToSign, mnemonic);

      final metaResp = await http.get(
        Uri.parse('$endpoint$metaPath'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': CryptoService.normalizePublicKey(pubKey),
          'X-Timestamp': timestamp,
          'X-Signature': metaSig,
        },
      );

      if (metaResp.statusCode != 200) {
        AppLogger.log('ChatService: Failed to get file metadata (download/$fileId): ${metaResp.statusCode} ${metaResp.body}');
        return null;
      }

      final metadata = jsonDecode(metaResp.body) as Map<String, dynamic>;
      AppLogger.log('ChatService.decrypt: Got metadata, keys: ${metadata.keys.toList()}');

      // 3. Get the first block (metadata block)
      final firstBlockId = metadata['firstBlockId'] ?? metadata['FirstBlockId'] ?? blockId;
      if (firstBlockId == null || firstBlockId.toString().isEmpty) {
        AppLogger.log('ChatService: No firstBlockId in metadata');
        return null;
      }

      final blockPath = '/api/file/block/$firstBlockId';
      final ts2 = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final blockDataToSign = 'GET$blockPath$ts2';
      final blockSig = await CryptoService.sign(blockDataToSign, mnemonic);

      final blockResp = await http.get(
        Uri.parse('$endpoint$blockPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(pubKey),
          'X-Timestamp': ts2,
          'X-Signature': blockSig,
        },
      );

      if (blockResp.statusCode != 200) {
        AppLogger.log('ChatService: Failed to get metadata block: ${blockResp.statusCode}');
        return null;
      }

      // 4. Build storeMetadata in the same format as posts use
      final storeMetadata = {
        'fileId': metadata['fileId'] ?? metadata['FileId'] ?? fileId,
        'ownerPubKey': metadata['ownerPubKey'] ?? metadata['OwnerPubKey'] ?? '',
        'encryptedKey': metadata['encryptedKey'] ?? metadata['EncryptedKey'] ?? '',
        'recipientPubKey': metadata['recipientPubKey'] ?? metadata['RecipientPubKey'] ?? '',
      };
      AppLogger.log('ChatService.decrypt: storeMetadata=$storeMetadata');

      // 5. Decrypt metadata block to get symmetric key
      final encryptedMetadataBlock = Uint8List.fromList(blockResp.bodyBytes);
      final decryptedMetadata = await FileCryptoService.decryptMetadataBlock(
        storeMetadata: storeMetadata,
        encryptedMetadataBlock: encryptedMetadataBlock,
        userPublicKey: pubKey,
        mnemonic: mnemonic,
      );

      final symmetricKey = decryptedMetadata['_symmetricKey'] as Uint8List?;
      if (symmetricKey == null) {
        AppLogger.log('ChatService: No symmetric key from metadata decryption');
        return null;
      }

      // 6. Get content block IDs from decrypted metadata
      final contentBlockIds = decryptedMetadata['contentBlockIds'] as List<dynamic>?;
      if (contentBlockIds == null || contentBlockIds.isEmpty) {
        AppLogger.log('ChatService: No content block IDs in decrypted metadata');
        return null;
      }

      // 7. Download and decrypt content block (chat message = 1 content block)
      final contentBlockId = contentBlockIds.first.toString();
      final contentBlockPath = '/api/file/block/$contentBlockId';
      final ts3 = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final contentSig = await CryptoService.sign('GET$contentBlockPath$ts3', mnemonic);

      final contentResp = await http.get(
        Uri.parse('$endpoint$contentBlockPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(pubKey),
          'X-Timestamp': ts3,
          'X-Signature': contentSig,
        },
      );

      if (contentResp.statusCode != 200) {
        AppLogger.log('ChatService: Failed to get content block: ${contentResp.statusCode}');
        return null;
      }

      final decryptedContent = await FileCryptoService.decryptRawBlockWithKey(
        Uint8List.fromList(contentResp.bodyBytes),
        symmetricKey,
      );

      if (decryptedContent == null) {
        AppLogger.log('ChatService: Failed to decrypt content block');
        return null;
      }

      // 8. Parse JSON
      final jsonStr = utf8.decode(decryptedContent);
      AppLogger.log('ChatService.decrypt: Success! Decrypted ${jsonStr.length} chars');
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.log('ChatService: decryptMessageFromStore error: $e');
      return null;
    }
  }

  // ========== UNREAD COUNT ==========

  static Future<int> getUnreadCount() async {
    try {
      final auth = await _getAuth();
      if (auth == null) return 0;

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;
      const path = '/chat/unread-count';
      final headers = await _signedHeaders(
        method: 'GET',
        path: '/api$path',
        pubKey: pubKey,
        mnemonic: mnemonic,
      );

      final resp = await http.get(
        Uri.parse('$_apiBase$path'),
        headers: headers,
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['unreadCount'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      AppLogger.log('ChatService: getUnreadCount error: $e');
      return 0;
    }
  }

  // ========== PRESENCE ==========

  /// Set current user online (heartbeat)
  static Future<Map<String, dynamic>?> setOnline() async {
    try {
      final auth = await _getAuth();
      if (auth == null) return null;

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;
      const path = '/chat/online';
      final bodyJson = '{}';
      final headers = await _signedHeaders(
        method: 'POST',
        path: '/api$path',
        pubKey: pubKey,
        mnemonic: mnemonic,
        body: bodyJson,
      );

      final resp = await http.post(
        Uri.parse('$_apiBase$path'),
        headers: headers,
        body: bodyJson,
      );

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      AppLogger.log('ChatService: setOnline error: $e');
      return null;
    }
  }

  /// Set current user offline
  static Future<void> setOffline() async {
    try {
      final auth = await _getAuth();
      if (auth == null) return;

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;
      const path = '/chat/online';
      final headers = await _signedHeaders(
        method: 'DELETE',
        path: '/api$path',
        pubKey: pubKey,
        mnemonic: mnemonic,
      );

      await http.delete(
        Uri.parse('$_apiBase$path'),
        headers: headers,
      );
    } catch (e) {
      AppLogger.log('ChatService: setOffline error: $e');
    }
  }

  /// Check if a user is online
  static Future<bool> isUserOnline(String userPubKey) async {
    try {
      final auth = await _getAuth();
      if (auth == null) return false;

      final pubKey = auth['publicKey']!;
      final mnemonic = auth['mnemonic']!;
      final path = '/chat/online-status?user=$userPubKey';
      final headers = await _signedHeaders(
        method: 'GET',
        path: '/api$path',
        pubKey: pubKey,
        mnemonic: mnemonic,
      );

      final resp = await http.get(
        Uri.parse('$_apiBase$path'),
        headers: headers,
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['online'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      AppLogger.log('ChatService: isUserOnline error: $e');
      return false;
    }
  }
}
