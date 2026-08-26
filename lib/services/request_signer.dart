import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:flutter/foundation.dart';
import 'package:deltanium_app/services/app_logger.dart';


class RequestSigner {
  final String publicKey;
  final String mnemonic;

  RequestSigner({
    required this.publicKey,
    required this.mnemonic,
  });

  /// Sign a request and return timestamp and signature
  Future<Map<String, String>> signRequest(String method, String path, [Uint8List? bodyBytes]) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    
    // Build message to sign: METHOD + PATH + TIMESTAMP + BODY_HASH
    final messageBuilder = StringBuffer();
    messageBuilder.write(method.toUpperCase());
    messageBuilder.write(path);
    messageBuilder.write(timestamp);
    
    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      final bodyHash = sha256.convert(bodyBytes);
      messageBuilder.write(base64Encode(bodyHash.bytes));
    }
    
    final message = messageBuilder.toString();
    
    // Use the same CryptoService.sign method used in file uploads
    final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
    final signature = await CryptoService.sign(message, kIsWeb ? mnemonic : keyPair);
    
    return {
      'timestamp': timestamp,
      'signature': signature,
    };
  }

  /// Sign arbitrary message data (used by storage contracts)
  Future<String> signData(String message) async {
    final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
    return CryptoService.sign(message, kIsWeb ? mnemonic : keyPair);
  }

  /// Get normalized (compressed) public key for API headers
  /// This ensures all API calls use consistent compressed format
  String getPublicKeyBase64() {
    // 🔧 FIX: Normalize to compressed format for API consistency
    final normalizedKey = CryptoService.normalizePublicKey(publicKey);
    AppLogger.log('RequestSigner: Normalized public key ${publicKey.length} -> ${normalizedKey.length} chars');
    return normalizedKey;
  }
} 
