import 'dart:typed_data';
import 'dart:math' as math;
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto_lib;
import 'package:bip39/bip39.dart' as bip39;
import 'package:deltanium_app/services/app_logger.dart';


/// ECIES (Elliptic Curve Integrated Encryption Scheme) Service
/// Provides secure encryption/decryption of symmetric keys using public/private key pairs
class EciesService {
  static const String MAGIC_HEADER = 'BIE1'; // Bitcoin ECIES v1
  static const int PUBKEY_SIZE = 33; // Compressed public key
  static const int MAC_SIZE = 32; // HMAC-SHA256
  static const int IV_SIZE = 16; // AES-CBC IV size
  
  /// Encrypt data using ECIES (for symmetric key encryption)
  static Future<Uint8List> encryptWithPublicKey({
    required Uint8List data,
    required String publicKeyHex,
  }) async {
    Uint8List? sharedSecret;
    Uint8List? encryptionKey;
    Uint8List? macKey;
    
    try {
      // 1. Parse recipient's public key
      final recipientPubKey = _parsePublicKey(publicKeyHex);
      
      // 2. Generate ephemeral key pair
      final ephemeralKeyPair = _generateKeyPair();
      final ephemeralPrivKey = ephemeralKeyPair.privateKey as ECPrivateKey;
      final ephemeralPubKey = ephemeralKeyPair.publicKey as ECPublicKey;
      
      // 3. Compute shared secret using ECDH
      sharedSecret = _computeSharedSecret(ephemeralPrivKey, recipientPubKey);
      
      // 4. Derive keys from shared secret using KDF
      final derivedKeys = _deriveKeys(sharedSecret);
      encryptionKey = derivedKeys['encryptionKey']!;
      macKey = derivedKeys['macKey']!;
      final iv = derivedKeys['iv']!;
      
      // 5. Encrypt data with AES-CBC
      final encryptedData = await _encryptAesCbc(data, encryptionKey, iv);
      
      // 6. Get compressed ephemeral public key
      final ephemeralPubKeyBytes = _compressPublicKey(ephemeralPubKey);
      
      // 7. Create payload for MAC calculation
      final payloadForMac = Uint8List.fromList([
        ...ephemeralPubKeyBytes,
        ...encryptedData,
      ]);
      
      // 8. Compute MAC
      final mac = _computeHmac(payloadForMac, macKey);
      
      // 9. Assemble final result: [MAGIC][EPHEMERAL_PUBKEY][ENCRYPTED_DATA][MAC]
      final result = Uint8List.fromList([
        ...MAGIC_HEADER.codeUnits,
        ...ephemeralPubKeyBytes,
        ...encryptedData,
        ...mac,
      ]);
      
      return result;
      
    } catch (e) {
      AppLogger.log('EciesService: ECIES encryption failed with error: $e');
      AppLogger.log('EciesService: Stack trace: ${StackTrace.current}');
      throw Exception('ECIES encryption failed: $e');
    } finally {
      // Clear sensitive data from memory
      _clearSensitiveData(sharedSecret);
      _clearSensitiveData(encryptionKey);
      _clearSensitiveData(macKey);
    }
  }
  
