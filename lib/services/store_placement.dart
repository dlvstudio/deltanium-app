import 'dart:convert';
import 'dart:typed_data';

import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/models/storage_contract.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/services/store_delete_service.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:http/http.dart' as http;

/// Central refused the payment for want of D (HTTP 402).
class StoragePaymentRefused implements Exception {
  final String message;
  StoragePaymentRefused(this.message);
  @override
  String toString() => message;
}

/// What [StorePlacement.place] did.
class PlacementResult {
  /// Stores that hold the item now (ids from the Store directory), first one is the primary.
  final List<Map<String, dynamic>> nodes;

  /// Store contract per Store id; each Store put a StorageOperation on chain for its contract.
  final Map<String, String> contractIds;

  /// A Store could not put its StorageOperation on chain yet; it retries in the background.
  final bool chainSubmitPending;

  const PlacementResult({required this.nodes, required this.contractIds, required this.chainSubmitPending});

  List<String> get nodeIds => [for (final n in nodes) '${n['id']}'];
  String get primaryEndpoint => '${nodes.first['httpsEndpoint'] ?? nodes.first['endpoint']}';
}

/// The one way every stored item reaches the network: posts, comments, reactions, attached files, chat messages.
///
/// An item is already encrypted (or made public) into metadata entries (one per reader) and blocks. For each Store
/// that is to hold it: the Store proposes a storage contract and the app signs it. Then Central is paid once for all
/// those Stores (with the block hashes it challenges them on), and only then does the item go to each Store: its
/// metadata entries carry that Store's contract, so each Store puts its own StorageOperation on chain (signed by the
/// app and the Store). Paying first means a short balance stops the item before anything reaches a Store or the chain.
class StorePlacement {
  /// Up to [count] Stores for a new item. Stores in [mustUse] (endpoints) come first and are the only ones used
  /// when [onlyThese] is set: a comment or reaction can only go where its post is, since readers look for it there
  /// and the Store checks the parent post exists.
  static Future<List<Map<String, dynamic>>> pickNodes({
    int? count,
    List<String> mustUse = const [],
    bool onlyThese = false,
  }) async {
    final n = count ?? AppConstants.replicationFactor;
    final nodes = await StoreNodeDirectory.listNodes();
    String ep(Map<String, dynamic> x) => StoreNodeDirectory.normalizeEndpoint('${x['httpsEndpoint'] ?? x['endpoint'] ?? ''}');
    final wanted = mustUse.map(StoreNodeDirectory.normalizeEndpoint).toSet();
    final first = nodes.where((x) => wanted.contains(ep(x))).toList();
    if (onlyThese) return first.isNotEmpty ? first.take(n).toList() : StoreNodeDirectory.pickForUpload(nodes, 1);
    final rest = StoreNodeDirectory.pickForUpload(nodes.where((x) => !first.contains(x)).toList(), n);
    return [...first, ...rest].take(n.clamp(1, nodes.length)).toList();
  }

  /// The Stores holding [parentFileId] (from its storage contract on Central), for its comments and reactions.
  static Future<List<Map<String, dynamic>>> nodesHolding(String parentFileId, String knownEndpoint) async =>
      pickNodes(mustUse: await StoreDeleteService.holdersOf(parentFileId, knownEndpoint), onlyThese: true);

  /// Bytes Central bills for an item: every metadata entry (as uploaded, carrying a 32-character Store contract id)
  /// plus every block. Quote with this and [place] pays for exactly this.
  static int billableBytes(List<Map<String, dynamic>> metadataEntries, List<Map<String, dynamic>> blocks) =>
      WalletService.storedBytes([
        for (final e in metadataEntries) {...e, 'contractId': 'x' * 32}
      ], blocks);

