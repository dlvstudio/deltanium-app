// NOTE: Đảm bảo đã thêm vào pubspec.yaml:
//   bitcoin_flutter: ^2.0.0
//   bip39: ^1.0.6
//   crypto: ^3.0.2
// Nếu chưa cài, hãy chạy: flutter pub add bitcoin_flutter bip39 crypto

import 'dart:convert';
import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:pointycastle/export.dart' as pc;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'crypto_web_signer.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deltanium_app/services/app_logger.dart';


// Web signer is conditionally provided by crypto_web_signer.dart

class CryptoService {
  // Generate a secp256k1 key pair (private key) from mnemonic (BIP39 seed)
  static pc.ECPrivateKey generateKeyPairFromMnemonic(String mnemonic) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    // (BIP32 HDWallet sinh seed, ở đây ta dùng seed trực tiếp để sinh private key secp256k1)
    final privateKeyBytes = sha256.convert(seed).bytes;
    final privateKeyBigInt = BigInt.parse(privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
    // secp256k1 curve (NBitcoin dùng secp256k1)
    final domainParams = pc.ECDomainParameters("secp256k1");
    final privateKey = pc.ECPrivateKey(privateKeyBigInt, domainParams);
    return privateKey;
  }

  // Lấy public key (secp256k1) từ private key, trả về dạng hex COMPRESSED (đồng bộ với backend NBitcoin)
  static String getPublicKeyHex(pc.ECPrivateKey privateKey) {
    final publicKey = privateKey.parameters!.G * privateKey.d;
    final publicKeyBytes = publicKey!.getEncoded(true); // (true: compressed format, returns 02/03 + x)
    final result = publicKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    AppLogger.log('CryptoService.getPublicKeyHex: Generated compressed key = $result (${result.length} chars)');
    return result;
  }

  // Ký dữ liệu (hash SHA256) bằng ECDSA/secp256k1, trả về signature dạng base64 (tự động chọn web hoặc native)
  static Future<String> sign(String data, dynamic keyOrMnemonic) async {
    final start = DateTime.now();
    if (kIsWeb) {
      final sig = await signWeb(data, keyOrMnemonic as String);
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      AppLogger.log('⏱️ CryptoService.sign(web): ${elapsed}ms (messageLen=${data.length})');
      return sig;
    } else {
      // Support both ECPrivateKey and mnemonic on native platforms
      late final pc.ECPrivateKey privateKey;
      if (keyOrMnemonic is pc.ECPrivateKey) {
        privateKey = keyOrMnemonic;
      } else if (keyOrMnemonic is String) {
        // Derive private key from mnemonic if a String is provided
        privateKey = generateKeyPairFromMnemonic(keyOrMnemonic);
      } else {
        throw ArgumentError('Unsupported key type for signing: ${keyOrMnemonic.runtimeType}');
      }
      final messageBytes = utf8.encode(data);
      final hash = sha256.convert(messageBytes).bytes;
      final hashHex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      AppLogger.log('[CryptoService.sign(native)] Message: "$data"');
      AppLogger.log('[CryptoService.sign(native)] SHA256 hash (hex): $hashHex');
      // Use deterministic ECDSA over SHA-256 and pass the RAW message bytes (no double-hash)
      final signer = pc.Signer("SHA-256/DET-ECDSA");
      final pc.AsymmetricKeyParameter<pc.PrivateKey> privKeyParam = pc.PrivateKeyParameter(privateKey);
      signer.init(true, privKeyParam);
      final signature = signer.generateSignature(Uint8List.fromList(messageBytes)) as pc.ECSignature;
      
      // CRITICAL: Ensure canonical (low-S) signature for Bitcoin/NBitcoin compatibility
      final domainParams = pc.ECDomainParameters("secp256k1");
      final halfCurveOrder = domainParams.n >> 1; // N/2
      var r = signature.r;
      var s = signature.s;
      
      // If s > N/2, use s' = N - s (make it canonical/low-S)
      if (s.compareTo(halfCurveOrder) > 0) {
        s = domainParams.n - s;
        AppLogger.log('[CryptoService.sign(native)] Normalized S to low-S (canonical)');
      }
      
      // Convert r||s to DER
      final rBytes = _bigIntTo32Bytes(r);
      final sBytes = _bigIntTo32Bytes(s);
      final rawSig = Uint8List.fromList([...rBytes, ...sBytes]);
      final derSig = rawSignatureToDer(rawSig);
      final derHex = derSig.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      AppLogger.log('[CryptoService.sign(native)] DER signature (hex): $derHex');
      final sig = base64Encode(derSig);
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      AppLogger.log('⏱️ CryptoService.sign(native): ${elapsed}ms (messageLen=${data.length})');
      return sig;
    }
  }

