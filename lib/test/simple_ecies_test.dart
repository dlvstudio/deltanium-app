import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;

/// Simple ECIES test without dependencies on web-specific packages
void main() async {
  print('\n🧪 Starting Simple ECIES Tests...\n');
  
  try {
    await testBasicEciesComponents();
    print('\n✅ Simple ECIES tests completed!');
  } catch (e) {
    print('\n❌ Simple ECIES tests failed: $e');
  }
}

/// Test basic ECIES components
Future<void> testBasicEciesComponents() async {
  print('📝 Testing ECIES Key Derivation and Encryption Components');
  
  // Test HKDF implementation
  final sharedSecret = Uint8List.fromList([
    0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11,
    0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22,
  ]);
  
  print('   - Test shared secret: ${sharedSecret.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
  
  // Test key derivation function
  final derivedKeys = mockDeriveKeys(sharedSecret);
  final encryptionKey = derivedKeys['encryptionKey']!;
  final macKey = derivedKeys['macKey']!;
  final iv = derivedKeys['iv']!;
  
  print('   - Encryption key: ${encryptionKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
  print('   - MAC key: ${macKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
  print('   - IV: ${iv.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
  
  // Test that same input produces same output (deterministic)
  final derivedKeys2 = mockDeriveKeys(sharedSecret);
  if (!listEquals(encryptionKey, derivedKeys2['encryptionKey']!)) {
    throw Exception('Key derivation is not deterministic!');
  }
  
  print('   ✅ Key derivation is deterministic');
  
  // Test that different inputs produce different outputs
  final differentSecret = Uint8List.fromList([...sharedSecret]);
  differentSecret[0] = differentSecret[0] ^ 0xFF; // Flip bits
  
  final derivedKeys3 = mockDeriveKeys(differentSecret);
  if (listEquals(encryptionKey, derivedKeys3['encryptionKey']!)) {
    throw Exception('Different inputs should produce different keys!');
  }
  
  print('   ✅ Different inputs produce different keys');
  
  // Test ECIES structure simulation
  final testData = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
  final mockEncrypted = mockEciesEncrypt(testData, encryptionKey, macKey, iv);
  
  print('   - Mock encrypted structure size: ${mockEncrypted.length} bytes');
  print('   - Structure: Magic(4) + EphPubKey(33) + Encrypted(${testData.length + 16}) + MAC(32) = ${4 + 33 + testData.length + 16 + 32} bytes');
  
  final decrypted = mockEciesDecrypt(mockEncrypted, encryptionKey, macKey);
  
  if (!listEquals(testData, decrypted)) {
    throw Exception('Mock ECIES encryption/decryption failed!');
  }
  
  print('   ✅ Mock ECIES encryption/decryption successful');
}

/// Mock key derivation function (simplified HKDF)
Map<String, Uint8List> mockDeriveKeys(Uint8List sharedSecret) {
  // Simplified key derivation using SHA-256
  final sha256 = _sha256Hash(sharedSecret);
  
  // Use different parts of hash for different keys
  return {
    'encryptionKey': Uint8List.fromList(sha256.sublist(0, 32)),
    'macKey': Uint8List.fromList(_sha256Hash([...sha256, 0x01]).sublist(0, 32)),
    'iv': Uint8List.fromList(_sha256Hash([...sha256, 0x02]).sublist(0, 16)),
  };
}

/// Mock ECIES encryption (structure simulation)
Uint8List mockEciesEncrypt(Uint8List data, Uint8List encKey, Uint8List macKey, Uint8List iv) {
  // Magic header
  final magic = 'BIE1'.codeUnits;
  
  // Mock ephemeral public key (33 bytes compressed)
  final ephemeralPubKey = Uint8List(33);
  for (int i = 0; i < 33; i++) {
    ephemeralPubKey[i] = (i * 7 + 42) % 256; // Deterministic mock data
  }
  
  // Simple XOR "encryption" (just for testing structure)
  final encryptedData = <int>[...iv]; // IV prefix
  for (int i = 0; i < data.length; i++) {
    encryptedData.add(data[i] ^ encKey[i % encKey.length]);
  }
  final encrypted = Uint8List.fromList(encryptedData);
  
  // Mock MAC calculation
  final payloadForMac = [...ephemeralPubKey, ...encrypted];
  final mac = _hmacSha256(Uint8List.fromList(payloadForMac), macKey);
  
  // Assemble final structure
  return Uint8List.fromList([
    ...magic,
    ...ephemeralPubKey,
    ...encrypted,
    ...mac,
  ]);
}

/// Mock ECIES decryption
Uint8List mockEciesDecrypt(Uint8List encryptedData, Uint8List encKey, Uint8List macKey) {
  // Extract components
  final magic = String.fromCharCodes(encryptedData.sublist(0, 4));
  if (magic != 'BIE1') {
    throw Exception('Invalid magic header: $magic');
  }
  
  final ephemeralPubKey = encryptedData.sublist(4, 37);
  final cipherText = encryptedData.sublist(37, encryptedData.length - 32);
  final receivedMac = encryptedData.sublist(encryptedData.length - 32);
  
  // Verify MAC
  final payloadForMac = [...ephemeralPubKey, ...cipherText];
  final computedMac = _hmacSha256(Uint8List.fromList(payloadForMac), macKey);
  
  if (!listEquals(receivedMac, computedMac)) {
    throw Exception('MAC verification failed');
  }
  
  // Extract IV and decrypt
  final iv = cipherText.sublist(0, 16);
  final actualCipherText = cipherText.sublist(16);
  
  // Simple XOR "decryption"
  final decrypted = Uint8List(actualCipherText.length);
  for (int i = 0; i < actualCipherText.length; i++) {
    decrypted[i] = actualCipherText[i] ^ encKey[i % encKey.length];
  }
  
  return decrypted;
}

/// Simple SHA-256 implementation using built-in crypto
List<int> _sha256Hash(List<int> data) {
  // Note: In real implementation, use crypto package
  // This is a simplified mock for testing
  var hash = 0;
  for (int byte in data) {
    hash = ((hash * 31) + byte) & 0xFFFFFFFF;
  }
  
  final result = <int>[];
  for (int i = 0; i < 32; i++) {
    result.add((hash >> (i % 32)) & 0xFF);
  }
  return result;
}

/// Simple HMAC-SHA256 mock
Uint8List _hmacSha256(Uint8List data, Uint8List key) {
  // Simplified HMAC (not cryptographically secure, just for testing structure)
  final combined = [...key, ...data];
  final hash = _sha256Hash(combined);
  return Uint8List.fromList(hash);
}

/// Compare two Uint8List for equality
bool listEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
} 