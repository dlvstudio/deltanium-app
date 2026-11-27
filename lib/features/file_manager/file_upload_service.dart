import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/services/store_placement.dart';
import 'package:deltanium_app/utils/d_format.dart';

// Removed pointycastle import - using WebCrypto for consistency

/// Service to handle encrypted file uploads to the Deltanium network
class FileUploadService {
  final String apiBaseUrl = AppConstants.apiBaseUrl;
  
  /// Encrypts [fileData] (or makes it a public file) into metadata entries (one per reader) and blocks, without
  /// uploading anything: what [StorePlacement.place] stores. Returns fileId (the owner's entry), firstBlockId,
  /// encryptedKey, recipientFileIds, metadataEntries, blocks and billableBytes.
  Future<Map<String, dynamic>> encryptForUpload({
    required Uint8List fileData,
    required String fileName,
    required String publicKey,
    required String mnemonic,
    List<String>? sharedWithUsers,
    Function(String)? onProgress,
    String? fileType,
    String? shareType,
    String? policyTag,
    String? capsuleFor,
    String? policyScheme,
    String? parentFileId,
  }) async {
    final Map<String, dynamic> processedFile;
    if (shareType == 'public') {
      onProgress?.call('Creating public file...');
      processedFile = await FileCryptoService.createPublicFile(
        fileData: fileData,
        fileName: fileName,
        ownerPublicKey: publicKey,
        sharedWithPublicKeys: sharedWithUsers,
        onProgress: onProgress,
        fileType: fileType,
        encryptedType: 'public',
        shareType: 'public',
      );
    } else {
      onProgress?.call('Encrypting file...');
      processedFile = await FileCryptoService.encryptAndSplitFile(
        fileData: fileData,
        fileName: fileName,
        ownerPublicKey: publicKey,
        mnemonic: mnemonic,
        sharedWithPublicKeys: sharedWithUsers,
        onProgress: onProgress,
        fileType: fileType,
        shareType: shareType,
        policyTag: policyTag,
        capsuleFor: capsuleFor,
        policyScheme: policyScheme,
      );
    }
    final metadataEntries = [
      for (final e in processedFile['metadataEntries'] as List)
        {
          ...Map<String, dynamic>.from(e as Map),
          if (parentFileId != null && parentFileId.isNotEmpty) 'parentFileId': parentFileId,
        }
    ];
    final blocks = [for (final b in processedFile['blocks'] as List) Map<String, dynamic>.from(b as Map)];

    // The owner's entry: its fileId is the file's id (and what Central bills); PRE entries may omit recipientPubKey.
    final normalizedPk = CryptoService.convertToCompressedPublicKey(publicKey);
    bool isOwner(Map<String, dynamic> e) {
      if (e['recipientPubKey'] == normalizedPk) return true;
      final ownerPk = (e['ownerPubKey'] ?? e['OwnerPubKey']) as String?;
      return ownerPk != null &&
          CryptoService.normalizePublicKey(ownerPk).toLowerCase() == CryptoService.normalizePublicKey(publicKey).toLowerCase();
    }
    final ownerEntry = metadataEntries.firstWhere(isOwner, orElse: () => metadataEntries.first);
    // The owner's entry goes first: StorePlacement gives content blocks to the first entry.
    metadataEntries
      ..remove(ownerEntry)
      ..insert(0, ownerEntry);
    final fileId = ownerEntry['fileId'] as String?;
    if (fileId == null || fileId.isEmpty) throw Exception('fileId is missing in ownerEntry');

    final k = ownerEntry['encryptedKey'];
    final encryptedKey = k is String ? k : (k is List ? base64Encode(Uint8List.fromList(k.cast<int>())) : '');
    final recipientFileIds = <String, String>{
      for (final e in metadataEntries)
        if ('${e['recipientPubKey'] ?? ''}'.isNotEmpty && '${e['fileId'] ?? ''}'.isNotEmpty && e['recipientPubKey'] != normalizedPk)
          '${e['recipientPubKey']}': '${e['fileId']}',
    };
    return {
      'fileId': fileId,
      'firstBlockId': ownerEntry['firstBlockId'] as String? ?? '',
      'encryptedKey': encryptedKey,
      'recipientFileIds': recipientFileIds,
      'metadataEntries': metadataEntries,
      'blocks': blocks,
      'billableBytes': StorePlacement.billableBytes(metadataEntries, blocks),
    };
  }

