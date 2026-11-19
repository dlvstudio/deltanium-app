import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// DLTP v1 framing: the client sends `DLTP/1\n`, the server echoes it, then each
/// frame is a 4-byte big-endian length followed by UTF-8 JSON.
class DltpWire {
  DltpWire._();

  static final Uint8List preface = Uint8List.fromList(utf8.encode('DLTP/1\n'));
  static const int maxFrame = 16 * 1024 * 1024;

  static Uint8List frame(Map<String, dynamic> message) {
    final payload = utf8.encode(json.encode(message));
    if (payload.length > maxFrame) throw DltpException('frame too large (${payload.length} bytes)');
    final out = Uint8List(4 + payload.length);
    ByteData.sublistView(out).setUint32(0, payload.length, Endian.big);
    out.setRange(4, out.length, payload);
    return out;
  }

  static Map<String, dynamic> request({
    required int id,
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> body,
  }) =>
      {
        'id': id,
        'method': method,
        'path': path,
        'headers': headers,
        if (body.isNotEmpty) 'body': base64.encode(body),
      };
}

class DltpException implements Exception {
  final String message;
  DltpException(this.message);
  @override
  String toString() => 'DltpException: $message';
}

/// Reads exact byte counts from a socket's byte stream.
class DltpReader {
  final _buf = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);
  Completer<void>? _waiter;
  Object? _error;
  bool _done = false;
  late final StreamSubscription<List<int>> _sub;

  DltpReader(Stream<List<int>> input) {
    _sub = input.listen(
      (chunk) {
        _buf.add(chunk);
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> readExact(int n) async {
    while (true) {
      if (_buf.length > 0) {
        final add = _buf.takeBytes();
        _pending = _pending.isEmpty ? add : (BytesBuilder(copy: false)..add(_pending)..add(add)).takeBytes();
      }
      if (_pending.length >= n) {
        final out = Uint8List.sublistView(_pending, 0, n);
        _pending = Uint8List.sublistView(_pending, n);
        return out;
      }
      if (_error != null) throw DltpException('connection error: $_error');
      if (_done) throw DltpException('connection closed');
      _waiter = Completer<void>();
      await _waiter!.future;
    }
  }

  Future<Map<String, dynamic>> readFrame() async {
    final head = await readExact(4);
    final n = ByteData.sublistView(head).getUint32(0, Endian.big);
    if (n > DltpWire.maxFrame) throw DltpException('frame too large ($n bytes)');
    final payload = await readExact(n);
    final decoded = json.decode(utf8.decode(payload));
    if (decoded is! Map) throw DltpException('bad frame');
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> cancel() => _sub.cancel();
}
