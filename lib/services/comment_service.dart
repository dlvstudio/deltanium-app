import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/services/store_placement.dart';
import 'package:deltanium_app/services/store_delete_service.dart';
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
    /// Unused: every Store holding the comment gets its own contract (StorePlacement).
    String? contractId,
    String? fileId,
    String? firstBlockId,
    /// Confirms Central's exact charge for each attached file before it is stored; false skips that file.
    Future<bool> Function(String fileName, int sizeBytes, double charge, double monthly)? confirmMediaCharge,
    /// The charge the user confirmed for the comment; checked against the real size before it is stored.
    double? confirmedCharge,
    Future<bool> Function(double charge)? reconfirmCharge,
  }) async {
    try {
      if (commentText.trim().isEmpty) {
        AppLogger.log('CommentService: Comment text is empty');
        return false;
      }
      if (shareType != 'public' && shareType != 'author') {
        AppLogger.log('CommentService: Invalid shareType: $shareType');
        return false;
      }
      if (shareType == 'author' && (postOwnerPublicKey == null || postOwnerPublicKey.isEmpty)) {
        AppLogger.log('CommentService: Missing post owner key for author-only comment');
        return false;
      }
      AppLogger.log('CommentService: sendComment post=$postFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}... shareType=$shareType');

      // A comment (and its files) goes to the Stores holding the post: readers look for it there, and a Store
      // only takes a comment whose post it holds.
      final nodes = await StorePlacement.nodesHolding(postFileId, nodeEndpoint);
      final primaryEndpoint = '${nodes.first['httpsEndpoint'] ?? nodes.first['endpoint']}';

      // 1. Attached files, stored like any item on the same Stores.
      final relatedFiles = <Map<String, dynamic>>[];
      if (attachedMedia != null && attachedMedia.isNotEmpty) {
        onProgress?.call('Uploading media files...');
        final uploader = FileUploadService();
        final sharedWithUsers = shareType == 'author' ? [postOwnerPublicKey!, userPublicKey] : null;
        for (final media in attachedMedia) {
          try {
            final Uint8List fileBytes;
            if (kIsWeb && media.containsKey('bytes')) {
              fileBytes = Uint8List.fromList(media['bytes'] as List<int>);
            } else if (!kIsWeb && media.containsKey('path')) {
              fileBytes = await File(media['path'] as String).readAsBytes();
            } else {
              AppLogger.log('CommentService: Cannot read file bytes for ${media['name']}');
              continue;
            }
            onProgress?.call('Uploading ${media['name'] ?? 'file'}...');
            final up = await uploader.uploadEncryptedFile(
              fileData: fileBytes,
              fileName: media['name'] ?? 'file.dat',
              publicKey: userPublicKey,
              mnemonic: userMnemonic,
              sharedWithUsers: sharedWithUsers,
              selectedNode: nodes.first,
              replicaNodes: nodes.skip(1).toList(),
              onlyTheseNodes: true,
              onProgress: onProgress,
              fileType: 'file',
              shareType: shareType == 'author' ? 'specific' : shareType,
              parentFileId: postFileId,
              confirmCharge: confirmMediaCharge == null
                  ? null
                  : (charge, monthly) =>
                      confirmMediaCharge(media['name']?.toString() ?? 'file', fileBytes.length, charge, monthly),
            );
            if (up['success'] != true) {
              AppLogger.log('CommentService: Failed to upload media: ${up['error']}');
              continue;
            }
            relatedFiles.add({
              'fileId': up['fileId'],
              'type': media['type'] ?? 'image',
              'caption': media['name'] ?? '',
              'order': relatedFiles.length,
              'relationshipType': 'attachment',
              'fileName': media['name'] ?? 'Unknown file',
              'fileSize': up['fileSize'] ?? fileBytes.length,
              'nodeEndpoint': up['nodeEndpoint'] ?? primaryEndpoint,
              'encryptedKey': up['encryptedKey'] ?? '',
            });
          } catch (e) {
            AppLogger.log('CommentService: Error uploading media: $e');
          }
        }
      }

      // 2. The comment: one public entry with a plaintext block, or entries for the post's author and the commenter.
      final now = DateTime.now().toUtc().toIso8601String();
      final effectiveFileId = fileId ?? _generateId(prefix: 'comment');
      final content = {
        'commenterPublicKey': CryptoService.normalizePublicKey(userPublicKey),
        'parentFileId': postFileId,
        'text': commentText,
        'createdAt': now,
        if (relatedFiles.isNotEmpty) 'relatedFiles': relatedFiles,
      };
      final List<Map<String, dynamic>> metadataEntries;
      final List<Map<String, dynamic>> blocks;
      if (shareType == 'public') {
        final effectiveFirstBlockId = firstBlockId ?? _generateId(prefix: 'b0');
        metadataEntries = [
          {
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
          }
        ];
        blocks = [
          {'blockId': effectiveFirstBlockId, 'blockIndex': 0, 'encryptedContent': Uint8List.fromList(utf8.encode(json.encode(content)))},
        ];
      } else {
        final result = await FileCryptoService.encryptAndSplitFile(
          fileData: Uint8List.fromList(utf8.encode(json.encode(content))),
          fileName: 'comment_${DateTime.now().millisecondsSinceEpoch}.json',
          ownerPublicKey: userPublicKey,
          mnemonic: userMnemonic,
          sharedWithPublicKeys: [postOwnerPublicKey!, userPublicKey],
          fileType: 'comment',
          relatedFiles: relatedFiles.isEmpty ? null : relatedFiles,
          onProgress: onProgress,
          encryptedType: 'encrypted',
          shareType: 'specific',
          policyTag: null,
          capsuleFor: null,
          policyScheme: null,
        );
        metadataEntries = [
          for (final e in result['metadataEntries'] as List)
            {
              ...Map<String, dynamic>.from(e as Map),
              'type': 'comment',
              'parentFileId': postFileId,
              'ownerPubKey': CryptoService.normalizePublicKey(userPublicKey),
            }
        ];
        blocks = [for (final b in result['blocks'] as List) Map<String, dynamic>.from(b as Map)];
      }

      // 3. Central's charge for the real size (re-confirmed if it differs from the one shown), then store it.
      final quote = await WalletService.quoteChargeDetail(
        sizeBytes: StorePlacement.billableBytes(metadataEntries, blocks),
        storeNodes: 1,
        replicas: AppConstants.replicationFactor,
        social: true,
      );
      if (quote == null) return false;
      if (confirmedCharge != null && quote.charge != confirmedCharge) {
        if (reconfirmCharge == null || !await reconfirmCharge(quote.charge)) return false;
      }
      await StorePlacement.place(
        escrowFileId: '${metadataEntries.first['fileId']}',
        metadataEntries: metadataEntries,
        blocks: blocks,
        nodes: nodes,
        publicKey: userPublicKey,
        mnemonic: userMnemonic,
        charge: quote.charge,
        replicas: AppConstants.replicationFactor,
        social: true,
        onProgress: onProgress,
      );
      return true;
    } catch (e) {
      AppLogger.log('CommentService error: $e');
      return false;
    }
  }

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
    List<String> attachmentFileIds = const [],
  }) async {
    try {
      AppLogger.log('CommentService: deleteComment comment=$commentFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}...');
      final gone = await StoreDeleteService.deleteEverywhere(
        fileId: commentFileId,
        path: '/api/post/comments/$commentFileId',
        knownEndpoint: nodeEndpoint,
        userPublicKey: userPublicKey,
        userMnemonic: userMnemonic,
      );
      // Stop paying for the deleted comment's storage (and its images).
      if (gone) {
        WalletService.stopRenewal(<String>{commentFileId, ...attachmentFileIds.where((id) => id.isNotEmpty)}.toList())
            .ignore();
      }
      return gone;
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
      // What Central takes for this social item (0 within the monthly social allowance, if the network has one;
      // otherwise small items are billed the minimum fee). sendComment re-checks the real size. No Store contract
      // here: sendComment makes one with each Store that stores the comment.
      final estimatedSize = 600 + commentText.length;
      final quote = await WalletService.quoteChargeDetail(
        sizeBytes: estimatedSize,
        storeNodes: 1,
        replicas: AppConstants.replicationFactor,
        social: true,
      );
      if (quote == null) return {'success': false, 'error': 'Could not get the storage price from Central'};
      return {
        'success': true,
        'contractId': null,
        'fileId': fileId ?? _generateId(prefix: 'comment'),
        'totalFee': quote.charge,
        'feeBasis': 'Central storage charge',
        'estimatedSize': estimatedSize,
        'monthlyFee': quote.monthly,
        'durationDays': durationDays,
        'estimatedCostPerDay': quote.charge / (durationDays > 0 ? durationDays : 1),
      };
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
