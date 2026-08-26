import 'dart:typed_data';
import 'dart:convert';
import 'package:deltanium_app/services/file_crypto_service.dart';

void main() async {
  print('🔍 Testing Complete Metadata Storage');
  
  // Test data
  final testContent = 'Test file for complete metadata storage verification';
  final fileData = Uint8List.fromList(utf8.encode(testContent));
  final fileName = 'metadata_test.txt';
  
  print('📄 Testing with file: $fileName');
  print('📊 File size: ${fileData.length} bytes');
  
  try {
    // Generate test encryption result
    final result = await FileCryptoService.encryptAndSplitFile(
      fileData: fileData,
      fileName: fileName,
      ownerPublicKey: '02a1b2c3d4e5f6789abcdef0123456789abcdef0123456789abcdef0123456789a',
      mnemonic: 'test_mnemonic_for_metadata_check',
    );
    
    print('\n✅ Encryption successful');
    print('📋 Checking metadata completeness:');
    
    final metadata = result['metadata'] as Map<String, dynamic>;
    
    // Check required fields
    final requiredFields = [
      'fileId',
      'fileName', 
      'fileSize',
      'ownerPubKey',
      'creationTime',
      'mimeType',
      'fileExtension',
      'blockCount',           // ✅ Should be included
      'blockIds',            // ✅ Random UUIDs now
      'blockContentIds',     // ✅ Should be included
      'encryptedKeysForPubKeys',
      'merkleRoot'           // ✅ Should be included
    ];
    
    print('\n📊 Field Analysis:');
    for (final field in requiredFields) {
      final hasField = metadata.containsKey(field);
      final value = hasField ? metadata[field] : null;
      final status = hasField ? '✅' : '❌';
      
      print('  $status $field: ${_formatFieldValue(value)}');
    }
    
    // Privacy checks
    print('\n🔒 Privacy Analysis:');
    final blocks = result['blocks'] as List<Map<String, dynamic>>;
    
    print('  📦 Total blocks: ${blocks.length}');
    
    // Check that block IDs are random UUIDs (not containing fileId)
    final fileId = metadata['fileId'] as String;
    bool allBlockIdsAreRandom = true;
    
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final blockId = block['blockId'] as String;
      
      // Check if blockId contains fileId (old pattern)
      if (blockId.contains(fileId)) {
        allBlockIdsAreRandom = false;
        print('  ❌ Block $i ID contains fileId: $blockId');
      } else {
        print('  ✅ Block $i ID is random: ${blockId.substring(0, 8)}...');
      }
    }
    
    if (allBlockIdsAreRandom) {
      print('  🎉 All block IDs are properly randomized!');
    }
    
    // Check blockContentIds for integrity verification
    final blockContentIds = metadata['blockContentIds'] as List<dynamic>;
    print('  🔍 BlockContentIds count: ${blockContentIds.length}');
    
    for (int i = 0; i < blockContentIds.length && i < 3; i++) {
      final contentId = blockContentIds[i] as String;
      print('    Content ID $i: ${contentId.substring(0, 10)}...');
    }
    
    // Check merkle root
    final merkleRoot = metadata['merkleRoot'] as String;
    print('  🌳 Merkle Root: ${merkleRoot.substring(0, 16)}...');
    
    print('\n🎯 Summary:');
    print('  - Random block IDs: ${allBlockIdsAreRandom ? "✅" : "❌"}');
    print('  - Complete metadata: ${requiredFields.every((f) => metadata.containsKey(f)) ? "✅" : "❌"}');
    print('  - Integrity verification: ${blockContentIds.isNotEmpty && merkleRoot.isNotEmpty ? "✅" : "❌"}');
    
  } catch (e) {
    print('❌ Test failed: $e');
  }
}

String _formatFieldValue(dynamic value) {
  if (value == null) return 'null';
  if (value is String) return value.length > 20 ? '${value.substring(0, 20)}...' : value;
  if (value is List) return 'Array[${value.length}]';
  if (value is Map) return 'Object{${value.keys.length} keys}';
  return value.toString();
} 