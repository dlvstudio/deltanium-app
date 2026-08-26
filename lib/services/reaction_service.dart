import 'dart:convert';
import 'dart:typed_data';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:http/http.dart' as http;

class ReactionService {
  static const List<String> supportedReactions = <String>[
    'like',
    'love',
    'laugh',
    'wow',
    'sad',
    'angry',
  ];

  /// Send a reaction (type = "react") for a post. UI-first stub: logs and returns success.
  static Future<bool> sendReaction({
    required String postFileId,
    required String nodeEndpoint,
    required String reactionKind,
    required String userPublicKey,
    required String userMnemonic,
    String? postOwnerPublicKey,
    String postEncryptedType = 'public',
    String? contractId,
    String? fileId,
    String? firstBlockId,
  }) async {
    try {
      if (!supportedReactions.contains(reactionKind)) {
        AppLogger.log('ReactionService: Unsupported reaction "$reactionKind"');
        return false;
      }
      AppLogger.log('ReactionService: sendReaction react="$reactionKind" post=$postFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}...');

      final isPublicPost = postEncryptedType == 'public';
      final now = DateTime.now().toIso8601String();
      final effectiveFileId = fileId ?? _generateId(prefix: 'react');
      final effectiveFirstBlockId = firstBlockId ?? _generateId(prefix: 'b0');

      if (isPublicPost) {
        // Public reaction: public metadata + plaintext block0
        final metadata = {
          'fileId': effectiveFileId,
          'firstBlockId': effectiveFirstBlockId,
          'type': 'react',
          'parentFileId': postFileId,
          'kind': reactionKind,
          'isPublic': true,
          'shareType': 'public',
          'encryptedType': 'public',
          'recipientPubKey': '',
          'version': '2.0',
          'ownerPubKey': CryptoService.normalizePublicKey(userPublicKey),
          if (contractId != null) 'contractId': contractId,
        };
        final block0 = {
          'reactorPublicKey': CryptoService.normalizePublicKey(userPublicKey),
          'parentFileId': postFileId,
          'kind': reactionKind,
          'createdAt': now,
        };

        // Upload metadata and block0
        final metaOk = await _uploadRaw(
          nodeEndpoint: nodeEndpoint,
          path: '/api/file/upload-metadata-raw',
          content: Uint8List.fromList(utf8.encode(json.encode(metadata))),
          fileName: '${effectiveFileId}_metadata.json',
          contentType: 'application/json',
          userPublicKey: userPublicKey,
          userMnemonic: userMnemonic,
        );
        if (!metaOk) return false;

        final blockOk = await _uploadRaw(
          nodeEndpoint: nodeEndpoint,
          path: '/api/file/upload-file-block-raw',
          content: Uint8List.fromList(utf8.encode(json.encode(block0))),
          fileName: effectiveFirstBlockId,
          contentType: 'application/octet-stream',
          userPublicKey: userPublicKey,
          userMnemonic: userMnemonic,
          extraHeaders: {
            'X-Block-Id': effectiveFirstBlockId,
            'X-File-Id': effectiveFileId,
            'X-Block-Index': '0',
            if (contractId != null) 'X-Contract-Id': contractId, // 🆕 Pass ContractId
          },
        );
        // Store submits StorageOperation to blockchain via contract
        return blockOk;
      }

      // Encrypted reaction: ECIES per-recipient
      if (postOwnerPublicKey == null || postOwnerPublicKey.isEmpty) {
        AppLogger.log('ReactionService: Missing post owner key for encrypted reaction');
        return false;
      }

      final contentBytes = Uint8List.fromList(utf8.encode(json.encode({
        'reactorPublicKey': CryptoService.normalizePublicKey(userPublicKey),
        'parentFileId': postFileId,
        'kind': reactionKind,
        'createdAt': now,
      })));

      final result = await FileCryptoService.encryptAndSplitFile(
        fileData: contentBytes,
        fileName: 'react_${DateTime.now().millisecondsSinceEpoch}.json',
        ownerPublicKey: userPublicKey,
        mnemonic: userMnemonic,
        sharedWithPublicKeys: [postOwnerPublicKey, userPublicKey],
        fileType: 'react',
        relatedFiles: null,
        onProgress: null,
        encryptedType: 'encrypted',
        shareType: 'specific',
        policyTag: null,
        capsuleFor: null,
        policyScheme: null,
      );

      final metadataEntries = List<Map<String, dynamic>>.from(result['metadataEntries'] as List);
      final blocks = List<Map<String, dynamic>>.from(result['blocks'] as List);

      // Upload all metadata entries
      for (int i = 0; i < metadataEntries.length; i++) {
        final entry = metadataEntries[i];
        // add react linkage fields (non-sensitive) for indexing
        entry['type'] = 'react';
        entry['parentFileId'] = postFileId;
        entry['kind'] = reactionKind;
        entry['ownerPubKey'] = CryptoService.normalizePublicKey(userPublicKey);
        if (contractId != null) entry['contractId'] = contractId;

        final ok = await _uploadRaw(
          nodeEndpoint: nodeEndpoint,
          path: '/api/file/upload-metadata-raw',
          content: Uint8List.fromList(utf8.encode(json.encode(entry))),
          fileName: '${entry['fileId']}_metadata_$i.json',
          contentType: 'application/json',
          userPublicKey: userPublicKey,
          userMnemonic: userMnemonic,
        );
        if (!ok) return false;
      }

      // Separate metadata blocks (index 0) and content (we only expect block 0 for tiny content, but handle generically)
      for (final block in blocks) {
        final blockId = block['blockId'] as String;
        final blockIndex = block['blockIndex'] as int;
        final encryptedContent = block['encryptedContent'] as Uint8List;

        // find fileId to attribute block 0 to
        String fileIdForBlock;
        if (blockIndex == 0) {
          final found = metadataEntries.firstWhere((e) => e['firstBlockId'] == blockId, orElse: () => metadataEntries.first);
          fileIdForBlock = found['fileId'] as String;
        } else {
          // use owner's first entry for content blocks
          fileIdForBlock = metadataEntries.first['fileId'] as String;
        }

        final ok = await _uploadRaw(
          nodeEndpoint: nodeEndpoint,
          path: '/api/file/upload-file-block-raw',
          content: encryptedContent,
          fileName: blockId,
          contentType: 'application/octet-stream',
          userPublicKey: userPublicKey,
          userMnemonic: userMnemonic,
          extraHeaders: {
            'X-Block-Id': blockId,
            'X-File-Id': fileIdForBlock,
            'X-Block-Index': blockIndex.toString(),
            if (contractId != null) 'X-Contract-Id': contractId, // 🆕 Pass ContractId
          },
        );
        if (!ok) return false;
      }

      // Store submits StorageOperation to blockchain via contract
      return true;
    } catch (e) {
      AppLogger.log('ReactionService error: $e');
      return false;
    }
  }