  /// Places one item on [nodes] (see the class comment). [escrowFileId] is the id Central bills (the owner's entry);
  /// [charge] is what the user confirmed, recorded on the Store contracts split between the Stores; [replicas] is the
  /// copy count the charge was quoted for. Throws [StoragePaymentRefused] on 402 and when no Store took the item.
  static Future<PlacementResult> place({
    required String escrowFileId,
    required List<Map<String, dynamic>> metadataEntries,
    required List<Map<String, dynamic>> blocks,
    required List<Map<String, dynamic>> nodes,
    required String publicKey,
    required String mnemonic,
    required double charge,
    required int replicas,
    bool social = false,
    int months = 1,
    void Function(String message)? onProgress,
  }) async {
    if (nodes.isEmpty) throw Exception('No Store to place the item on');
    final size = billableBytes(metadataEntries, blocks);
    final fileIds = <String>{for (final e in metadataEntries) '${e['fileId']}'}.toList();

    // 1. A signed contract with every Store. A Store that will not agree is left out (the item needs one).
    final share = splitCharge(charge, nodes.length);
    final agreed = <Map<String, dynamic>>[];
    final contractIds = <String, String>{};
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      onProgress?.call('Agreeing storage with Store ${i + 1}/${nodes.length}...');
      try {
        final id = await _openContract(node, publicKey, mnemonic, size, fileIds, share[i]);
        contractIds['${node['id']}'] = id;
        agreed.add(node);
      } catch (e) {
        AppLogger.log('StorePlacement: no contract with ${_endpoint(node)}: $e');
      }
    }
    if (agreed.isEmpty) throw Exception('No Store agreed to store this item. Try again.');

    // 2. Pay Central once, for every Store that agreed.
    onProgress?.call('Paying for storage...');
    final reg = await WalletService.registerStorage(
      fileId: escrowFileId,
      storeNodeIds: [for (final n in agreed) '${n['id']}'],
      sizeBytes: size,
      social: social,
      months: months,
      blocks: WalletService.blockHashes(blocks),
      replicas: replicas,
    );
    if (reg.status == 402) throw StoragePaymentRefused('Not enough D to store this: ${reg.error}');
    if (!reg.ok) throw Exception('Central did not take the storage payment (${reg.status}): ${reg.error}');

