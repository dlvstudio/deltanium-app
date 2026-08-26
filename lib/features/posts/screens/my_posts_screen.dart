import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:deltanium_app/features/feed/widgets/related_files_widget.dart';
import 'package:deltanium_app/features/posts/widgets/optimized_post_list.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/pre_ffi.dart';


class PostMetadata {
  final String fileId;
  final String? fileName;
  final String fileSize;
  final DateTime creationTime;
  final String? fileExtension;
  final bool isDecrypted;
  final String? textContent;
  final List<dynamic>? attachedMedia;
  final String? visibility;
  final List<String>? tags;
  final String? firstBlockId; // 🔧 FIX: Use firstBlockId instead of blockIds
  final String? encryptedKey; // 🆕 Single encrypted key instead of dictionary
  final String? recipientPubKey; // 🆕 Recipient public key from new API
  final String? ownerPubKey; // 🔧 FIX: Owner public key from decrypted metadata
  final String encryptedType; // 🆕 Type of encryption: 'public' or 'encrypted'
  final List<Map<String, dynamic>>? relatedFiles;
  final String? authorName;
  final String? capsuleFor; // PRE: 'tag' for PRE posts
  final String? policyTag; // PRE: policy tag like 'followers:2025'
  final String? policyScheme; // PRE: 'CPRE' for PRE posts
  final String? encapsulatedForRecipient; // 🆕 PRE capsule for followers

  PostMetadata({
    required this.fileId,
    this.fileName,
    required this.fileSize,
    required this.creationTime,
    this.fileExtension,
    this.isDecrypted = false,
    this.textContent,
    this.attachedMedia,
    this.visibility,
    this.tags,
    this.firstBlockId,
    this.encryptedKey,
    this.recipientPubKey,
    this.ownerPubKey,
    this.encryptedType = 'encrypted', // Default to encrypted for safety
    this.relatedFiles,
    this.authorName,
    this.capsuleFor,
    this.policyTag,
    this.policyScheme,
    this.encapsulatedForRecipient,
  });

  factory PostMetadata.fromJson(Map<String, dynamic> json) {
    // Accept both camelCase (app) and PascalCase (store) keys
    String? _str(dynamic v) => v?.toString();
    dynamic _pick(List<String> keys) {
      for (final k in keys) {
        if (json.containsKey(k)) return json[k];
      }
      return null;
    }

    final fileSizeVal = _pick(['fileSize', 'FileSize']);
    final fileSizeStr = (fileSizeVal is num) ? fileSizeVal.toString() : _str(fileSizeVal) ?? '0';

    final creationStr = _str(_pick(['creationTime', 'CreationTime'])) ?? '';

    final related = _pick(['relatedFiles', 'RelatedFiles']);

    return PostMetadata(
      fileId: _str(_pick(['fileId', 'FileId'])) ?? '',
      fileName: _str(_pick(['fileName', 'FileName'])),
      fileSize: fileSizeStr,
      creationTime: DateTime.tryParse(creationStr) ?? DateTime.now(),
      fileExtension: _str(_pick(['fileExtension', 'FileExtension'])),
      isDecrypted: (_pick(['isDecrypted', 'IsDecrypted']) as bool?) ?? false,
      textContent: _pick(['textContent', 'TextContent']),
      attachedMedia: _pick(['attachedMedia', 'AttachedMedia']),
      visibility: _str(_pick(['visibility', 'Visibility'])),
      tags: _pick(['tags', 'Tags']) != null ? List<String>.from(_pick(['tags', 'Tags'])) : null,
      firstBlockId: _str(_pick(['firstBlockId', 'FirstBlockId'])),
      encryptedKey: _str(_pick(['encryptedKey', 'EncryptedKey'])),
      recipientPubKey: _str(_pick(['recipientPubKey', 'RecipientPubKey'])),
      ownerPubKey: _str(_pick(['ownerPubKey', 'OwnerPubKey'])),
      encryptedType: _str(_pick(['encryptedType', 'EncryptedType'])) ?? 'encrypted',
      relatedFiles: (related as List?)?.map((e) => Map<String, dynamic>.from(e)).toList(),
      authorName: _str(_pick(['authorName', 'AuthorName'])),
      capsuleFor: _str(_pick(['capsuleFor', 'CapsuleFor'])),
      policyTag: _str(_pick(['policyTag', 'PolicyTag'])),
      policyScheme: _str(_pick(['policyScheme', 'PolicyScheme'])),
      encapsulatedForRecipient: _str(_pick(['encapsulatedForRecipient', 'EncapsulatedForRecipient'])),
    );
  }

  int get fileSizeInt => int.parse(fileSize);

  String get fileSizeFormatted {
    if (fileSizeInt < 1024) {
      return '$fileSizeInt B';
    } else if (fileSizeInt < 1024 * 1024) {
      return '${(fileSizeInt / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSizeInt / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  IconData get postIcon {
    if (attachedMedia != null && attachedMedia!.isNotEmpty) {
      return Icons.photo_library; // Post with media
    }
    return Icons.article; // Text-only post
  }

  Color get postIconColor {
    if (attachedMedia != null && attachedMedia!.isNotEmpty) {
      return Colors.blue;
    }
    return Colors.green;
  }
}

class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({Key? key}) : super(key: key);

  @override
  _MyPostsScreenState createState() => _MyPostsScreenState();

  // Helper: Fetch rekey from Central API (mode=client)
  static Future<String?> _fetchRekeyFromCentral(
    String apiBaseUrl,
    String followerPubKey,
    String followingPubKey,
    String policyTag,
    String mnemonic,
  ) async {
    try {
      // 1) Get PoP nonce
      final nonceResp = await http.get(Uri.parse('$apiBaseUrl/policy/nonce?userPubKey=$followerPubKey'));
      if (nonceResp.statusCode != 200) return null;
      final nonce = (json.decode(nonceResp.body) as Map<String, dynamic>)['nonce'] as String?;
      if (nonce == null || nonce.isEmpty) return null;

      // 2) Sign nonce with follower's key
      final popSignature = await CryptoService.sign(nonce, mnemonic);

      // 3) Request rekey (mode=client) with signed headers
      final method = 'POST';
      final pathForUrl = '/policy/fetch-rekey';
      final pathForSign = '/api/policy/fetch-rekey';
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final bodyJson = json.encode({
        'followerPubKey': followerPubKey,
        'followingPubKey': followingPubKey,
        'tag': policyTag,
        'mode': 'client', // ← Client mode: get rekey, not transform token
        'proof': {
          'nonce': nonce,
          'signature': popSignature,
        }
      });
      // Calculate SHA256 hex hash of body for signature
      final bodyBytes = utf8.encode(bodyJson);
      final bodyHashHex = sha256.convert(bodyBytes).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final sig = await CryptoService.sign('$method$pathForSign$ts$bodyHashHex', mnemonic);

      final resp = await http.post(
        Uri.parse('$apiBaseUrl$pathForUrl'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': CryptoService.normalizePublicKey(followerPubKey),
          'X-Timestamp': ts,
          'X-Signature': sig,
        },
        body: bodyJson,
      );
      
      if (resp.statusCode == 404) {
        // Rekey not found - author hasn't generated it yet
        AppLogger.log('⏳ Central API: Rekey not available (404) - waiting for author to generate it');
        final body = json.decode(resp.body) as Map<String, dynamic>;
        AppLogger.log('   Message: ${body['message'] ?? 'Rekey not generated yet'}');
        return null;
      }
      
      if (resp.statusCode != 200) {
        AppLogger.log('❌ Central API returned ${resp.statusCode}: ${resp.body}');
        return null;
      }
      
      final data = json.decode(resp.body) as Map<String, dynamic>;
      return data['rekey'] as String?;
    } catch (e) {
      AppLogger.log('❌ Error fetching rekey: $e');
      return null;
    }
  }

