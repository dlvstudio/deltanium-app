// Downloads and decrypts one attached file the way posts show it (runs in a background isolate via compute).
// Moved out of RelatedFilesWidget so the same code path can be tested against real Store nodes.
import 'package:flutter/foundation.dart';
import 'package:deltanium_app/services/egress_receipt_service.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';

class AttachmentDownloader {
  AttachmentDownloader._();

  /// params: fileId, nodeEndpoint, userPublicKey, userMnemonic, optional fileName / fileSize.
  /// Returns {success: true, imageData: Uint8List} or {success: false, error}.
  static Future<Map<String, dynamic>> download(Map<String, dynamic> params) async {
    try {
      final fileId = params['fileId'] as String;
      final nodeEndpoint = params['nodeEndpoint'] as String;
      final userPublicKey = params['userPublicKey'] as String;
      final userMnemonic = params['userMnemonic'] as String;
      final String? fileName = params['fileName'] as String?; // 🆕 For matching user's file
      final int? fileSize = params['fileSize'] as int?; // 🆕 For matching user's file
      
      
      // Step 1: Download file metadata to get encryptedKey
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final metadataPath = '/api/file/download/$fileId';
      final bodyHash = '';
      
      final dataToSign = '$method$metadataPath$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, userMnemonic);
      
      var fileMetadataResponse = await BlockHttp.get(
        Uri.parse('$nodeEndpoint$metadataPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      
      if (fileMetadataResponse.statusCode != 200) {
        throw Exception('Failed to download file metadata: ${fileMetadataResponse.statusCode}');
      }
      
      var fileMetadata = json.decode(fileMetadataResponse.body);
      var recipientPubKey = fileMetadata['recipientPubKey'] as String?;
      var encryptedKey = fileMetadata['encryptedKey'] as String?;
      var firstBlockId = fileMetadata['firstBlockId'] as String?;
      // 🆕 Check if this is a public file
      final bool isPublic = fileMetadata['isPublic'] == true || 
                           (fileMetadata['encryptedType'] as String? ?? '').toLowerCase() == 'public' ||
                           (fileMetadata['shareType'] as String? ?? '').toLowerCase() == 'public';
      // PRE fields from store metadata (if any)
      final String? policyTag = fileMetadata['policyTag'] as String?;
      final String? capsuleFor = fileMetadata['capsuleFor'] as String?;
      final String? ownerPubKey = fileMetadata['ownerPubKey'] as String?;
      final String? encapsulatedForRecipient = fileMetadata['encapsulatedForRecipient'] as String?;
      
      // 🆕 FIX: Check if this metadata entry belongs to the requesting user
      // If not, try to find the user's fileId from their file list
      String? actualFileId = fileId;
      bool needsUserFileId = false;
      
      if (recipientPubKey != null && recipientPubKey.isNotEmpty) {
        try {
          final normalizedRecipient = CryptoService.normalizePublicKey(recipientPubKey);
          final normalizedUser = CryptoService.normalizePublicKey(userPublicKey);
          if (normalizedRecipient.toLowerCase() != normalizedUser.toLowerCase()) {
            needsUserFileId = true;
            print('⚠️ Metadata entry RecipientPubKey ($recipientPubKey) does not match user ($userPublicKey), searching for user\'s fileId...');
          }
        } catch (e) {
          // Fallback to direct comparison
          if (recipientPubKey.toLowerCase() != userPublicKey.toLowerCase()) {
            needsUserFileId = true;
            print('⚠️ Metadata entry RecipientPubKey does not match user (direct comparison), searching for user\'s fileId...');
          }
        }
      }
      
      // 🆕 If metadata doesn't belong to user, find user's fileId from their file list
      // Use ownerPubKey to match (since each user has their own fileId for the same content)
      if (needsUserFileId && ownerPubKey != null) {
        try {
          final ownerKeyPreview = ownerPubKey.length > 10 ? ownerPubKey.substring(0, 10) : ownerPubKey;
          print('🔍 Searching for user\'s fileId with ownerPubKey: $ownerKeyPreview...');
          final listTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          final listMethod = 'GET';
          final listPath = '/api/file/list';
          final listBodyHash = '';
          final listDataToSign = '$listMethod$listPath$listTimestamp$listBodyHash';
          final listSignature = await CryptoService.sign(listDataToSign, userMnemonic);
          
          final listResponse = await BlockHttp.get(
            Uri.parse('$nodeEndpoint$listPath'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
              'X-Timestamp': listTimestamp,
              'X-Signature': listSignature,
            },
          );
          
          if (listResponse.statusCode == 200) {
            final userFiles = json.decode(listResponse.body) as List<dynamic>;
            print('📋 Found ${userFiles.length} files for user, searching for matching file...');
            
            // Find file with matching ownerPubKey + fileName + fileSize
            // Note: We need to decrypt metadata block to get fileName and fileSize
            // But we can try to match by ownerPubKey first, then verify with decrypted metadata
            Map<String, dynamic>? matchingFile;
            try {
              // First, try to find files with matching ownerPubKey
              final candidates = userFiles.where((f) {
                final fOwnerPubKey = f['ownerPubKey'] as String?;
                if (fOwnerPubKey == null) return false;
                try {
                  return CryptoService.normalizePublicKey(fOwnerPubKey).toLowerCase() == 
                         CryptoService.normalizePublicKey(ownerPubKey).toLowerCase();
                } catch (e) {
                  return fOwnerPubKey.toLowerCase() == ownerPubKey.toLowerCase();
                }
              }).toList();
              
              print('📋 Found ${candidates.length} files with matching ownerPubKey');
              
              // If we have fileName and fileSize, try to match more precisely
              // But we need to decrypt metadata block to get these, which is expensive
              // So for now, just take the first candidate with matching ownerPubKey
              // The backend should have already filtered by RecipientPubKey
              if (candidates.isNotEmpty) {
                matchingFile = candidates.first as Map<String, dynamic>;
              }
            } catch (e) {
              matchingFile = null;
            }
            
            if (matchingFile != null) {
              actualFileId = matchingFile['fileId'] as String?;
              print('✅ Found user\'s fileId: $actualFileId (original: $fileId)');
              
              // Re-download metadata with user's fileId
              final newMetadataPath = '/api/file/download/$actualFileId';
              final newTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
              final newDataToSign = '$listMethod$newMetadataPath$newTimestamp$listBodyHash';
              final newSignature = await CryptoService.sign(newDataToSign, userMnemonic);
              
              fileMetadataResponse = await BlockHttp.get(
                Uri.parse('$nodeEndpoint$newMetadataPath'),
                headers: {
                  'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
                  'X-Timestamp': newTimestamp,
                  'X-Signature': newSignature,
                },
              );
              
              if (fileMetadataResponse.statusCode == 200) {
                fileMetadata = json.decode(fileMetadataResponse.body);
                encryptedKey = fileMetadata['encryptedKey'] as String?;
                firstBlockId = fileMetadata['firstBlockId'] as String?;
                recipientPubKey = fileMetadata['recipientPubKey'] as String?;
                print('✅ Successfully loaded metadata for user\'s fileId');
              } else {
                throw Exception('Failed to download metadata for user\'s fileId: ${fileMetadataResponse.statusCode}');
              }
            } else {
              print('⚠️ Could not find user\'s fileId with matching ownerPubKey, using original fileId');
            }
          } else {
            print('⚠️ Failed to list user files: ${listResponse.statusCode}');
          }
        } catch (e) {
          print('⚠️ Error searching for user\'s fileId: $e');
          // Continue with original fileId
        }
      }
      
      // 🆕 FIX: For public files, encryptedKey can be empty
      if (!isPublic && (encryptedKey == null || encryptedKey.isEmpty)) {
        throw Exception('No encrypted key found for this file');
      }
      
      if (firstBlockId == null || firstBlockId.isEmpty) {
        throw Exception('No first block ID found for this file');
      }
      
      // 🆕 FIX: Handle public files differently (no decryption needed)
      if (isPublic) {
        print('📂 Loading public file (no decryption needed)');
        return await _loadPublicFile(
          fileId: actualFileId ?? fileId,
          nodeEndpoint: nodeEndpoint,
          userPublicKey: userPublicKey,
          userMnemonic: userMnemonic,
          firstBlockId: firstBlockId,
        );
      }
      
      // Step 2: Download metadata block (block 0) using firstBlockId (for encrypted files)
      final blockPath = '/api/file/block/$firstBlockId';
      final blockTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final blockDataToSign = '$method$blockPath$blockTimestamp$bodyHash';
      final blockSignature = await CryptoService.sign(blockDataToSign, userMnemonic);
      
      final metadataResponse = await BlockHttp.get(
        Uri.parse('$nodeEndpoint$blockPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': blockTimestamp,
          'X-Signature': blockSignature,
        },
      );
      
      if (metadataResponse.statusCode != 200) {
        throw Exception('Failed to download metadata block: ${metadataResponse.statusCode}');
      }
      
      // Step 3: Decrypt metadata block using the encryptedKey from file metadata
      // Use actualFileId (user's fileId) if found, otherwise use original fileId
      final storeMetadata = {
        'fileId': actualFileId ?? fileId,
        'ownerPubKey': ownerPubKey ?? '',
        'encryptedKey': encryptedKey,
        'recipientPubKey': userPublicKey,
        if (policyTag != null) 'policyTag': policyTag,
        if (capsuleFor != null) 'capsuleFor': capsuleFor,
        if (encapsulatedForRecipient != null) 'encapsulatedForRecipient': encapsulatedForRecipient,
      };
      
      final decryptedMetadata = await FileCryptoService.decryptMetadataBlock(
        storeMetadata: storeMetadata,
        encryptedMetadataBlock: metadataResponse.bodyBytes,
        userPublicKey: userPublicKey,
        mnemonic: userMnemonic,
      );
      
      // Step 4: Download content blocks (ALWAYS use metaNodeEndpoint)
      final contentBlockIds = decryptedMetadata['contentBlockIds'] as List<dynamic>? ?? [];
      final List<Uint8List> encryptedContentBlocks = [];
      
      for (final blockId in contentBlockIds) {
        final contentBlockPath = '/api/file/block/$blockId';
        final contentBlockTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
        final contentBlockDataToSign = '$method$contentBlockPath$contentBlockTimestamp$bodyHash';
        final contentBlockSignature = await CryptoService.sign(contentBlockDataToSign, userMnemonic);
        
        final contentBlockResponse = await BlockHttp.get(
          Uri.parse('$nodeEndpoint$contentBlockPath'), // <--- always use metaNodeEndpoint
          headers: {
            'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
            'X-Timestamp': contentBlockTimestamp,
            'X-Signature': contentBlockSignature,
          },
        );
        
        if (contentBlockResponse.statusCode == 200) {
          encryptedContentBlocks.add(contentBlockResponse.bodyBytes);
        }
      }
      
      // Step 5: Decrypt content
      // Use actualFileId (user's fileId) if found, otherwise use original fileId
      final completeMetadata = {
        'fileId': actualFileId ?? fileId,
        'ownerPubKey': (decryptedMetadata['ownerPubKey'] ?? ownerPubKey ?? '') as String,
        'fileSize': decryptedMetadata['fileSize'],
        'encryptedKey': encryptedKey,
        if (policyTag != null) 'policyTag': policyTag,
        if (capsuleFor != null) 'capsuleFor': capsuleFor,
        if (encapsulatedForRecipient != null) 'encapsulatedForRecipient': encapsulatedForRecipient,
      };
      
      final decryptedData = await FileCryptoService.decryptFile(
        fileMetadata: completeMetadata,
        encryptedBlocks: encryptedContentBlocks,
        userPublicKey: userPublicKey,
        mnemonic: userMnemonic,
      );
      
      if (decryptedData != null) {
        return {
          'success': true,
          'imageData': decryptedData,
        };
      } else {
        throw Exception('Failed to decrypt image data');
      }
      
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // 🆕 Load public file (no decryption needed)
  static Future<Map<String, dynamic>> _loadPublicFile({
    required String fileId,
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
    required String firstBlockId,
  }) async {
    try {
      print('📂 Loading public file: $fileId');
      
      // Step 1: Download metadata block (plaintext)
      final method = 'GET';
      final blockPath = '/api/file/block/$firstBlockId';
      final bodyHash = '';
      final blockTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final blockDataToSign = '$method$blockPath$blockTimestamp$bodyHash';
      final blockSignature = await CryptoService.sign(blockDataToSign, userMnemonic);
      
      final metadataResponse = await BlockHttp.get(
        Uri.parse('$nodeEndpoint$blockPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': blockTimestamp,
          'X-Signature': blockSignature,
        },
      );
      
      if (metadataResponse.statusCode != 200) {
        throw Exception('Failed to download public metadata block: ${metadataResponse.statusCode}');
      }
      
      // Step 2: Parse metadata block (plaintext JSON)
      final metadataBlock = metadataResponse.bodyBytes;
      final metadataString = utf8.decode(metadataBlock);
      final metadataContent = json.decode(metadataString) as Map<String, dynamic>;
      
      print('📂 Public metadata loaded: ${metadataContent.keys.toList()}');
      
      // Step 3: Download content blocks (plaintext)
      final contentBlockIds = metadataContent['contentBlockIds'] as List<dynamic>? ?? [];
      final List<Uint8List> contentBlocks = [];
      
      for (int i = 0; i < contentBlockIds.length; i++) {
        final blockId = contentBlockIds[i] as String;
        final contentBlockPath = '/api/file/block/$blockId';
        final contentBlockTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
        final contentBlockDataToSign = '$method$contentBlockPath$contentBlockTimestamp$bodyHash';
        final contentBlockSignature = await CryptoService.sign(contentBlockDataToSign, userMnemonic);
        
        final contentBlockResponse = await BlockHttp.get(
          Uri.parse('$nodeEndpoint$contentBlockPath'),
          headers: {
            'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
            'X-Timestamp': contentBlockTimestamp,
            'X-Signature': contentBlockSignature,
          },
        );
        
        if (contentBlockResponse.statusCode == 200) {
          contentBlocks.add(contentBlockResponse.bodyBytes);
        } else {
          throw Exception('Failed to download content block $blockId: ${contentBlockResponse.statusCode}');
        }
      }
      
      // Step 4: Use FileCryptoService.loadPublicFile to assemble file
      final result = await FileCryptoService.loadPublicFile(
        metadataBlock: metadataBlock,
        contentBlocks: contentBlocks,
      );
      
      final fileData = result['content'] as Uint8List;
      print('✅ Public file loaded successfully: ${fileData.length} bytes');
      
      return {
        'success': true,
        'imageData': fileData,
      };
    } catch (e) {
      print('❌ Error loading public file: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
