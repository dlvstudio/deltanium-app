import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:deltanium_app/services/dltp/dltp_client_io.dart';
import 'package:deltanium_app/services/dltp/dltp_wire.dart';
import 'package:deltanium_app/services/dltp/node_address.dart';
import 'package:deltanium_app/services/dltp/node_proof.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' as pc;


/// A throwaway self-signed TLS certificate made for this run with openssl (no key is kept in the repo).
/// Returns null when openssl is not installed; the TLS tests are then skipped.
({String certPem, String keyPem})? _makeTestCertificate() {
  try {
    final dir = Directory.systemTemp.createTempSync('dltp-test-');
    final r = Process.runSync('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
      '-subj', '/CN=deltanium-node-test',
      '-keyout', '${dir.path}/key.pem', '-out', '${dir.path}/cert.pem',
    ]);
    if (r.exitCode != 0) return null;
    final out = (certPem: File('${dir.path}/cert.pem').readAsStringSync(), keyPem: File('${dir.path}/key.pem').readAsStringSync());
    dir.deleteSync(recursive: true);
    return out;
  } catch (_) {
    return null;
  }
}

final _testCert = _makeTestCertificate();

void main() {
  setUp(() {
    NodeAddress.clear();
    NodeAddress.enabled = true;
  });
  tearDown(() {
    NodeAddress.clear();
    NodeAddress.enabled = false;
  });

  test('tcp endpoint validation', () {
    expect(NodeAddress.parseTcp('tcps://store-1.deltanium.com:7333'), isNotNull);
    expect(NodeAddress.parseTcp('tcp://localhost:7333'), isNotNull);
    expect(NodeAddress.parseTcp('tcp://store-1.deltanium.com:7333'), isNull); // plain TCP only locally
    expect(NodeAddress.parseTcp('tcps://store-1.deltanium.com'), isNull); // port required
    expect(NodeAddress.parseTcp('https://store-1.deltanium.com'), isNull);
    expect(NodeAddress.parseTcp(null), isNull);
  });

  test('a node with both keeps its HTTPS URL and gets a DLTP route with fallback', () {
    final base = NodeAddress.of('https://store-1.deltanium.com/', 'tcps://store-1.deltanium.com:7333');
    expect(base, 'https://store-1.deltanium.com');
    final route = NodeAddress.routeFor(Uri.parse('$base/api/file/download/x'))!;
    expect(route.authority, 'store-1.deltanium.com:7333');
    expect(route.hasHttps, isTrue);
  });

  test('a TCP-only node gets a routable base URL without fallback', () {
    final base = NodeAddress.of('', 'tcps://store-9.example.com:7333');
    expect(base, 'https://store-9.example.com:7333');
    expect(NodeAddress.routeFor(Uri.parse('$base/api/x'))!.hasHttps, isFalse);
  });

  test('web builds (no DLTP) ignore TCP endpoints', () {
    NodeAddress.enabled = false;
    expect(NodeAddress.of('', 'tcps://store-9.example.com:7333'), '');
    expect(NodeAddress.of('https://s.example.com', 'tcps://s.example.com:7333'), 'https://s.example.com');
    expect(NodeAddress.routeFor(Uri.parse('https://s.example.com/api')), isNull);
  });

  test('normalizeNode reads tcpEndpoint and keeps the real HTTPS endpoint', () {
    final n = StoreNodeDirectory.normalizeNode({'id': 'a', 'endpoint': '', 'tcpEndpoint': 'tcps://a.example.com:7333'});
    expect(n['endpoint'], 'https://a.example.com:7333');
    expect(n['httpsEndpoint'], '');
  });

  test('upload primary is a node with HTTPS whenever there is one', () {
    final nodes = [
      {'id': 't1', 'endpoint': 'https://t1:7333', 'httpsEndpoint': ''},
      {'id': 't2', 'endpoint': 'https://t2:7333', 'httpsEndpoint': ''},
      {'id': 'h', 'endpoint': 'https://h', 'httpsEndpoint': 'https://h'},
    ];
    for (var i = 0; i < 20; i++) {
      for (final n in [1, 2, 3]) {
        final picked = StoreNodeDirectory.pickForUpload(nodes, n);
        expect(picked.length, n);
        expect(picked.first['id'], 'h');
      }
    }
  });

  test('frame is length-prefixed JSON', () {
    final f = DltpWire.frame({'id': 1});
    expect(ByteData.sublistView(f).getUint32(0), f.length - 4);
    expect(json.decode(utf8.decode(f.sublist(4))), {'id': 1});
  });

  test('a request to a TCP-only node travels over DLTP, two on one connection', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var connections = 0;
    server.listen((sock) async {
      connections++;
      final reader = DltpReader(sock);
      final pre = await reader.readExact(7);
      expect(utf8.decode(pre), 'DLTP/1\n');
      sock.add(DltpWire.preface);
      while (true) {
        Map<String, dynamic> req;
        try {
          req = await reader.readFrame();
        } catch (_) {
          break;
        }
        final h = Map<String, dynamic>.from(req['headers'] as Map);
        final body = req['body'] == null ? '' : utf8.decode(base64.decode(req['body'] as String));
        final echo = '${req['method']} ${req['path']} host=${h['Host']} sig=${h['X-Signature']} body=$body';
        sock.add(DltpWire.frame({
          'id': req['id'],
          'status': 201,
          'headers': {'Content-Type': 'text/plain'},
          'body': base64.encode(utf8.encode(echo)),
        }));
      }
      await sock.close();
    });

    final port = server.port;
    final base = NodeAddress.of('', 'tcp://localhost:$port');
    final client = DltpRoutingClient();
    try {
      final r1 = await client.post(Uri.parse('$base/api/post?x=1'), headers: {'X-Signature': 'abc'}, body: 'hi');
      expect(r1.statusCode, 201);
      expect(r1.headers['content-type'], 'text/plain');
      expect(r1.body, 'POST /api/post?x=1 host=localhost:$port sig=abc body=hi');
      final r2 = await client.get(Uri.parse('$base/api/version'));
      expect(r2.body, 'GET /api/version host=localhost:$port sig=null body=');
      expect(connections, 1);
    } finally {
      client.close();
      await server.close();
    }
  });

  // Signed by NBitcoin (the .NET nodes' library): key 0x11..11 over "DLTP-ID|" + sha256("not-a-real-certificate").
  const vecKey = '034f355bdcb7cc0af728ef3cceb9615d90684bb5b2ca5f859ab0f0b704075871aa';
  const vecProof = 'MEQCIE9L3hgzIxnPWN7kxP5+XN+cLTiGw6z8FnEfm+Yc0RjkAiABvaRIaKeKRZF+EgxgPgV65Gwlvfkwyn2dLWRw+UcPVg==';
  final vecCert = utf8.encode('not-a-real-certificate');

  test('node proof made by a .NET node verifies', () {
    expect(NodeProof.verify(expectedPublicKey: vecKey, presentedPublicKey: vecKey, proofBase64: vecProof, certificateDer: vecCert), isTrue);
    expect(NodeProof.verify(expectedPublicKey: vecKey, presentedPublicKey: vecKey, proofBase64: vecProof, certificateDer: utf8.encode('another certificate')), isFalse);
    const other = '02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
    expect(NodeProof.verify(expectedPublicKey: other, presentedPublicKey: other, proofBase64: vecProof, certificateDer: vecCert), isFalse);
    expect(NodeProof.verify(expectedPublicKey: vecKey, presentedPublicKey: other, proofBase64: vecProof, certificateDer: vecCert), isFalse);
  });

  test('an IP endpoint needs the node key, a host endpoint does not', () {
    expect(NodeAddress.isIpLiteral('203.0.113.7'), isTrue);
    expect(NodeAddress.isIpLiteral('store-1.deltanium.com'), isFalse);
    final base = NodeAddress.of('', 'tcps://203.0.113.7:7333', publicKey: vecKey);
    expect(base, 'https://203.0.113.7:7333');
    final route = NodeAddress.routeFor(Uri.parse('$base/api/x'))!;
    expect(route.keyMode, isTrue);
    expect(route.nodePublicKey, vecKey);
    expect(NodeAddress.of('', 'tcps://198.51.100.9:7333'), ''); // no key: not reachable
    expect(NodeAddress.routeFor(Uri.parse('https://store-1.deltanium.com/api')), isNull);
    expect(NodeAddress.of('https://store-1.deltanium.com', 'tcps://store-1.deltanium.com:7333'), 'https://store-1.deltanium.com');
    expect(NodeAddress.routeFor(Uri.parse('https://store-1.deltanium.com/api'))!.keyMode, isFalse);
  });

  for (final honest in [true, false]) {
    test('IP endpoint over TLS: ${honest ? "the registered node is accepted" : "a different key is refused"}', () async {
      final ctx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(_testCert!.certPem))
        ..usePrivateKeyBytes(utf8.encode(_testCert!.keyPem));
      final server = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, ctx);
      final nodeKey = BigInt.parse('11' * 32, radix: 16);
      final signingKey = honest ? nodeKey : BigInt.parse('22' * 32, radix: 16);
      server.listen((sock) async {
        final reader = DltpReader(sock);
        await reader.readExact(7);
        sock.add(DltpWire.preface);
        final hello = await reader.readFrame();
        expect(hello['method'], 'HELLO');
        final certDer = _pemToDer(_testCert!.certPem);
        sock.add(DltpWire.frame({
          'id': 0,
          'status': 200,
          'headers': {'X-Node-PubKey': vecKey, 'X-Node-Proof': _sign(signingKey, NodeProof.message(NodeProof.certHash(certDer)))},
        }));
        try {
          final req = await reader.readFrame();
          sock.add(DltpWire.frame({'id': req['id'], 'status': 200, 'headers': {}, 'body': base64.encode(utf8.encode('ok'))}));
        } catch (_) {}
        await sock.close();
      });

      final base = NodeAddress.of('', 'tcps://127.0.0.1:${server.port}', publicKey: vecKey);
      final client = DltpRoutingClient();
      try {
        if (honest) {
          final r = await client.get(Uri.parse('$base/api/version'));
          expect(r.body, 'ok');
        } else {
          await expectLater(client.get(Uri.parse('$base/api/version')), throwsA(isA<DltpException>()));
        }
      } finally {
        client.close();
        await server.close();
      }
    }, skip: _testCert == null ? 'openssl is not installed' : false);
  }

  test('requests for other hosts are untouched', () async {
    var hit = false;
    final client = DltpRoutingClient(inner: _FakeClient(() => hit = true));
    await client.get(Uri.parse('https://api.example.com/x'));
    expect(hit, isTrue);
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.onSend);
  final void Function() onSend;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onSend();
    return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
  }
}

List<int> _pemToDer(String pem) => base64.decode(pem
    .split('\n')
    .where((l) => l.isNotEmpty && !l.startsWith('-----'))
    .join());

String _sign(BigInt d, String message) {
  final domain = pc.ECDomainParameters('secp256k1');
  final signer = pc.Signer('SHA-256/DET-ECDSA')..init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(pc.ECPrivateKey(d, domain)));
  final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(message))) as pc.ECSignature;
  var s = sig.s;
  if (s > domain.n >> 1) s = domain.n - s;
  List<int> enc(BigInt v) {
    var b = v.toRadixString(16);
    if (b.length.isOdd) b = '0$b';
    final bytes = [for (var i = 0; i < b.length; i += 2) int.parse(b.substring(i, i + 2), radix: 16)];
    return bytes.first >= 0x80 ? [0, ...bytes] : bytes;
  }
  final r = enc(sig.r), ss = enc(s);
  return base64.encode([0x30, r.length + ss.length + 4, 0x02, r.length, ...r, 0x02, ss.length, ...ss]);
}
