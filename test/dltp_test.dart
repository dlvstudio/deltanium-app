import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:deltanium_app/services/dltp/dltp_client_io.dart';
import 'package:deltanium_app/services/dltp/dltp_wire.dart';
import 'package:deltanium_app/services/dltp/node_address.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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
