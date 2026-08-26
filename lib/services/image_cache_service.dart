import 'dart:typed_data';
import 'package:flutter/foundation.dart';


class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  // Cache for downloaded images: fileId -> Uint8List
  final Map<String, Uint8List> _imageCache = {};
  
  // Cache for download status: fileId -> bool (true = downloading, false = failed)
  final Map<String, bool> _downloadStatus = {};
  
  // Callbacks for when downloads complete: fileId -> List of callbacks
  final Map<String, List<Function(Uint8List)>> _downloadCallbacks = {};
  
  // Callbacks for when downloads fail: fileId -> List of callbacks
  final Map<String, List<Function(String)>> _errorCallbacks = {};

  /// Check if image is already cached
  bool hasImage(String fileId) {
    return _imageCache.containsKey(fileId);
  }

  /// Get cached image
  Uint8List? getImage(String fileId) {
    return _imageCache[fileId];
  }

  /// Check if image is currently downloading
  bool isDownloading(String fileId) {
    return _downloadStatus[fileId] == true;
  }

  /// Check if image download failed
  bool hasFailed(String fileId) {
    return _downloadStatus[fileId] == false;
  }

  /// Add callback for when download completes
  void addDownloadCallback(String fileId, Function(Uint8List) callback) {
    _downloadCallbacks.putIfAbsent(fileId, () => []).add(callback);
  }

  /// Add callback for when download fails
  void addErrorCallback(String fileId, Function(String) callback) {
    _errorCallbacks.putIfAbsent(fileId, () => []).add(callback);
  }

  /// Store downloaded image and notify callbacks
  void storeImage(String fileId, Uint8List imageData) {
    _imageCache[fileId] = imageData;
    _downloadStatus.remove(fileId); // Remove from downloading status
    
    // Notify all callbacks
    final callbacks = _downloadCallbacks[fileId] ?? [];
    for (final callback in callbacks) {
      try {
        callback(imageData);
      } catch (e) {
      }
    }
    _downloadCallbacks.remove(fileId);
  }

  /// Mark download as failed and notify callbacks
  void markFailed(String fileId, String error) {
    _downloadStatus[fileId] = false;
    
    // Notify all error callbacks
    final callbacks = _errorCallbacks[fileId] ?? [];
    for (final callback in callbacks) {
      try {
        callback(error);
      } catch (e) {
      }
    }
    _errorCallbacks.remove(fileId);
  }

  /// Mark download as started
  void markDownloading(String fileId) {
    _downloadStatus[fileId] = true;
  }

  /// Clear all caches (useful for testing or memory management)
  void clearCache() {
    _imageCache.clear();
    _downloadStatus.clear();
    _downloadCallbacks.clear();
    _errorCallbacks.clear();
  }

  /// Clear status for a specific file (useful for retry functionality)
  void clearFileStatus(String fileId) {
    _downloadStatus.remove(fileId);
    _downloadCallbacks.remove(fileId);
    _errorCallbacks.remove(fileId);
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cachedImages': _imageCache.length,
      'downloading': _downloadStatus.values.where((status) => status == true).length,
      'failed': _downloadStatus.values.where((status) => status == false).length,
      'pendingCallbacks': _downloadCallbacks.length + _errorCallbacks.length,
    };
  }
} 
