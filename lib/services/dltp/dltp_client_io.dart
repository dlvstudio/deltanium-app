import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'dltp_wire.dart';
import 'node_address.dart';
import 'node_proof.dart';

/// An [http.Client] that sends requests for nodes with a DLTP endpoint over TCP
/// (see [NodeAddress]) and everything else over plain HTTPS.
class DltpRoutingClient extends http.BaseClient {
  DltpRoutingClient({http.Client? inner}) : _inner = inner ?? IOClient();

  final http.Client _inner;

  /// Bodies above this go over HTTPS when the node has it (base64 grows them by a third).
  static const int _maxDltpBody = 11 * 1024 * 1024;
  static const Duration _timeout = Duration(seconds: 60);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final route = NodeAddress.routeFor(request.url);
    if (route == null) return _inner.send(request);

    final body = await request.finalize().toBytes();
    if (body.length > _maxDltpBody && route.hasHttps) return _inner.send(_copy(request, body));

    try {
      final res = await DltpPool.instance.send(route, request.method, _pathOf(request.url), request.headers, body).timeout(_timeout);
      return http.StreamedResponse(
        Stream.value(res.body),
        res.status,
        contentLength: res.body.length,
        request: request,
        headers: res.headers,
      );
    } catch (e) {
      if (!route.hasHttps) rethrow;
      return _inner.send(_copy(request, body)); // DLTP unreachable: same request over HTTPS
    }
  }

  static String _pathOf(Uri u) => (u.path.isEmpty ? '/' : u.path) + (u.hasQuery ? '?${u.query}' : '');

  static http.Request _copy(http.BaseRequest original, Uint8List body) {
    final copy = http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    copy.headers.addAll(original.headers);
    copy.bodyBytes = body;
    return copy;
  }

  @override
  void close() => _inner.close();
}

class DltpResult {
  final int status;
  final Map<String, String> headers;
  final Uint8List body;
  DltpResult(this.status, this.headers, this.body);
}

/// Keeps idle DLTP connections per node; one request at a time per connection.
class DltpPool {
  DltpPool._();
  static final DltpPool instance = DltpPool._();

  final Map<String, List<_Conn>> _idle = {};
  int _nextId = 1;

  Future<DltpResult> send(DltpRoute route, String method, String path, Map<String, String> headers, List<int> body) async {
    // Keyed by the node key too: a connection proven for one key is never reused for another.
    final key = '${route.tls}|${route.authority}|${route.nodePublicKey ?? ''}';
    final pooled = _idle[key];
    var conn = (pooled != null && pooled.isNotEmpty) ? pooled.removeLast() : null;
    final reused = conn != null;
    conn ??= await _Conn.open(route);
    try {
      final res = await conn.call(_nextId++, method, path, headers, body);
      (_idle[key] ??= []).add(conn);
      return res;
    } catch (_) {
      conn.close();
      if (!reused) rethrow;
      // An idle connection the server already closed: one retry on a fresh one.
      final fresh = await _Conn.open(route);
      try {
        final res = await fresh.call(_nextId++, method, path, headers, body);
        (_idle[key] ??= []).add(fresh);
        return res;
      } catch (_) {
        fresh.close();
        rethrow;
      }
    }
  }
}

class _Conn {
  final Socket socket;
  final DltpReader reader;
  final String host;
  _Conn(this.socket, this.reader, this.host);

  static Future<_Conn> open(DltpRoute route) async {
    final t = route.tcp;
    final Socket socket = route.tls
        ? await SecureSocket.connect(t.host, t.port,
            timeout: const Duration(seconds: 15),
            // IP endpoint: the certificate is self-signed; the node key vouches for it below (HELLO).
            onBadCertificate: route.keyMode ? (_) => true : null)
        : await Socket.connect(t.host, t.port, timeout: const Duration(seconds: 15));
    final reader = DltpReader(socket);
    try {
      socket.add(DltpWire.preface);
      await socket.flush();
      final echo = await reader.readExact(DltpWire.preface.length);
      if (utf8.decode(echo) != 'DLTP/1\n') throw DltpException('bad preface');
      if (route.keyMode) await _proveNode(socket as SecureSocket, reader, route);
      return _Conn(socket, reader, route.authority);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  /// HELLO: the node must sign this connection's TLS certificate with its registered key.
  static Future<void> _proveNode(SecureSocket socket, DltpReader reader, DltpRoute route) async {
    final cert = socket.peerCertificate;
    if (cert == null || route.nodePublicKey == null) throw DltpException('no certificate or node key');
    socket.add(DltpWire.frame({'id': 0, 'method': 'HELLO', 'path': '/'}));
    await socket.flush();
    final r = await reader.readFrame();
    final h = <String, String>{};
    (r['headers'] as Map? ?? const {}).forEach((k, v) => h[k.toString().toLowerCase()] = v.toString());
    final ok = (r['id'] as num?)?.toInt() == 0 &&
        (r['status'] as num?)?.toInt() == 200 &&
        NodeProof.verify(
          expectedPublicKey: route.nodePublicKey!,
          presentedPublicKey: h['x-node-pubkey'],
          proofBase64: h['x-node-proof'],
          certificateDer: cert.der,
        );
    if (!ok) throw DltpException('node did not prove its registered key');
  }

  Future<DltpResult> call(int id, String method, String path, Map<String, String> headers, List<int> body) async {
    final h = <String, String>{};
    headers.forEach((k, v) {
      final lower = k.toLowerCase();
      if (lower != 'host' && lower != 'content-length') h[k] = v;
    });
    h['Host'] = host;
    socket.add(DltpWire.frame(DltpWire.request(id: id, method: method, path: path, headers: h, body: body)));
    await socket.flush();
    final r = await reader.readFrame();
    if ((r['id'] as num?)?.toInt() != id) throw DltpException('response id mismatch');
    final headersOut = <String, String>{};
    (r['headers'] as Map? ?? const {}).forEach((k, v) => headersOut[k.toString().toLowerCase()] = v.toString());
    final rawBody = r['body'] as String?;
    return DltpResult(
      (r['status'] as num?)?.toInt() ?? 502,
      headersOut,
      rawBody == null || rawBody.isEmpty ? Uint8List(0) : base64.decode(rawBody),
    );
  }

  void close() {
    reader.cancel();
    socket.destroy();
  }
}
