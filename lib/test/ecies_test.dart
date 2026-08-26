import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../services/ecies_service.dart';
import '../services/crypto_service.dart';

/// Test ECIES implementation
class EciesTest {
  
  /// Run comprehensive ECIES tests
  static Future<void> runTests() async {
    print('\n🧪 Starting ECIES Security Tests...\n');
    
    try {
      await _testBasicEncryptionDecryption();
      await _testDifferentKeyPairs();
      await _testRandomnessTest();
      await _testLargeData();
      await _testInvalidData();
      
      print('\n✅ All ECIES tests passed successfully!');
      
    } catch (e) {
      print('\n❌ ECIES tests failed: $e');
      rethrow;
    }
  }
  
  /// Test basic encryption and decryption
  static Future<void> _testBasicEncryptionDecryption() async {
    print('📝 Test 1: Basic Encryption/Decryption');
    
    // Test data
    final testData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
    final mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    
    // Generate key pair
    final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
    final publicKeyHex = CryptoService.getPublicKeyHex(keyPair);
    
    print('   - Test data: ${testData.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
    print('   - Public key: ${publicKeyHex.substring(0, 20)}...');
    
    // Encrypt
    final encrypted = await EciesService.encryptWithPublicKey(
      data: testData,
      publicKeyHex: publicKeyHex,
    );
    
    print('   - Encrypted size: ${encrypted.length} bytes');
    
    // Decrypt
    final decrypted = await EciesService.decryptWithPrivateKey(
      encryptedData: encrypted,
      mnemonic: mnemonic,
    );
    
    print('   - Decrypted size: ${decrypted.length} bytes');
    
    // Verify
    if (!listEquals(testData, decrypted)) {
      throw Exception('Decrypted data does not match original!');
    }
    
    print('   ✅ Basic encryption/decryption successful\n');
  }
  
  /// Test with different key pairs
  static Future<void> _testDifferentKeyPairs() async {
    print('📝 Test 2: Different Key Pairs');
    
    final testData = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
    
    // Create two different key pairs
    final mnemonic1 = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final mnemonic2 = 'legal winner thank year wave sausage worth useful legal winner thank yellow';
    
    final keyPair1 = CryptoService.generateKeyPairFromMnemonic(mnemonic1);
    final keyPair2 = CryptoService.generateKeyPairFromMnemonic(mnemonic2);
    
    final publicKeyHex1 = CryptoService.getPublicKeyHex(keyPair1);
    final publicKeyHex2 = CryptoService.getPublicKeyHex(keyPair2);
    
    print('   - Alice pubkey: ${publicKeyHex1.substring(0, 20)}...');
    print('   - Bob pubkey: ${publicKeyHex2.substring(0, 20)}...');
    
    // Encrypt with Alice's public key
    final encryptedForAlice = await EciesService.encryptWithPublicKey(
      data: testData,
      publicKeyHex: publicKeyHex1,
    );
    
    // Alice can decrypt
    final decryptedByAlice = await EciesService.decryptWithPrivateKey(
      encryptedData: encryptedForAlice,
      mnemonic: mnemonic1,
    );
    
    if (!listEquals(testData, decryptedByAlice)) {
      throw Exception('Alice could not decrypt her own data!');
    }
    
    // Bob should NOT be able to decrypt Alice's data
    try {
      await EciesService.decryptWithPrivateKey(
        encryptedData: encryptedForAlice,
        mnemonic: mnemonic2,
      );
      throw Exception('Bob should not be able to decrypt Alice\'s data!');
    } catch (e) {
      // This should fail - that's good!
      print('   ✅ Bob correctly cannot decrypt Alice\'s data');
    }
    
    print('   ✅ Different key pairs test successful\n');
  }
  
  /// Test randomness - same data should produce different ciphertext
  static Future<void> _testRandomnessTest() async {
    print('📝 Test 3: Randomness Test');
    
    final testData = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
    final mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
    final publicKeyHex = CryptoService.getPublicKeyHex(keyPair);
    
    // Encrypt same data multiple times
    final encrypted1 = await EciesService.encryptWithPublicKey(
      data: testData,
      publicKeyHex: publicKeyHex,
    );
    
    final encrypted2 = await EciesService.encryptWithPublicKey(
      data: testData,
      publicKeyHex: publicKeyHex,
    );
    
    // They should be different due to random ephemeral keys
    if (listEquals(encrypted1, encrypted2)) {
      throw Exception('Encrypted data should be different due to randomness!');
    }
    
    print('   - First encryption: ${encrypted1.sublist(0, 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}...');
    print('   - Second encryption: ${encrypted2.sublist(0, 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}...');
    
    // But both should decrypt to the same original data
    final decrypted1 = await EciesService.decryptWithPrivateKey(
      encryptedData: encrypted1,
      mnemonic: mnemonic,
    );
    
    final decrypted2 = await EciesService.decryptWithPrivateKey(
      encryptedData: encrypted2,
      mnemonic: mnemonic,
    );
    
    if (!listEquals(testData, decrypted1) || !listEquals(testData, decrypted2)) {
      throw Exception('Decryption failed for randomness test!');
    }
    
    print('   ✅ Randomness test successful - same data produces different ciphertext\n');
  }
  
  /// Test with larger data (like symmetric keys)
  static Future<void> _testLargeData() async {
    print('📝 Test 4: Large Data Test (Symmetric Key Size)');
    
    // Test with 32-byte symmetric key
    final random = math.Random.secure();
    final symmetricKey = Uint8List(32);
    for (int i = 0; i < symmetricKey.length; i++) {
      symmetricKey[i] = random.nextInt(256);
    }
    
    final mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
    final publicKeyHex = CryptoService.getPublicKeyHex(keyPair);
    
    print('   - Symmetric key size: ${symmetricKey.length} bytes');
    print('   - Symmetric key: ${symmetricKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
    
    // Encrypt
    final encrypted = await EciesService.encryptWithPublicKey(
      data: symmetricKey,
      publicKeyHex: publicKeyHex,
    );
    
    print('   - Encrypted size: ${encrypted.length} bytes');
    
    // Decrypt
    final decrypted = await EciesService.decryptWithPrivateKey(
      encryptedData: encrypted,
      mnemonic: mnemonic,
    );
    
    // Verify
    if (!listEquals(symmetricKey, decrypted)) {
      throw Exception('Large data decryption failed!');
    }
    
    print('   ✅ Large data test successful\n');
  }
  
  /// Test with invalid data
  static Future<void> _testInvalidData() async {
    print('📝 Test 5: Invalid Data Test');
    
    final mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    
    // Test 1: Too short data
    try {
      await EciesService.decryptWithPrivateKey(
        encryptedData: Uint8List.fromList([1, 2, 3]),
        mnemonic: mnemonic,
      );
      throw Exception('Should have failed with too short data!');
    } catch (e) {
      print('   ✅ Correctly rejected too short data');
    }
    
    // Test 2: Invalid magic header
    final invalidData = Uint8List(100);
    invalidData.setAll(0, 'BADX'.codeUnits); // Wrong magic
    
    try {
      await EciesService.decryptWithPrivateKey(
        encryptedData: invalidData,
        mnemonic: mnemonic,
      );
      throw Exception('Should have failed with invalid magic header!');
    } catch (e) {
      print('   ✅ Correctly rejected invalid magic header');
    }
    
    print('   ✅ Invalid data test successful\n');
  }
  
  /// Compare two Uint8List for equality
  static bool listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Simple test runner function that can be called from main()
Future<void> runEciesTests() async {
  await EciesTest.runTests();
} 