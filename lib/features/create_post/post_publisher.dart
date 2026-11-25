import 'dart:convert';
import 'dart:typed_data';

import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/features/file_manager/file_upload_service.dart';
import 'package:deltanium_app/models/storage_contract.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/post_service.dart';
import 'package:deltanium_app/services/pre_service.dart';
import 'package:deltanium_app/services/pre_keys.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One file attached to a post.
class PostMediaInput {
  final Uint8List bytes;
  final String name;
  final String type;
  final String extension;

  const PostMediaInput({required this.bytes, required this.name, this.type = 'file', this.extension = 'unknown'});

  int get size => bytes.length;
}

/// What to publish. [preTag] is set for a followers post that uses Umbral PRE (the post is encrypted
/// once under the tag and followers get re-encryption keys); [rekeyFor] lists who receives them.
class PostPublishRequest {
  final String text;
  final List<PostMediaInput> media;
  final String shareType; // 'public' | 'me' | 'followers'
  final String encryptedType; // 'public' | 'encrypted'
  final List<String> recipients; // metadata entries (the author, or each follower without PRE)
  final List<String> sharedWithPublicKeys; // extra readers of the attached files
  final String? preTag;
  final List<String> rekeyFor;
  final String? authorName;
  final List<String> tags;

  const PostPublishRequest({
    required this.text,
    this.media = const [],
    required this.shareType,
    required this.encryptedType,
    required this.recipients,
    this.sharedWithPublicKeys = const [],
    this.preTag,
    this.rekeyFor = const [],
    this.authorName,
    this.tags = const [],
  });
}

class PostPublishResult {
  final String postId;
  final String fileId;
  final Map<String, dynamic> primaryNode;
  final List<Map<String, dynamic>> uploadedMedia;
  final Map<String, bool> rekeys;

  const PostPublishResult({
    required this.postId,
    required this.fileId,
    required this.primaryNode,
    required this.uploadedMedia,
    required this.rekeys,
  });
}

/// The user declined the storage fee.
class PostPublishCancelled implements Exception {
  @override
  String toString() => 'Upload cancelled';
}

/// Publishes a post the way the create-post screen does: pick Store nodes, upload attached files
/// (N-of-M replicas), build the post, agree and sign the storage contract, pay, upload the post's
/// metadata and blocks, then hand out PRE re-encryption keys for followers posts.
/// The screen only adds UI (progress, the fee dialog, messages); tests drive this class directly.
class PostPublisher {
  final String publicKey;
  final String mnemonic;
  final String apiBaseUrl;

  /// Shown the storage quote; return false to cancel before anything is paid or uploaded.
  final Future<bool> Function(Map<String, dynamic> storageInfo) confirmStorage;
  final void Function(String message)? onProgress;

  /// Non-fatal problems the user should hear about (e.g. a chain submission that will be retried).
  final void Function(String message)? onWarning;

  PostPublisher({
    required this.publicKey,
    required this.mnemonic,
    required this.confirmStorage,
    this.onProgress,
    this.onWarning,
    String? apiBaseUrl,
  }) : apiBaseUrl = apiBaseUrl ?? AppConstants.apiBaseUrl;

  void _progress(String m) => onProgress?.call(m);