  // Static helper để dùng chung giải mã post cho các nơi khác (ví dụ Following Posts)
  static Future<PostMetadata?> tryDecryptPostStatic(
    PostMetadata post,
    String nodeEndpoint,
    String mnemonic,
    {required String currentUserPublicKey}
  ) async {
    try {
      AppLogger.log('==== DEBUG tryDecryptPostStatic START ====');
      AppLogger.log('Input post:');
      AppLogger.log('  fileId: ${post.fileId}');
      AppLogger.log('  encryptedKey: ${post.encryptedKey}');
      AppLogger.log('  recipientPubKey: ${post.recipientPubKey}');
      AppLogger.log('  ownerPubKey: ${post.ownerPubKey}');
      AppLogger.log('  capsuleFor: ${post.capsuleFor}');
      AppLogger.log('  policyTag: ${post.policyTag}');
      AppLogger.log('  nodeEndpoint: $nodeEndpoint');
      AppLogger.log('  mnemonic: ${mnemonic.substring(0, 8)}...');
      
      final encryptedKey = post.encryptedKey;
      final isPublicPost = encryptedKey == null || encryptedKey.isEmpty;
      final isPrePost = post.capsuleFor == 'tag' && post.policyTag != null && post.policyTag!.isNotEmpty;
      
      AppLogger.log('isPublicPost: $isPublicPost');
      AppLogger.log('isPrePost: $isPrePost');
      
      // Handle PRE posts
      if (isPrePost) {
        AppLogger.log('🔐 Detected PRE post - fileId: ${post.fileId}, policyTag: ${post.policyTag}');
        
        try {
          // Get author public key from ownerPubKey (must be provided by Store)
          final authorPubKey = post.ownerPubKey;
          
          if (authorPubKey == null || authorPubKey.isEmpty) {
            AppLogger.log('❌ PRE: Missing ownerPubKey - old posts without ownerPubKey are skipped');
            return null;
          }
          
          AppLogger.log('✅ PRE: Using ownerPubKey: $authorPubKey');
          AppLogger.log('🔍 DEBUG: currentUserPublicKey: $currentUserPublicKey');
          
          // Check if current user is the author
          final isAuthor = authorPubKey.toLowerCase() == currentUserPublicKey.toLowerCase();
          AppLogger.log('🔍 DEBUG: isAuthor = $isAuthor (authorPubKey == currentUserPublicKey)');
          
          Uint8List? symmetricKey;
          
          if (isAuthor) {
            // Author reading their own post - use ECIES (fast & simple!)
            AppLogger.log('📝 PRE: Current user is author - ECIES direct decryption');
            
            try {
              // encryptedKey is ECIES(K, pkAuthor) - decrypt with author's private key
              final eciesEncryptedKey = base64.decode(post.encryptedKey!);
              AppLogger.log('🔐 ECIES: Encrypted key size: ${eciesEncryptedKey.length} bytes');
              
              symmetricKey = await FileCryptoService.decryptSymmetricKeyWithPrivateKey(eciesEncryptedKey, mnemonic);
              AppLogger.log('✅ ECIES: Successfully decrypted symmetric key (${symmetricKey.length} bytes)');
            } catch (e) {
              AppLogger.log('❌ ECIES: Error during decryption: $e');
              symmetricKey = null;
            }
          } else {
            // Follower reading author's post - client-side transform then decapsulate
            AppLogger.log('👤 PRE: Current user is follower - client-transform + decapsulate');
            
            // Check if encapsulatedForRecipient is available
            if (post.encapsulatedForRecipient == null || post.encapsulatedForRecipient!.isEmpty) {
              AppLogger.log('❌ PRE: Missing encapsulatedForRecipient - old post format not supported');
              return null;
            }
            
            try {
              // Step 1: Get rekey rk(A→B) from Central API
              AppLogger.log('🔑 PRE: Fetching rekey from Central API...');
              final rkBase64 = await _fetchRekeyFromCentral(
                AppConstants.apiBaseUrl,
                currentUserPublicKey, // followerPubKey (B)
                authorPubKey, // followingPubKey (A)
                post.policyTag!,
                mnemonic,
              );
              
              if (rkBase64 == null) {
                AppLogger.log('⏳ PRE: Rekey not available yet - author needs to generate it');
                AppLogger.log('💡 PRE: This is normal for new followers. The author will generate rekeys in the background.');
                return null;
              }
              
              final rk = base64.decode(rkBase64);
              AppLogger.log('✅ PRE: Got rekey (${rk.length} bytes)');
              
              // Step 2: Client-side transform: capsuleForB = reencrypt(capsuleForA, rk)
              AppLogger.log('🔄 PRE: Client-side re-encryption (capsule transform)...');
              final capsuleForAuthor = base64.decode(post.encapsulatedForRecipient!);
              AppLogger.log('   Capsule for author size: ${capsuleForAuthor.length} bytes');
              
              final pre = PreFfi.instance();
              final capsuleForFollower = pre.reencrypt(
                encapsulatedForAuthor: capsuleForAuthor,
                rekey: rk,
              );
              
              if (capsuleForFollower.isEmpty) {
                AppLogger.log('❌ PRE: Client-side re-encryption failed');
                return null;
              }
              
              AppLogger.log('✅ PRE: Re-encrypted capsule (${capsuleForFollower.length} bytes)');
              
              // Step 3: Decapsulate with follower's private key to get K
              AppLogger.log('🔐 PRE: Decapsulating with follower key...');
              
              // Derive follower's secret key from mnemonic
              final seed = bip39.mnemonicToSeed(mnemonic);
              final skFollower = sha256.convert(seed).bytes as Uint8List;
              
              symmetricKey = pre.decapsulateForRecipient(
                encapsulatedForRecipient: capsuleForFollower,
                skRecipient: Uint8List.fromList(skFollower),
                tag: post.policyTag!,
              );
              
              if (symmetricKey.isEmpty) {
                AppLogger.log('❌ PRE: Decapsulation failed');
                return null;
              }
              
              AppLogger.log('✅ PRE: Successfully decapsulated symmetric key (${symmetricKey.length} bytes)');
            } catch (e) {
              AppLogger.log('❌ PRE: Error during client-transform: $e');
              symmetricKey = null;
            }
          }
          
          if (symmetricKey == null) {
            AppLogger.log('❌ Failed to recover symmetric key');
            return null;
          }
          
          AppLogger.log('✅ PRE: Decapsulated symmetric key successfully');
          
          // Step 3: Download and decrypt metadata block using symmetric key
          final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          final method = 'GET';
          final blockPath = '/api/file/block/${post.firstBlockId}';
          final bodyHash = '';
          final dataToSign = '$method$blockPath$timestamp$bodyHash';
          final signature = await CryptoService.sign(dataToSign, mnemonic);
          
          final metadataResponse = await http.get(
            Uri.parse('$nodeEndpoint$blockPath'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPublicKey),
              'X-Timestamp': timestamp,
              'X-Signature': signature,
            },
          );
          
          if (metadataResponse.statusCode != 200) {
            AppLogger.log('❌ PRE: Failed to fetch metadata block: ${metadataResponse.statusCode}');
            return null;
          }
          
          // Decrypt metadata with symmetric key
          final decryptedMetadata = await FileCryptoService.decryptRawBlockWithKey(
            metadataResponse.bodyBytes,
            symmetricKey,
          );
          
          if (decryptedMetadata == null) {
            AppLogger.log('❌ PRE: Failed to decrypt metadata block');
            return null;
          }
          
          final metadataJson = json.decode(utf8.decode(decryptedMetadata));
          AppLogger.log('✅ PRE: Decrypted metadata successfully');
          
          // Step 4: Download and decrypt content blocks
          final contentBlockIds = metadataJson['contentBlockIds'] as List<dynamic>? ?? [];
          final List<Uint8List> contentBlocks = [];
          
          for (final blockId in contentBlockIds) {
            final contentPath = '/api/file/block/$blockId';
            final contentDataToSign = '$method$contentPath$timestamp$bodyHash';
            final contentSignature = await CryptoService.sign(contentDataToSign, mnemonic);
            
            final contentResponse = await http.get(
              Uri.parse('$nodeEndpoint$contentPath'),
              headers: {
                'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPublicKey),
                'X-Timestamp': timestamp,
                'X-Signature': contentSignature,
              },
            );
            
            if (contentResponse.statusCode == 200) {
              final decryptedBlock = await FileCryptoService.decryptRawBlockWithKey(
                contentResponse.bodyBytes,
                symmetricKey,
              );
              if (decryptedBlock != null) {
                contentBlocks.add(decryptedBlock);
              }
            }
          }
          
          // Step 5: Combine content blocks and parse post
          final fileSize = metadataJson['fileSize'] as int;
          final result = Uint8List(fileSize);
          int currentPosition = 0;
          for (final block in contentBlocks) {
            final bytesToCopy = math.min(block.length, fileSize - currentPosition);
            result.setRange(currentPosition, currentPosition + bytesToCopy, block);
            currentPosition += bytesToCopy;
          }
          
          final postContentString = utf8.decode(result);
          final postData = json.decode(postContentString);
          
          AppLogger.log('✅ PRE post decrypted successfully');
          
          return PostMetadata(
            fileId: post.fileId,
            fileName: metadataJson['fileName'],
            fileSize: post.fileSize,
            creationTime: post.creationTime,
            fileExtension: metadataJson['fileExtension'],
            isDecrypted: true,
            textContent: postData['textContent'],
            attachedMedia: postData['attachedMedia'],
            visibility: postData['visibility'],
            tags: postData['tags'] != null ? List<String>.from(postData['tags']) : null,
            firstBlockId: post.firstBlockId,
            encryptedKey: '',
            recipientPubKey: post.recipientPubKey,
            ownerPubKey: metadataJson['ownerPubKey'],
            authorName: postData['authorName'],
            encryptedType: 'encrypted',
            relatedFiles: (metadataJson['relatedFiles'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList(),
            capsuleFor: post.capsuleFor,
            policyTag: post.policyTag,
            policyScheme: post.policyScheme,
          );
        } catch (e) {
          AppLogger.log('❌ PRE post decryption error: $e');
          return null;
        }
      }
      if (isPublicPost) {
        final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
        final method = 'GET';
      final path = post.firstBlockId != null && post.firstBlockId!.isNotEmpty
          ? '/api/file/block/${post.firstBlockId}'
          : '/api/file/block/${post.fileId}/0';
        final bodyHash = '';
        final dataToSign = '$method$path$timestamp$bodyHash';
        final signature = await CryptoService.sign(dataToSign, mnemonic);
        final metadataResponse = await http.get(
          Uri.parse('$nodeEndpoint$path'),
          headers: {
            'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPublicKey),
            'X-Timestamp': timestamp,
            'X-Signature': signature,
          },
        );
        AppLogger.log('metadataResponse.statusCode: ${metadataResponse.statusCode}');
        if (metadataResponse.statusCode != 200) return null;
        final metadataString = utf8.decode(metadataResponse.bodyBytes);
        AppLogger.log('metadataString: $metadataString');
        final metadataContent = json.decode(metadataString);
        AppLogger.log('DEBUG metadataContent: $metadataContent');
        final contentBlockIds = metadataContent['contentBlockIds'] as List<dynamic>? ?? [];
        AppLogger.log('contentBlockIds: $contentBlockIds');
        if (contentBlockIds.isEmpty) return null;
        List<Uint8List> contentBlocks = [];
        for (final blockId in contentBlockIds) {
      final contentPath = '/api/file/block/$blockId';
          final contentDataToSign = '$method$contentPath$timestamp$bodyHash';
          final contentSignature = await CryptoService.sign(contentDataToSign, mnemonic);
          final _cStart = DateTime.now();
          AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint$contentPath' + ' START ' + _cStart.toIso8601String());
          final contentResponse = await http.get(
            Uri.parse('$nodeEndpoint$contentPath'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPublicKey),
              'X-Timestamp': timestamp,
              'X-Signature': contentSignature,
            },
          );
          AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint$contentPath' + ' END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_cStart).inMilliseconds.toString() + 'ms) code=' + contentResponse.statusCode.toString());
          AppLogger.log('contentResponse.statusCode for block $blockId: ${contentResponse.statusCode}');
          if (contentResponse.statusCode != 200) {
            AppLogger.log('❌ Failed to download content block $blockId: ${contentResponse.statusCode}');
            continue; // Skip this block
          }
          if (contentResponse.bodyBytes.isEmpty) {
            AppLogger.log('❌ Downloaded block $blockId is empty!');
            continue;
          }
          contentBlocks.add(contentResponse.bodyBytes);
        }
        final fileSize = metadataContent['fileSize'];
        AppLogger.log('DEBUG fileSize: $fileSize (${fileSize.runtimeType})');
        if (fileSize == null || fileSize is! int) {
          AppLogger.log('❌ fileSize is null or not int!');
          AppLogger.log('metadataContent: $metadataContent');
          return null;
        }
        final result = Uint8List(fileSize);
        int currentPosition = 0;
        for (final block in contentBlocks) {
          final bytesToCopy = math.min(block.length, fileSize - currentPosition);
          result.setRange(currentPosition, currentPosition + bytesToCopy, block);
          currentPosition += bytesToCopy;
        }
        String postContentString;
        try {
          postContentString = utf8.decode(result);
        } catch (e) {
          AppLogger.log('utf8.decode failed: $e');
          postContentString = String.fromCharCodes(result);
        }
        AppLogger.log('postContentString: ${postContentString.substring(0, math.min(200, postContentString.length))}');
        final postData = json.decode(postContentString);
        AppLogger.log('DEBUG postData: $postData');
        // Thêm log chi tiết trước khi trả về PostMetadata
        AppLogger.log('DEBUG about to return PostMetadata:');
        AppLogger.log('  fileId: \\${post.fileId}');
        AppLogger.log('  fileName: \\${metadataContent['fileName']}');
        AppLogger.log('  fileSize: \\$fileSize');
        AppLogger.log('  creationTime: \\${post.creationTime}');
        AppLogger.log('  fileExtension: \\${metadataContent['fileExtension']}');
        AppLogger.log('  textContent: \\${postData['textContent']}');
        AppLogger.log('  attachedMedia: \\${postData['attachedMedia']}');
        AppLogger.log('  visibility: \\${postData['visibility']}');
        AppLogger.log('  tags: \\${postData['tags']}');
        AppLogger.log('  firstBlockId: \\${post.firstBlockId}');
        AppLogger.log('  encryptedKey: \\${post.encryptedKey}');
        AppLogger.log('  recipientPubKey: \\${post.recipientPubKey}');
        AppLogger.log('  ownerPubKey: \\${metadataContent['ownerPubKey']}');
        AppLogger.log('==== DEBUG tryDecryptPostStatic END (public) ====');
        
        // 🔍 DEBUG: Check related files before returning public post
        AppLogger.log('🔍 DEBUG PUBLIC POST RETURN - fileId: ${post.fileId}');
        AppLogger.log('  Original post relatedFiles: ${post.relatedFiles}');
        AppLogger.log('  Original post relatedFiles length: ${post.relatedFiles?.length ?? 0}');
        AppLogger.log('  PostData relatedFiles: ${postData['relatedFiles']}');
        AppLogger.log('  PostData attachedMedia: ${postData['attachedMedia']}');
        AppLogger.log('  Metadata content relatedFiles: ${metadataContent['relatedFiles']}');
        AppLogger.log('🔍 END DEBUG PUBLIC POST RETURN');
        
        return PostMetadata(
          fileId: post.fileId,
          fileName: metadataContent['fileName'],
          fileSize: post.fileSize,
          creationTime: post.creationTime,
          fileExtension: metadataContent['fileExtension'],
          isDecrypted: true,
          textContent: postData['textContent'],
          attachedMedia: postData['attachedMedia'],
          visibility: postData['visibility'],
          tags: postData['tags'] != null ? List<String>.from(postData['tags']) : null,
          firstBlockId: post.firstBlockId,
          encryptedKey: '',
          recipientPubKey: post.recipientPubKey,
          ownerPubKey: metadataContent['ownerPubKey'],
        authorName: postData['authorName'],
          encryptedType: 'public',
          relatedFiles: (metadataContent['relatedFiles'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList(),
        );
      }
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final metadataPath = (post.firstBlockId != null && post.firstBlockId!.isNotEmpty)
          ? '/api/file/block/${post.firstBlockId}'
          : '/api/file/block/${post.fileId}/0';
      final bodyHash = '';
      final dataToSign = '$method$metadataPath$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, mnemonic);
      final _metaStart = DateTime.now();
      AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint$metadataPath' + ' START ' + _metaStart.toIso8601String());
      final metadataResponse = await http.get(
        Uri.parse('$nodeEndpoint$metadataPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint$metadataPath' + ' END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_metaStart).inMilliseconds.toString() + 'ms) code=' + metadataResponse.statusCode.toString());
      AppLogger.log('metadataResponse.statusCode (private): ${metadataResponse.statusCode}');
      if (metadataResponse.statusCode != 200) return null;
      final storeMetadata = {
        'fileId': post.fileId,
        'ownerPubKey': post.ownerPubKey ?? '',
        'encryptedKey': post.encryptedKey ?? '',
        'recipientPubKey': post.recipientPubKey ?? '',
      };
      AppLogger.log('storeMetadata: $storeMetadata');
      final decryptedMetadata = await FileCryptoService.decryptMetadataBlock(
        storeMetadata: storeMetadata,
        encryptedMetadataBlock: metadataResponse.bodyBytes,
        userPublicKey: post.recipientPubKey ?? '',
        mnemonic: mnemonic,
      );
      AppLogger.log('DEBUG decryptedMetadata: $decryptedMetadata');
      
      // 🔍 DEBUG: Check related files in decrypted metadata
      AppLogger.log('🔍 DEBUG DECRYPTED METADATA - fileId: ${post.fileId}');
      AppLogger.log('  Full decrypted metadata: $decryptedMetadata');
      AppLogger.log('  relatedFiles in metadata: ${decryptedMetadata['relatedFiles']}');
      AppLogger.log('  relatedFiles type: ${decryptedMetadata['relatedFiles']?.runtimeType}');
      AppLogger.log('  relatedFiles length: ${(decryptedMetadata['relatedFiles'] as List?)?.length ?? 0}');
      if (decryptedMetadata['relatedFiles'] != null) {
        AppLogger.log('  relatedFiles content:');
        for (int i = 0; i < (decryptedMetadata['relatedFiles'] as List).length; i++) {
          AppLogger.log('    [$i]: ${decryptedMetadata['relatedFiles'][i]}');
        }
      }
      AppLogger.log('🔍 END DEBUG DECRYPTED METADATA');

      // Update storeMetadata with fileSize from decrypted metadata
      final fileSize = decryptedMetadata['fileSize'];
      final fileSizeInt = (fileSize is num) ? fileSize.toInt() : int.parse(fileSize.toString());
      storeMetadata['fileSize'] = fileSizeInt.toString();

      final contentBlockIds = decryptedMetadata['contentBlockIds'] as List<dynamic>? ?? [];
      AppLogger.log('contentBlockIds (private): $contentBlockIds');
      if (contentBlockIds.isEmpty) return null;
      List<Uint8List> encryptedContentBlocks = [];
      for (final blockId in contentBlockIds) {
        final contentPath = '/api/file/block/$blockId';
        final contentDataToSign = '$method$contentPath$timestamp$bodyHash';
        final contentSignature = await CryptoService.sign(contentDataToSign, mnemonic);
        final _cStart2 = DateTime.now();
        AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint$contentPath' + ' START ' + _cStart2.toIso8601String());
        final contentResponse = await http.get(
          Uri.parse('$nodeEndpoint$contentPath'),
          headers: {
            'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPublicKey),
            'X-Timestamp': timestamp,
            'X-Signature': contentSignature,
          },
        );
        AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint$contentPath' + ' END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_cStart2).inMilliseconds.toString() + 'ms) code=' + contentResponse.statusCode.toString());
        AppLogger.log('contentResponse.statusCode for block $blockId (private): ${contentResponse.statusCode}');
        if (contentResponse.statusCode != 200) {
          AppLogger.log('❌ Failed to download content block $blockId (private): ${contentResponse.statusCode}');
          continue; // Skip this block
        }
        if (contentResponse.bodyBytes.isEmpty) {
          AppLogger.log('❌ Downloaded block $blockId (private) is empty!');
          continue;
        }
        encryptedContentBlocks.add(contentResponse.bodyBytes);
      }
      final decryptedData = await FileCryptoService.decryptFile(
        fileMetadata: {
          'fileId': post.fileId,
          'ownerPubKey': post.ownerPubKey ?? '',
          'encryptedKey': post.encryptedKey ?? '',
          'recipientPubKey': post.recipientPubKey ?? '',
          'fileSize': int.parse(decryptedMetadata['fileSize'].toString()),
        },
        encryptedBlocks: encryptedContentBlocks,
        userPublicKey: CryptoService.normalizePublicKey(currentUserPublicKey),
        mnemonic: mnemonic,
      );
      AppLogger.log('decryptedData length: ${decryptedData.length}');
      final postContentString = utf8.decode(decryptedData);
      AppLogger.log('postContentString (private): ${postContentString.substring(0, math.min(200, postContentString.length))}');
      final postData = json.decode(postContentString);
      AppLogger.log('DEBUG postData (private): $postData');
      // Thêm log chi tiết trước khi trả về PostMetadata
      AppLogger.log('DEBUG about to return PostMetadata (private):');
      AppLogger.log('  fileId: \\${post.fileId}');
      AppLogger.log('  fileName: \\${decryptedMetadata['fileName']}');
      AppLogger.log('  fileSize: \\$fileSize');
      AppLogger.log('  creationTime: \\${post.creationTime}');
      AppLogger.log('  fileExtension: \\${decryptedMetadata['fileExtension']}');
      AppLogger.log('  textContent: \\${postData['textContent']}');
      AppLogger.log('  attachedMedia: \\${postData['attachedMedia']}');
      AppLogger.log('  visibility: \\${postData['visibility']}');
      AppLogger.log('  tags: \\${postData['tags']}');
      AppLogger.log('  firstBlockId: \\${post.firstBlockId}');
      AppLogger.log('  encryptedKey: \\${post.encryptedKey}');
      AppLogger.log('  recipientPubKey: \\${post.recipientPubKey}');
      AppLogger.log('  ownerPubKey: \\${decryptedMetadata['ownerPubKey']}');
      AppLogger.log('==== DEBUG tryDecryptPostStatic END (private) ====');
      AppLogger.log('DEBUG: encryptedContentBlocks count: \\${encryptedContentBlocks.length}');
      for (int i = 0; i < encryptedContentBlocks.length; i++) {
        final block = encryptedContentBlocks[i];
        AppLogger.log('DEBUG: Block #$i type: \\${block.runtimeType}, length: \\${block is Uint8List ? block.length : 'N/A'}');
        if (block == null) print('❌ Block #$i is null!');
        if (block is! Uint8List) print('❌ Block #$i is not Uint8List!');
      }
      
      // 🔍 DEBUG: Check related files before returning private post
      AppLogger.log('🔍 END DEBUG PRIVATE POST RETURN');
      
      // 🔍 DEBUG: Check related files before returning private post
      AppLogger.log('🔍 DEBUG PRIVATE POST RETURN - fileId: ${post.fileId}');
      AppLogger.log('  Original post relatedFiles: ${post.relatedFiles}');
      AppLogger.log('  Original post relatedFiles length: ${post.relatedFiles?.length ?? 0}');
      AppLogger.log('  PostData relatedFiles: ${postData['relatedFiles']}');
      AppLogger.log('  PostData attachedMedia: ${postData['attachedMedia']}');
      AppLogger.log('  Decrypted metadata relatedFiles: ${decryptedMetadata['relatedFiles']}');
      AppLogger.log('🔍 END DEBUG PRIVATE POST RETURN');
      
      return PostMetadata(
        fileId: post.fileId,
        fileName: decryptedMetadata['fileName'],
        fileSize: post.fileSize,
        creationTime: post.creationTime,
        fileExtension: decryptedMetadata['fileExtension'],
        isDecrypted: true,
        textContent: postData['textContent'],
        attachedMedia: postData['attachedMedia'],
        visibility: postData['visibility'],
        tags: postData['tags'] != null ? List<String>.from(postData['tags']) : null,
        firstBlockId: post.firstBlockId,
        encryptedKey: '',
        recipientPubKey: post.recipientPubKey,
        ownerPubKey: decryptedMetadata['ownerPubKey'],
        authorName: postData['authorName'],
        encryptedType: 'encrypted',
        relatedFiles: (decryptedMetadata['relatedFiles'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    } catch (e, stack) {
      AppLogger.log('❌ Error in tryDecryptPostStatic: $e');
      AppLogger.log('STACKTRACE: $stack');
      return null;
    }
  }
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  final AuthService _authService = AuthService();
  
  bool _isLoading = true;
  String _loadingMessage = 'Loading your posts...';
  String? _errorMessage;
  String? _userPublicKey;
  String? _userMnemonic;
  
  List<Map<String, dynamic>> _storeNodes = [];
  Map<String, List<PostMetadata>> _postsByNode = {};
  
  // 🆕 Performance tracking
  final Map<String, int> _timingLog = {};
  DateTime? _loadStartTime;
  
  @override
  void initState() {
    super.initState();
    // 🔥 CACHE: Check cache status when entering My Posts
    FileCryptoService.checkCacheStatus();
    _loadUserInfo();
  }
  
  // 🆕 Helper method to log timing
  void _logTiming(String operation, int milliseconds) {
    _timingLog[operation] = milliseconds;
    AppLogger.log('⏱️ TIMING: $operation took ${milliseconds}ms');
  }
  
  // 🆕 Helper method to start timing
  DateTime _startTiming(String operation) {
    final startTime = DateTime.now();
    AppLogger.log('⏱️ TIMING: Starting $operation...');
    return startTime;
  }
  
  // 🆕 Helper method to end timing
  void _endTiming(String operation, DateTime startTime) {
    final duration = DateTime.now().difference(startTime).inMilliseconds;
    _logTiming(operation, duration);
  }
  
  Future<void> _loadUserInfo() async {
    final startTime = _startTiming('Load User Info');
    
    final authInfo = await _authService.getCurrentAuthInfo();
    if (authInfo != null) {
      setState(() {
        _userPublicKey = authInfo['publicKey'];
        _userMnemonic = authInfo['mnemonic'];
      });
      
      _endTiming('Load User Info', startTime);
      _loadUserPosts();
    } else {
      _endTiming('Load User Info', startTime);
      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be logged in to view your posts';
      });
    }
  }
  
