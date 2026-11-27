import 'dart:convert';
import 'dart:typed_data';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/services/store_placement.dart';
import 'package:deltanium_app/services/store_delete_service.dart';
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
    /// Unused: every Store holding the reaction gets its own contract (StorePlacement).
    String? contractId,
    String? fileId,
    String? firstBlockId,
    /// The charge the user confirmed; checked against the real size before anything is stored.
    double? confirmedCharge,
    Future<bool> Function(double charge)? reconfirmCharge,
  }) async {
    try {
      if (!supportedReactions.contains(reactionKind)) {
        AppLogger.log('ReactionService: Unsupported reaction "$reactionKind"');
        return false;
      }
      AppLogger.log('ReactionService: sendReaction react="$reactionKind" post=$postFileId node=$nodeEndpoint user=${userPublicKey.substring(0, 10)}...');

      final isPublicPost = postEncryptedType == 'public';
      if (!isPublicPost && (postOwnerPublicKey == null || postOwnerPublicKey.isEmpty)) {
        AppLogger.log('ReactionService: Missing post owner key for encrypted reaction');
        return false;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final effectiveFileId = fileId ?? _generateId(prefix: 'react');
      final content = {
        'reactorPublicKey': CryptoService.normalizePublicKey(userPublicKey),
        'parentFileId': postFileId,
        'kind': reactionKind,
        'createdAt': now,
      };

      final List<Map<String, dynamic>> metadataEntries;
      final List<Map<String, dynamic>> blocks;
      if (isPublicPost) {
        final effectiveFirstBlockId = firstBlockId ?? _generateId(prefix: 'b0');
        metadataEntries = [
          {
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
          }
        ];
        blocks = [
          {'blockId': effectiveFirstBlockId, 'blockIndex': 0, 'encryptedContent': Uint8List.fromList(utf8.encode(json.encode(content)))},
        ];
      } else {
        final result = await FileCryptoService.encryptAndSplitFile(
          fileData: Uint8List.fromList(utf8.encode(json.encode(content))),
          fileName: 'react_${DateTime.now().millisecondsSinceEpoch}.json',
          ownerPublicKey: userPublicKey,
          mnemonic: userMnemonic,
          sharedWithPublicKeys: [postOwnerPublicKey!, userPublicKey],
          fileType: 'react',
          relatedFiles: null,
          onProgress: null,
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
              'type': 'react',
              'parentFileId': postFileId,
              'kind': reactionKind,
              'ownerPubKey': CryptoService.normalizePublicKey(userPublicKey),
            }
        ];
        blocks = [for (final b in result['blocks'] as List) Map<String, dynamic>.from(b as Map)];
      }

      // Central's charge for the real size (re-confirmed if it differs from the one shown), then the reaction on
      // every Store holding the post (readers count reactions there), each under its own contract.
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
        nodes: await StorePlacement.nodesHolding(postFileId, nodeEndpoint),
        publicKey: userPublicKey,
        mnemonic: userMnemonic,
        charge: quote.charge,
        replicas: AppConstants.replicationFactor,
        social: true,
      );
      return true;
    } catch (e) {
      AppLogger.log('ReactionService error: $e');
      return false;
    }
  }

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
      // The Store signs the path without the query string (Request.Path), so sign that and send the query apart.
      final path = '/api/post/reactions/$postFileId';
      // The reaction is on every Store holding the post: remove it from each.
      final removedIds = <String>{};
      var anyOk = false;
      for (final endpoint in await StoreDeleteService.holdersOf(postFileId, nodeEndpoint)) {
        try {
          final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
          final signature = await CryptoService.sign('DELETE$path$timestamp', userMnemonic);
          final resp = await http.delete(
            Uri.parse('$endpoint$path$kindParam'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
              'X-Timestamp': timestamp,
              'X-Signature': signature,
            },
          );
          if (resp.statusCode != 200) continue;
          anyOk = true;
          final ids = (jsonDecode(resp.body) as Map)['fileIds'] as List? ?? const [];
          removedIds.addAll(ids.map((e) => '$e'));
        } catch (e) {
          AppLogger.log('ReactionService: remove on $endpoint failed: $e');
        }
      }
      // Stop paying for the removed reactions' storage (the Stores return their file ids).
      if (removedIds.isNotEmpty) WalletService.stopRenewal(removedIds.toList()).ignore();
      return anyOk;
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
      // What Central takes for this social item; sendReaction re-checks the real size and makes a contract with
      // each Store that stores the reaction.
      const estimatedSize = 500;
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
        'fileId': fileId ?? _generateId(prefix: 'react'),
        'totalFee': quote.charge,
        'feeBasis': 'Central storage charge',
        'estimatedSize': estimatedSize,
        'monthlyFee': quote.monthly,
        'durationDays': durationDays,
        'estimatedCostPerDay': quote.charge / (durationDays > 0 ? durationDays : 1),
      };
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