  /// Decrypt data using ECIES (for symmetric key decryption)
  static Future<Uint8List> decryptWithPrivateKey({
    required Uint8List encryptedData,
    required String mnemonic,
  }) async {
    Uint8List? sharedSecret;
    Uint8List? encryptionKey;
    Uint8List? macKey;
    
    try {
      // 1. Validate minimum size and magic header
      if (encryptedData.length < 4 + PUBKEY_SIZE + IV_SIZE + MAC_SIZE) {
        throw Exception('Invalid encrypted data format');
      }
      
      final magic = String.fromCharCodes(encryptedData.sublist(0, 4));
      if (magic != MAGIC_HEADER) {
        throw Exception('Invalid data format');
      }
      
      // 2. Extract components
      int offset = 4;
      final ephemeralPubKeyBytes = encryptedData.sublist(offset, offset + PUBKEY_SIZE);
      offset += PUBKEY_SIZE;
      
      final cipherText = encryptedData.sublist(offset, encryptedData.length - MAC_SIZE);
      final receivedMac = encryptedData.sublist(encryptedData.length - MAC_SIZE);
      
      // 3. Parse ephemeral public key
      final ephemeralPubKey = _parseCompressedPublicKey(ephemeralPubKeyBytes);
      
      // 4. Get recipient's private key from mnemonic
      final recipientPrivKey = _getPrivateKeyFromMnemonic(mnemonic);
      
      // 5. Compute shared secret using ECDH
      sharedSecret = _computeSharedSecret(recipientPrivKey, ephemeralPubKey);
      
      // 6. Derive keys from shared secret
      final derivedKeys = _deriveKeys(sharedSecret);
      encryptionKey = derivedKeys['encryptionKey']!;
      macKey = derivedKeys['macKey']!;
      final iv = derivedKeys['iv']!;
      
      // 7. Verify MAC
      final payloadForMac = Uint8List.fromList([
        ...ephemeralPubKeyBytes,
        ...cipherText,
      ]);
      final computedMac = _computeHmac(payloadForMac, macKey);
      
      if (!_constantTimeEquals(receivedMac, computedMac)) {
        throw Exception('Authentication failed');
      }
      
      // 8. Decrypt data
      final decryptedData = await _decryptAesCbc(cipherText, encryptionKey, iv);
      
      return decryptedData;
      
    } catch (e) {
      AppLogger.log('EciesService: ECIES decryption failed with error: $e');
      AppLogger.log('EciesService: Stack trace: ${StackTrace.current}');
      throw Exception('ECIES decryption failed: $e');
    } finally {
      // Clear sensitive data from memory
      _clearSensitiveData(sharedSecret);
      _clearSensitiveData(encryptionKey);
      _clearSensitiveData(macKey);
    }
  }
  
  // ================================
  // PRIVATE HELPER METHODS
  // ================================
  
  /// Generate a new ECDSA key pair using secp256k1
  static AsymmetricKeyPair<ECPublicKey, ECPrivateKey> _generateKeyPair() {
    final keyGen = ECKeyGenerator();
    final secureRandom = FortunaRandom();
    
    // Seed the random number generator
    final seedSource = math.Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(seedSource.nextInt(256));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    
    // Use secp256k1 curve (same as Bitcoin)
    final domainParams = ECDomainParameters('secp256k1');
    keyGen.init(ParametersWithRandom(ECKeyGeneratorParameters(domainParams), secureRandom));
    
    final keyPair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<ECPublicKey, ECPrivateKey>(
      keyPair.publicKey as ECPublicKey,
      keyPair.privateKey as ECPrivateKey,
    );
  }
  
  /// Parse public key from hex string
  static ECPublicKey _parsePublicKey(String publicKeyHex) {
    AppLogger.log('EciesService: Parsing public key: ${publicKeyHex.substring(0, 16)}... (${publicKeyHex.length} chars)');
    final publicKeyBytes = _hexToBytes(publicKeyHex);
    AppLogger.log('EciesService: Public key bytes length: ${publicKeyBytes.length}');
    return _parseCompressedPublicKey(publicKeyBytes);
  }
  
  /// Parse compressed public key from bytes
  static ECPublicKey _parseCompressedPublicKey(Uint8List bytes) {
    if (bytes.length != 33) {
      throw Exception('Invalid compressed public key length: ${bytes.length}');
    }
    
    final domainParams = ECDomainParameters('secp256k1');
    final curve = domainParams.curve;
    
    // Parse compressed point
    final point = curve.decodePoint(bytes);
    if (point == null) {
      throw Exception('Failed to decode compressed public key');
    }
    
    return ECPublicKey(point, domainParams);
  }
  
  /// Get private key from mnemonic (using same method as CryptoService)
  static ECPrivateKey _getPrivateKeyFromMnemonic(String mnemonic) {
    // 🔧 FIX: Use BIP39 proper seed derivation to match CryptoService
    final seed = bip39.mnemonicToSeed(mnemonic);
    final privateKeyBytes = sha256.convert(seed).bytes;
    
    final domainParams = ECDomainParameters('secp256k1');
    final d = BigInt.parse(
      privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(''),
      radix: 16,
    );
    
    return ECPrivateKey(d, domainParams);
  }
  
  /// Compute shared secret using ECDH
  static Uint8List _computeSharedSecret(ECPrivateKey privateKey, ECPublicKey publicKey) {
    final ecdh = ECDHBasicAgreement();
    ecdh.init(privateKey);
    
    final sharedSecret = ecdh.calculateAgreement(publicKey);
    
    // Convert BigInt to 32-byte array
    final bytes = _bigIntToBytes(sharedSecret, 32);
    return bytes;
  }
  