  /// Get reactions summary for a post (counts per kind, total, my reaction)
  static Future<Map<String, dynamic>?> getReactions({
    required String postFileId,
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
  }) async {
    try {
      AppLogger.log('ReactionService: getReactions post=$postFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}...');
      final path = '/api/post/reactions/$postFileId';
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final bodyHash = '';
      final dataToSign = '$method$path$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, userMnemonic);
      final resp = await http.get(
        Uri.parse('$nodeEndpoint$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      if (resp.statusCode == 200) {
        final responseBody = json.decode(resp.body) as Map<String, dynamic>;
        AppLogger.log('ReactionService: getReactions success: $responseBody');
        return responseBody;
      } else {
        AppLogger.log('ReactionService: getReactions failed ${resp.statusCode}: ${resp.body}');
        return null;
      }
    } catch (e) {
      AppLogger.log('ReactionService: getReactions error: $e');
      return null;
    }
  }

  /// Remove reaction for a post (UI-first stub)
  static Future<bool> removeReaction({
    required String postFileId,
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
    String? reactionKind,
  }) async {
    try {
      AppLogger.log('ReactionService: removeReaction post=$postFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}...');
      final kindParam = (reactionKind != null && reactionKind.isNotEmpty) ? '?kind=$reactionKind' : '';
      final path = '/api/post/reactions/$postFileId$kindParam';
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'DELETE';
      final bodyHash = '';
      final dataToSign = '$method$path$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, userMnemonic);
      final resp = await http.delete(
        Uri.parse('$nodeEndpoint$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      return resp.statusCode == 200;
    } catch (e) {
      AppLogger.log('ReactionService error: $e');
      return false;
    }
  }

  static Map<String, String> generateIds() {
    return {
      'fileId': _generateId(prefix: 'react'),
      'firstBlockId': _generateId(prefix: 'b0'),
    };
  }

  static String _generateId({required String prefix}) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = (DateTime.now().microsecondsSinceEpoch % 9973).toString().padLeft(4, '0');
    return '${prefix}_${ts}_$rand';
  }

  static Future<bool> _uploadRaw({
    required String nodeEndpoint,
    required String path,
    required Uint8List content,
    required String fileName,
    required String contentType,
    required String userPublicKey,
    required String userMnemonic,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final uri = Uri.parse('$nodeEndpoint$path');
      final digest = await CryptoService.hashSHA256(content);
      final bodyHash = base64.encode(digest);
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'POST';
      final pathForSigning = Uri.parse(path).path;
      final dataToSign = '$method$pathForSigning$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, userMnemonic);
      final headers = {
        'Content-Type': contentType,
        'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
        'X-Timestamp': timestamp,
        'X-Signature': signature,
      };
      if (extraHeaders != null) headers.addAll(extraHeaders);
      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..bodyBytes = content;
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200) return true;
      AppLogger.log('ReactionService: upload failed ${response.statusCode}: ${response.body}');
      return false;
    } catch (e) {
      AppLogger.log('ReactionService: _uploadRaw error: $e');
      return false;
    }
  }

  /// Prepare a reaction with storage cost confirmation.
  /// Returns fee info for UI to show confirmation dialog.
  static Future<Map<String, dynamic>> prepareReactionWithStorageCost({
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
    required String storageNodePublicKey,
    String? fileId,
    int durationDays = 365,
  }) async {
    try {
      // Estimate size: metadata (~300 bytes) + block0 (~200 bytes)
      const estimatedSize = 500;
      final effectiveFileId = fileId ?? _generateId(prefix: 'react');

      final signer = RequestSigner(
        publicKey: userPublicKey,
        mnemonic: userMnemonic,
      );

      final now = DateTime.now();
      final startDate = now.millisecondsSinceEpoch ~/ 1000;
      final endDate = now.add(Duration(days: durationDays)).millisecondsSinceEpoch ~/ 1000;

      final body = jsonEncode({
        'contractType': 'TimeFixed',
        'startDateUnix': startDate,
        'endDateUnix': endDate,
        'totalFileSize': estimatedSize,
        'fileIds': [effectiveFileId],
      });

      final signature = await signer.signRequest(
        'POST',
        '/api/storage/contracts/create',
        Uint8List.fromList(utf8.encode(body)),
      );
      final normalizedPubKey = signer.getPublicKeyBase64();

      final response = await http.post(
        Uri.parse('$nodeEndpoint/api/storage/contracts/create'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': normalizedPubKey,
          'X-Timestamp': signature['timestamp']!,
          'X-Signature': signature['signature']!,
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final totalFee = (data['totalFee'] as num?)?.toDouble() ?? 0.0;
        return {
          'success': true,
          'contractId': data['contractId'],
          'fileId': effectiveFileId,
          'totalFee': totalFee,
          'feeBasis': data['feeBasis'] ?? 'Storage node calculated fee',
          'estimatedSize': estimatedSize,
          'durationDays': durationDays,
          'estimatedCostPerDay': totalFee / (durationDays > 0 ? durationDays : 1),
        };
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      AppLogger.log('ReactionService: prepareReactionWithStorageCost error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Sign and approve a contract (after user confirms fee)
  static Future<bool> signContract({
    required String nodeEndpoint,
    required String contractId,
    required String userPublicKey,
    required String userMnemonic,
    required String storageNodePublicKey,
    required double totalFee,
    required int totalFileSize,
    required int startDateUnix,
    int? endDateUnix,
  }) async {
    try {
      final signer = RequestSigner(
        publicKey: userPublicKey,
        mnemonic: userMnemonic,
      );
      final contractService = StorageContractService(
        storeBaseUrl: nodeEndpoint,
        signer: signer,
      );

      final contract = await contractService.getContract(
        contractId: contractId,
        userPublicKey: userPublicKey,
      );
      if (contract == null) return false;

      final signed = await contractService.approveAndSignContract(
        contract: contract,
        appPrivateKey: userMnemonic,
      );
      return signed != null;
    } catch (e) {
      AppLogger.log('ReactionService: signContract error: $e');
      return false;
    }
  }
}