  Future<PostPublishResult> publish(PostPublishRequest r) async {
    String? paidUnuploadedFileId; // paid but not fully uploaded: a failure cancels the escrow
    try {
      final storeNodes = await StoreNodeDirectory.listNodes();
      if (storeNodes.isEmpty) throw Exception('No available storage nodes found');
      final selectedNodes = StoreNodeDirectory.pickForUpload(storeNodes, AppConstants.replicationFactor);
      final node = selectedNodes.first;
      final replicaNodes = selectedNodes.length > 1 ? selectedNodes.sublist(1) : <Map<String, dynamic>>[];
      AppLogger.log('PostPublisher: ${selectedNodes.length} store node(s); primary=${node['endpoint']}');

      // 1. Attached files, each on N Stores. They are paid only after the user confirms the total (step 3).
      final uploadedMedia = <Map<String, dynamic>>[];
      final pendingMedia = <({String name, Map<String, dynamic> pending})>[];
      for (final m in r.media) {
        try {
          final up = await _uploadMedia(m, node, replicaNodes, r);
          uploadedMedia.add({
            'fileId': up['fileId'],
            'name': m.name,
            'type': m.type,
            'url': '${node['endpoint']}/api/file/download/${up['fileId']}',
            'nodeId': node['id'],
            'nodeEndpoint': node['endpoint'],
            'size': m.size,
            'extension': m.extension,
            'encryptedKey': up['encryptedKey'],
          });
          final pending = up['pendingRegistration'] as Map<String, dynamic>?;
          if (pending != null) pendingMedia.add((name: m.name, pending: pending));
        } catch (e) {
          // One failed attachment does not stop the post (as before).
          AppLogger.log('PostPublisher: attachment ${m.name} failed: $e');
        }
      }

      // 2. The post itself.
      _progress(uploadedMedia.isEmpty ? 'Creating text post...' : 'Creating post...');
      final policyTag = r.preTag;
      final postResult = await PostService.createPost(
        textContent: r.text,
        authorPublicKey: publicKey,
        authorName: r.authorName,
        mnemonic: mnemonic,
        attachedMedia: uploadedMedia.isEmpty
            ? null
            : [
                for (var i = 0; i < uploadedMedia.length; i++)
                  {
                    'fileId': uploadedMedia[i]['fileId'],
                    'type': uploadedMedia[i]['type'],
                    'caption': uploadedMedia[i]['name'],
                    'order': i,
                    'nodeEndpoint': uploadedMedia[i]['nodeEndpoint'],
                    'nodeId': uploadedMedia[i]['nodeId'],
                    'size': uploadedMedia[i]['size'],
                    'extension': uploadedMedia[i]['extension'],
                    'encryptedKey': uploadedMedia[i]['encryptedKey'],
                  }
              ],
        sharedWithUsers: r.recipients,
        encryptedType: r.encryptedType,
        shareType: r.shareType,
        tags: r.tags,
        policyTag: policyTag,
        capsuleFor: policyTag != null ? 'tag' : null,
        policyScheme: policyTag != null ? PreKeys.schemeFor(policyTag) : null,
        onProgress: onProgress,
      );

      // 3. Storage cost: Central's exact charge for each attachment and the post (the same inputs registration
      // sends), shown once as a total; the Store contract records the post's charge, so the fee on chain is the fee paid.
      _progress('Calculating storage cost...');
      final metadataEntries = postResult['metadataEntries'] as List<Map<String, dynamic>>;
      final postBlocks = postResult['blocks'] as List<Map<String, dynamic>>;
      final postFileId = postResult['fileId'] as String;
      final lines = <StorageChargeItem>[];
      for (final m in pendingMedia) {
        final p = m.pending;
        final c = await WalletService.quoteCharge(
          sizeBytes: p['fileSize'] as int,
          storeNodes: (p['storeNodeIds'] as List).length,
          months: p['months'] as int? ?? 12,
        );
        if (c == null) throw Exception('Could not get the storage price from Central. Try again.');
        lines.add(StorageChargeItem(m.name, p['fileSize'] as int, c));
      }
      final postSize = postStoredBytes(metadataEntries, postBlocks, contractIdLength: 32, shareType: r.shareType);
      final postCharge = await WalletService.quoteCharge(
        sizeBytes: postSize,
        storeNodes: 1,
        replicas: AppConstants.replicationFactor,
      );
      if (postCharge == null) throw Exception('Could not get the storage price from Central. Try again.');
      lines.add(StorageChargeItem('Post', postSize, postCharge));

      final storageInfo = await PostService.preparePostUploadWithStorageCost(
        postResult: postResult,
        storeBaseUrl: node['endpoint'],
        appPublicKey: publicKey,
        storageNodePublicKey: node['publicKey'] ?? '',
        userMnemonic: mnemonic,
        onProgress: onProgress,
        centralCharge: postCharge,
      );
      if (storageInfo['success'] != true) throw Exception(storageInfo['error'] ?? 'Failed to calculate storage cost');
      storageInfo['totalFee'] = StorageChargeItem.total(lines);
      storageInfo['estimatedSize'] = lines.fold<int>(0, (a, l) => a + l.sizeBytes);
      storageInfo['breakdown'] = lines;
      storageInfo['feeBasis'] = '';
      _progress('Awaiting fee confirmation...');
      if (!await confirmStorage(storageInfo)) throw PostPublishCancelled();

      _progress('Signing storage contract...');
      final contractId = storageInfo['contractId'] as String? ?? '';
      if (contractId.isEmpty) throw Exception('Missing contractId from storage proposal');
      await _signStorageContract(storeBaseUrl: node['endpoint'] as String, contractId: contractId);

      for (final entry in metadataEntries) {
        entry['contractId'] = contractId;
        entry['type'] ??= 'post';
        entry['shareType'] ??= r.shareType;
      }

      // 4. Pay before anything reaches the Store: it submits the post to the chain once it has the metadata,
      // so a short balance must stop the post here (402). Central copies it to more Stores later.
      _progress('Paying for storage...');
      final paidPostSize = WalletService.storedBytes(metadataEntries, postBlocks);
      if (paidPostSize != postSize) {
        // Never charge something other than what was shown.
        final again = await WalletService.quoteCharge(
            sizeBytes: paidPostSize, storeNodes: 1, replicas: AppConstants.replicationFactor);
        if (again != postCharge) throw Exception('The storage price changed while posting. Nothing was charged; try again.');
      }
      final uploader = FileUploadService();
      for (final m in pendingMedia) {
        final reg = await uploader.registerPending(m.pending, mnemonic: mnemonic);
        if (reg['status'] == 402) throw Exception('Not enough D to store ${m.name}: ${reg['error']}');
        if (reg['ok'] != true) AppLogger.log('Storage registration for ${m.name} failed (${reg['status']}): ${reg['error']}');
      }
      final storageReg = await WalletService.registerStorage(
        fileId: postFileId,
        storeNodeIds: [node['id'].toString()],
        sizeBytes: paidPostSize,
        blocks: WalletService.blockHashes(postBlocks),
      );
      if (storageReg.status == 402) throw Exception('Not enough D to store this post: ${storageReg.error}');
      if (!storageReg.ok) AppLogger.log('Storage registration failed (${storageReg.status}), posting anyway: ${storageReg.error}');
      if (storageReg.ok) paidUnuploadedFileId = postFileId;

      // 5. Metadata entries (one per reader), their metadata blocks, then the shared content blocks.
      for (var i = 0; i < metadataEntries.length; i++) {
        _progress('Uploading metadata entry ${i + 1}/${metadataEntries.length}...');
        final res = await _upload(
          nodeEndpoint: node['endpoint'] as String,
          path: '/api/file/upload-metadata-raw',
          content: Uint8List.fromList(utf8.encode(json.encode(metadataEntries[i]))),
          contentType: 'application/json',
        );
        if (res['success'] != true) throw Exception('Failed to upload post metadata entry ${i + 1}: ${res['error']}');
      }
      final ownerFileId = metadataEntries[0]['fileId'] as String;
      final metadataBlocks = postBlocks.where((b) => (b['isMetadataBlock'] as bool? ?? false) || b['blockIndex'] == 0).toList();
      final contentBlocks = postBlocks.where((b) => !metadataBlocks.contains(b)).toList();
      for (var i = 0; i < metadataBlocks.length; i++) {
        final b = metadataBlocks[i];
        final entry = metadataEntries.firstWhere((e) => e['firstBlockId'] == b['blockId'], orElse: () => metadataEntries[0]);
        _progress('Uploading metadata block ${i + 1}/${metadataBlocks.length}...');
        await _uploadBlock(node, b, entry['fileId'] as String, contractId);
      }
      for (var i = 0; i < contentBlocks.length; i++) {
        _progress('Uploading content block ${i + 1}/${contentBlocks.length}...');
        await _uploadBlock(node, contentBlocks[i], ownerFileId, contractId);
      }
      paidUnuploadedFileId = null;
      AppLogger.log('PostPublisher: post $postFileId uploaded');

      // 6. Followers post with PRE: re-encryption keys for the current followers (and the author).
      var rekeys = <String, bool>{};
      if (policyTag != null && r.rekeyFor.isNotEmpty) {
        try {
          _progress('Publishing PRE tag and uploading rekeys...');
          rekeys = await PreService().generateAndUploadRekeys(
            apiBaseUrl: apiBaseUrl,
            authorPubKey: publicKey,
            mnemonic: mnemonic,
            followerPubKeys: r.rekeyFor,
            tag: policyTag,
          );
          AppLogger.log('PRE rekeys uploaded: ${rekeys.values.where((v) => v).length}/${rekeys.length}');
        } catch (e) {
          AppLogger.log('PRE rekeys upload error: $e');
        }
      }

      return PostPublishResult(
        postId: postResult['postId']?.toString() ?? '',
        fileId: postFileId,
        primaryNode: node,
        uploadedMedia: uploadedMedia,
        rekeys: rekeys,
      );
    } catch (e) {
      final unpaid = paidUnuploadedFileId;
      if (unpaid != null) {
        // Paid but the upload failed: get the fee back and spare the Stores a challenge on missing blocks.
        await WalletService.cancelStorage(unpaid);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _uploadMedia(
    PostMediaInput m,
    Map<String, dynamic> node,
    List<Map<String, dynamic>> replicas,
    PostPublishRequest r,
  ) async {
    final up = await FileUploadService().uploadEncryptedFile(
      fileData: m.bytes,
      fileName: m.name,
      publicKey: publicKey,
      mnemonic: mnemonic,
      sharedWithUsers: r.sharedWithPublicKeys.isNotEmpty ? r.sharedWithPublicKeys : null,
      selectedNode: node,
      replicaNodes: replicas,
      onProgress: onProgress,
      fileType: 'file',
      shareType: r.shareType,
      policyTag: r.preTag,
      capsuleFor: r.preTag != null ? 'tag' : null,
      policyScheme: r.preTag != null ? PreKeys.schemeFor(r.preTag!) : null,
      deferRegistration: true,
    );
    if (up['success'] != true) throw Exception('FileUploadService failed: ${up['error']}');
    if (up['blockchainSubmitted'] == false) {
      onWarning?.call('Metadata uploaded, but blockchain submission failed. Will retry in background.');
    }
    return up;
  }

  Future<void> _uploadBlock(Map<String, dynamic> node, Map<String, dynamic> block, String fileId, String contractId) async {
    final res = await _upload(
      nodeEndpoint: node['endpoint'] as String,
      path: '/api/file/upload-file-block-raw',
      content: block['encryptedContent'] as Uint8List,
      contentType: 'application/octet-stream',
      extraHeaders: {
        'X-Block-Id': block['blockId'] as String,
        'X-File-Id': fileId,
        'X-Block-Index': block['blockIndex'].toString(),
        'X-Contract-Id': contractId,
      },
    );
    if (res['success'] != true) throw Exception('Failed to upload block ${block['blockIndex']}: ${res['error']}');
  }

  Future<void> _signStorageContract({required String storeBaseUrl, required String contractId}) async {
    final service = StorageContractService(
      storeBaseUrl: storeBaseUrl,
      signer: RequestSigner(publicKey: publicKey, mnemonic: mnemonic),
    );
    final StorageContract? contract = await service.getContract(contractId: contractId, userPublicKey: publicKey);
    if (contract == null) throw Exception('Storage contract not found');
    final signed = await service.approveAndSignContract(contract: contract, appPrivateKey: mnemonic);
    if (signed == null || signed.status.toLowerCase() != 'active') throw Exception('Failed to sign storage contract');
  }

  /// POST raw bytes to a Store, signed like the C# RequestSigner: METHOD + path + timestamp + base64(sha256(body)).
  Future<Map<String, dynamic>> _upload({
    required String nodeEndpoint,
    required String path,
    required Uint8List content,
    required String contentType,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final bodyHash = base64.encode(await CryptoService.hashSHA256(content));
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final dataToSign = 'POST${Uri.parse(path).path}$timestamp$bodyHash';
      final signature = await CryptoService.sign(
        dataToSign,
        kIsWeb ? mnemonic : CryptoService.generateKeyPairFromMnemonic(mnemonic),
      );
      final request = http.Request('POST', Uri.parse('$nodeEndpoint$path'))
        ..headers.addAll({
          'Content-Type': contentType,
          'X-User-PubKey': CryptoService.normalizePublicKey(publicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
          ...?extraHeaders,
        })
        ..bodyBytes = content;
      final resp = await http.Response.fromStream(await request.send());
      if (resp.statusCode == 200) return {'success': true, 'response': json.decode(resp.body)};
      return {'success': false, 'error': 'HTTP ${resp.statusCode}: ${resp.body}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

}

/// One item of an upload's storage charge: what Central takes for it (D, whole 0.0001 D).
class StorageChargeItem {
  final String label;
  final int sizeBytes;
  final double charge;
  const StorageChargeItem(this.label, this.sizeBytes, this.charge);

  /// Sum in 0.0001 D steps, so floating point never adds or drops a fraction of what is shown.
  static double total(List<StorageChargeItem> items) =>
      items.fold<int>(0, (a, l) => a + (l.charge * 10000).round()) / 10000;
}

/// Bytes Central bills for a post, the way [WalletService.storedBytes] counts them once each metadata entry
/// carries its contractId (a [contractIdLength]-character id from the Store), type and shareType.
int postStoredBytes(
  List<Map<String, dynamic>> metadataEntries,
  List<Map<String, dynamic>> blocks, {
  required int contractIdLength,
  required String shareType,
}) {
  final entries = [
    for (final e in metadataEntries)
      {
        ...e,
        'contractId': 'x' * contractIdLength,
        'type': e['type'] ?? 'post',
        'shareType': e['shareType'] ?? shareType,
      }
  ];
  return WalletService.storedBytes(entries, blocks);
}