  /// Derive encryption key, MAC key, and IV from shared secret using HKDF
  static Map<String, Uint8List> _deriveKeys(Uint8List sharedSecret) {
    // Use HKDF-SHA256 to derive keys
    // Extract phase
    final hmac = Hmac(sha256, Uint8List(32)); // Empty salt
    final prk = Uint8List.fromList(hmac.convert(sharedSecret).bytes);
    
    // Expand phase
    final info = Uint8List.fromList('ECIES-AES256-HMAC-SHA256'.codeUnits);
    final expandedKeys = _hkdfExpand(prk, info, 64); // 32 for encryption + 32 for MAC
    
    // Additional IV derivation from shared secret
    final ivSource = sha256.convert([...sharedSecret, ...info]).bytes;
    
    return {
      'encryptionKey': expandedKeys.sublist(0, 32),
      'macKey': expandedKeys.sublist(32, 64),
      'iv': Uint8List.fromList(ivSource.sublist(0, 16)),
    };
  }
  
  /// HKDF Expand function
  static Uint8List _hkdfExpand(Uint8List prk, Uint8List info, int length) {
    final hmac = Hmac(sha256, prk);
    final result = <int>[];
    int iterations = (length / 32).ceil();
    Uint8List t = Uint8List(0);
    
    for (int i = 1; i <= iterations; i++) {
      final input = [...t, ...info, i];
      t = Uint8List.fromList(hmac.convert(input).bytes);
      result.addAll(t);
    }
    
    return Uint8List.fromList(result.sublist(0, length));
  }
  
  /// Encrypt data using AES-CBC
  static Future<Uint8List> _encryptAesCbc(Uint8List data, Uint8List key, Uint8List iv) async {
    try {
      final aesKey = await crypto_lib.AesCbc.with256bits(macAlgorithm: crypto_lib.MacAlgorithm.empty);
      final secretKey = await aesKey.newSecretKeyFromBytes(key);
      final secretBox = await aesKey.encrypt(data, secretKey: secretKey, nonce: iv);
      return Uint8List.fromList(secretBox.cipherText);
    } catch (e) {
      // Fallback to PointyCastle if cryptography package fails
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      cipher.init(true, PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null,
      ));
      return cipher.process(data);
    }
  }
  
  /// Decrypt data using AES-CBC
  static Future<Uint8List> _decryptAesCbc(Uint8List encryptedData, Uint8List key, Uint8List iv) async {
    try {
      final aesKey = await crypto_lib.AesCbc.with256bits(macAlgorithm: crypto_lib.MacAlgorithm.empty);
      final secretKey = await aesKey.newSecretKeyFromBytes(key);
      final secretBox = crypto_lib.SecretBox(encryptedData, nonce: iv, mac: crypto_lib.Mac.empty);
      final decrypted = await aesKey.decrypt(secretBox, secretKey: secretKey);
      return Uint8List.fromList(decrypted);
    } catch (e) {
      // Fallback to PointyCastle if cryptography package fails
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      cipher.init(false, PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null,
      ));
      return cipher.process(encryptedData);
    }
  }
  
  /// Compute HMAC-SHA256
  static Uint8List _computeHmac(Uint8List data, Uint8List key) {
    final hmac = Hmac(sha256, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
  }
  
  /// Get compressed public key bytes from ECPublicKey
  static Uint8List _compressPublicKey(ECPublicKey pubKey) {
    return pubKey.Q!.getEncoded(true); // true = compressed
  }
  
  /// Constant time comparison to prevent timing attacks
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
  
  /// Convert hex string to bytes
  static Uint8List _hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      throw Exception('Invalid hex string length');
    }
    
    return Uint8List.fromList(
      List.generate(hex.length ~/ 2, (i) =>
        int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)
      )
    );
  }
  
  /// Convert BigInt to fixed-length byte array
  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final bytes = <int>[];
    var temp = value;
    
    for (int i = 0; i < length; i++) {
      bytes.insert(0, (temp & BigInt.from(0xff)).toInt());
      temp = temp >> 8;
    }
    
    return Uint8List.fromList(bytes);
  }
  
  /// Clear sensitive data from memory by filling with zeros
  static void _clearSensitiveData(Uint8List? data) {
    if (data != null) {
      data.fillRange(0, data.length, 0);
    }
  }
} 
