import 'package:flutter/material.dart';
import 'package:deltanium_app/services/attachment_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/services/egress_receipt_service.dart';
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
      final result = await compute(AttachmentDownloader.download, {
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
