// Live checks of the app's DLTP client against the real testnet nodes. Skipped unless LIVE_TESTNET=1.
// Run: flutter test test/live --dart-define=NETWORK_ID=deltanium-test \
//        --dart-define=CENTRAL_API_BASE=https://testnet-api.deltanium.com/api   (with LIVE_TESTNET=1 in the env)
// Read-only: GET requests only, signed with a throwaway key made for this run.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/config/network.dart';
import 'package:deltanium_app/services/dltp/dltp_client_io.dart';
import 'package:deltanium_app/services/dltp/dltp_wire.dart';
import 'package:deltanium_app/services/dltp/node_address.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pointycastle/export.dart' as pc;

class _NoHttps extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('HTTPS fallback used for ${request.url}: DLTP did not answer');
}

void main() {
  final live = Platform.environment['LIVE_TESTNET'] == '1';
  final https = IOClient();
  // Only DLTP: no HTTPS fallback, so a pass proves the TCP path itself.
  final dltpOnly = DltpRoutingClient(inner: _NoHttps());
  late List<Map<String, dynamic>> stores;
  late List<Map<String, dynamic>> blockers;

  setUpAll(() async {
    if (!live) return;
    NodeAddress.enabled = true;
    expect(Network.name, 'deltanium-test', reason: 'build with --dart-define=NETWORK_ID=deltanium-test');
    stores = (json.decode((await https.get(Uri.parse('${AppConstants.apiBaseUrl}/storenode/list'))).body) as List)
        .map((e) => StoreNodeDirectory.normalizeNode(Map<String, dynamic>.from(e as Map))).toList();
    blockers = (json.decode((await https.get(Uri.parse('${AppConstants.apiBaseUrl}/blockcreatornode/list'))).body) as List)
        .map((e) => StoreNodeDirectory.normalizeNode(Map<String, dynamic>.from(e as Map))).toList();
    for (final n in [...stores, ...blockers]) {
      // ignore: avoid_print
      print('node ${n['endpoint']}  tcp=${n['tcpEndpoint']}');
    }
  });

  test('every node with a TCP endpoint answers over DLTP like over HTTPS', () async {
    var checked = 0;
    for (final n in [...stores, ...blockers]) {
      if ((n['tcpEndpoint'] ?? '').toString().isEmpty) continue;
      final base = n['endpoint'] as String;
      final viaTcp = await dltpOnly.get(Uri.parse('$base/api/version'));
      expect(viaTcp.statusCode, 200, reason: base);
      final v = json.decode(viaTcp.body) as Map;
      final httpsBase = (n['httpsEndpoint'] as String?) ?? '';
      if (httpsBase.isNotEmpty) {
        final viaHttps = json.decode((await https.get(Uri.parse('$httpsBase/api/version'))).body) as Map;
        expect(v['service'], viaHttps['service'], reason: base);
        expect(v['startedAtUtc'], viaHttps['startedAtUtc'], reason: '$base: same process behind both');
      }
      // ignore: avoid_print
      print('OK  ${n['tcpEndpoint']}  ${NodeAddress.routeFor(Uri.parse(base))!.keyMode ? "(node key checked)" : "(CA certificate)"}  ${v['service']}');
      checked++;
    }
    expect(checked, greaterThanOrEqualTo(3));
  }, skip: !live);

  test('an IP endpoint is authenticated with the node key', () async {
    final ipNodes = stores.where((n) {
      final t = NodeAddress.parseTcp(n['tcpEndpoint']?.toString());
      return t != null && NodeAddress.isIpLiteral(t.host);
    }).toList();
    expect(ipNodes, isNotEmpty, reason: 'testnet-store-2 runs the built-in listener on its IP');
    final n = ipNodes.first;
    final tcp = n['tcpEndpoint'] as String;

    // The real key: works.
    final ok = await dltpOnly.get(Uri.parse('${NodeAddress.of('', tcp, publicKey: n['publicKey'] as String)}/api/version'));
    expect(ok.statusCode, 200);

    // Another node's key on the same address: refused before any request is sent.
    NodeAddress.clear();
    final wrongKey = stores.firstWhere((o) => o['publicKey'] != n['publicKey'])['publicKey'] as String;
    final base = NodeAddress.of('', tcp, publicKey: wrongKey);
    await expectLater(dltpOnly.get(Uri.parse('$base/api/version')), throwsA(isA<DltpException>()));
    NodeAddress.clear();
    for (final o in [...stores, ...blockers]) {
      StoreNodeDirectory.normalizeNode(o);
    }
  }, skip: !live);

  test('a signed user request returns the same over DLTP and HTTPS', () async {
    final d = BigInt.parse(List.generate(32, (i) => (i * 37 + DateTime.now().microsecond) % 256)
        .map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
    final domain = pc.ECDomainParameters('secp256k1');
    final pub = (domain.G * d)!;
    final pubHex = pub.getEncoded(true).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    Map<String, String> sign(String method, String path) {
      final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final msg = Network.scope('$method$path$ts');
      final signer = pc.Signer('SHA-256/DET-ECDSA')..init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(pc.ECPrivateKey(d, domain)));
      final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(msg))) as pc.ECSignature;
      var s = sig.s;
      if (s > domain.n >> 1) s = domain.n - s;
      List<int> enc(BigInt v) {
        var h = v.toRadixString(16);
        if (h.length.isOdd) h = '0$h';
        final b = [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
        return b.first >= 0x80 ? [0, ...b] : b;
      }
      final r = enc(sig.r), ss = enc(s);
      final der = [0x30, r.length + ss.length + 4, 0x02, r.length, ...r, 0x02, ss.length, ...ss];
      return {'X-User-PubKey': pubHex, 'X-Timestamp': ts, 'X-Signature': base64.encode(der)};
    }

    const path = '/api/post/public-feed';
    var checked = 0;
    for (final n in stores) {
      if ((n['tcpEndpoint'] ?? '').toString().isEmpty || (n['httpsEndpoint'] as String).isEmpty) continue;
      final a = await https.get(Uri.parse('${n['httpsEndpoint']}$path'), headers: sign('GET', path));
      final b = await dltpOnly.get(Uri.parse('${n['endpoint']}$path'), headers: sign('GET', path));
      expect(b.statusCode, a.statusCode, reason: n['endpoint'] as String);
      expect(crypto.sha256.convert(b.bodyBytes), crypto.sha256.convert(a.bodyBytes), reason: n['endpoint'] as String);
      // ignore: avoid_print
      print('OK  signed GET $path on ${n['httpsEndpoint']}: ${a.statusCode}, ${a.bodyBytes.length} bytes, same body');
      checked++;
    }
    expect(checked, greaterThanOrEqualTo(2));
  }, skip: !live);
}
