import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/app_logger.dart';

// Removed pointycastle import - using WebCrypto for consistency

/// Service to handle encrypted file uploads to the Deltanium network
class FileUploadService {
  final String apiBaseUrl = AppConstants.apiBaseUrl;
  
  /// Upload a file with encryption
  /// 
  /// The file will be encrypted and split into chunks before uploading
  /// to the selected storage node
  Future<Map<String, dynamic>> uploadEncryptedFile({
    required Uint8List fileData,
    required String fileName,
    required String publicKey,
    required String mnemonic,
    List<String>? sharedWithUsers,
    required Map<String, dynamic> selectedNode,
    /// Extra Store nodes for N-of-M (same ciphertext / same fileId).
    List<Map<String, dynamic>>? replicaNodes,
    Function(String)? onProgress, // Progress callback
    String? fileType, // 🆕 File type ('file', 'post', etc.)
    String? shareType, // 🆕 Share type: 'public', 'shared', 'following'
    // 🆕 PRE fields (optional)
    String? policyTag,
    String? capsuleFor,
    String? policyScheme,
    String? parentFileId, // 🆕 Parent file ID (for comment media, etc.)
    String? contractId, // 🆕 Storage Contract ID for blockchain integration
  }) async {
    try {
      // Step 1: Initial setup
      onProgress?.call('Setting up encryption...');
      await Future.delayed(const Duration(milliseconds: 10)); // Yield control
      
      // Log raw file content for debugging if it's small enough
      if (fileData.length < 100) {
        String rawContent = String.fromCharCodes(fileData);
        AppLogger.log('RAW FILE CONTENT: $rawContent');
        AppLogger.log('This content must be encrypted before upload');
      }

      // Step 2: Encrypt and split the file (or create public file)
      AppLogger.log('Starting file processing for file: $fileName, size: ${fileData.length} bytes, shareType: $shareType');
      
      // 🆕 FIX: For public files, use createPublicFile instead of encryptAndSplitFile
      // This ensures public files are accessible by everyone, not just owner
      final Map<String, dynamic> processedFile;
      if (shareType == 'public') {
        AppLogger.log('Using createPublicFile for public file (no encryption)');
        onProgress?.call('Creating public file...');
        await Future.delayed(const Duration(milliseconds: 10)); // Yield control
        
        processedFile = await FileCryptoService.createPublicFile(
          fileData: fileData,
          fileName: fileName,
          ownerPublicKey: publicKey,
          sharedWithPublicKeys: sharedWithUsers, // Can be null for truly public files
          onProgress: onProgress,
          fileType: fileType,
          encryptedType: 'public',
          shareType: 'public',
        );
      } else {
        AppLogger.log('Using encryptAndSplitFile for encrypted file');
        onProgress?.call('Encrypting file...');
        await Future.delayed(const Duration(milliseconds: 10)); // Yield control
        
        // FOR NORMAL FILES: Use the FileCryptoService
        processedFile = await FileCryptoService.encryptAndSplitFile(
          fileData: fileData,
          fileName: fileName,
          ownerPublicKey: publicKey,
          mnemonic: mnemonic,
          sharedWithPublicKeys: sharedWithUsers,
          onProgress: onProgress, // Pass progress callback
          fileType: fileType, // 🆕 Pass file type to crypto service
          shareType: shareType, // 🆕 Pass share type
          policyTag: policyTag,
          capsuleFor: capsuleFor,
          policyScheme: policyScheme,
        );
      }
      
      // 🆕 ZERO-KNOWLEDGE SHARING: Handle multiple metadata entries
      final metadataEntries = processedFile['metadataEntries'] as List<dynamic>;
      final blocks = processedFile['blocks'] as List<dynamic>;
      
      // Lấy fileId của owner làm fileId chính
      Map<String, dynamic> ownerEntry;
      final normalizedPk = CryptoService.convertToCompressedPublicKey(publicKey);
      try {
        ownerEntry = metadataEntries.firstWhere((e) => e['recipientPubKey'] == normalizedPk);
      } catch (_) {
        // PRE path: recipientPubKey may be omitted; fall back to ownerPubKey match or first entry
        try {
          ownerEntry = metadataEntries.firstWhere((e) {
            final ownerPk = (e['ownerPubKey'] ?? e['OwnerPubKey']) as String?;
            if (ownerPk == null) return false;
            final normOwnerPk = CryptoService.normalizePublicKey(ownerPk);
            final normInput = CryptoService.normalizePublicKey(publicKey);
            return normOwnerPk.toLowerCase() == normInput.toLowerCase();
          });
        } catch (_) {
          ownerEntry = metadataEntries.first as Map<String, dynamic>;
        }
      }
      final String? fileIdValue = ownerEntry['fileId'] as String?;
      if (fileIdValue == null || fileIdValue.isEmpty) {
        throw Exception('fileId is missing in ownerEntry');
      }
      final String fileId = fileIdValue;
      // Handle encryptedKey: could be String (Base64) or List<int> (bytes)
      String encryptedKey = '';
      final encryptedKeyValue = ownerEntry['encryptedKey'];
      if (encryptedKeyValue != null) {
        if (encryptedKeyValue is String) {
          encryptedKey = encryptedKeyValue;
        } else if (encryptedKeyValue is List) {
          // Convert bytes to Base64
          encryptedKey = base64Encode(Uint8List.fromList(encryptedKeyValue.cast<int>()));
        } else if (encryptedKeyValue is Uint8List) {
          encryptedKey = base64Encode(encryptedKeyValue);
        }
      }
      AppLogger.log('🔍 DEBUG: Owner entry: $ownerEntry');
      AppLogger.log('🔍 DEBUG: Using fileId for content blocks: $fileId');
      AppLogger.log('🔍 DEBUG: Owner encryptedKey type: ${encryptedKeyValue.runtimeType}, length: ${encryptedKey.length}');
      final String? fileHash = null; // Không còn merkleRoot public

      // N-of-M target nodes (primary + replicas), deduped by id
      final List<Map<String, dynamic>> targetNodes = [selectedNode];
      if (replicaNodes != null) {
        for (final n in replicaNodes) {
          final id = n['id']?.toString() ?? n['Id']?.toString() ?? '';
          final already = targetNodes.any((t) => (t['id']?.toString() ?? t['Id']?.toString() ?? '') == id);
          if (id.isNotEmpty && !already) targetNodes.add(n);
        }
      }
      final factor = AppConstants.replicationFactor;
      while (targetNodes.length > factor && targetNodes.length > 1) {
        targetNodes.removeLast();
      }

      var blockchainSubmitted = true;
      final List<String> blockchainSubmitErrors = [];
      final List<String> placedNodeIds = [];

      for (var ni = 0; ni < targetNodes.length; ni++) {
        final node = targetNodes[ni];
        final String? nodeEndpointValue = (node['endpoint'] ?? node['Endpoint']) as String?;
        if (nodeEndpointValue == null || nodeEndpointValue.isEmpty) {
          throw Exception('nodeEndpoint is missing in selectedNode');
        }
        final String nodeEndpoint = nodeEndpointValue;
        onProgress?.call('Uploading to store ${ni + 1}/${targetNodes.length}...');

        for (int i = 0; i < metadataEntries.length; i++) {
          final metadataEntry = Map<String, dynamic>.from(metadataEntries[i] as Map);
          if (parentFileId != null && parentFileId.isNotEmpty) {
            metadataEntry['parentFileId'] = parentFileId;
          }
          if (contractId != null && contractId.isNotEmpty) {
            metadataEntry['contractId'] = contractId;
          }
          final metadataJson = json.encode(metadataEntry);
          final metadataResult = await _uploadContent(
            nodeEndpoint: nodeEndpoint,
            path: '/api/file/upload-metadata-raw',
            content: Uint8List.fromList(utf8.encode(metadataJson)),
            fileName: '${metadataEntry['firstBlockId']}_metadata.json',
            contentType: 'application/json',
            publicKey: publicKey,
            mnemonic: mnemonic,
          );
          if (metadataResult['success'] != true) {
            throw Exception('Failed to upload metadata entry ${i + 1} to node ${ni + 1}: ${metadataResult['error']}');
          }
          final response = metadataResult['response'];
          if (response is Map && response['BlockchainSubmitted'] == false) {
            blockchainSubmitted = false;
            final error = response['BlockchainSubmitError'];
            if (error is String && error.isNotEmpty) blockchainSubmitErrors.add(error);
          }
        }

        for (int i = 0; i < blocks.length; i++) {
          final block = blocks[i] as Map<String, dynamic>;
          final blockId = block['blockId'] as String;
          final blockIndex = block['blockIndex'] as int;
          final encryptedContent = block['encryptedContent'] as Uint8List;
          final isMetadataBlock = block['isMetadataBlock'] == true;
          String fileIdForBlock;
          if (isMetadataBlock) {
            final correspondingMetadata = metadataEntries.firstWhere(
              (entry) => entry['firstBlockId'] == blockId,
              orElse: () => throw Exception('No metadata found for block $blockId'),
            );
            fileIdForBlock = correspondingMetadata['fileId'] as String;
          } else {
            fileIdForBlock = fileId;
          }
          final blockResult = await _uploadContent(
            nodeEndpoint: nodeEndpoint,
            path: '/api/file/upload-file-block-raw',
            content: encryptedContent,
            fileName: blockId,
            contentType: 'application/octet-stream',
            publicKey: publicKey,
            mnemonic: mnemonic,
            extraHeaders: {
              'X-Block-Id': blockId,
              'X-File-Id': fileIdForBlock,
              'X-Block-Index': blockIndex.toString(),
              if (contractId != null) 'X-Contract-Id': contractId,
            },
          );
          if (blockResult['success'] != true) {
            throw Exception('Failed to upload file block $blockIndex to node ${ni + 1}: ${blockResult['error']}');
          }
        }

        final String? nodeId = (node['id'] ?? node['Id'])?.toString();
        if (nodeId != null && nodeId.isNotEmpty) placedNodeIds.add(nodeId);
      }

      onProgress?.call('Finalizing...');
      if (placedNodeIds.isNotEmpty) {
        await _registerReplicasWithAPI(
          fileId: fileId,
          publicKey: publicKey,
          mnemonic: mnemonic,
          storeNodeIds: placedNodeIds,
          fileSize: fileData.length,
          fileHash: fileHash ?? '',
        );
      }
      
      onProgress?.call('Upload completed!');
      
      // Get firstBlockId from ownerEntry
      final firstBlockId = ownerEntry['firstBlockId'] as String? ?? '';
      
      // Build map of recipientPubKey -> fileId for all shared users
      final Map<String, String> recipientFileIds = {};
      for (final entry in metadataEntries) {
        final recipientKey = entry['recipientPubKey'] as String? ?? '';
        final entryFileId = entry['fileId'] as String? ?? '';
        if (recipientKey.isNotEmpty && entryFileId.isNotEmpty && recipientKey != normalizedPk) {
          recipientFileIds[recipientKey] = entryFileId;
        }
      }
      
      // Return success with file information
      return {
        'success': true,
        'fileId': fileId,
        'firstBlockId': firstBlockId, // 🆕 Include firstBlockId for decryption
        'recipientFileIds': recipientFileIds, // 🆕 Map of recipient -> their fileId
        'fileName': fileName,
        'fileSize': fileData.length,
        'url': '${(selectedNode['endpoint'] ?? selectedNode['Endpoint'])}/api/file/download/$fileId',
        'blockCount': blocks.length,
        'sharedWith': sharedWithUsers ?? [],
        'encryptedKey': encryptedKey,
        'storeNodeIds': placedNodeIds,
        'replicationFactor': placedNodeIds.length,
        'blockchainSubmitted': blockchainSubmitted,
        'blockchainSubmitErrors': blockchainSubmitErrors,
      };
    } catch (e) {
      AppLogger.log('Error in encrypted file upload: $e');
      onProgress?.call('Upload failed: ${e.toString()}');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// Download and decrypt a file
  Future<Map<String, dynamic>> downloadAndDecryptFile({
    required String fileId,
    required String nodeUrl,
    required String userPublicKey,
    required String mnemonic,
    Function(String)? onProgress, // Progress callback
  }) async {
    try {
      // Step 1: Get file metadata
      onProgress?.call('Fetching file metadata...');
      await Future.delayed(Duration(milliseconds: 10)); // Yield control
      
      final metadataPath = '/api/file/metadata/$fileId';
      final method = 'GET';
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final bodyHash = '';
      final dataToSign = '$method$metadataPath$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, mnemonic);
      final metadataUrl = '$nodeUrl$metadataPath';
      final metadataResponse = await http.get(
        Uri.parse(metadataUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      
      if (metadataResponse.statusCode != 200) {
        throw Exception('Failed to get file metadata: ${metadataResponse.statusCode}');
      }
      
      final metadata = json.decode(metadataResponse.body) as Map<String, dynamic>;
      final blockCount = metadata['blockCount'] as int;
      final fileName = metadata['fileName'] as String;
      final fileSize = metadata['fileSize'] as int;
      
      AppLogger.log('Download: File $fileName, size: $fileSize bytes, blocks: $blockCount');
      
      // Step 2: Download all encrypted blocks with progress
      onProgress?.call('Downloading encrypted blocks...');
      await Future.delayed(Duration(milliseconds: 10)); // Yield control
      
      AppLogger.log('Downloading $blockCount encrypted blocks...');
      
      final List<Uint8List> encryptedBlocks = [];
      
      // Get block IDs from metadata
      final blockIds = metadata['blockIds'] as List<dynamic>;
      if (blockIds.length != blockCount) {
        throw Exception('Metadata block count mismatch: expected $blockCount, got ${blockIds.length}');
      }
      
      for (int i = 0; i < blockCount; i++) {
        // Update progress for each block
        final progressPercent = ((i / blockCount) * 50).round(); // 50% for download
        onProgress?.call('Downloading block ${i + 1}/$blockCount ($progressPercent%)...');
        await Future.delayed(Duration(milliseconds: 20)); // Yield control
        
        final blockId = blockIds[i] as String;
        final blockUrl = '$nodeUrl/api/file/block/$blockId';
        final blockResponse = await http.get(
          Uri.parse(blockUrl),
          headers: {
            'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          },
        );
        
        if (blockResponse.statusCode != 200) {
          throw Exception('Failed to download block $i ($blockId): ${blockResponse.statusCode}');
        }
        
        final blockData = blockResponse.bodyBytes;
        AppLogger.log('Downloaded block $i ($blockId): ${blockData.length} bytes');
        
        // Debug: Show first few bytes of encrypted block
        if (blockData.length > 0) {
          final preview = blockData.sublist(0, min(16, blockData.length));
          AppLogger.log('Block $i preview: ${preview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        }
        
        encryptedBlocks.add(blockData);
      }
      
      // Step 3: Decrypt the file with progress
      onProgress?.call('Decrypting file...');
      await Future.delayed(Duration(milliseconds: 10)); // Yield control
      
      AppLogger.log('Decrypting file...');
      final decryptedData = await FileCryptoService.decryptFile(
        fileMetadata: metadata,
        encryptedBlocks: encryptedBlocks,
        userPublicKey: userPublicKey,
        mnemonic: mnemonic,
        onProgress: (message) {
          onProgress?.call('Decrypting: $message');
        },
      );
      
      AppLogger.log('Decryption complete: ${decryptedData.length} bytes');
      
      // Simple debug logging for all files
      if (decryptedData.length > 0) {
        final preview = decryptedData.sublist(0, min(20, decryptedData.length));
        AppLogger.log('Download: Decrypted preview: ${preview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }
      
      onProgress?.call('Download completed!');
      
      return {
        'success': true,
        'fileName': metadata['fileName'],
        'fileSize': metadata['fileSize'],
        'mimeType': metadata['mimeType'],
        'data': decryptedData,
      };
    } catch (e) {
      AppLogger.log('Error downloading and decrypting file: $e');
      onProgress?.call('Download failed: ${e.toString()}');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// Upload content to a node
  Future<Map<String, dynamic>> _uploadContent({
    required String nodeEndpoint,
    required String path,
    required Uint8List content,
    required String fileName,
    required String contentType,
    required String publicKey,
    required String mnemonic,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final uri = Uri.parse('$nodeEndpoint$path');
      AppLogger.log('Creating request to $uri');

      // Calculate content hash for signing
      final digest = await CryptoService.hashSHA256(content);
      final bodyHash = base64Encode(digest);

      // Generate signature components
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'POST';
      final pathForSigning = Uri.parse(path).path;
      final buffer = StringBuffer();
      buffer.write(method);
      buffer.write(pathForSigning);
      buffer.write(timestamp);
      buffer.write(bodyHash);
      final dataToSign = buffer.toString();

      // Generate a key pair from mnemonic
      final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
      final signature = await CryptoService.sign(dataToSign, kIsWeb ? mnemonic : keyPair);

      // Set up headers
      final headers = {
        'Content-Type': contentType,
        'X-User-PubKey': CryptoService.normalizePublicKey(publicKey),
        'X-Timestamp': timestamp,
        'X-Signature': signature,
      };
      
      // Add any extra headers if provided
      if (extraHeaders != null) {
        headers.addAll(extraHeaders);
      }

      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..bodyBytes = content;

      final response = await request.send();
      final resp = await http.Response.fromStream(response);

      if (resp.statusCode == 200) {
        return {
          'success': true,
          'response': json.decode(resp.body),
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${resp.statusCode}: ${resp.body}',
        };
      }
    } catch (e) {
      AppLogger.log('Exception in _uploadContent: ${e}');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// Register N-of-M placements with Central (signed).
  Future<void> _registerReplicasWithAPI({
    required String fileId,
    required String publicKey,
    required String mnemonic,
    required List<String> storeNodeIds,
    required int fileSize,
    required String fileHash,
  }) async {
    try {
      final bodyMap = {
        'fileId': fileId,
        'ownerPublicKey': publicKey,
        'storeNodeIds': storeNodeIds,
        'fileSize': fileSize,
        'fileHash': fileHash,
      };
      final body = json.encode(bodyMap);
      final path = '/api/storedfile/register-replicas';
      // apiBaseUrl already includes /api — strip for path used in signature
      final pathForSigning = path;
      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final bodyHash = sha256.convert(utf8.encode(body)).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final dataToSign = 'POST$pathForSigning$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, mnemonic);
      final compressedPk = CryptoService.convertToCompressedPublicKey(publicKey);

      AppLogger.log('Registering replicas with API: $fileId nodes=$storeNodeIds');
      final response = await http.post(
        Uri.parse('$apiBaseUrl/storedfile/register-replicas'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': compressedPk,
          'X-Timestamp': timestamp.toString(),
          'X-Signature': signature,
        },
        body: body,
      );

      if (response.statusCode != 200) {
        AppLogger.log('Warning: Failed to register replicas: ${response.statusCode} ${response.body}');
      } else {
        AppLogger.log('Replicas registered: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('Warning: Error registering replicas: $e');
    }
  }
  
  /// Generate a unique ID for a file
  String _generateUniqueId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join('-');
  }
  
  /// Determine MIME type from file name
  String _getMimeType(String fileName) {
    final extension = _getFileExtension(fileName).toLowerCase();
    
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
  
  /// Extract file extension
  String _getFileExtension(String fileName) {
    return fileName.contains('.')
        ? fileName.split('.').last
        : '';
  }
} 
