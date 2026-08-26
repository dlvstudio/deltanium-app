import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'dart:typed_data';
import 'package:deltanium_app/services/image_cache_service.dart';
import 'package:deltanium_app/services/app_logger.dart';


class SimpleImageWidget extends StatefulWidget {
  final String fileId;
  final String? nodeEndpoint;
  final String? userPublicKey;
  final String? userMnemonic;
  final double? aspectRatio;
  final bool forceLarge;
  final BorderRadius? customBorderRadius;
  final EdgeInsetsGeometry? margin;
  final Function(String fileId, String nodeEndpoint)? onImageVisible;
  final Uint8List? downloadedImage;
  final bool isDownloading;
  final bool downloadFailed;

  const SimpleImageWidget({
    Key? key,
    required this.fileId,
    this.nodeEndpoint,
    this.userPublicKey,
    this.userMnemonic,
    this.aspectRatio,
    this.forceLarge = false,
    this.customBorderRadius,
    this.margin,
    this.onImageVisible,
    this.downloadedImage,
    this.isDownloading = false,
    this.downloadFailed = false,
  }) : super(key: key);

  @override
  State<SimpleImageWidget> createState() => _SimpleImageWidgetState();
}

class _SimpleImageWidgetState extends State<SimpleImageWidget> {
  bool _hasTriggeredDownload = false;
  final ImageCacheService _cacheService = ImageCacheService();

  @override
  void initState() {
    super.initState();
    AppLogger.log('SimpleImageWidget: initState for ${widget.fileId}');
    // Trigger download after the first frame is rendered to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.log('SimpleImageWidget: Post frame callback for ${widget.fileId}');
      _triggerDownload();
    });
  }

  void _triggerDownload() {
    AppLogger.log('SimpleImageWidget: _triggerDownload called for ${widget.fileId}');
    if (_hasTriggeredDownload) {
      AppLogger.log('SimpleImageWidget: Already triggered download for ${widget.fileId}');
      return; // Already triggered
    }
    
    // Check if already cached
    if (_cacheService.hasImage(widget.fileId)) {
      AppLogger.log('SimpleImageWidget: Image ${widget.fileId} already cached, skipping download');
      _hasTriggeredDownload = true;
      return;
    }
    
    // Check if already downloading
    if (_cacheService.isDownloading(widget.fileId)) {
      AppLogger.log('SimpleImageWidget: Image ${widget.fileId} already downloading, skipping');
      _hasTriggeredDownload = true;
      return;
    }
    
    // Check if download failed before
    if (_cacheService.hasFailed(widget.fileId)) {
      AppLogger.log('SimpleImageWidget: Image ${widget.fileId} previously failed, skipping');
      _hasTriggeredDownload = true;
      return;
    }
    
    if (widget.onImageVisible != null && 
        widget.nodeEndpoint != null &&
        widget.userPublicKey != null &&
        widget.userMnemonic != null) {
      
      AppLogger.log('SimpleImageWidget: Triggering download for ${widget.fileId}');
      _hasTriggeredDownload = true;
      widget.onImageVisible!(widget.fileId, widget.nodeEndpoint!);
    } else {
      AppLogger.log('SimpleImageWidget: Cannot trigger download for ${widget.fileId}');
      AppLogger.log('  - onImageVisible: ${widget.onImageVisible != null}');
      AppLogger.log('  - nodeEndpoint: ${widget.nodeEndpoint != null}');
      AppLogger.log('  - userPublicKey: ${widget.userPublicKey != null}');
      AppLogger.log('  - userMnemonic: ${widget.userMnemonic != null}');
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we have the downloaded image, show it
    if (widget.downloadedImage != null) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio ?? 1,
        child: Container(
          width: widget.forceLarge ? double.infinity : null,
          height: widget.forceLarge ? null : 120,
          margin: widget.forceLarge ? const EdgeInsets.only(bottom: 0) : const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: widget.customBorderRadius ?? BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(
            widget.downloadedImage!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.image,
                size: 80,
                color: Colors.grey,
              );
            },
          ),
        ),
      );
    }

    // If downloading, show loading indicator
    if (widget.isDownloading) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio ?? 1,
        child: Container(
          width: widget.forceLarge ? double.infinity : null,
          height: widget.forceLarge ? null : 120,
          alignment: Alignment.center,
          margin: widget.forceLarge ? const EdgeInsets.only(bottom: 0) : const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: widget.customBorderRadius ?? BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // If download failed, show error state with retry button
    if (widget.downloadFailed) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio ?? 1,
        child: Container(
          width: widget.forceLarge ? double.infinity : null,
          height: widget.forceLarge ? null : 120,
          alignment: Alignment.center,
          margin: widget.forceLarge ? const EdgeInsets.only(bottom: 0) : const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: widget.customBorderRadius ?? BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.broken_image, size: 80, color: Colors.redAccent),
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    // Clear failed status from cache service
                    _cacheService.clearFileStatus(widget.fileId);
                    _hasTriggeredDownload = false;
                    _triggerDownload();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show placeholder with manual download button
    return AspectRatio(
      aspectRatio: widget.aspectRatio ?? 1,
      child: Container(
        width: widget.forceLarge ? double.infinity : null,
        height: widget.forceLarge ? null : 120,
        alignment: Alignment.center,
        margin: widget.forceLarge ? const EdgeInsets.only(bottom: 0) : const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: widget.customBorderRadius ?? BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.image, size: 80, color: Colors.grey),
            // Always show download button as fallback
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  AppLogger.log('SimpleImageWidget: Manual download triggered for ${widget.fileId}');
                  _cacheService.clearFileStatus(widget.fileId);
                  _hasTriggeredDownload = false;
                  _triggerDownload();
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.download,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 
