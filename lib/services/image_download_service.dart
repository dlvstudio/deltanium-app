import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/app_logger.dart';


class ImageDownloadService {
  static final ImageDownloadService _instance = ImageDownloadService._internal();
  factory ImageDownloadService() => _instance;
  ImageDownloadService._internal();

  // Cache for downloaded images
  final Map<String, Uint8List> _imageCache = {};
  
  // Download status tracking
  final Map<String, bool> _downloadStatus = {};
  
  // Queue management
  final List<String> _downloadQueue = [];
  static const int _maxConcurrentDownloads = 6;
  int _activeDownloads = 0;
  
  // Callbacks for when downloads complete
  final Map<String, List<Function(Uint8List)>> _downloadCallbacks = {};

  /// Get cached image or return null if not cached
  Uint8List? getCachedImage(String fileId) {
    return _imageCache[fileId];
  }

  /// Check if image is currently downloading
  bool isDownloading(String fileId) {
    return _downloadStatus[fileId] == true;
  }

  /// Check if image download failed
  bool hasDownloadFailed(String fileId) {
    return _downloadStatus[fileId] == false;
  }

  /// Request image download with callback
  void requestImageDownload({
    required String fileId,
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
    required Function(Uint8List) onComplete,
    String? postNodeEndpoint,
  }) {
    // If already cached, return immediately
    if (_imageCache.containsKey(fileId)) {
      onComplete(_imageCache[fileId]!);
      return;
    }

    // If already downloading, add callback to existing download
    if (_downloadStatus[fileId] == true) {
      _downloadCallbacks[fileId] ??= [];
      _downloadCallbacks[fileId]!.add(onComplete);
      return;
    }

    // If download failed, don't retry automatically
    if (_downloadStatus[fileId] == false) {
      return;
    }

    // Add callback
    _downloadCallbacks[fileId] ??= [];
    _downloadCallbacks[fileId]!.add(onComplete);

    // Queue download
    if (!_downloadQueue.contains(fileId)) {
      _downloadQueue.add(fileId);
      _processQueue(
        fileId: fileId,
        nodeEndpoint: nodeEndpoint,
        userPublicKey: userPublicKey,
        userMnemonic: userMnemonic,
        postNodeEndpoint: postNodeEndpoint,
      );
    }
  }

  void _processQueue({
    required String fileId,
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
    String? postNodeEndpoint,
  }) {
    if (_activeDownloads >= _maxConcurrentDownloads || _downloadQueue.isEmpty) {
      return;
    }

    _activeDownloads++;
    _downloadStatus[fileId] = true;

    _downloadImage(
      fileId: fileId,
      nodeEndpoint: nodeEndpoint,
      userPublicKey: userPublicKey,
      userMnemonic: userMnemonic,
      postNodeEndpoint: postNodeEndpoint,
    ).then((imageData) {
      if (imageData != null) {
        _imageCache[fileId] = imageData;
        _downloadStatus.remove(fileId);
        
        // Notify all callbacks
        final callbacks = _downloadCallbacks[fileId] ?? [];
        for (final callback in callbacks) {
          callback(imageData);
        }
        _downloadCallbacks.remove(fileId);
      } else {
        _downloadStatus[fileId] = false;
        _downloadCallbacks.remove(fileId);
      }
    }).catchError((error) {
      AppLogger.log('ImageDownloadService: Error downloading $fileId: $error');
      _downloadStatus[fileId] = false;
      _downloadCallbacks.remove(fileId);
    }).whenComplete(() {
      _activeDownloads--;
      _downloadQueue.remove(fileId);
      
      // Process next item in queue
      if (_downloadQueue.isNotEmpty) {
        final nextFileId = _downloadQueue.first;
        // Find the file info for the next download
        // This would need to be passed through the queue or stored separately
      }
    });
  }

