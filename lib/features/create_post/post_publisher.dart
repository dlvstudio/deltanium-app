import 'dart:typed_data';


import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/features/file_manager/file_upload_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/post_service.dart';
import 'package:deltanium_app/services/pre_service.dart';
import 'package:deltanium_app/services/pre_keys.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/services/store_placement.dart';

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
    // Every item of the post (each attached file, then the post itself) is stored the same way, on the same N Stores:
    // a signed contract with each Store, Central paid once for all of them, then the item on each Store, where each
    // puts its own StorageOperation on chain (StorePlacement).
    final nodes = await StorePlacement.pickNodes();
    final primary = nodes.first;
    final primaryEndpoint = '${primary['httpsEndpoint'] ?? primary['endpoint']}';
    AppLogger.log('PostPublisher: ${nodes.length} store node(s); primary=$primaryEndpoint');

    // 1. Attached files, encrypted here; nothing leaves the device before the user confirms the total (step 3).
    final uploader = FileUploadService();
    final media = <({PostMediaInput input, Map<String, dynamic> enc})>[];
    for (final m in r.media) {
      try {
        _progress('Encrypting ${m.name}...');
        final enc = await uploader.encryptForUpload(
          fileData: m.bytes,
          fileName: m.name,
          publicKey: publicKey,
          mnemonic: mnemonic,
          sharedWithUsers: r.sharedWithPublicKeys.isNotEmpty ? r.sharedWithPublicKeys : null,
          onProgress: onProgress,
          fileType: 'file',
          shareType: r.shareType,
          policyTag: r.preTag,
          capsuleFor: r.preTag != null ? 'tag' : null,
          policyScheme: r.preTag != null ? PreKeys.schemeFor(r.preTag!) : null,
        );
        media.add((input: m, enc: enc));
      } catch (e) {
        // One failed attachment does not stop the post (as before).
        AppLogger.log('PostPublisher: attachment ${m.name} failed: $e');
      }
    }

    // 2. The post itself, pointing at the attachments on the primary Store (the others hold the same copies).
    _progress(media.isEmpty ? 'Creating text post...' : 'Creating post...');
    final policyTag = r.preTag;
    final uploadedMedia = [
      for (final x in media)
        {
          'fileId': x.enc['fileId'],
          'name': x.input.name,
          'type': x.input.type,
          'url': '$primaryEndpoint/api/file/download/${x.enc['fileId']}',
          'nodeId': primary['id'],
          'nodeEndpoint': primaryEndpoint,
          'size': x.input.size,
          'extension': x.input.extension,
          'encryptedKey': x.enc['encryptedKey'],
        }
    ];
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
    final postEntries = [
      for (final e in postResult['metadataEntries'] as List<Map<String, dynamic>>)
        {...e, 'type': e['type'] ?? 'post', 'shareType': e['shareType'] ?? r.shareType}
    ];
    final postBlocks = postResult['blocks'] as List<Map<String, dynamic>>;
    final postFileId = postResult['fileId'] as String;

    // 3. Central's exact charge for each item on these Stores, shown once as a total.
    _progress('Calculating storage cost...');
    Future<StorageChargeItem> quote(String label, int size) async {
      final c = await WalletService.quoteChargeDetail(sizeBytes: size, storeNodes: nodes.length, replicas: nodes.length);
      if (c == null) throw Exception('Could not get the storage price from Central. Try again.');
      return StorageChargeItem(label, size, c.charge, monthly: c.monthly);
    }

    final lines = <StorageChargeItem>[
      for (final x in media) await quote(x.input.name, x.enc['billableBytes'] as int),
      await quote('Post', StorePlacement.billableBytes(postEntries, postBlocks)),
    ];
    final storageInfo = <String, dynamic>{
      'totalFee': StorageChargeItem.total(lines),
      'estimatedSize': lines.fold<int>(0, (a, l) => a + l.sizeBytes),
      'breakdown': lines,
      'monthlyFee': StorageChargeItem.totalMonthly(lines),
      'feeBasis': '',
      'storeNodes': nodes.length,
    };
    _progress('Awaiting fee confirmation...');
    if (!await confirmStorage(storageInfo)) throw PostPublishCancelled();

    // 4. Store each attached file, then the post (it points at them), on the same Stores.
    var chainPending = false;
    for (var i = 0; i < media.length; i++) {
      final x = media[i];
      _progress('Storing ${x.input.name}...');
      try {
        final placed = await StorePlacement.place(
          escrowFileId: x.enc['fileId'] as String,
          metadataEntries: x.enc['metadataEntries'] as List<Map<String, dynamic>>,
          blocks: x.enc['blocks'] as List<Map<String, dynamic>>,
          nodes: nodes,
          publicKey: publicKey,
          mnemonic: mnemonic,
          charge: lines[i].charge,
          replicas: nodes.length,
          onProgress: onProgress,
        );
        chainPending |= placed.chainSubmitPending;
      } on StoragePaymentRefused catch (e) {
        throw Exception('Not enough D to store ${x.input.name}: $e');
      }
    }
    _progress('Storing post...');
    final placed = await StorePlacement.place(
      escrowFileId: postFileId,
      metadataEntries: postEntries,
      blocks: postBlocks,
      nodes: nodes,
      publicKey: publicKey,
      mnemonic: mnemonic,
      charge: lines.last.charge,
      replicas: nodes.length,
      onProgress: onProgress,
    );
    chainPending |= placed.chainSubmitPending;
    if (chainPending) onWarning?.call('Stored, but a Store could not put it on chain yet. It retries in the background.');
    AppLogger.log('PostPublisher: post $postFileId stored on ${placed.nodes.length} Store(s)');

    // 5. Followers post with PRE: re-encryption keys for the current followers (and the author).
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
      primaryNode: placed.nodes.first,
      uploadedMedia: uploadedMedia,
      rekeys: rekeys,
    );
  }
}

/// One item of an upload's storage charge: what Central takes for it (D, whole 0.0001 D).
class StorageChargeItem {
  final String label;
  final int sizeBytes;
  final double charge;

  /// Taken each month afterwards while it is stored (AutoRenew).
  final double monthly;
  const StorageChargeItem(this.label, this.sizeBytes, this.charge, {this.monthly = 0});

  /// Sum in 0.0001 D steps, so floating point never adds or drops a fraction of what is shown.
  static double total(List<StorageChargeItem> items) =>
      items.fold<int>(0, (a, l) => a + (l.charge * 10000).round()) / 10000;

  static double totalMonthly(List<StorageChargeItem> items) =>
      items.fold<int>(0, (a, l) => a + (l.monthly * 10000).round()) / 10000;
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