    // 3. The item to every Store, each under its own contract.
    final placed = <Map<String, dynamic>>[];
    var chainPending = false;
    for (var i = 0; i < agreed.length; i++) {
      final node = agreed[i];
      onProgress?.call('Uploading to Store ${i + 1}/${agreed.length}...');
      try {
        final pending = await _upload(node, contractIds['${node['id']}']!, metadataEntries, blocks, publicKey, mnemonic);
        chainPending |= pending;
        placed.add(node);
      } catch (e) {
        // Paid for this Store but it did not take the item: Central's replica repair copies it from a Store that has it.
        AppLogger.log('StorePlacement: upload to ${_endpoint(node)} failed: $e');
      }
    }
    if (placed.isEmpty) {
      await WalletService.cancelStorage(escrowFileId); // nothing stored: get the payment back
      throw Exception('Could not upload to any Store. Nothing was charged.');
    }
    return PlacementResult(nodes: placed, contractIds: contractIds, chainSubmitPending: chainPending);
  }

  /// [total] split into [n] parts in 0.0001 D steps that add up to it exactly (the first part takes the remainder).
  static List<double> splitCharge(double total, int n) {
    final units = (total * 10000).round();
    final each = units ~/ n;
    return [for (var i = 0; i < n; i++) (i == 0 ? units - each * (n - 1) : each) / 10000];
  }

  static String _endpoint(Map<String, dynamic> node) =>
      StoreNodeDirectory.normalizeEndpoint('${node['httpsEndpoint'] ?? node['endpoint'] ?? ''}');

  static Future<String> _openContract(Map<String, dynamic> node, String publicKey, String mnemonic, int size,
      List<String> fileIds, double charge) async {
    final endpoint = _endpoint(node);
    final signer = RequestSigner(publicKey: publicKey, mnemonic: mnemonic);
    final now = DateTime.now();
    final body = jsonEncode({
      'contractType': 'TimeFixed',
      'startDateUnix': now.millisecondsSinceEpoch ~/ 1000,
      'endDateUnix': now.add(const Duration(days: 365)).millisecondsSinceEpoch ~/ 1000,
      'totalFileSize': size,
      'fileIds': fileIds,
      'centralCharge': charge,
    });
    final sig = await signer.signRequest('POST', '/api/storage/contracts/create', Uint8List.fromList(utf8.encode(body)));
    final resp = await http.post(
      Uri.parse('$endpoint/api/storage/contracts/create'),
      headers: {
        'Content-Type': 'application/json',
        'X-User-PubKey': signer.getPublicKeyBase64(),
        'X-Timestamp': sig['timestamp']!,
        'X-Signature': sig['signature']!,
      },
      body: body,
    );
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    final contractId = (jsonDecode(resp.body) as Map<String, dynamic>)['contractId'] as String;

    final service = StorageContractService(storeBaseUrl: endpoint, signer: signer);
    final StorageContract? contract = await service.getContract(contractId: contractId, userPublicKey: publicKey);
    if (contract == null) throw Exception('Contract $contractId not found after creating it');
    final signed = await service.approveAndSignContract(contract: contract, appPrivateKey: mnemonic);
    if (signed == null || signed.status.toLowerCase() != 'active') throw Exception('Could not sign contract $contractId');
    return contractId;
  }

  /// Metadata entries (each carrying [contractId]) then blocks. A block belongs to the entry whose firstBlockId it
  /// is (one metadata block per reader); content blocks belong to the owner's entry (the first). Returns true when
  /// the Store could not put its StorageOperation on chain right away (it retries on its own).
  static Future<bool> _upload(Map<String, dynamic> node, String contractId, List<Map<String, dynamic>> metadataEntries,
      List<Map<String, dynamic>> blocks, String publicKey, String mnemonic) async {
    final endpoint = _endpoint(node);
    var chainPending = false;
    for (final entry in metadataEntries) {
      final res = await _post(endpoint, '/api/file/upload-metadata-raw',
          Uint8List.fromList(utf8.encode(json.encode({...entry, 'contractId': contractId}))), 'application/json',
          publicKey, mnemonic);
      if (res is Map && (res['BlockchainSubmitted'] == false || res['blockchainSubmitted'] == false)) chainPending = true;
    }
    final ownerFileId = '${metadataEntries.first['fileId']}';
    for (final b in blocks) {
      final blockId = '${b['blockId']}';
      final entry = metadataEntries.where((e) => e['firstBlockId'] == blockId);
      final content = b['encryptedContent'];
      await _post(
        endpoint,
        '/api/file/upload-file-block-raw',
        content is Uint8List ? content : Uint8List.fromList((content as List).cast<int>()),
        'application/octet-stream',
        publicKey,
        mnemonic,
        headers: {
          'X-Block-Id': blockId,
          'X-File-Id': entry.isNotEmpty ? '${entry.first['fileId']}' : ownerFileId,
          'X-Block-Index': '${b['blockIndex']}',
          'X-Contract-Id': contractId,
        },
      );
    }
    return chainPending;
  }

  /// Signed POST to a Store: METHOD + path + timestamp + base64(sha256(body)), like the Store's verifier.
  static Future<dynamic> _post(String endpoint, String path, Uint8List body, String contentType, String publicKey,
      String mnemonic,
      {Map<String, String> headers = const {}}) async {
    final bodyHash = base64.encode(await CryptoService.hashSHA256(body));
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signature = await CryptoService.sign('POST$path$timestamp$bodyHash', mnemonic);
    final req = http.Request('POST', Uri.parse('$endpoint$path'))
      ..headers.addAll({
        'Content-Type': contentType,
        'X-User-PubKey': CryptoService.normalizePublicKey(publicKey),
        'X-Timestamp': timestamp,
        'X-Signature': signature,
        ...headers,
      })
      ..bodyBytes = body;
    final resp = await http.Response.fromStream(await req.send());
    if (resp.statusCode != 200) throw Exception('$path: HTTP ${resp.statusCode}: ${resp.body}');
    try {
      return json.decode(resp.body);
    } catch (_) {
      return null;
    }
  }
}