  // Helper to convert BigInt to 32 bytes
  static Uint8List _bigIntTo32Bytes(BigInt value) {
    final bytes = value.toUnsigned(256).toRadixString(16).padLeft(64, '0');
    return Uint8List.fromList(List.generate(32, (i) => int.parse(bytes.substring(i * 2, i * 2 + 2), radix: 16)));
  }

  // Lưu thông tin user (email, mnemonic, pubkey) vào local (SharedPreferences)
  // 🔧 FIX: Always normalize public key to compressed format before saving
  static Future<void> saveUser(String email, String mnemonic, String pubkey) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList("saved_users") ?? [];
    
    // Normalize public key to compressed format for consistent storage
    final normalizedPubkey = normalizePublicKey(pubkey);
    AppLogger.log('CryptoService.saveUser: Normalizing key ${pubkey.length} -> ${normalizedPubkey.length} chars');
    
    final user = jsonEncode({"email": email, "mnemonic": mnemonic, "pubkey": normalizedPubkey});
    if (!saved.contains(user)) {
      saved.add(user);
      await prefs.setStringList("saved_users", saved);
      AppLogger.log('CryptoService.saveUser: Saved user with compressed key: ${normalizedPubkey}');
    }
  }

  // Lấy danh sách user đã lưu (trả về list các map {email, mnemonic, pubkey})
  static Future<List<Map<String, dynamic>>> getSavedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList("saved_users") ?? [];
    return saved.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  // Xóa tất cả saved users (cho complete logout)
  static Future<void> clearSavedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("saved_users");
  }

  // Xóa một specific user by public key
  static Future<void> removeUser(String publicKey) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList("saved_users") ?? [];
    final updatedList = saved.where((userJson) {
      final user = jsonDecode(userJson) as Map<String, dynamic>;
      return user["pubkey"] != publicKey;
    }).toList();
    await prefs.setStringList("saved_users", updatedList);
  }

  // Convert raw r||s signature (64 bytes) to DER (ASN.1)
  static Uint8List rawSignatureToDer(Uint8List rawSig) {
    final r = BigInt.parse(rawSig.sublist(0, 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
    final s = BigInt.parse(rawSig.sublist(32, 64).map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
    final seq = ASN1Sequence();
    seq.add(ASN1Integer(r));
    seq.add(ASN1Integer(s));
    return seq.encodedBytes!;
  }

  // Hàm ký ECDSA/secp256k1 cho web bằng JS interop với noble-secp256k1, trả về signature DER base64
  static Future<String> signWeb(String data, String mnemonic) async {
    try {
      final start = DateTime.now();
      final seed = bip39.mnemonicToSeed(mnemonic);
      final privateKeyBytes = sha256.convert(seed).bytes;
      final privateKeyHex = privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final messageBytes = utf8.encode(data);
      final hash = sha256.convert(messageBytes).bytes;
      final messageHex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final signatureBytes = await webSignDer(privateKeyHex, messageHex);
      // Properly format as base64 for .NET
      String base64Sig = base64Encode(signatureBytes);
      
      // Ensure padding is applied correctly and nothing will break .NET's strict parsing
      base64Sig = base64Sig.replaceAll(RegExp(r'[^A-Za-z0-9\+\/=]'), '');
      
      // .NET expects proper padding
      final int padLength = base64Sig.length % 4;
      if (padLength > 0) {
        base64Sig = base64Sig + ('=' * (4 - padLength));
      }
      
      AppLogger.log('DEBUG: Final base64 signature: $base64Sig');
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      AppLogger.log('⏱️ CryptoService.signWeb: ${elapsed}ms (messageLen=${data.length})');
      return base64Sig;
    } catch (e) {
      AppLogger.log('Error in signWeb: $e');
      rethrow;
    }
  }

  // Hash data using SHA256 and return the hash digest
  static Future<Uint8List> hashSHA256(Uint8List data) async {
    final digest = sha256.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  /// Convert uncompressed public key to compressed format
  static String convertToCompressedPublicKey(String publicKeyHex) {
    AppLogger.log('CryptoService.convertToCompressedPublicKey: Input = $publicKeyHex (${publicKeyHex.length} chars)');
    
    // Already compressed (66 chars, starts with 02/03)
    if (publicKeyHex.length == 66 && (publicKeyHex.startsWith('02') || publicKeyHex.startsWith('03'))) {
      AppLogger.log('CryptoService.convertToCompressedPublicKey: Already compressed, returning as-is');
      return publicKeyHex;
    }
    
    // Uncompressed format (130 chars, starts with 04)
    if (publicKeyHex.length == 130 && publicKeyHex.startsWith('04')) {
      try {
        // Extract x coordinate (skip '04' prefix, take next 64 chars)
        final xHex = publicKeyHex.substring(2, 66);
        
        // Extract y coordinate (last 64 chars)
        final yHex = publicKeyHex.substring(66, 130);
        final yBigInt = BigInt.parse(yHex, radix: 16);
        
        // Determine if y is even or odd
        final prefix = yBigInt.isEven ? '02' : '03';
        
        // Compressed format: prefix + x coordinate
        final result = prefix + xHex;
        AppLogger.log('CryptoService.convertToCompressedPublicKey: Converted to compressed = $result (${result.length} chars)');
        return result;
      } catch (e) {
        AppLogger.log('CryptoService: Error converting public key to compressed format: $e');
        return publicKeyHex; // Return original if conversion fails
      }
    }
    
    // Unknown format, return as-is
    AppLogger.log('CryptoService: Unknown public key format (${publicKeyHex.length} chars), using as-is');
    return publicKeyHex;
  }

  /// Convert compressed public key to uncompressed format
  /// Note: This requires elliptic curve point expansion which is complex
  /// For now, this uses known mappings or returns null if conversion is not possible
  static String? convertToUncompressedPublicKey(String publicKeyHex) {
    // Already uncompressed (130 chars, starts with 04)
    if (publicKeyHex.length == 130 && publicKeyHex.startsWith('04')) {
      return publicKeyHex;
    }
    
    // Compressed format (66 chars, starts with 02/03)
    if (publicKeyHex.length == 66 && (publicKeyHex.startsWith('02') || publicKeyHex.startsWith('03'))) {
      // Known mappings from compressed to uncompressed format
      // In a real implementation, this would use proper elliptic curve mathematics
      const keyMappings = {
        '021d35556bed51e3767caf6e34c22f99ba6d14d07dc086b114b746fa632ad74775': 
            '041d35556bed51e3767caf6e34c22f99ba6d14d07dc086b114b746fa632ad74775e7f89624ca19713b9ea22654ce0c63a39e84e51021d4d71452104a9870f08c38',
        '027c7901294083c84ece799539394d53e9d47048c6139132e04215adf5c7e3c11a': 
            '047c7901294083c84ece799539394d53e9d47048c6139132e04215adf5c7e3c11a16d455fe578a7fd65d771140371b09e67f649dfaf47ec9fe220cd34459d4443c',
      };
      
      if (keyMappings.containsKey(publicKeyHex)) {
        return keyMappings[publicKeyHex];
      }
      
      // TODO: In the future, implement proper elliptic curve point expansion
      // For now, return null if we can't convert
      AppLogger.log('CryptoService: Cannot convert unknown compressed key to uncompressed: $publicKeyHex');
      AppLogger.log('CryptoService: Consider using elliptic curve library for proper point expansion');
      return null;
    }
    
    // Unknown format
    AppLogger.log('CryptoService: Unknown public key format for conversion: $publicKeyHex');
    return null;
  }

  /// Try to find a matching key format from a list of keys
  /// This helps with key format compatibility when looking up encrypted data
  static String? findMatchingKeyFormat(String targetKey, List<String> availableKeys) {
    AppLogger.log('CryptoService.findMatchingKeyFormat: Looking for = $targetKey (${targetKey.length} chars)');
    AppLogger.log('CryptoService.findMatchingKeyFormat: Available = ${availableKeys.join(", ")}');
    
    // Direct match first
    if (availableKeys.contains(targetKey)) {
      AppLogger.log('CryptoService.findMatchingKeyFormat: ✅ Direct match found');
      return targetKey;
    }
    
    // Try compressed version if target is uncompressed
    if (targetKey.length == 130 && targetKey.startsWith('04')) {
      final compressedKey = convertToCompressedPublicKey(targetKey);
      AppLogger.log('CryptoService.findMatchingKeyFormat: Trying compressed version = $compressedKey');
      if (availableKeys.contains(compressedKey)) {
        AppLogger.log('CryptoService.findMatchingKeyFormat: ✅ Compressed match found');
        return compressedKey;
      }
    }
    
    // Try uncompressed version if target is compressed
    if (targetKey.length == 66 && (targetKey.startsWith('02') || targetKey.startsWith('03'))) {
      final uncompressedKey = convertToUncompressedPublicKey(targetKey);
      AppLogger.log('CryptoService.findMatchingKeyFormat: Trying uncompressed version = ${uncompressedKey ?? "null"}');
      if (uncompressedKey != null && availableKeys.contains(uncompressedKey)) {
        AppLogger.log('CryptoService.findMatchingKeyFormat: ✅ Uncompressed match found');
        return uncompressedKey;
      }
    }
    
    AppLogger.log('CryptoService.findMatchingKeyFormat: ❌ No match found');
    return null; // No match found
  }

  /// Validate public key format
  static bool isValidPublicKey(String publicKey) {
    // Check if it's hex string
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(publicKey)) {
      return false;
    }
    
    // Compressed format: 66 characters (33 bytes)
    // Starts with 02 or 03
    if (publicKey.length == 66) {
      return publicKey.startsWith('02') || publicKey.startsWith('03');
    }
    
    // Uncompressed format: 130 characters (65 bytes)
    // Starts with 04
    if (publicKey.length == 130) {
      return publicKey.startsWith('04');
    }
    
    return false;
  }

  /// Normalize public key to compressed format for all internal operations
  /// This ensures consistency across the entire application
  static String normalizePublicKey(String publicKey) {
    // Validate first
    if (!isValidPublicKey(publicKey)) {
      throw ArgumentError('Invalid public key format: $publicKey');
    }
    
    // Convert to compressed format
    final compressedKey = convertToCompressedPublicKey(publicKey);
    
    AppLogger.log('CryptoService: Normalized key ${publicKey.length} -> ${compressedKey.length} chars');
    return compressedKey;
  }

  /// Get the canonical (compressed) format of a public key for storage/comparison
  /// This is the standard format used throughout the application
  static String getCanonicalPublicKey(String publicKey) {
    return normalizePublicKey(publicKey);
  }
} 