  Future<void> _loadUserPosts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _loadingMessage = 'Loading your posts...';
    });

    _loadStartTime = DateTime.now();
    AppLogger.log('🚀 PERFORMANCE: Starting complete posts loading process...');

    try {
      // Verify user info is already loaded from initState
      if (_userPublicKey == null || _userMnemonic == null) {
        throw Exception('User not authenticated');
      }

      AppLogger.log('Found current user in SharedPreferences');

      // Fetch available storage nodes
      final nodesStartTime = _startTiming('Fetch Storage Nodes');
      _storeNodes = await _fetchAvailableNodes();
      _endTiming('Fetch Storage Nodes', nodesStartTime);

      AppLogger.log('Found ${_storeNodes.length} storage nodes');

      // Query all nodes for posts with parallel processing
      final totalNodesStartTime = _startTiming('Query All Nodes');
      final Map<String, List<PostMetadata>> postsByNode = {};

      for (int nodeIndex = 0; nodeIndex < _storeNodes.length; nodeIndex++) {
        final node = _storeNodes[nodeIndex];
        final nodeEndpoint = node['endpoint'] as String;

        setState(() {
          _loadingMessage = 'Checking node ${nodeIndex + 1}/${_storeNodes.length}...';
        });
        
        // Add yield control to prevent UI freezing
        await Future.delayed(Duration(milliseconds: 20));
        
        final nodeStartTime = _startTiming('Query Node ${nodeIndex + 1}');
        
        try {
          AppLogger.log('Querying node: $nodeEndpoint for posts');
          
          // Query for posts only (type='post') with proper authentication
          final authStartTime = _startTiming('Node ${nodeIndex + 1} Auth Setup');
          
          final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          final method = 'GET';
          final path = '/api/file/posts';
          final bodyHash = ''; // Empty body for GET request
          
          // Create data to sign
          final dataToSign = '$method$path$timestamp$bodyHash';
          
          // Generate signature
          final signature = await CryptoService.sign(dataToSign, _userMnemonic!);
          
          _endTiming('Node ${nodeIndex + 1} Auth Setup', authStartTime);
          
          final requestStartTime = _startTiming('Node ${nodeIndex + 1} HTTP Request');
          final _httpStart = DateTime.now();
          AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint/api/file/posts' + ' START ' + _httpStart.toIso8601String());
          final postsResponse = await http.get(
            Uri.parse('$nodeEndpoint/api/file/posts'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(_userPublicKey!),
              'X-Timestamp': timestamp,
              'X-Signature': signature,
            },
          );
          final _httpElapsed = DateTime.now().difference(_httpStart).inMilliseconds;
          AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint/api/file/posts' + ' END ' + DateTime.now().toIso8601String() + ' (' + _httpElapsed.toString() + 'ms) code=' + postsResponse.statusCode.toString());

          _endTiming('Node ${nodeIndex + 1} HTTP Request', requestStartTime);

          if (postsResponse.statusCode == 200) {
            final parseStartTime = _startTiming('Node ${nodeIndex + 1} Parse Response');
            
            final responseBody = json.decode(postsResponse.body);
            AppLogger.log('Node ${nodeEndpoint} response: $responseBody');
            
            // Handle the new API response format
            List<dynamic> postsJson;
            if (responseBody is Map<String, dynamic> && responseBody.containsKey('posts')) {
              postsJson = responseBody['posts'] as List<dynamic>;
              AppLogger.log('Node ${nodeEndpoint} returned ${postsJson.length} posts (from posts field)');
            } else if (responseBody is List<dynamic>) {
              postsJson = responseBody;
              AppLogger.log('Node ${nodeEndpoint} returned ${postsJson.length} posts (direct array)');
            } else {
              AppLogger.log('Node ${nodeEndpoint} returned unexpected format: ${responseBody.runtimeType}');
              _endTiming('Node ${nodeIndex + 1} Parse Response', parseStartTime);
              continue;
            }
            
            _endTiming('Node ${nodeIndex + 1} Parse Response', parseStartTime);
            
            // 🚀 PARALLEL PROCESSING: Process posts concurrently instead of sequentially
            final processStartTime = _startTiming('Node ${nodeIndex + 1} Process Posts');
            
            // Convert raw JSON to PostMetadata objects first
            final List<PostMetadata> postMetadataList = [];
            for (final postJson in postsJson) {
              try {
                AppLogger.log('Processing post JSON: $postJson');
                final postMetadata = PostMetadata.fromJson(postJson);
                AppLogger.log('Created PostMetadata: fileId=${postMetadata.fileId}, creationTime=${postMetadata.creationTime}');
                
                // 🔍 DEBUG: Check related files in raw JSON and PostMetadata
                AppLogger.log('🔍 DEBUG POST PROCESSING - fileId: ${postMetadata.fileId}');
                AppLogger.log('  Raw JSON relatedFiles: ${postJson['relatedFiles']}');
                AppLogger.log('  PostMetadata relatedFiles: ${postMetadata.relatedFiles}');
                AppLogger.log('  PostMetadata relatedFiles length: ${postMetadata.relatedFiles?.length ?? 0}');
                AppLogger.log('  Raw JSON attachedMedia: ${postJson['attachedMedia']}');
                AppLogger.log('  PostMetadata attachedMedia: ${postMetadata.attachedMedia}');
                AppLogger.log('  PostMetadata attachedMedia length: ${postMetadata.attachedMedia?.length ?? 0}');
                AppLogger.log('🔍 END DEBUG POST PROCESSING');
                
                postMetadataList.add(postMetadata);
              } catch (e) {
                AppLogger.log('Error creating PostMetadata: $e');
                AppLogger.log('Post JSON that failed: $postJson');
              }
            }
            
            AppLogger.log('🚀 PARALLEL: Starting concurrent decryption of ${postMetadataList.length} posts...');
            
            // 🆕 TRUE PARALLEL DECRYPTION: Use Future.wait with batching
            const int maxConcurrency = 5; // 🚀 INCREASED: Process 5 posts at a time for better performance
            final List<PostMetadata> nodePosts = [];
            
            // Split posts into batches for true parallel processing
            final batches = <List<PostMetadata>>[];
            for (int i = 0; i < postMetadataList.length; i += maxConcurrency) {
              final end = (i + maxConcurrency > postMetadataList.length) 
                  ? postMetadataList.length 
                  : i + maxConcurrency;
              batches.add(postMetadataList.sublist(i, end));
            }
            
            AppLogger.log('🚀 PARALLEL: Created ${batches.length} batches with max $maxConcurrency posts per batch');
            
            // Process each batch in parallel
            for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
              final batch = batches[batchIndex];
              
              setState(() {
                _loadingMessage = 'Processing batch ${batchIndex + 1}/${batches.length} (${batch.length} posts) from node ${nodeIndex + 1}...';
              });
              
              final batchStartTime = _startTiming('Parallel Batch ${batchIndex + 1}');
              
              // 🚀 TRUE PARALLEL: Process all posts in this batch concurrently
              final futures = batch.map((postMetadata) {
                return MyPostsScreen.tryDecryptPostStatic(
                  postMetadata,
                  nodeEndpoint,
                  _userMnemonic!,
                  currentUserPublicKey: _userPublicKey!,
                );
              }).toList();
              
              // Wait for all posts in this batch to complete
              final batchResults = await Future.wait(futures, eagerError: false);
              
              _endTiming('Parallel Batch ${batchIndex + 1}', batchStartTime);
              
              // Add successful decryptions to nodePosts
              for (int i = 0; i < batchResults.length; i++) {
                final result = batchResults[i];
                if (result != null) {
                  nodePosts.add(result);
                  AppLogger.log('✅ Successfully decrypted post: ${batch[i].fileId}');
                } else {
                  AppLogger.log('❌ Failed to decrypt post: ${batch[i].fileId}');
                }
              }
            }
            
            _endTiming('Node ${nodeIndex + 1} Process Posts', processStartTime);
            
            AppLogger.log('🎯 PARALLEL RESULT: Processed ${nodePosts.length} posts from ${postMetadataList.length} total');
            
            if (nodePosts.isNotEmpty) {
              postsByNode[node['id']] = nodePosts;
            }
          } else {
            AppLogger.log('Node ${nodeEndpoint} returned status ${postsResponse.statusCode}');
          }
        } catch (e) {
          AppLogger.log('Error querying node $nodeEndpoint: $e');
        }
        
        _endTiming('Query Node ${nodeIndex + 1}', nodeStartTime);
      }

      _endTiming('Query All Nodes', totalNodesStartTime);

      setState(() {
        _postsByNode = postsByNode;
        _isLoading = false;
        _errorMessage = null;
      });

      // 🆕 Performance summary
      final totalTime = DateTime.now().difference(_loadStartTime!).inMilliseconds;
      AppLogger.log('🎯 PERFORMANCE SUMMARY:');
      AppLogger.log('   Total loading time: ${totalTime}ms');
      _timingLog.forEach((operation, time) {
        final percentage = ((time / totalTime) * 100).toStringAsFixed(1);
        AppLogger.log('   $operation: ${time}ms (${percentage}%)');
      });

      AppLogger.log('=== FINAL RESULTS ===');
      AppLogger.log('Loaded posts from ${postsByNode.length} nodes');
      final totalPosts = postsByNode.values.fold(0, (sum, posts) => sum + posts.length);
      AppLogger.log('Total posts: $totalPosts');
      
      // Debug each node's posts
      postsByNode.forEach((nodeId, posts) {
        AppLogger.log('Node $nodeId has ${posts.length} posts:');
        for (final post in posts) {
          AppLogger.log('  - Post ${post.fileId}: ${post.isDecrypted ? "decrypted" : "encrypted"}');
        }
      });
      
      AppLogger.log('_postsByNode.isEmpty: ${_postsByNode.isEmpty}');
      AppLogger.log('=== END RESULTS ===');

    } catch (e) {
      final totalTime = _loadStartTime != null ? DateTime.now().difference(_loadStartTime!).inMilliseconds : 0;
      AppLogger.log('❌ Error loading user posts after ${totalTime}ms: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load posts: ${e.toString()}';
      });
    }
  }
  
  
  Future<PostMetadata?> _loadPublicPost(PostMetadata post, String nodeEndpoint) async {
    final loadStartTime = _startTiming('Load Public Post ${post.fileId}');
    
    try {
      AppLogger.log('🔓 Loading public post: ${post.fileId}');
      
      // Download metadata block (index 0) - plain text for public posts
      final metadataDownloadStartTime = _startTiming('Download Public Metadata Block ${post.fileId}');
      
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final path = '/api/file/block/${post.fileId}/0'; // Index 0 is always metadata block
      final bodyHash = '';
      
      final dataToSign = '$method$path$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, _userMnemonic!);
      
      final metadataResponse = await http.get(
        Uri.parse('$nodeEndpoint$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(_userPublicKey!),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      
      _endTiming('Download Public Metadata Block ${post.fileId}', metadataDownloadStartTime);
      
      if (metadataResponse.statusCode != 200) {
        AppLogger.log('❌ Failed to download public metadata block: ${metadataResponse.statusCode}');
        _endTiming('Load Public Post ${post.fileId}', loadStartTime);
        return null;
      }
      
      AppLogger.log('✅ Downloaded public metadata block: ${metadataResponse.bodyBytes.length} bytes');
      
      // Parse metadata as plain text JSON (no decryption needed)
      final metadataParseStartTime = _startTiming('Parse Public Metadata ${post.fileId}');
      
      String metadataString;
      try {
        metadataString = utf8.decode(metadataResponse.bodyBytes);
      } catch (e) {
        AppLogger.log('❌ Failed to decode public metadata as UTF-8: $e');
        _endTiming('Parse Public Metadata ${post.fileId}', metadataParseStartTime);
        _endTiming('Load Public Post ${post.fileId}', loadStartTime);
        return null;
      }
      
      final metadataContent = json.decode(metadataString) as Map<String, dynamic>;
      
      _endTiming('Parse Public Metadata ${post.fileId}', metadataParseStartTime);
      
      AppLogger.log('✅ Parsed public metadata: $metadataContent');
      
      // Get content block IDs from metadata
      final contentBlockIds = metadataContent['contentBlockIds'] as List<dynamic>? ?? [];
      
      if (contentBlockIds.isEmpty) {
        AppLogger.log('❌ No content block IDs found for public post ${post.fileId}');
        _endTiming('Load Public Post ${post.fileId}', loadStartTime);
        return null;
      }
      
      AppLogger.log('📥 Downloading ${contentBlockIds.length} public content blocks...');
      
      // Download content blocks (plain text)
      final contentDownloadStartTime = _startTiming('Download Public Content Blocks ${post.fileId}');
      
      final blockDownloadFutures = contentBlockIds.asMap().entries.map((entry) async {
        final contentIndex = entry.key;
        final String blockId = entry.value as String;
        
        AppLogger.log('📥 Starting download of public content block ${contentIndex + 1}/${contentBlockIds.length}: $blockId');
        
        try {
          final blockTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          final blockMethod = 'GET';
          final blockPath = '/api/file/block/$blockId';
          final blockBodyHash = '';
          
          final blockDataToSign = '$blockMethod$blockPath$blockTimestamp$blockBodyHash';
          final blockSignature = await CryptoService.sign(blockDataToSign, _userMnemonic!);
          
          final blockResponse = await http.get(
            Uri.parse('$nodeEndpoint$blockPath'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(_userPublicKey!),
              'X-Timestamp': blockTimestamp,
              'X-Signature': blockSignature,
            },
          );
          
          if (blockResponse.statusCode == 200) {
            AppLogger.log('✅ Downloaded public content block $blockId: ${blockResponse.bodyBytes.length} bytes');
            return {
              'index': contentIndex,
              'blockId': blockId,
              'data': blockResponse.bodyBytes,
              'success': true,
            };
          } else {
            AppLogger.log('❌ Failed to download public content block $blockId: ${blockResponse.statusCode}');
            return {
              'index': contentIndex,
              'blockId': blockId,
              'success': false,
              'error': 'HTTP ${blockResponse.statusCode}',
            };
          }
        } catch (e) {
          AppLogger.log('❌ Exception downloading public content block $blockId: $e');
          return {
            'index': contentIndex,
            'blockId': blockId,
            'success': false,
            'error': e.toString(),
          };
        }
      }).toList();
      
      final blockResults = await Future.wait(blockDownloadFutures, eagerError: false);
      
      // Sort and extract successful downloads
      final List<Uint8List> contentBlocks = [];
      blockResults.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
      
      for (final result in blockResults) {
        if (result['success'] == true) {
          contentBlocks.add(result['data'] as Uint8List);
        } else {
          AppLogger.log('❌ Public block ${result['blockId']} failed: ${result['error']}');
        }
      }
      
      _endTiming('Download Public Content Blocks ${post.fileId}', contentDownloadStartTime);
      
      if (contentBlocks.isEmpty) {
        AppLogger.log('❌ No public content blocks downloaded for post ${post.fileId}');
        _endTiming('Load Public Post ${post.fileId}', loadStartTime);
        return null;
      }
      
      // Reassemble content (plain text)
      final contentAssembleStartTime = _startTiming('Assemble Public Content ${post.fileId}');
      
      final fileSize = metadataContent['fileSize'] as int;
      final result = Uint8List(fileSize);
      
      int currentPosition = 0;
      for (final block in contentBlocks) {
        final bytesToCopy = math.min(block.length, fileSize - currentPosition);
        result.setRange(currentPosition, currentPosition + bytesToCopy, block);
        currentPosition += bytesToCopy;
      }
      
      _endTiming('Assemble Public Content ${post.fileId}', contentAssembleStartTime);
      
      // Parse the public post content as JSON
      final parseContentStartTime = _startTiming('Parse Public Content ${post.fileId}');
      
      String postContentString;
      try {
        postContentString = utf8.decode(result);
      } catch (e) {
        AppLogger.log('❌ Failed to decode public post content as UTF-8: $e');
        postContentString = String.fromCharCodes(result);
      }
      
      final postData = json.decode(postContentString);
      AppLogger.log('📋 Parsed public post data: $postData');
      
      _endTiming('Parse Public Content ${post.fileId}', parseContentStartTime);
      _endTiming('Load Public Post ${post.fileId}', loadStartTime);
      
      return PostMetadata(
        fileId: post.fileId,
        fileName: metadataContent['fileName'],
        fileSize: post.fileSize,
        creationTime: post.creationTime,
        fileExtension: metadataContent['fileExtension'],
        isDecrypted: true,
        textContent: postData['textContent'],
        attachedMedia: postData['attachedMedia'],
        visibility: postData['visibility'],
        tags: postData['tags'] != null ? List<String>.from(postData['tags']) : null,
        firstBlockId: post.firstBlockId,
        encryptedKey: '', // No encryption key for public posts
        recipientPubKey: post.recipientPubKey,
        ownerPubKey: metadataContent['ownerPubKey'],
        authorName: postData['authorName'],
        encryptedType: 'public',
        relatedFiles: post.relatedFiles,
      );
      
    } catch (e) {
      AppLogger.log('❌ Error loading public post ${post.fileId}: $e');
      _endTiming('Load Public Post ${post.fileId}', loadStartTime);
    }
    
    return null;
  }
  
  // 🆕 Method to fetch available storage nodes
  Future<List<Map<String, dynamic>>> _fetchAvailableNodes() async {
    try {
      final _httpStart = DateTime.now();
      AppLogger.log('🌐 HTTP GET /api/storenode/list START ' + _httpStart.toIso8601String());
      final storeNodesResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/storenode/list'),
      );
      AppLogger.log('🌐 HTTP GET /api/storenode/list END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_httpStart).inMilliseconds.toString() + 'ms) code=' + storeNodesResponse.statusCode.toString());

      if (storeNodesResponse.statusCode != 200) {
        throw Exception('Failed to fetch storage nodes');
      }

      final List<dynamic> storeNodesJson = json.decode(storeNodesResponse.body);
      return storeNodesJson.map((node) => Map<String, dynamic>.from(node)).toList();
    } catch (e) {
      AppLogger.log('Error fetching storage nodes: $e');
      return [];
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    if (_isLoading) {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  _loadingMessage,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextPrimaryColor
                      : DeltaniumTheme.lightTextPrimaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadUserPosts,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    
    return _buildPostsList(isDarkMode);
  }
  
  Widget _buildPostsList(bool isDarkMode) {
    return OptimizedPostList(
      postsByNode: _postsByNode,
      storeNodes: _storeNodes,
      isDarkMode: isDarkMode,
      userPublicKey: _userPublicKey,
      userMnemonic: _userMnemonic,
      onRefresh: _loadUserPosts,
      emptyMessage: 'No posts found',
      emptySubMessage: 'Create your first post to see it here',
    );
  }
} 
