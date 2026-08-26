import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/image_cache_service.dart';
import 'package:deltanium_app/features/feed/widgets/simple_image_widget.dart';


// Mute verbose logs for RelatedFilesWidget in production
void print(Object? object) {}

class RelatedFilesWidget extends StatefulWidget {
  final List<Map<String, dynamic>> relatedFiles;
  final bool isDarkMode;
  final Function(String fileId, String nodeEndpoint)? onFileDownload;
  final Function(String fileId)? onFileRemove;
  final String? userPublicKey;
  final String? userMnemonic;
  final String? postNodeEndpoint;

  const RelatedFilesWidget({
    super.key,
    required this.relatedFiles,
    required this.isDarkMode,
    this.onFileDownload,
    this.onFileRemove,
    this.userPublicKey,
    this.userMnemonic,
    this.postNodeEndpoint,
  });

  @override
  State<RelatedFilesWidget> createState() => _RelatedFilesWidgetState();
}

class _RelatedFilesWidgetState extends State<RelatedFilesWidget> {
  // Use global cache service instead of local cache
  final ImageCacheService _cacheService = ImageCacheService();
  
  // Local state for UI updates
  final Map<String, Uint8List> _localImages = {};
  final Map<String, bool> _localDownloadStatus = {};
  
  // Limit concurrent downloads to prevent UI freezing
  static const int _maxConcurrentDownloads = 6;
  int _activeDownloads = 0;
  final List<String> _downloadQueue = [];
  