  /// Encrypts a file and stores it the way every item is stored ([StorePlacement.place]): a signed contract with
  /// each Store, Central paid for all of them, then the file on each Store (each puts a StorageOperation on chain).
  /// The Stores are [selectedNode] and [replicaNodes], filled up to the replication factor unless
  /// [onlyTheseNodes] (attachments of a comment stay on the Stores of its post).
  Future<Map<String, dynamic>> uploadEncryptedFile({
    required Uint8List fileData,
    required String fileName,
    required String publicKey,
    required String mnemonic,
    List<String>? sharedWithUsers,
    required Map<String, dynamic> selectedNode,
    List<Map<String, dynamic>>? replicaNodes,
    bool onlyTheseNodes = false,
    Function(String)? onProgress,
    String? fileType,
    String? shareType,
    String? policyTag,
    String? capsuleFor,
    String? policyScheme,
    String? parentFileId,
    bool socialItem = false, // §10: reactions, comments, chat messages
    /// Asked with Central's exact charge (D) before anything is paid or uploaded, when the charge is above 0;
    /// return false to cancel.
    Future<bool> Function(double charge, double monthly)? confirmCharge,
  }) async {
    try {
      final enc = await encryptForUpload(
        fileData: fileData,
        fileName: fileName,
        publicKey: publicKey,
        mnemonic: mnemonic,
        sharedWithUsers: sharedWithUsers,
        onProgress: onProgress,
        fileType: fileType,
        shareType: shareType,
        policyTag: policyTag,
        capsuleFor: capsuleFor,
        policyScheme: policyScheme,
        parentFileId: parentFileId,
      );
      final fileId = enc['fileId'] as String;
      final metadataEntries = enc['metadataEntries'] as List<Map<String, dynamic>>;
      final blocks = enc['blocks'] as List<Map<String, dynamic>>;
      final size = enc['billableBytes'] as int;

      String ep(Map<String, dynamic> n) => '${n['httpsEndpoint'] ?? n['endpoint'] ?? n['Endpoint'] ?? ''}';
      final nodes = await StorePlacement.pickNodes(
        mustUse: [ep(selectedNode), ...?replicaNodes?.map(ep)],
        onlyThese: onlyTheseNodes,
      );

      // TOKENOMICS_V2 §6/§10: Central's exact charge for this size on these Stores; stop if unaffordable or declined.
      final q = await WalletService.quoteChargeDetail(
        sizeBytes: size,
        storeNodes: nodes.length,
        replicas: nodes.length,
        social: socialItem,
      );
      if (q == null) throw Exception('Could not get the storage price from Central. Try again.');
      if (q.charge > 0) {
        final balance = await WalletService.getBalance() ?? 0;
        if (balance < q.charge) {
          throw Exception('Storage costs ${DFormat.exact(q.charge)} but your balance is '
              '${DFormat.exact(balance)}. Top up your wallet first.');
        }
        if (confirmCharge != null && !await confirmCharge(q.charge, q.monthly)) throw StorageChargeDeclined();
      }

      final placed = await StorePlacement.place(
        escrowFileId: fileId,
        metadataEntries: metadataEntries,
        blocks: blocks,
        nodes: nodes,
        publicKey: publicKey,
        mnemonic: mnemonic,
        charge: q.charge,
        replicas: nodes.length,
        social: socialItem,
        onProgress: onProgress,
      );
      onProgress?.call('Upload completed!');
      return {
        'success': true,
        'fileId': fileId,
        'firstBlockId': enc['firstBlockId'],
        'recipientFileIds': enc['recipientFileIds'],
        'fileName': fileName,
        'fileSize': fileData.length,
        'url': '${placed.primaryEndpoint}/api/file/download/$fileId',
        'nodeEndpoint': placed.primaryEndpoint,
        'nodeId': placed.nodeIds.first,
        'blockCount': blocks.length,
        'sharedWith': sharedWithUsers ?? [],
        'encryptedKey': enc['encryptedKey'],
        'storeNodeIds': placed.nodeIds,
        'replicationFactor': placed.nodes.length,
        'blockchainSubmitted': !placed.chainSubmitPending,
        'blockchainSubmitErrors': const <String>[],
      };
    } catch (e) {
      AppLogger.log('Error in encrypted file upload: $e');
      onProgress?.call('Upload failed: ${e.toString()}');
      return {
        'success': false,
        'error': e.toString(),
        if (e is StorageChargeDeclined) 'cancelled': true,
        if (e is StoragePaymentRefused) 'status': 402,
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

/// The user declined the storage charge shown before upload; nothing was uploaded or paid.
class StorageChargeDeclined implements Exception {
  @override
  String toString() => 'Upload cancelled: storage fee not confirmed';
}