  Future<Uint8List?> _downloadImage({
    required String fileId,
    required String nodeEndpoint,
    required String userPublicKey,
    required String userMnemonic,
    String? postNodeEndpoint,
  }) async {
    try {
      final metaNodeEndpoint = postNodeEndpoint ?? nodeEndpoint;
      AppLogger.log('ImageDownloadService: Downloading image $fileId from $metaNodeEndpoint');
      
      // Step 1: Download file metadata to get encryptedKey
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final metadataPath = '/api/file/download/$fileId';
      final bodyHash = '';
      
      final dataToSign = '$method$metadataPath$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, userMnemonic);
      
      final fileMetadataResponse = await http.get(
        Uri.parse('$metaNodeEndpoint$metadataPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      
      if (fileMetadataResponse.statusCode != 200) {
        throw Exception('Failed to download file metadata: ${fileMetadataResponse.statusCode}');
      }
      
      final fileMetadata = json.decode(fileMetadataResponse.body);
      final encryptedKey = fileMetadata['encryptedKey'] as String?;
      final firstBlockId = fileMetadata['firstBlockId'] as String?;
      
      if (encryptedKey == null || encryptedKey.isEmpty) {
        throw Exception('No encrypted key found for this file');
      }
      
      if (firstBlockId == null || firstBlockId.isEmpty) {
        throw Exception('No first block ID found for this file');
      }
      
      // Step 2: Download metadata block (block 0) using firstBlockId
      final blockPath = '/api/file/block/$firstBlockId';
      final blockTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final blockDataToSign = '$method$blockPath$blockTimestamp$bodyHash';
      final blockSignature = await CryptoService.sign(blockDataToSign, userMnemonic);
      
      final metadataResponse = await http.get(
        Uri.parse('$metaNodeEndpoint$blockPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': blockTimestamp,
          'X-Signature': blockSignature,
        },
      );
      
      if (metadataResponse.statusCode != 200) {
        throw Exception('Failed to download metadata block: ${metadataResponse.statusCode}');
      }
      
      // Step 3: Decrypt metadata block
      final storeMetadata = {
        'fileId': fileId,
        'ownerPubKey': '',
        'encryptedKey': encryptedKey,
        'recipientPubKey': userPublicKey,
      };
      
      final decryptedMetadata = await FileCryptoService.decryptMetadataBlock(
        storeMetadata: storeMetadata,
        encryptedMetadataBlock: metadataResponse.bodyBytes,
        userPublicKey: userPublicKey,
        mnemonic: userMnemonic,
      );
      
      // Step 4: Download content blocks
      final contentBlockIds = decryptedMetadata['contentBlockIds'] as List<dynamic>? ?? [];
      final List<Uint8List> encryptedContentBlocks = [];
      
      for (final blockId in contentBlockIds) {
        final contentBlockPath = '/api/file/block/$blockId';
        final contentBlockTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
        final contentBlockDataToSign = '$method$contentBlockPath$contentBlockTimestamp$bodyHash';
        final contentBlockSignature = await CryptoService.sign(contentBlockDataToSign, userMnemonic);
        
        final contentBlockResponse = await http.get(
          Uri.parse('$metaNodeEndpoint$contentBlockPath'),
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
      final completeMetadata = {
        'fileId': fileId,
        'ownerPubKey': decryptedMetadata['ownerPubKey'] ?? '',
        'fileSize': decryptedMetadata['fileSize'],
        'encryptedKey': encryptedKey,
      };
      
      final decryptedData = await FileCryptoService.decryptFile(
        fileMetadata: completeMetadata,
        encryptedBlocks: encryptedContentBlocks,
        userPublicKey: userPublicKey,
        mnemonic: userMnemonic,
      );
      
      if (decryptedData != null) {
        AppLogger.log('ImageDownloadService: Successfully downloaded image $fileId (${decryptedData.length} bytes)');
        return decryptedData;
      } else {
        throw Exception('Failed to decrypt image data');
      }
      
    } catch (e) {
      AppLogger.log('ImageDownloadService: Error downloading image $fileId: $e');
      return null;
    }
  }

  /// Clear cache to free memory
  void clearCache() {
    _imageCache.clear();
  }

  /// Remove specific image from cache
  void removeFromCache(String fileId) {
    _imageCache.remove(fileId);
    _downloadStatus.remove(fileId);
    _downloadCallbacks.remove(fileId);
  }

  /// Get cache size
  int get cacheSize => _imageCache.length;

  /// Get active downloads count
  int get activeDownloads => _activeDownloads;

  /// Get queue size
  int get queueSize => _downloadQueue.length;
} 