  // Flag to track if widget is disposed
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _setupCacheCallbacks();
    _scheduleVisibleImageDownloads();
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Clean up callbacks to prevent memory leaks
    for (final file in widget.relatedFiles) {
      final fileId = file['fileId'] as String?;
      if (fileId != null) {
        _cacheService.addDownloadCallback(fileId, (_) {});
        _cacheService.addErrorCallback(fileId, (_) {});
      }
    }
    super.dispose();
  }

  void _setupCacheCallbacks() {
    for (final file in widget.relatedFiles) {
      final fileId = file['fileId'] as String?;
      if (fileId != null) {
        
        // Remove any existing callbacks first to avoid duplicates
        _cacheService.clearFileStatus(fileId);
        
        // Add callback for successful downloads
        _cacheService.addDownloadCallback(fileId, (imageData) {
          if (mounted && !_isDisposed) {
            setState(() {
              _localImages[fileId] = imageData;
              _localDownloadStatus.remove(fileId);
            });
          } else {
          }
        });
        
        // Add callback for failed downloads
        _cacheService.addErrorCallback(fileId, (error) {
          if (mounted && !_isDisposed) {
            setState(() {
              _localDownloadStatus[fileId] = false;
            });
          } else {
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(RelatedFilesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relatedFiles != widget.relatedFiles) {
      _setupCacheCallbacks();
      _scheduleVisibleImageDownloads();
    }
  }

  void _scheduleVisibleImageDownloads() {
    // Schedule downloads for all image files immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final file in widget.relatedFiles) {
        final fileId = file['fileId'] as String?;
        final fileType = file['type'] as String?;
        final nodeEndpoint = file['nodeEndpoint'] as String?;
        
        
        if (fileId != null && 
            fileType == 'image' && 
            nodeEndpoint != null &&
            widget.userPublicKey != null &&
            widget.userMnemonic != null) {
          _queueImageDownload(fileId);
        } else {
        }
      }
      
      // Force trigger downloads again after a short delay to ensure all posts are processed
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _forceTriggerDownloads();
        }
      });
    });
  }

  void _forceTriggerDownloads() {
    for (final file in widget.relatedFiles) {
      final fileId = file['fileId'] as String?;
      final fileType = file['type'] as String?;
      final nodeEndpoint = file['nodeEndpoint'] as String?;
      
      if (fileId != null && 
          fileType == 'image' && 
          nodeEndpoint != null &&
          widget.userPublicKey != null &&
          widget.userMnemonic != null) {
        
        // Check if this file needs to be downloaded
        if (!_cacheService.hasImage(fileId) && 
            !_cacheService.isDownloading(fileId) && 
            !_cacheService.hasFailed(fileId) &&
            !_downloadQueue.contains(fileId)) {
          _queueImageDownload(fileId);
        }
      }
    }
  }

  void _processDownloadQueue() {
    if (_activeDownloads >= _maxConcurrentDownloads || _downloadQueue.isEmpty) {
      return;
    }

    final fileId = _downloadQueue.removeAt(0);
    _activeDownloads++;
    
    // Download in background without blocking UI
    _downloadImage(fileId, widget.relatedFiles.firstWhere(
      (file) => file['fileId'] == fileId,
      orElse: () => {},
    )['nodeEndpoint'] as String? ?? '');
  }

  void _queueImageDownload(String fileId) {
    if (_isDisposed) {
      return;
    }
    
    // Check if already cached or downloading
    if (_cacheService.hasImage(fileId)) {
      // Image is already cached, just update local state
      final cachedImage = _cacheService.getImage(fileId);
      if (cachedImage != null && mounted && !_isDisposed) {
        setState(() {
          _localImages[fileId] = cachedImage;
        });
      }
      return;
    }
    
    if (_cacheService.isDownloading(fileId)) {
      // Already downloading, just update local status
      if (mounted && !_isDisposed) {
        setState(() {
          _localDownloadStatus[fileId] = true;
        });
      }
      return;
    }
    
    if (_cacheService.hasFailed(fileId)) {
      // Previously failed, just update local status
      if (mounted && !_isDisposed) {
        setState(() {
          _localDownloadStatus[fileId] = false;
        });
      }
      return;
    }
    
    // Not in queue, not cached, not downloading, not failed - add to queue
    if (!_downloadQueue.contains(fileId)) {
      _downloadQueue.add(fileId);
      _processDownloadQueue();
    } else {
    }
  }

  void _onImageVisible(String fileId, String nodeEndpoint) {
    _queueImageDownload(fileId);
  }

  Future<void> _downloadImage(String fileId, String nodeEndpoint) async {
    if (_isDisposed) {
      _activeDownloads--;
      return;
    }
    
    try {
      final metaNodeEndpoint = widget.postNodeEndpoint ?? nodeEndpoint;
      
      // Mark as downloading in cache service
      _cacheService.markDownloading(fileId);
      
      // Update local UI state
      if (mounted && !_isDisposed) {
        setState(() {
          _localDownloadStatus[fileId] = true;
        });
      }
      
      // Get file info from relatedFiles for better matching
      final fileInfo = widget.relatedFiles.firstWhere(
        (file) => file['fileId'] == fileId,
        orElse: () => <String, dynamic>{},
      );
      final fileName = fileInfo['fileName'] as String? ?? fileInfo['name'] as String?;
      final fileSize = fileInfo['fileSize'] as int? ?? fileInfo['size'] as int?;
      
      // Run all heavy operations on background thread
      final result = await compute(_downloadImageInBackground, {
        'fileId': fileId,
        'nodeEndpoint': metaNodeEndpoint,
        'userPublicKey': widget.userPublicKey!,
        'userMnemonic': widget.userMnemonic!,
        'fileName': fileName, // 🆕 Pass fileName for matching
        'fileSize': fileSize, // 🆕 Pass fileSize for matching
      });
      
      if (result['success'] == true) {
        final imageData = result['imageData'] as Uint8List;
        // Store in global cache service (this will trigger callbacks to update UI)
        _cacheService.storeImage(fileId, imageData);
      } else {
        throw Exception(result['error'] as String? ?? 'Unknown error');
      }
      
    } catch (e) {
      // Mark as failed in cache service (this will trigger callbacks to update UI)
      _cacheService.markFailed(fileId, e.toString());
    } finally {
      _activeDownloads--;
      // Process next item in queue
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processDownloadQueue();
      });
    }
  }

  // Static method to run on background thread
  static Future<Map<String, dynamic>> _downloadImageInBackground(Map<String, dynamic> params) async {
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
      
      var fileMetadataResponse = await http.get(
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
          
          final listResponse = await http.get(
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
              
              fileMetadataResponse = await http.get(
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
      
      final metadataResponse = await http.get(
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
        
        final contentBlockResponse = await http.get(
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
      
      final metadataResponse = await http.get(
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
        
        final contentBlockResponse = await http.get(
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

  @override
  Widget build(BuildContext context) {
    if (widget.relatedFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    // Force trigger downloads on every build to ensure all images are processed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureAllImagesDownloaded();
    });

    // Separate images and non-images
    final imageFiles = widget.relatedFiles.where((file) {
      final fileType = file['type'] ?? 'unknown';
      final mimeType = file['mimeType'] ?? 'application/octet-stream';
      return fileType == 'image' || mimeType.toString().startsWith('image/');
    }).toList();
    final nonImageFiles = widget.relatedFiles.where((file) {
      final fileType = file['type'] ?? 'unknown';
      final mimeType = file['mimeType'] ?? 'application/octet-stream';
      return !(fileType == 'image' || mimeType.toString().startsWith('image/'));
    }).toList();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? DeltaniumTheme.surfaceDark.withOpacity(0.5)
            : DeltaniumTheme.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isDarkMode
              ? DeltaniumTheme.darkDividerColor
              : DeltaniumTheme.lightDividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.attachment,
                size: 20,
                color: widget.isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.relatedFiles.length} related file(s)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: widget.isDarkMode
                      ? DeltaniumTheme.darkTextPrimaryColor
                      : DeltaniumTheme.lightTextPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (imageFiles.isNotEmpty) _buildImageAlbum(context, imageFiles),
          if (nonImageFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...nonImageFiles.map((file) => _buildFileItem(file)).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildImageAlbum(BuildContext context, List<Map<String, dynamic>> imageFiles) {
    final count = imageFiles.length;
    // 1: full width, 2: row, 3: row, 4: Facebook-style, 5+: 2x2 + overlay
    if (count == 1) {
      return _buildFileItem(imageFiles[0], forceLarge: true, minimal: true);
    } else if (count == 2) {
      return Row(
        children: [
          Expanded(child: _buildFileItem(imageFiles[0], forceLarge: true, aspectRatio: 1, minimal: true)),
          const SizedBox(width: 4),
          Expanded(child: _buildFileItem(imageFiles[1], forceLarge: true, aspectRatio: 1, minimal: true)),
        ],
      );
    } else if (count == 3) {
      return Row(
        children: [
          Expanded(child: _buildFileItem(imageFiles[0], forceLarge: true, aspectRatio: 1, minimal: true)),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              children: [
                _buildFileItem(imageFiles[1], forceLarge: true, aspectRatio: 1, minimal: true),
                const SizedBox(height: 4),
                _buildFileItem(imageFiles[2], forceLarge: true, aspectRatio: 1, minimal: true),
              ],
            ),
          ),
        ],
      );
    } else if (count == 4) {
      // Beautiful Facebook-style: 1 large left, 3 stacked right, unified rounded corners
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Row(
            children: [
              // Left: Large image (2/3 width)
              Expanded(
                flex: 2,
                child: _buildFileItem(
                  imageFiles[0],
                  forceLarge: true,
                  aspectRatio: 1,
                  minimal: true,
                  customBorderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  margin: EdgeInsets.zero,
                ),
              ),
              // Right: 3 stacked images (1/3 width)
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    Expanded(
                      child: _buildFileItem(
                        imageFiles[1],
                        forceLarge: true,
                        aspectRatio: 1,
                        minimal: true,
                        customBorderRadius: const BorderRadius.only(topRight: Radius.circular(16)),
                        margin: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: _buildFileItem(
                        imageFiles[2],
                        forceLarge: true,
                        aspectRatio: 1,
                        minimal: true,
                        customBorderRadius: BorderRadius.zero,
                        margin: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: _buildFileItem(
                        imageFiles[3],
                        forceLarge: true,
                        aspectRatio: 1,
                        minimal: true,
                        customBorderRadius: const BorderRadius.only(bottomRight: Radius.circular(16)),
                        margin: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // 5+ images: 2x2 grid, last cell overlays +N
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(4, (i) {
          if (i < 3) {
            return _buildFileItem(imageFiles[i], forceLarge: true, aspectRatio: 1, minimal: true);
          } else {
            // Last cell overlays +N
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildFileItem(imageFiles[3], forceLarge: true, aspectRatio: 1, minimal: true),
                Container(
                  color: Colors.black.withOpacity(0.5),
                  alignment: Alignment.center,
                  child: Text(
                    '+${count - 4}',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          }
        }),
      );
    }
  }

  Widget _buildFileItem(
    Map<String, dynamic> file, {
    bool forceLarge = false,
    double? aspectRatio,
    bool minimal = false,
    BorderRadius? customBorderRadius,
    EdgeInsetsGeometry? margin,
  }) {
    final fileName = file['fileName'] ?? 'Unknown file';
    final fileSize = file['fileSize'] ?? 0;
    final fileType = file['type'] ?? 'unknown';
    final relationshipType = file['relationshipType'] ?? 'attachment';
    final fileId = file['fileId'] ?? '';
    final nodeEndpoint = file['nodeEndpoint'] ?? '';
    final mimeType = file['mimeType'] ?? 'application/octet-stream';
    final caption = file['caption'] ?? '';

    final isImage = fileType == 'image' || mimeType.startsWith('image/');
    final hasDownloadedImage = _localImages.containsKey(fileId);
    final isDownloading = _localDownloadStatus.containsKey(fileId) && _localDownloadStatus[fileId] == true;
    final downloadFailed = _localDownloadStatus.containsKey(fileId) && _localDownloadStatus[fileId] == false;

    Widget filePreviewWidget;
    if (isImage) {
      // Use SimpleImageWidget for more reliable image loading
      filePreviewWidget = SimpleImageWidget(
        fileId: fileId,
        nodeEndpoint: nodeEndpoint,
        userPublicKey: widget.userPublicKey,
        userMnemonic: widget.userMnemonic,
        aspectRatio: aspectRatio,
        forceLarge: forceLarge,
        customBorderRadius: customBorderRadius,
        margin: margin,
        onImageVisible: _onImageVisible,
        downloadedImage: hasDownloadedImage ? _localImages[fileId] : null,
        isDownloading: isDownloading,
        downloadFailed: downloadFailed,
        );
    } else {
      filePreviewWidget = const SizedBox.shrink();
    }

    // Minimal image card: only show the image, nothing else
    if (isImage && minimal) {
      return Container(
        margin: margin ?? const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: customBorderRadius ?? BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: filePreviewWidget,
      );
    }

    // Full info/actions for non-image or non-minimal
    return Card(
      color: widget.isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isImage) filePreviewWidget,
            // File info below image
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isImage)
                  Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.insert_drive_file, size: 32, color: Colors.grey),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        caption,
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Text(
                            '${fileSize} B',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('ATTACHMENT', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () => widget.onFileDownload?.call(fileId, nodeEndpoint),
                  tooltip: 'Download',
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                  onPressed: () => widget.onFileRemove?.call(fileId),
                  tooltip: 'Remove',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileType, String mimeType) {
    if (fileType == 'image' || mimeType.startsWith('image/')) {
      return Icons.image;
    } else if (fileType == 'video' || mimeType.startsWith('video/')) {
      return Icons.video_file;
    } else if (fileType == 'audio' || mimeType.startsWith('audio/')) {
      return Icons.audio_file;
    } else if (mimeType == 'application/pdf') {
      return Icons.picture_as_pdf;
    } else if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    } else if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
      return Icons.table_chart;
    } else if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return Icons.folder_zip;
    } else if (mimeType.startsWith('text/')) {
      return Icons.text_snippet;
    }
    return Icons.insert_drive_file;
  }

  Color _getFileIconColor(String fileType, String mimeType) {
    if (fileType == 'image' || mimeType.startsWith('image/')) {
      return Colors.blue[400]!;
    } else if (fileType == 'video' || mimeType.startsWith('video/')) {
      return Colors.red[700]!;
    } else if (fileType == 'audio' || mimeType.startsWith('audio/')) {
      return Colors.purple[400]!;
    } else if (mimeType == 'application/pdf') {
      return Colors.red[400]!;
    } else if (mimeType.contains('word') || mimeType.contains('document')) {
      return Colors.blue[800]!;
    } else if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
      return Colors.green[800]!;
    } else if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return Colors.amber[700]!;
    } else if (mimeType.startsWith('text/')) {
      return Colors.blueGrey[400]!;
    }
    return Colors.grey[600]!;
  }

  Color _getRelationshipTypeColor(String relationshipType) {
    switch (relationshipType.toLowerCase()) {
      case 'attachment':
        return Colors.blue;
      case 'reference':
        return Colors.green;
      case 'source':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatFileSize(int size) {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  void _ensureAllImagesDownloaded() {
    for (final file in widget.relatedFiles) {
      final fileId = file['fileId'] as String?;
      if (fileId != null && file['type'] == 'image') {
        _queueImageDownload(fileId);
      }
    }
  }
} 
