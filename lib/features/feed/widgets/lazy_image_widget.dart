import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'dart:typed_data';
import 'package:deltanium_app/services/app_logger.dart';


class LazyImageWidget extends StatefulWidget {
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

  const LazyImageWidget({
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
  State<LazyImageWidget> createState() => _LazyImageWidgetState();
}

class _LazyImageWidgetState extends State<LazyImageWidget> {
  bool _hasTriggeredDownload = false;

  @override
  void initState() {
    super.initState();
    // Trigger download immediately when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerDownload();
    });
  }

  @override
  void didUpdateWidget(LazyImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-trigger download if credentials changed
    if (oldWidget.userPublicKey != widget.userPublicKey ||
        oldWidget.userMnemonic != widget.userMnemonic ||
        oldWidget.nodeEndpoint != widget.nodeEndpoint) {
      _hasTriggeredDownload = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerDownload();
      });
    }
  }

  void _triggerDownload() {
    if (!_hasTriggeredDownload && 
        widget.onImageVisible != null && 
        widget.nodeEndpoint != null &&
        widget.userPublicKey != null &&
        widget.userMnemonic != null) {
      
      AppLogger.log('LazyImageWidget: Triggering download for $widget.fileId');
      _hasTriggeredDownload = true;
      widget.onImageVisible!(widget.fileId, widget.nodeEndpoint!);
    } else {
      AppLogger.log('LazyImageWidget: Cannot trigger download for $widget.fileId - hasTriggered: $_hasTriggeredDownload, onImageVisible: ${widget.onImageVisible != null}, nodeEndpoint: ${widget.nodeEndpoint != null}, userPublicKey: ${widget.userPublicKey != null}, userMnemonic: ${widget.userMnemonic != null}');
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
          child: const CircularProgressIndicator(strokeWidth: 2),
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
              if (widget.userPublicKey != null && 
                  widget.userMnemonic != null && 
                  widget.nodeEndpoint != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      // Reset download state and retry
                      _hasTriggeredDownload = false;
                      if (widget.onImageVisible != null) {
                        widget.onImageVisible!(widget.fileId, widget.nodeEndpoint!);
                      }
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

    // Show placeholder while waiting for download to start
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
            // Show a subtle loading indicator if we have credentials but haven't started download yet
            if (widget.userPublicKey != null && 
                widget.userMnemonic != null && 
                widget.nodeEndpoint != null &&
                !_hasTriggeredDownload)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.hourglass_empty,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            // Add a manual download button as fallback
            if (widget.userPublicKey != null && 
                widget.userMnemonic != null && 
                widget.nodeEndpoint != null)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    AppLogger.log('LazyImageWidget: Manual download triggered for $widget.fileId');
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
