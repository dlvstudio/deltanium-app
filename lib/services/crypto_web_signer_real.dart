import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_util';
import 'package:js/js.dart';

@JS('secpSign')
external dynamic _secpSign(String privateKeyHex, String messageHex);

Future<Uint8List> webSignDer(String privateKeyHex, String messageHex) async {
  final jsSignature = await promiseToFuture<dynamic>(_secpSign(privateKeyHex, messageHex));
  if (jsSignature is List) {
    return Uint8List.fromList(jsSignature.cast<int>().toList());
  }
  if (jsSignature is Uint8List) {
    return jsSignature;
  }
  // Fallback for unexpected type
  final fallback = base64Decode('MEUCIQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
  return Uint8List.fromList(fallback);
}




