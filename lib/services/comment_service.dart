import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/features/file_manager/file_upload_service.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart' show kIsWeb;

class CommentService {
  /// Send a comment (type = "comment") for a post
  /// shareType: "author" (chỉ author của post xem) hoặc "public" (mọi người xem)
  /// attachedMedia: List of media files to attach (images)
  static Future<bool> sendComment({
    required String postFileId,
    required String nodeEndpoint,
    required String commentText,
    required String userPublicKey,
    required String userMnemonic,
    String? postOwnerPublicKey,
    String shareType = 'author',
    List<Map<String, dynamic>>? attachedMedia,
    Function(String)? onProgress,
    String? contractId,
    String? fileId,
    String? firstBlockId,
  }) async {
    try {
      if (commentText.trim().isEmpty) {
        AppLogger.log('CommentService: Comment text is empty');
        return false;
      }

      AppLogger.log('CommentService: sendComment post=$postFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}... shareType=$shareType');

      // 🆕 Step 1: Upload attached media files if any
      List<Map<String, dynamic>>? uploadedMedia;
      if (attachedMedia != null && attachedMedia.isNotEmpty) {
        AppLogger.log('CommentService: Starting upload of ${attachedMedia.length} media files');
        onProgress?.call('Uploading media files...');
        uploadedMedia = [];
        final fileUploadService = FileUploadService();
        
        // Determine sharing for media (same as comment)
        final List<String>? sharedWithUsers = shareType == 'author' && postOwnerPublicKey != null
            ? [postOwnerPublicKey, userPublicKey]
            : null;
        
        AppLogger.log('CommentService: Media sharing - shareType=$shareType, sharedWithUsers=${sharedWithUsers?.length ?? 0}');
        
        for (int i = 0; i < attachedMedia.length; i++) {
          final media = attachedMedia[i];
          try {
            AppLogger.log('CommentService: Processing media $i/${attachedMedia.length}: ${media['name']}, keys: ${media.keys.toList()}');
            onProgress?.call('Uploading ${media['name'] ?? 'file'}...');
            
            // Prepare file bytes
            late Uint8List fileBytes;
            if (kIsWeb && media.containsKey('bytes')) {
              final bytes = media['bytes'] as List<int>;
              fileBytes = Uint8List.fromList(bytes);
              AppLogger.log('CommentService: Read ${fileBytes.length} bytes from web bytes');
            } else if (!kIsWeb && media.containsKey('path')) {
              final path = media['path'] as String;
              fileBytes = await File(path).readAsBytes();
              AppLogger.log('CommentService: Read ${fileBytes.length} bytes from path: $path');
            } else {
              AppLogger.log('CommentService: Cannot read file bytes for ${media['name']} - missing path/bytes. Keys: ${media.keys.toList()}');
              continue;
            }
            
            // Upload file
            AppLogger.log('CommentService: Calling uploadEncryptedFile for ${media['name']}');
            final uploadResult = await fileUploadService.uploadEncryptedFile(
              fileData: fileBytes,
              fileName: media['name'] ?? 'file.dat',
              publicKey: userPublicKey,
              mnemonic: userMnemonic,
              sharedWithUsers: sharedWithUsers,
              selectedNode: {'endpoint': nodeEndpoint},
              onProgress: onProgress,
              fileType: 'file',
              shareType: shareType == 'author' ? 'specific' : shareType,
              parentFileId: postFileId, // 🆕 Set ParentFileId for comment media
              contractId: contractId, // 🆕 Pass ContractId for blockchain integration
            );
            
            AppLogger.log('CommentService: Upload result for ${media['name']}: success=${uploadResult['success']}, fileId=${uploadResult['fileId']}, error=${uploadResult['error']}');
            
            if (uploadResult['success'] == true) {
              // 🆕 DEBUG: Log metadata entries count to verify zero-knowledge sharing
              AppLogger.log('CommentService: Media upload successful - fileId=${uploadResult['fileId']}, sharedWithUsers=${sharedWithUsers?.length ?? 0}');
              if (sharedWithUsers != null && sharedWithUsers.isNotEmpty) {
                AppLogger.log('CommentService: Media should have ${sharedWithUsers.length + 1} metadata entries (owner + ${sharedWithUsers.length} shared)');
              }
              
              uploadedMedia.add({
                'fileId': uploadResult['fileId'],
                'type': media['type'] ?? 'image',
                'name': media['name'] ?? 'file',
                'order': uploadedMedia.length,
                'nodeEndpoint': nodeEndpoint,
                'size': uploadResult['fileSize'] ?? fileBytes.length,
                'extension': media['extension'] ?? 'unknown',
                'mimeType': media['mimeType'] ?? 'image/jpeg',
                'encryptedKey': uploadResult['encryptedKey'],
              });
              AppLogger.log('CommentService: Successfully uploaded media file ${uploadResult['fileId']}');
            } else {
              AppLogger.log('CommentService: Failed to upload media: ${uploadResult['error']}');
            }
          } catch (e) {
            AppLogger.log('CommentService: Error uploading media: $e');
            // Continue with other files
          }
        }
        
        AppLogger.log('CommentService: Uploaded ${uploadedMedia.length}/${attachedMedia.length} media files');
      }

      final now = DateTime.now().toIso8601String();
      final effectiveFileId = fileId ?? _generateId(prefix: 'comment');
      final effectiveFirstBlockId = firstBlockId ?? _generateId(prefix: 'b0');

      // 🆕 Build relatedFiles from uploaded media
      List<Map<String, dynamic>>? relatedFiles;
      if (uploadedMedia != null && uploadedMedia.isNotEmpty) {
        relatedFiles = uploadedMedia.map((media) => {
          'fileId': media['fileId'],
          'type': media['type'] ?? 'image',
          'caption': media['name'] ?? '',
          'order': media['order'] ?? 0,
          'relationshipType': 'attachment',
          'fileName': media['name'] ?? 'Unknown file',
          'fileSize': media['size'] ?? 0,
          'nodeEndpoint': media['nodeEndpoint'] ?? nodeEndpoint,
          'encryptedKey': media['encryptedKey'] ?? '',
        }).toList();
      }

      // Public comment: public metadata + plaintext block0
      if (shareType == 'public') {
        final metadata = {
          'fileId': effectiveFileId,
          'firstBlockId': effectiveFirstBlockId,
          'type': 'comment',
          'parentFileId': postFileId,
          'isPublic': true,
          'shareType': 'public',
          'encryptedType': 'public',
          'recipientPubKey': '',
          'version': '2.0',
          'ownerPubKey': CryptoService.normalizePublicKey(userPublicKey),
          if (contractId != null) 'contractId': contractId,
        };
        final block0 = {
          'commenterPublicKey': CryptoService.normalizePublicKey(userPublicKey),
          'parentFileId': postFileId,
          'text': commentText,
          'createdAt': now,
          if (relatedFiles != null) 'relatedFiles': relatedFiles, // 🆕 Add relatedFiles
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

      // Encrypted comment: Chỉ chia sẻ với author của post
      if (shareType == 'author') {
        if (postOwnerPublicKey == null || postOwnerPublicKey.isEmpty) {
          AppLogger.log('CommentService: Missing post owner key for author-only comment');
          return false;
        }

        final contentBytes = Uint8List.fromList(utf8.encode(json.encode({
          'commenterPublicKey': CryptoService.normalizePublicKey(userPublicKey),
          'parentFileId': postFileId,
          'text': commentText,
          'createdAt': now,
          if (relatedFiles != null) 'relatedFiles': relatedFiles, // 🆕 Add relatedFiles
        })));

        // Chia sẻ với author của post và chính người comment
        final result = await FileCryptoService.encryptAndSplitFile(
          fileData: contentBytes,
          fileName: 'comment_${DateTime.now().millisecondsSinceEpoch}.json',
          ownerPublicKey: userPublicKey,
          mnemonic: userMnemonic,
          sharedWithPublicKeys: [postOwnerPublicKey, userPublicKey],
          fileType: 'comment',
          relatedFiles: relatedFiles, // 🆕 Pass relatedFiles
          onProgress: onProgress,
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
          // add comment linkage fields (non-sensitive) for indexing
          entry['type'] = 'comment';
          entry['parentFileId'] = postFileId;
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

        // Upload blocks
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
      }

      AppLogger.log('CommentService: Invalid shareType: $shareType');
      return false;
    } catch (e) {
      AppLogger.log('CommentService error: $e');
      return false;
    }
  }

  /// Get comments for a post
  static Future<List<Map<String, dynamic>>?> getComments({
    required String postFileId,
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
  }) async {
    try {
      AppLogger.log('CommentService: getComments post=$postFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}...');
      final path = '/api/post/comments/$postFileId';
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
        AppLogger.log('CommentService: getComments - Response body keys: ${responseBody.keys.toList()}');
        AppLogger.log('CommentService: getComments - Response body: ${resp.body.substring(0, resp.body.length > 500 ? 500 : resp.body.length)}');
        
        // Handle both PascalCase (Comments) and camelCase (comments)
        final comments = responseBody['Comments'] as List<dynamic>? ?? 
                        responseBody['comments'] as List<dynamic>?;
        final commentCount = comments?.length ?? 0;
        AppLogger.log('CommentService: getComments success: $commentCount comments');
        if (comments != null && comments.isNotEmpty) {
          AppLogger.log('CommentService: getComments - First comment keys: ${(comments.first as Map).keys.toList()}');
          return comments.map((c) => Map<String, dynamic>.from(c as Map)).toList();
        }
        AppLogger.log('CommentService: getComments - No comments found in response. Response keys: ${responseBody.keys.toList()}');
        return [];
      } else {
        AppLogger.log('CommentService: getComments failed ${resp.statusCode}: ${resp.body}');
        return null;
      }
    } catch (e) {
      AppLogger.log('CommentService: getComments error: $e');
      return null;
    }
  }

  /// Delete a comment
  static Future<bool> deleteComment({
    required String commentFileId,
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
  }) async {
    try {
      AppLogger.log('CommentService: deleteComment comment=$commentFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}...');
      final path = '/api/post/comments/$commentFileId';
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
      AppLogger.log('CommentService error: $e');
      return false;
    }
  }

  static Map<String, String> generateIds() {
    return {
      'fileId': _generateId(prefix: 'comment'),
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
      AppLogger.log('CommentService: upload failed ${response.statusCode}: ${response.body}');
      return false;
    } catch (e) {
      AppLogger.log('CommentService: _uploadRaw error: $e');
      return false;
    }
  }

  /// Prepare a comment with storage cost confirmation.
  /// Returns fee info for UI to show confirmation dialog.
  static Future<Map<String, dynamic>> prepareCommentWithStorageCost({
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
    required String storageNodePublicKey,
    required String commentText,
    String? fileId,
    int durationDays = 365,
  }) async {
    try {
      // Estimate size: metadata (~400 bytes) + block0 (~commentText.length + 200 bytes)
      final estimatedSize = 600 + commentText.length;
      final effectiveFileId = fileId ?? _generateId(prefix: 'comment');

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
      AppLogger.log('CommentService: prepareCommentWithStorageCost error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Sign and approve a contract (after user confirms fee)
  static Future<bool> signContract({
    required String nodeEndpoint,
    required String contractId,
    required String userPublicKey,
    required String userMnemonic,
  }) async {
    try {
      final signer = RequestSigner(
        publicKey: userPublicKey,
        mnemonic: userMnemonic,
      );
      final contractService = StorageContractService(
        storeBaseUrl: nodeEndpoint,
        signer: signer,
      );      final contract = await contractService.getContract(
        contractId: contractId,
        userPublicKey: userPublicKey,
      );
      if (contract == null) return false;      final signed = await contractService.approveAndSignContract(
        contract: contract,
        appPrivateKey: userMnemonic,
      );
      return signed != null;
    } catch (e) {
      AppLogger.log('CommentService: signContract error: $e');
      return false;
    }
  }
}
