import 'dart:typed_data';
import 'dart:math' as math;
import '../services/file_crypto_service.dart';
import '../services/crypto_service.dart';

/// Test file splitting functionality
void main() async {
  print('🧪 Testing File Splitting Functionality...\n');
  
  try {
    // Test 1: Small file (should be 1 block)
    await testSmallFile();
    
    // Test 2: Medium file (should be 2-3 blocks)
    await testMediumFile();
    
    // Test 3: Large file (should be multiple blocks)
    await testLargeFile();
    
    print('\n✅ All file splitting tests passed!');
    
  } catch (e) {
    print('\n❌ File splitting tests failed: $e');
  }
}

Future<void> testSmallFile() async {
  print('📝 Test 1: Small file (1MB)');
  
  // Create 1MB file
  final fileData = _createTestFile(1 * 1024 * 1024); // 1MB
  final testMnemonic = 'test mnemonic for crypto operations here today';
  final keyPair = CryptoService.generateKeyPairFromMnemonic(testMnemonic);
  final pubKey = CryptoService.getPublicKeyHex(keyPair);
  
  final result = await FileCryptoService.encryptAndSplitFile(
    fileData: fileData,
    fileName: 'test_1mb.dat',
    ownerPublicKey: pubKey,
    mnemonic: testMnemonic,
    blockSize: 4 * 1024 * 1024, // 4MB blocks
  );
  
  final metadata = result['metadata'] as Map<String, dynamic>;
  final blocks = result['blocks'] as List<Map<String, dynamic>>;
  
  print('   File size: ${fileData.length} bytes');
  print('   Block count: ${metadata['blockCount']}');
  print('   Actual blocks created: ${blocks.length}');
  print('   Expected blocks: 1');
  
  if (metadata['blockCount'] != 1 || blocks.length != 1) {
    throw Exception('Small file should create 1 block, got ${blocks.length}');
  }
  
  print('   ✅ Small file test passed\n');
}

Future<void> testMediumFile() async {
  print('📝 Test 2: Medium file (6MB)');
  
  // Create 6MB file
  final fileData = _createTestFile(6 * 1024 * 1024); // 6MB
  final testMnemonic = 'test mnemonic for crypto operations here today';
  final keyPair = CryptoService.generateKeyPairFromMnemonic(testMnemonic);
  final pubKey = CryptoService.getPublicKeyHex(keyPair);
  
  final result = await FileCryptoService.encryptAndSplitFile(
    fileData: fileData,
    fileName: 'test_6mb.dat',
    ownerPublicKey: pubKey,
    mnemonic: testMnemonic,
    blockSize: 4 * 1024 * 1024, // 4MB blocks
  );
  
  final metadata = result['metadata'] as Map<String, dynamic>;
  final blocks = result['blocks'] as List<Map<String, dynamic>>;
  
  print('   File size: ${fileData.length} bytes');
  print('   Block count: ${metadata['blockCount']}');
  print('   Actual blocks created: ${blocks.length}');
  print('   Expected blocks: 2 (6MB / 4MB = 1.5 → ceil = 2)');
  
  if (metadata['blockCount'] != 2 || blocks.length != 2) {
    throw Exception('6MB file should create 2 blocks, got ${blocks.length}');
  }
  
  // Verify block sizes
  final block0Size = blocks[0]['size'] as int;
  final block1Size = blocks[1]['size'] as int;
  
  print('   Block 0 size: $block0Size bytes');
  print('   Block 1 size: $block1Size bytes');
  
  if (block0Size != 4 * 1024 * 1024) {
    throw Exception('First block should be 4MB, got $block0Size bytes');
  }
  
  if (block1Size != 2 * 1024 * 1024) {
    throw Exception('Second block should be 2MB, got $block1Size bytes');
  }
  
  print('   ✅ Medium file test passed\n');
}

Future<void> testLargeFile() async {
  print('📝 Test 3: Large file (10MB)');
  
  // Create 10MB file
  final fileData = _createTestFile(10 * 1024 * 1024); // 10MB
  final testMnemonic = 'test mnemonic for crypto operations here today';
  final keyPair = CryptoService.generateKeyPairFromMnemonic(testMnemonic);
  final pubKey = CryptoService.getPublicKeyHex(keyPair);
  
  final result = await FileCryptoService.encryptAndSplitFile(
    fileData: fileData,
    fileName: 'test_10mb.dat',
    ownerPublicKey: pubKey,
    mnemonic: testMnemonic,
    blockSize: 4 * 1024 * 1024, // 4MB blocks
  );
  
  final metadata = result['metadata'] as Map<String, dynamic>;
  final blocks = result['blocks'] as List<Map<String, dynamic>>;
  
  print('   File size: ${fileData.length} bytes');
  print('   Block count: ${metadata['blockCount']}');
  print('   Actual blocks created: ${blocks.length}');
  print('   Expected blocks: 3 (10MB / 4MB = 2.5 → ceil = 3)');
  
  if (metadata['blockCount'] != 3 || blocks.length != 3) {
    throw Exception('10MB file should create 3 blocks, got ${blocks.length}');
  }
  
  // Verify block sizes
  final block0Size = blocks[0]['size'] as int;
  final block1Size = blocks[1]['size'] as int;
  final block2Size = blocks[2]['size'] as int;
  
  print('   Block 0 size: $block0Size bytes');
  print('   Block 1 size: $block1Size bytes');
  print('   Block 2 size: $block2Size bytes');
  
  if (block0Size != 4 * 1024 * 1024) {
    throw Exception('First block should be 4MB, got $block0Size bytes');
  }
  
  if (block1Size != 4 * 1024 * 1024) {
    throw Exception('Second block should be 4MB, got $block1Size bytes');
  }
  
  if (block2Size != 2 * 1024 * 1024) {
    throw Exception('Third block should be 2MB, got $block2Size bytes');
  }
  
  print('   ✅ Large file test passed\n');
}

/// Create test file with specified size
Uint8List _createTestFile(int sizeInBytes) {
  final random = math.Random.secure();
  final data = Uint8List(sizeInBytes);
  
  for (int i = 0; i < sizeInBytes; i++) {
    data[i] = random.nextInt(256);
  }
  
  return data;
} 