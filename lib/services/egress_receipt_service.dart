import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:http/http.dart' as http;

/// `http.get` that also notes Store block downloads for a reader-signed bandwidth receipt.
/// Behaves exactly like `http.get` for every other URL.
class BlockHttp {
  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final resp = await http.get(url, headers: headers);
    if (resp.statusCode == 200) EgressReceipts.note(url, resp.bodyBytes.length);
    return resp;
  }
}

/// TOKENOMICS_V2 §7: the reader signs how many bytes each Store served it. Central bills the uploader only
/// for bytes covered by these receipts (Economics:Bandwidth:ReceiptMode=require), so a Store cannot invent
/// traffic. Receipts are batched per Store and sent to `{store}/api/proof/egress/receipt`.
class EgressReceipts {
  static final Map<String, Map<String, int>> _pending = {};
  static Timer? _timer;
  static const _flushEvery = Duration(seconds: 60);
  static const _maxItems = 200;

  /// Same normalisation as Central's ReceiptOrigin: scheme://host[:port], default port dropped, lowercase.
  static String originOf(Uri u) {
    final defaultPort = u.scheme == 'https' ? 443 : 80;
    final port = u.hasPort && u.port != defaultPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port'.toLowerCase();
  }

  /// `/api/file/block/{blockId}` → blockId; `/api/file/block/{fileId}/{index}` → `fileId/index`.
  static String? blockKeyOf(Uri u) {
    final s = u.pathSegments;
    final i = s.indexOf('block');
    if (i < 2 || s[i - 1] != 'file' || s[i - 2] != 'api') return null;
    final rest = s.sublist(i + 1);
    if (rest.length == 1) return rest[0];
    if (rest.length == 2) return '${rest[0]}/${rest[1]}';
    return null;
  }

  static void note(Uri url, int bytes) {
    final key = blockKeyOf(url);
    if (key == null || bytes <= 0) return;
    final perStore = _pending.putIfAbsent(originOf(url), () => {});
    perStore[key] = (perStore[key] ?? 0) + bytes;
    if (perStore.length >= _maxItems) {
      unawaited(flush());
    } else {
      _timer ??= Timer(_flushEvery, () => unawaited(flush()));
    }
  }

  /// Message the reader signs; must match Central's EconomicsService.ReceiptMessage.
  static String message(String origin, String reader, int ts, List<MapEntry<String, int>> items) {
    final joined = items.map((e) => '${e.key}:${e.value}').join(';');
    return 'EGRESS|$origin|$reader|$ts|${sha256.convert(utf8.encode(joined))}';
  }

  static Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final auth = await AuthService().getCurrentAuthInfo();
    if (auth == null) return;
    final reader = CryptoService.normalizePublicKey(auth['publicKey']!);
    final batch = Map<String, Map<String, int>>.from(_pending);
    _pending.clear();
    final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    for (final entry in batch.entries) {
      final items = entry.value.entries.toList();
      try {
        final signature = await CryptoService.sign(message(entry.key, reader, ts, items), auth['mnemonic']!);
        final body = jsonEncode({
          'reader': reader,
          'origin': entry.key,
          'ts': ts,
          'items': [for (final i in items) {'block': i.key, 'bytes': i.value}],
          'signature': signature,
        });
        final resp = await http.post(Uri.parse('${entry.key}/api/proof/egress/receipt'),
            headers: {'Content-Type': 'application/json'}, body: body);
        if (resp.statusCode != 200) {
          AppLogger.log('Egress receipt to ${entry.key}: ${resp.statusCode} ${resp.body}');
        }
      } catch (e) {
        AppLogger.log('Egress receipt to ${entry.key} failed: $e');
      }
    }
  }
}
