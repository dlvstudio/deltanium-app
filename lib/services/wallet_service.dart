import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:http/http.dart' as http;

/// Result of a signed wallet/economics call: [ok] plus decoded JSON [data] or an [error] message.
class WalletResult {
  final bool ok;
  final int status;
  final dynamic data;
  final String? error;
  const WalletResult(this.ok, this.status, this.data, this.error);

  Map<String, dynamic>? get map => data is Map<String, dynamic> ? data as Map<String, dynamic> : null;
}

/// D credit wallet and TOKENOMICS_V2 economics (top-up channels, usage, redemption,
/// subscriptions, tips). Base unit D = 1 VND; 1 DLT = 1,000,000 D.
class WalletService {
  static Future<Map<String, String>?> _auth() => AuthService().getCurrentAuthInfo();

  static Future<Map<String, String>> _signedHeaders({
    required String method,
    required String path,
    required String pubKey,
    required String mnemonic,
    String? body,
  }) async {
    final timestamp =
        (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    var bodyHash = '';
    if ((method == 'POST' || method == 'PUT' || method == 'PATCH') && body != null) {
      bodyHash = sha256.convert(utf8.encode(body)).toString();
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

  /// [path] starts with `/api/` and includes any query string (it is part of the signature).
  static Future<WalletResult> _call(String method, String path, {Object? json, bool signed = true}) async {
    try {
      final body = json == null ? null : jsonEncode(json);
      var headers = <String, String>{'Content-Type': 'application/json'};
      if (signed) {
        final auth = await _auth();
        if (auth == null) return const WalletResult(false, 401, null, 'Not signed in');
        headers = await _signedHeaders(
          method: method,
          path: path,
          pubKey: auth['publicKey']!,
          mnemonic: auth['mnemonic']!,
          body: body,
        );
      }
      final base = AppConstants.apiBaseUrl.endsWith('/api')
          ? AppConstants.apiBaseUrl.substring(0, AppConstants.apiBaseUrl.length - 4)
          : AppConstants.apiBaseUrl;
      final uri = Uri.parse('$base$path');
      final resp = method == 'POST'
          ? await http.post(uri, headers: headers, body: body)
          : await http.get(uri, headers: headers);
      dynamic data;
      try {
        data = resp.body.isEmpty ? null : jsonDecode(resp.body);
      } catch (_) {
        data = resp.body;
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return WalletResult(true, resp.statusCode, data, null);
      }
      final err = data is Map && data['error'] != null ? data['error'].toString() : resp.body;
      AppLogger.log('WalletService $method $path: ${resp.statusCode} $err');
      return WalletResult(false, resp.statusCode, data, err.isEmpty ? 'HTTP ${resp.statusCode}' : err);
    } catch (e) {
      AppLogger.log('WalletService $method $path error: $e');
      return WalletResult(false, 0, null, e.toString());
    }
  }

  // ---------- storage registration (TOKENOMICS_V2 §6, §10) ----------

  /// Register an item stored on a Store node with Central. This opens its storage escrow, which is what counts
  /// toward the free quota (and is billed beyond it). [social] marks reactions, comments and chat messages:
  /// Central never charges the wallet for those. Returns status 402 when a paid item could not be funded.
  static Future<WalletResult> registerStorage({
    required String fileId,
    required List<String> storeNodeIds,
    required int sizeBytes,
    bool social = false,
    int months = 12,
    List<Map<String, Object>> blocks = const [],
    int? replicas,
  }) async {
    final auth = await _auth();
    if (auth == null) return const WalletResult(false, 401, null, 'Not signed in');
    final r = await _call('POST', '/api/storedfile/register-replicas', json: {
      'fileId': fileId,
      'ownerPublicKey': CryptoService.normalizePublicKey(auth['publicKey']!),
      'storeNodeIds': storeNodeIds,
      'fileSize': sizeBytes,
      'fileHash': '',
      'months': months,
      'contractType': 'TimeFixed',
      'blocks': blocks,
      // Copies to pay for: Central copies the item to more Stores until this many hold it, so a post
      // uploaded to one Store still ends up replicated (TOKENOMICS_V2 §6).
      'replicas': replicas ?? AppConstants.replicationFactor,
      if (social) 'kind': 'social',
    });
    AppLogger.log('WalletService.registerStorage $fileId ($sizeBytes B, social=$social): ${r.status}');
    return r;
  }

  /// The upload failed after [registerStorage] paid for it: close the escrow and refund the payer.
  /// Central refuses once a Store holds the whole file, so this never undoes a finished upload.
  static Future<WalletResult> cancelStorage(String fileId) async {
    final r = await _call('POST', '/api/storedfile/cancel-escrow', json: {'fileId': fileId});
    AppLogger.log('WalletService.cancelStorage $fileId: ${r.status} ${r.error ?? ''}');
    return r;
  }

  /// [registerStorage] for an item uploaded to [nodeEndpoint]; the node id is looked up in the Store directory.
  static Future<WalletResult> registerStorageAt({
    required String nodeEndpoint,
    required String fileId,
    required int sizeBytes,
    bool social = false,
    List<Map<String, Object>> blocks = const [],
  }) async {
    try {
      final target = StoreNodeDirectory.normalizeEndpoint(nodeEndpoint);
      final nodes = await StoreNodeDirectory.listNodes(requireNonEmpty: false);
      final node = nodes.where((n) => StoreNodeDirectory.normalizeEndpoint('${n['endpoint'] ?? ''}') == target);
      if (node.isEmpty) return WalletResult(false, 0, null, 'Unknown store node $target');
      return registerStorage(
        fileId: fileId,
        storeNodeIds: ['${node.first['id']}'],
        sizeBytes: sizeBytes,
        social: social,
        blocks: blocks,
      );
    } catch (e) {
      return WalletResult(false, 0, null, e.toString());
    }
  }

  /// SHA-256 of every uploaded block, so Central can run proof-of-storage challenges (same format as media).
  static List<Map<String, Object>> blockHashes(List<Map<String, dynamic>> blocks) => [
        for (final b in blocks)
          if (b['blockId'] is String && b['encryptedContent'] is List<int>)
            {
              'blockId': b['blockId'] as String,
              'sha256': sha256.convert(b['encryptedContent'] as List<int>).toString(),
              'blockIndex': (b['blockIndex'] as num?)?.toInt() ?? -1,
            },
      ];

  /// Bytes an item occupies on a Store node: every metadata entry plus every block.
  static int storedBytes(List<Map<String, dynamic>> metadataEntries, List<Map<String, dynamic>> blocks) {
    var n = 0;
    for (final m in metadataEntries) {
      n += utf8.encode(jsonEncode(m)).length;
    }
    for (final b in blocks) {
      final c = b['encryptedContent'];
      if (c is List) n += c.length;
    }
    return n;
  }

  // ---------- balances & economics ----------

  static Future<Map<String, dynamic>?> getEconomics() async =>
      (await _call('GET', '/api/wallet/economics', signed: false)).map;

  static Future<double?> getBalance() async {
    final r = await _call('GET', '/api/wallet/balance');
    return r.ok ? (r.map?['balance'] as num?)?.toDouble() : null;
  }

  /// Public proof-of-reserve snapshot.
  static Future<Map<String, dynamic>?> getReserve() async =>
      (await _call('GET', '/api/wallet/reserve', signed: false)).map;

  /// Free tier, storage, egress and subscriptions of the signed-in user.
  static Future<Map<String, dynamic>?> getUsage() async => (await _call('GET', '/api/wallet/usage')).map;

  // ---------- email verification (free tier, TOKENOMICS_V2 §10) ----------

  /// Email a 6-digit code to [email]; the server limits this to one a minute and five a day.
  static Future<WalletResult> sendEmailCode(String email) =>
      _call('POST', '/api/email/send-code', json: {'email': email.trim()});

  static Future<WalletResult> verifyEmailCode(String code) =>
      _call('POST', '/api/email/verify', json: {'code': code.trim()});

  // ---------- top-up (channel: transfer | card | iap) ----------

  static Future<Map<String, dynamic>?> createTopUp({required double fiatAmountVnd, String channel = 'transfer'}) async {
    final r = await _call('POST', '/api/wallet/topup', json: {'fiatAmountVnd': fiatAmountVnd, 'channel': channel});
    return r.ok ? r.map : null;
  }

  static Future<WalletResult> createTopUpResult({required double fiatAmountVnd, String channel = 'transfer'}) =>
      _call('POST', '/api/wallet/topup', json: {'fiatAmountVnd': fiatAmountVnd, 'channel': channel});

  /// The signed-in user's own top-up orders (newest first) and the receiving bank account.
  static Future<WalletResult> myTopUps() => _call('GET', '/api/wallet/topups');

  // ---------- redemption (KYC-verified creators / node operators) ----------

  static Future<WalletResult> redeem(double amountD) => _call('POST', '/api/wallet/redeem', json: {'amount': amountD});

  static Future<WalletResult> myRedemptions() => _call('GET', '/api/wallet/redemptions');

  // ---------- bandwidth ----------

  static Future<WalletResult> setEgressCap(double maxDPerMonth) =>
      _call('POST', '/api/wallet/egress-cap', json: {'maxDPerMonth': maxDPerMonth});

  static Future<Map<String, dynamic>?> quoteStorage({
    required int sizeBytes,
    int replicas = 2,
    int months = 12,
    String? owner,
  }) async {
    final q = 'sizeBytes=$sizeBytes&replicas=$replicas&months=$months'
        '${owner != null ? '&owner=${Uri.encodeQueryComponent(owner)}' : ''}';
    return (await _call('GET', '/api/storedfile/quote?$q', signed: false)).map;
  }

  // ---------- creator economy ----------

  static Future<Map<String, dynamic>?> getPlan(String creatorPublicKey) async =>
      (await _call('GET', '/api/subscription/plan/${Uri.encodeComponent(creatorPublicKey)}', signed: false)).map;

  static Future<WalletResult> setPlan(double pricePerMonthD) =>
      _call('POST', '/api/subscription/plan', json: {'pricePerMonthD': pricePerMonthD});

  static Future<WalletResult> subscribe(String creatorPublicKey, {int months = 1}) =>
      _call('POST', '/api/subscription/subscribe', json: {'creatorPublicKey': creatorPublicKey, 'months': months});

  static Future<bool> isSubscribed(String creatorPublicKey) async {
    final r = await _call('GET', '/api/subscription/status/${Uri.encodeComponent(creatorPublicKey)}');
    return r.ok && r.map?['subscribed'] == true;
  }

  /// Creator only: subscribers paid through the current epoch (for `subscribers:YYYY-MM` rekeys).
  static Future<List<String>> getSubscribers({String? epoch}) async {
    final r = await _call('GET', '/api/subscription/subscribers${epoch != null ? '?epoch=$epoch' : ''}');
    if (!r.ok) return [];
    final list = (r.map?['subscribers'] as List?) ?? const [];
    return list.map((e) => (e as Map)['publicKey'].toString()).toList();
  }

  static Future<WalletResult> tip(String toPublicKey, double amountD, {String? postId}) =>
      _call('POST', '/api/tip', json: {'toPublicKey': toPublicKey, 'amount': amountD, if (postId != null) 'postId': postId});

  /// Current subscriber policy tag, e.g. `subscribers:2026-11`.
  static String currentSubscriberTag() {
    final now = DateTime.now().toUtc();
    return 'subscribers:${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }
}
