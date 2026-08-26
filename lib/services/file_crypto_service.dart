import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/ecies_service.dart';
import 'package:deltanium_app/services/pre_ffi.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:http/http.dart' as http;
import 'package:bip39/bip39.dart' as bip39;
import 'package:deltanium_app/services/pre_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:webcrypto/webcrypto.dart';
import 'dart:isolate';
import 'package:deltanium_app/services/app_logger.dart';


/// Cache manager for symmetric keys and decrypted blocks
class _CacheManager {
  // Cache configs
  static const int MAX_SYMMETRIC_KEYS = 50;
  static const int MAX_DECRYPTED_BLOCKS = 100;
  static const int CACHE_EXPIRE_MINUTES = 120; // 🔧 INCREASED: 2 hours instead of 30 minutes
  static const int MAX_BLOCK_CACHE_SIZE = 1024 * 1024; // 1MB max per block
  
  // Cache storage
  static final Map<String, _CacheEntry<Uint8List>> _symmetricKeyCache = {};
  static final Map<String, _CacheEntry<Uint8List>> _decryptedBlockCache = {};
  
  // 🔧 DEBUGGING: Cache disable flag
  static bool _cacheDisabled = false;
  
  /// Generate cache key for symmetric key with improved collision resistance
  static String _generateSymmetricKeyCacheKey(Uint8List encryptedData, String mnemonic) {
    // 🔧 FIXED: Use content-based hashing only (NO timestamp) for proper cache hits
    final dataHash = sha256.convert(encryptedData).toString();
    final mnemonicHash = sha256.convert(utf8.encode(mnemonic)).toString();
    
    final combined = 'SYMKEY|$dataHash|${mnemonicHash.substring(0, 16)}';
    final finalHash = sha256.convert(utf8.encode(combined)).toString();
    final shortKey = finalHash.substring(0, 16);
    return finalHash.substring(0, 24); // Deterministic key for proper caching
  }
  
  /// Generate cache key for decrypted block with improved collision resistance  
  static String _generateBlockCacheKey(Uint8List encryptedData, Uint8List key) {
    // 🔧 FIXED: Use content-based hashing only (NO timestamp) for proper cache hits
    final encDataHash = sha256.convert(encryptedData).toString();
    final keyHash = sha256.convert(key).toString();
    
    final combined = 'BLOCK|$encDataHash|$keyHash|${encryptedData.length}';
    final finalHash = sha256.convert(utf8.encode(combined)).toString();
    return finalHash.substring(0, 24); // Deterministic key for proper caching
  }
  
  /// Get cached symmetric key with enhanced validation
  static Uint8List? getCachedSymmetricKey(Uint8List encryptedKey, String mnemonic) {
    // 🔧 Check if cache is disabled for debugging
    if (_cacheDisabled) {
      AppLogger.log('🔧 DEBUG: Cache disabled, skipping cache lookup');
      return null;
    }
    
    final key = _generateSymmetricKeyCacheKey(encryptedKey, mnemonic);
    final entry = _symmetricKeyCache[key];
    
    if (entry == null) {
      return null;
    }
    
    // Check expiration
    if (DateTime.now().difference(entry.createdAt).inMinutes > CACHE_EXPIRE_MINUTES) {
      _symmetricKeyCache.remove(key);
      AppLogger.log('CacheManager: Expired symmetric key cache entry removed');
      return null;
    }
    
    // 🔧 ENHANCED VALIDATION: Check cached data integrity
    final cachedKey = entry.data;
    
    if (cachedKey.isEmpty) {
      AppLogger.log('❌ CRITICAL: Cached symmetric key is empty! Removing corrupted cache entry.');
      _symmetricKeyCache.remove(key);
      return null;
    }
    
    if (cachedKey.length != 32) {
      AppLogger.log('❌ CRITICAL: Cached symmetric key has wrong length: ${cachedKey.length} bytes! Removing corrupted cache entry.');
      _symmetricKeyCache.remove(key);
      return null;
    }
    
    // Check for all-zero corruption
    final allZeros = cachedKey.every((b) => b == 0);
    if (allZeros) {
      AppLogger.log('❌ CRITICAL: Cached symmetric key is all zeros! Removing corrupted cache entry.');
      _symmetricKeyCache.remove(key);
      return null;
    }
    
    // Check for suspicious patterns
    final allSame = cachedKey.every((b) => b == cachedKey[0]);
    if (allSame) {
      AppLogger.log('❌ WARNING: Cached symmetric key has all same bytes: ${cachedKey[0]}! Removing corrupted cache entry.');
      _symmetricKeyCache.remove(key);
      return null;
    }
    
    // Update access time
    entry.accessedAt = DateTime.now();
    AppLogger.log('✅ FileCryptoService: Using valid cached symmetric key (${cachedKey.length * 8}-bit)');
    return Uint8List.fromList(cachedKey); // Return copy to prevent external modification
  }
  
  /// Cache symmetric key
  static void cacheSymmetricKey(Uint8List encryptedKey, String mnemonic, Uint8List symmetricKey) {
    // 🔧 Check if cache is disabled for debugging
    if (_cacheDisabled) {
      AppLogger.log('🔧 DEBUG: Cache disabled, skipping cache write');
      return;
    }
    
    // 🔧 STRICT VALIDATION: Check if symmetric key is valid before caching
    if (symmetricKey.isEmpty) {
      AppLogger.log('❌ CRITICAL: Refusing to cache empty symmetric key!');
      return;
    }
    
    if (symmetricKey.length != 32) {
      AppLogger.log('❌ CRITICAL: Refusing to cache symmetric key with wrong length: ${symmetricKey.length} bytes');
      return;
    }
    
    // Check for all-zero key (corruption indicator)
    final allZeros = symmetricKey.every((b) => b == 0);
    if (allZeros) {
      AppLogger.log('❌ CRITICAL: Refusing to cache all-zero symmetric key!');
      return;
    }
    
    // Check for suspicious patterns
    final allSame = symmetricKey.every((b) => b == symmetricKey[0]);
    if (allSame) {
      AppLogger.log('❌ WARNING: Refusing to cache symmetric key with all same bytes: ${symmetricKey[0]}');
      return;
    }
    
    final key = _generateSymmetricKeyCacheKey(encryptedKey, mnemonic);
    
    // Ensure cache size limit
    _ensureSymmetricKeyCacheSize();
    
    // Create cache entry with VALIDATION
    final entry = _CacheEntry<Uint8List>(
      data: Uint8List.fromList(symmetricKey), // COPY to prevent external modification
      createdAt: DateTime.now(),
      accessedAt: DateTime.now(),
    );
    
    _symmetricKeyCache[key] = entry;
    
    // Double-check what we just cached
    final cachedData = _symmetricKeyCache[key]?.data;
    if (cachedData != null) {
      final cachedAllZeros = cachedData.every((b) => b == 0);
      if (cachedAllZeros) {
        AppLogger.log('❌ CRITICAL: Just cached symmetric key became all zeros! Removing immediately.');
        _symmetricKeyCache.remove(key);
        return;
      }
    }
    
    AppLogger.log('CacheManager: Cached symmetric key (${symmetricKey.length * 8}-bit) with validation passed');
  }
  
  /// Get cached decrypted block
  static Uint8List? getCachedDecryptedBlock(Uint8List encryptedData, Uint8List symmetricKey) {
    // 🔧 Check if cache is disabled for debugging
    if (_cacheDisabled) {
      AppLogger.log('🔧 DEBUG: Cache disabled, skipping cache lookup');
      return null;
    }
    
    // Don't cache large blocks
    if (encryptedData.length > MAX_BLOCK_CACHE_SIZE) {
      return null;
    }
    
    final key = _generateBlockCacheKey(encryptedData, symmetricKey);
    final entry = _decryptedBlockCache[key];
    
    if (entry == null) {
      return null;
    }
    
    // Check expiration
    if (entry.isExpired()) {
      _decryptedBlockCache.remove(key);
      AppLogger.log('CacheManager: Expired decrypted block cache entry removed');
      return null;
    }
    
    // Quick integrity check - see if first few bytes look reasonable
    final preview = entry.data.length >= 4 ? entry.data.sublist(0, 4) : entry.data;
    final previewHex = preview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    
    AppLogger.log('CacheManager: Cache HIT for decrypted block (${entry.data.length} bytes), preview: $previewHex');
    return entry.data;
  }
  
  /// Cache decrypted block
  static void cacheDecryptedBlock(Uint8List encryptedData, Uint8List symmetricKey, Uint8List decryptedBlock) {
    // 🔧 Check if cache is disabled for debugging
    if (_cacheDisabled) {
      AppLogger.log('🔧 DEBUG: Cache disabled, skipping cache write');
      return;
    }
    
    // Don't cache large blocks
    if (encryptedData.length > MAX_BLOCK_CACHE_SIZE || decryptedBlock.length > MAX_BLOCK_CACHE_SIZE) {
      AppLogger.log('🔍 DEBUG: Skipping cache for large block: encrypted=${encryptedData.length}, decrypted=${decryptedBlock.length}');
      return;
    }
    
    // 🔧 INTEGRITY CHECK: Verify input data before caching
    if (decryptedBlock.isEmpty) {
      AppLogger.log('❌ WARNING: Attempting to cache empty decrypted block! Skipping cache.');
      return;
    }
    
    final key = _generateBlockCacheKey(encryptedData, symmetricKey);
    
    // Ensure cache size limit
    _ensureDecryptedBlockCacheSize();
    
    // 🔧 DEBUG: Check if we're overwriting existing cache entry
    if (_decryptedBlockCache.containsKey(key)) {
      final existingEntry = _decryptedBlockCache[key];
      final existingPreview = existingEntry!.data.length >= 4 ? existingEntry.data.sublist(0, 4) : existingEntry.data;
      final existingHex = existingPreview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      AppLogger.log('🔍 DEBUG: Overwriting existing cache entry with preview: $existingHex');
    }
    
    // Create cache entry
    final entry = _CacheEntry<Uint8List>(
      data: Uint8List.fromList(decryptedBlock), // Copy to avoid external modification
      createdAt: DateTime.now(),
      accessedAt: DateTime.now(),
    );
    
    _decryptedBlockCache[key] = entry;
    
    // 🔧 DEBUG: Verify cached data immediately
    final cachedPreview = entry.data.length >= 4 ? entry.data.sublist(0, 4) : entry.data;
    final cachedHex = cachedPreview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final originalPreview = decryptedBlock.length >= 4 ? decryptedBlock.sublist(0, 4) : decryptedBlock;
    final originalHex = originalPreview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    
    if (cachedHex != originalHex) {
      AppLogger.log('❌ CRITICAL: Cache data corruption detected! Original: $originalHex, Cached: $cachedHex');
    } else {
      AppLogger.log('✅ CacheManager: Cached decrypted block (${decryptedBlock.length} bytes), preview: $cachedHex');
    }
  }
  
  /// Ensure symmetric key cache size limit (LRU eviction)
  static void _ensureSymmetricKeyCacheSize() {
    while (_symmetricKeyCache.length >= MAX_SYMMETRIC_KEYS) {
      // Find oldest accessed entry
      String? oldestKey;
      DateTime? oldestTime;
      
      for (final entry in _symmetricKeyCache.entries) {
        if (oldestTime == null || entry.value.accessedAt.isBefore(oldestTime)) {
          oldestTime = entry.value.accessedAt;
          oldestKey = entry.key;
        }
      }
      
      if (oldestKey != null) {
        _removeSymmetricKeyCache(oldestKey);
      }
    }
  }
  
  /// Ensure decrypted block cache size limit (LRU eviction)
  static void _ensureDecryptedBlockCacheSize() {
    while (_decryptedBlockCache.length >= MAX_DECRYPTED_BLOCKS) {
      // Find oldest accessed entry
      String? oldestKey;
      DateTime? oldestTime;
      
      for (final entry in _decryptedBlockCache.entries) {
        if (oldestTime == null || entry.value.accessedAt.isBefore(oldestTime)) {
          oldestTime = entry.value.accessedAt;
          oldestKey = entry.key;
        }
      }
      
      if (oldestKey != null) {
        _removeDecryptedBlockCache(oldestKey);
      }
    }
  }
  
  /// Remove symmetric key from cache with secure memory clearing
  static void _removeSymmetricKeyCache(String key) {
    final entry = _symmetricKeyCache.remove(key);
    if (entry != null) {
      // Secure clear memory
      entry.data.fillRange(0, entry.data.length, 0);
    }
  }
  
  /// Remove decrypted block from cache with secure memory clearing
  static void _removeDecryptedBlockCache(String key) {
    final entry = _decryptedBlockCache.remove(key);
    if (entry != null) {
      // Secure clear memory
      entry.data.fillRange(0, entry.data.length, 0);
    }
  }
  
  /// Clear all caches (for logout or security)
  static void clearAllCaches() {
    // Secure clear all symmetric keys
    for (final entry in _symmetricKeyCache.values) {
      entry.data.fillRange(0, entry.data.length, 0);
    }
    _symmetricKeyCache.clear();
    
    // Secure clear all decrypted blocks
    for (final entry in _decryptedBlockCache.values) {
      entry.data.fillRange(0, entry.data.length, 0);
    }
    _decryptedBlockCache.clear();
    
    AppLogger.log('CacheManager: All caches cleared securely');
  }
  
  /// Clear expired cache entries
  static void clearExpiredCaches() {
    final now = DateTime.now();
    
    // Clear expired symmetric keys
    final expiredSymmetricKeys = <String>[];
    for (final entry in _symmetricKeyCache.entries) {
      if (entry.value.isExpired()) {
        expiredSymmetricKeys.add(entry.key);
      }
    }
    for (final key in expiredSymmetricKeys) {
      _removeSymmetricKeyCache(key);
    }
    
    // Clear expired decrypted blocks
    final expiredBlockKeys = <String>[];
    for (final entry in _decryptedBlockCache.entries) {
      if (entry.value.isExpired()) {
        expiredBlockKeys.add(entry.key);
      }
    }
    for (final key in expiredBlockKeys) {
      _removeDecryptedBlockCache(key);
    }
    
    if (expiredSymmetricKeys.isNotEmpty || expiredBlockKeys.isNotEmpty) {
      AppLogger.log('CacheManager: Cleared ${expiredSymmetricKeys.length} expired symmetric keys, ${expiredBlockKeys.length} expired blocks');
    }
  }
  
  /// Get cache statistics
  static Map<String, dynamic> getCacheStats() {
    return {
      'symmetricKeys': _symmetricKeyCache.length,
      'decryptedBlocks': _decryptedBlockCache.length,
      'maxSymmetricKeys': MAX_SYMMETRIC_KEYS,
      'maxDecryptedBlocks': MAX_DECRYPTED_BLOCKS,
      'cacheExpireMinutes': CACHE_EXPIRE_MINUTES,
    };
  }
}

/// Cache entry with expiration and LRU tracking
class _CacheEntry<T> {
  final T data;
  final DateTime createdAt;
  DateTime accessedAt;
  
  _CacheEntry({
    required this.data,
    required this.createdAt,
    required this.accessedAt,
  });
  
  void updateAccessTime() {
    accessedAt = DateTime.now();
  }
  
  bool isExpired() {
    final now = DateTime.now();
    return now.difference(createdAt).inMinutes > _CacheManager.CACHE_EXPIRE_MINUTES;
  }
}

/// Service to handle file encryption, decryption and chunking for the Deltanium app
class FileCryptoService {
  static const int DEFAULT_BLOCK_SIZE = 4 * 1024 * 1024; // 4MB default chunk size

  /// Hex to bytes helper
  static Uint8List _hexToBytes(String hex) {
    final s = hex.trim();
    final len = s.length;
    final out = Uint8List(len ~/ 2);
    for (int i = 0; i < len; i += 2) {
      out[i >> 1] = int.parse(s.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  /// Encrypts and splits a file into blocks
  /// Returns a map with file metadata and encrypted blocks
  static Future<Map<String, dynamic>> encryptAndSplitFile({
    required Uint8List fileData,
    required String fileName,
    required String ownerPublicKey,
    required String mnemonic,
    List<String>? sharedWithPublicKeys,
    int blockSize = DEFAULT_BLOCK_SIZE,
    Function(String)? onProgress, // Progress callback
    // 🆕 Post-specific fields
    String? fileType, // 'post', 'image', 'document', etc.
    List<Map<String, dynamic>>? relatedFiles, // For posts: attached media
    String? shareType, // 🆕 Share type: 'public', 'shared', 'following'
    String encryptedType = 'encrypted',
    // 🆕 PRE (Option 2) - optional policy fields
    String? policyTag, // e.g., followers:2025
    String? capsuleFor, // e.g., 'tag'
    String? policyScheme, // e.g., 'CPRE'
    // 🆕 Storage contract ID
    String? contractId,
  }) async {
    final _encStart = DateTime.now();
    AppLogger.log('⏱️ FileCryptoService.encrypt START ' + _encStart.toIso8601String() + ' file=$fileName size=${fileData.length}');
    onProgress?.call('Generating encryption key...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    // Generate symmetric key (32 bytes)
    final random = math.Random.secure();
    final tmp = Uint8List(32);
    for (int i = 0; i < tmp.length; i++) {
      tmp[i] = random.nextInt(256);
    }
    final symmetricKey = tmp;
    AppLogger.log('FileCryptoService: Generated random symmetric key (${symmetricKey.length * 8}-bit)');

    // Calculate number of content blocks needed (file data only)
    final contentBlockCount = (fileData.length / blockSize).ceil();
    AppLogger.log('FileCryptoService: File will be split into $contentBlockCount content blocks of $blockSize bytes');
    onProgress?.call('Splitting file into $contentBlockCount blocks...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    // Generate a unique fileId using a UUID-like approach
    final fileId = _generateUniqueId();
    
    // 🔒 ZERO-KNOWLEDGE: Pre-generate content block IDs and info for metadata block
    final List<String> contentBlockIds = [];
    final List<String> contentBlockContentIds = [];
    
    // Pre-calculate content block structure for metadata
    for (int i = 0; i < contentBlockCount; i++) {
      contentBlockIds.add(_generateUniqueId()); // Random UUID for each content block
    }
    
    onProgress?.call('Pre-processing content blocks for metadata...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    // Calculate content block hashes for metadata
    for (int blockIndex = 0; blockIndex < contentBlockCount; blockIndex++) {
      final int start = blockIndex * blockSize;
      final int end = math.min(start + blockSize, fileData.length);
      final Uint8List blockData = fileData.sublist(start, end);
      
      final blockHash = sha256.convert(blockData).bytes;
      final contentId = base64Encode(blockHash);
      contentBlockContentIds.add(contentId);
    }
    
    // 🔒 ZERO-KNOWLEDGE: Create metadata block with sensitive file information
    onProgress?.call('Creating encrypted metadata block...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    final metadataBlockContent = {
      'fileName': fileName,
      'fileSize': fileData.length,
      'mimeType': _getMimeType(fileName),
      'fileExtension': _getFileExtension(fileName),
      'contentBlockCount': contentBlockCount,
      'contentBlockIds': contentBlockIds,
      'contentBlockContentIds': contentBlockContentIds,
      'contentMerkleRoot': _calculateMerkleRoot(contentBlockContentIds),
      'version': '1.0', // For future compatibility
      'creationTime': DateTime.now().toIso8601String(),
      // 🆕 Post-specific fields
      if (fileType != null) 'type': fileType,
      if (relatedFiles != null) 'relatedFiles': relatedFiles,
      'ownerPubKey': ownerPublicKey,
      'encryptedType': encryptedType,
      'shareType': shareType,
      // 🆕 PRE policy fields
      if (policyTag != null) 'policyTag': policyTag,
      if (capsuleFor != null) 'capsuleFor': capsuleFor,
      if (policyScheme != null) 'policyScheme': policyScheme,
    };
    
    AppLogger.log('FileCryptoService: Created metadata block with sensitive info: ${metadataBlockContent.keys.toList()}');
    
    // Convert metadata to JSON and then to bytes
    final metadataJson = json.encode(metadataBlockContent);
    final metadataBytes = Uint8List.fromList(utf8.encode(metadataJson));
    
    // Encrypt the metadata block
    final encryptedMetadataContent = await _encryptData(metadataBytes, symmetricKey);
    final metadataBlockId = _generateUniqueId();
    
    AppLogger.log('FileCryptoService: Metadata block encrypted: ${metadataBytes.length} bytes -> ${encryptedMetadataContent.length} bytes');
    
    // Calculate metadata block hash
    final metadataBlockHash = sha256.convert(metadataBytes).bytes;
    final metadataContentId = base64Encode(metadataBlockHash);
    
    // Total block count = metadata block (1) + content blocks (n)
    final totalBlockCount = 1 + contentBlockCount;
    final List<String> allBlockIds = [metadataBlockId, ...contentBlockIds];
    final List<String> allBlockContentIds = [metadataContentId, ...contentBlockContentIds];
    
    // Process blocks (start with metadata block, then content blocks)
    final List<Map<String, dynamic>> encryptedBlocks = [];
    
    // Add metadata block first (index 0)
    encryptedBlocks.add({
      'blockId': metadataBlockId,
      'blockIndex': 0,
      'totalBlocks': totalBlockCount,
      'size': metadataBytes.length,
      'encryptedSize': encryptedMetadataContent.length,
      'encryptedContent': encryptedMetadataContent,
      'contentId': metadataContentId,
      'isMetadataBlock': true, // Flag to identify metadata block
    });
    
    AppLogger.log('FileCryptoService: Added metadata block (index 0): ${metadataBytes.length} bytes');
    
    // Now process content blocks (starting from index 1)
    // --- SONG SONG HÓA MÃ HÓA BLOCK ---
    // Tạo danh sách các block cần mã hóa
    final List<_BlockEncryptTask> blockTasks = [];
    for (int contentBlockIndex = 0; contentBlockIndex < contentBlockCount; contentBlockIndex++) {
      final int start = contentBlockIndex * blockSize;
      final int end = math.min(start + blockSize, fileData.length);
      final Uint8List blockData = fileData.sublist(start, end);
      final blockId = contentBlockIds[contentBlockIndex];
      final contentId = contentBlockContentIds[contentBlockIndex];
      blockTasks.add(_BlockEncryptTask(
        blockIndex: contentBlockIndex + 1,
        blockId: blockId,
        contentId: contentId,
        blockData: blockData,
        symmetricKey: symmetricKey,
        totalBlocks: totalBlockCount,
      ));
    }

    // Hàm mã hóa 1 block (chạy trong Isolate)
    Future<Map<String, dynamic>> _encryptBlockIsolate(_BlockEncryptTask task) async {
      final encryptedContent = await _encryptData(task.blockData, task.symmetricKey);
      return {
        'blockId': task.blockId,
        'blockIndex': task.blockIndex,
        'totalBlocks': task.totalBlocks,
        'size': task.blockData.length,
        'encryptedSize': encryptedContent.length,
        'encryptedContent': encryptedContent,
        'contentId': task.contentId,
        'isMetadataBlock': false,
      };
    }

    // Giới hạn số lượng block song song (ví dụ 4)
    const int maxParallel = 4;
    final List<Map<String, dynamic>> encryptedContentBlocks = [];
    int current = 0;
    while (current < blockTasks.length) {
      final batch = blockTasks.skip(current).take(maxParallel).toList();
      // Hiển thị progress cho batch
      for (final task in batch) {
        final progressPercent = ((task.blockIndex - 1) / contentBlockCount * 100).round();
        onProgress?.call('Encrypting content block ${task.blockIndex}/$contentBlockCount ($progressPercent%)...');
      }
      // Mã hóa song song batch này
      final results = await Future.wait(batch.map((task) => compute(_encryptBlockIsolate, task)));
      encryptedContentBlocks.addAll(results);
      current += batch.length;
    }
    // Sắp xếp lại đúng thứ tự blockIndex
    encryptedContentBlocks.sort((a, b) => a['blockIndex'].compareTo(b['blockIndex']));
    encryptedBlocks.addAll(encryptedContentBlocks);

    // 🆕 ZERO-KNOWLEDGE SHARING: Create separate metadata entries for each user
    onProgress?.call('Creating metadata entries for access control...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    final List<Map<String, dynamic>> metadataEntries = [];
    final List<Map<String, dynamic>> allBlocks = [];
    final List<String> allUsersWithAccess = [ownerPublicKey];
    
    // Add shared users to the list
    if (sharedWithPublicKeys != null && sharedWithPublicKeys.isNotEmpty) {
      for (final pubKey in sharedWithPublicKeys) {
        if (pubKey != ownerPublicKey) {
          allUsersWithAccess.add(pubKey);
        }
      }
    }
    
    // Tạo content blocks (dùng chung cho mọi user, index >= 1)
    for (int contentBlockIndex = 0; contentBlockIndex < contentBlockCount; contentBlockIndex++) {
      final int start = contentBlockIndex * blockSize;
      final int end = math.min(start + blockSize, fileData.length);
      final Uint8List blockData = fileData.sublist(start, end);
      final encryptedContent = await _encryptData(blockData, symmetricKey);
      final blockId = contentBlockIds[contentBlockIndex];
      final contentId = contentBlockContentIds[contentBlockIndex];
      allBlocks.add({
        'blockId': blockId,
        'blockIndex': contentBlockIndex + 1, // 1-based (0 là metadata block)
        'totalBlocks': 1 + contentBlockCount, // block 0 + content blocks
        'size': blockData.length,
        'encryptedSize': encryptedContent.length,
        'encryptedContent': encryptedContent,
        'contentId': contentId,
        'isMetadataBlock': false,
      });
    }

    // Tạo metadata entry và block 0 riêng cho từng user
    final bool isPreTag = (capsuleFor != null && capsuleFor == 'tag' && policyTag != null);
    
    // 🆕 PRE: Generate BOTH ECIES (for author) and PRE capsule (for followers)
    Uint8List? preCapsuleForFollowers;
    if (isPreTag) {
      final pre = PreFfi.instance();
      final pkAuthorBytes = _hexToBytes(ownerPublicKey);
      AppLogger.log('🔐 PRE: Generating capsule with pkAuthor (${pkAuthorBytes.length} bytes), tag: $policyTag');
      preCapsuleForFollowers = pre.encapsulateWithTag(
        pkAuthor: pkAuthorBytes,
        tag: policyTag!,
        key: symmetricKey,
      );
      AppLogger.log('✅ PRE: Generated capsule for followers (${preCapsuleForFollowers.length} bytes)');
    }
    
    for (final userPubKey in allUsersWithAccess) {
      // 🔧 FIX: Sinh fileId riêng cho mỗi user (unique per user)
      final userFileId = _generateUniqueId();
      // Sinh id riêng cho block 0 (firstBlockId)
      final firstBlockId = _generateUniqueId();
      
      // 🆕 HYBRID: encryptedKey is ALWAYS ECIES (for author direct access)
      // For PRE posts: also add encapsulatedForRecipient (PRE capsule for followers)
      final Uint8List encryptedKeyForUserBytes = await _encryptSymmetricKeyWithPublicKey(
        symmetricKey, 
        isPreTag ? ownerPublicKey : userPubKey, // PRE: encrypt for author; Non-PRE: encrypt for recipient
      );
      
      final normalizedUserKey = CryptoService.convertToCompressedPublicKey(userPubKey);
      
      // Tạo metadata entry; với PRE-tag, KHÔNG gán recipientPubKey để Store nhận diện Option 2
      final metadataEntry = {
        'fileId': userFileId, // 🆕 Unique fileId per user
        'firstBlockId': firstBlockId, // 🆕 Unique firstBlockId per user
        if (!isPreTag) 'recipientPubKey': normalizedUserKey,
        'creationTime': DateTime.now().toIso8601String(),
        'encryptedKey': base64Encode(encryptedKeyForUserBytes), // ECIES(K, pkAuthor for PRE, pkRecipient for non-PRE)
        if (fileType != null) 'type': fileType,
        'shareType': shareType,
        'encryptedType': encryptedType,
        if (contractId != null && contractId.isNotEmpty) 'contractId': contractId,
        // 🆕 PRE policy fields (copied per-entry for convenience in feeds)
        if (policyTag != null) 'policyTag': policyTag,
        if (capsuleFor != null) 'capsuleFor': capsuleFor,
        if (policyScheme != null) 'policyScheme': policyScheme,
        // 🆕 FIX: Add ownerPubKey for ALL files (not just PRE posts) to enable zero-knowledge sharing lookup
        'ownerPubKey': ownerPublicKey,
        // 🆕 HYBRID: Add PRE capsule for followers (if PRE post)
        if (isPreTag && preCapsuleForFollowers != null) 
          'encapsulatedForRecipient': base64Encode(preCapsuleForFollowers),
      };
      metadataEntries.add(metadataEntry);
      // Tạo metadata block content (chứa thông tin nhạy cảm)
      final metadataBlockContent = {
        'fileName': fileName,
        'fileSize': fileData.length,
        'mimeType': _getMimeType(fileName),
        'fileExtension': _getFileExtension(fileName),
        'contentBlockCount': contentBlockCount,
        'contentBlockIds': contentBlockIds,
        'contentBlockContentIds': contentBlockContentIds,
        'contentMerkleRoot': _calculateMerkleRoot(contentBlockContentIds),
        'version': '1.0',
        'creationTime': DateTime.now().toIso8601String(),
        if (fileType != null) 'type': fileType,
        if (relatedFiles != null) 'relatedFiles': relatedFiles,
        'ownerPubKey': ownerPublicKey,
        'shareType': shareType,
        'encryptedType': encryptedType,
        // 🆕 PRE policy fields
        if (policyTag != null) 'policyTag': policyTag,
        if (capsuleFor != null) 'capsuleFor': capsuleFor,
        if (policyScheme != null) 'policyScheme': policyScheme,
      };
      
      // 🔍 DEBUG: Log related files in metadata creation
      AppLogger.log('🔍 DEBUG FILECRYPTOSERVICE - Creating metadata for user: ${userPubKey.substring(0, 10)}...');
      AppLogger.log('  relatedFiles in metadata: ${metadataBlockContent['relatedFiles']}');
      AppLogger.log('  relatedFiles type: ${metadataBlockContent['relatedFiles']?.runtimeType}');
      AppLogger.log('  relatedFiles length: ${(metadataBlockContent['relatedFiles'] as List?)?.length ?? 0}');
      if (metadataBlockContent['relatedFiles'] != null) {
        final relatedFilesList = metadataBlockContent['relatedFiles'] as List;
        AppLogger.log('  relatedFiles content:');
        for (int i = 0; i < relatedFilesList.length; i++) {
          AppLogger.log('    [$i]: ${relatedFilesList[i]}');
        }
      }
      AppLogger.log('🔍 END DEBUG FILECRYPTOSERVICE');
      
      final metadataJson = json.encode(metadataBlockContent);
      final metadataBytes = Uint8List.fromList(utf8.encode(metadataJson));
      final encryptedMetadataContent = await _encryptData(metadataBytes, symmetricKey);
      final metadataBlockHash = sha256.convert(metadataBytes).bytes;
      final metadataContentId = base64Encode(metadataBlockHash);
      // Thêm block 0 riêng cho user này
      allBlocks.add({
        'blockId': firstBlockId,
        'blockIndex': 0,
        'totalBlocks': 1 + contentBlockCount,
        'size': metadataBytes.length,
        'encryptedSize': encryptedMetadataContent.length,
        'encryptedContent': encryptedMetadataContent,
        'contentId': metadataContentId,
        'isMetadataBlock': true,
        'shareType': shareType,
        'encryptedType': encryptedType,
        'recipientFileId': userFileId, // Link to specific recipient's fileId
      });
    }

    AppLogger.log('FileCryptoService: Encryption complete. Created ${allBlocks.length} blocks (metadata + content)');
    final _encElapsed = DateTime.now().difference(_encStart).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService.encrypt END ' + DateTime.now().toIso8601String() + ' (' + _encElapsed.toString() + 'ms)');
    symmetricKey.fillRange(0, symmetricKey.length, 0);
    return {
      'metadataEntries': metadataEntries,
      'blocks': allBlocks,
    };
  }
  
  /// 🔒 ZERO-KNOWLEDGE: Decrypt metadata block to get sensitive file information
  /// This is called first during download to extract file details
  /// 🚀 PERFORMANCE: Now returns both metadata AND symmetric key for reuse
  static Future<Map<String, dynamic>> decryptMetadataBlock({
    required Map<String, dynamic> storeMetadata,
    required Uint8List encryptedMetadataBlock,
    required String userPublicKey,
    required String mnemonic,
  }) async {
    final metadataStartTime = DateTime.now();
    AppLogger.log('⏱️ FileCryptoService: Starting metadata block decryption...');
    
    // Determine PRE mode
    final policyTag = (storeMetadata['policyTag'] ?? storeMetadata['PolicyTag']) as String?;
    final capsuleFor = (storeMetadata['capsuleFor'] ?? storeMetadata['CapsuleFor']) as String?;
    final ownerPubKey = (storeMetadata['ownerPubKey'] ?? storeMetadata['OwnerPubKey']) as String?;
    final encapsulatedForRecipientB64 = (storeMetadata['encapsulatedForRecipient'] ?? storeMetadata['EncapsulatedForRecipient']) as String?;

    Uint8List symmetricKey;
    final isPre = (capsuleFor == 'tag' && policyTag != null && policyTag.isNotEmpty);
    final isAuthor = ownerPubKey != null && ownerPubKey.toLowerCase() == userPublicKey.toLowerCase();

    if (isPre && !isAuthor && encapsulatedForRecipientB64 != null && encapsulatedForRecipientB64.isNotEmpty) {
      AppLogger.log('FileCryptoService: PRE follower flow for metadata decryption');
      final capsuleForAuthor = base64Decode(encapsulatedForRecipientB64);
      final rkB64 = await _fetchRekeyFromCentral(
        followerPubKey: userPublicKey,
        followingPubKey: ownerPubKey!,
        policyTag: policyTag!,
        mnemonic: mnemonic,
      );
      if (rkB64 == null) {
        throw Exception('Rekey not available yet');
      }
      final rk = base64Decode(rkB64);
      final pre = PreFfi.instance();
      final capsuleForFollower = pre.reencrypt(
        encapsulatedForAuthor: capsuleForAuthor,
        rekey: rk,
      );
      if (capsuleForFollower.isEmpty) {
        throw Exception('PRE re-encryption failed for metadata');
      }
      final seed = bip39.mnemonicToSeed(mnemonic);
      final skFollower = sha256.convert(seed).bytes;
      final keyBytes = pre.decapsulateForRecipient(
        encapsulatedForRecipient: capsuleForFollower,
        skRecipient: Uint8List.fromList(skFollower),
        tag: policyTag,
      );
      if (keyBytes.isEmpty) {
        throw Exception('PRE decapsulation failed for metadata');
      }
      symmetricKey = keyBytes;
    } else {
      // ECIES path
      final encryptedKeyString = storeMetadata['encryptedKey'] as String?;
      if (encryptedKeyString == null || encryptedKeyString.isEmpty) {
        throw Exception('No encrypted key found for this file');
      }
      final keyDecryptStartTime = DateTime.now();
      final encryptedKey = base64Decode(encryptedKeyString);
      symmetricKey = await _decryptSymmetricKeyWithPrivateKey(encryptedKey, mnemonic);
      final keyDecryptTime = DateTime.now().difference(keyDecryptStartTime).inMilliseconds;
      AppLogger.log('⏱️ FileCryptoService: Symmetric key decryption took ${keyDecryptTime}ms');
      AppLogger.log('✅ FileCryptoService: Using valid cached symmetric key (${symmetricKey.length * 8}-bit)');
    }
    
    AppLogger.log('FileCryptoService: Decrypted symmetric key from metadata');
    
    // Decrypt metadata block content
    final contentDecryptStartTime = DateTime.now();
    final decryptedMetadataBytes = await _decryptData(encryptedMetadataBlock, symmetricKey);
    final contentDecryptTime = DateTime.now().difference(contentDecryptStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: Metadata content decryption took ${contentDecryptTime}ms');
    
    // Parse JSON from decrypted bytes
    final parseStartTime = DateTime.now();
    
    // 🐛 DEBUG: Check decrypted metadata bytes before parsing
    AppLogger.log('🔍 DEBUG: Decrypted metadata bytes length: ${decryptedMetadataBytes.length}');
    if (decryptedMetadataBytes.length <= 100) {
      final hexPreview = decryptedMetadataBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      AppLogger.log('🔍 DEBUG: Decrypted metadata hex: $hexPreview');
    } else {
      final preview = decryptedMetadataBytes.sublist(0, 50);
      final hexPreview = preview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      AppLogger.log('🔍 DEBUG: Decrypted metadata hex (first 50 bytes): $hexPreview...');
    }
    
    // Try to decode as UTF-8 and catch specific errors
    String metadataJson;
    try {
      metadataJson = utf8.decode(decryptedMetadataBytes);
      AppLogger.log('🔍 DEBUG: Successfully decoded UTF-8, JSON length: ${metadataJson.length}');
      if (metadataJson.length <= 200) {
        AppLogger.log('🔍 DEBUG: JSON content preview: $metadataJson');
      } else {
        AppLogger.log('🔍 DEBUG: JSON content preview (first 200 chars): ${metadataJson.substring(0, 200)}...');
      }
    } catch (utf8Error) {
      AppLogger.log('❌ DEBUG: UTF-8 decode failed: $utf8Error');
      
      // Try alternative decoding methods
      try {
        // Try Latin-1 decoding (fallback)
        metadataJson = String.fromCharCodes(decryptedMetadataBytes);
        AppLogger.log('🔍 DEBUG: Fallback Latin-1 decode successful, length: ${metadataJson.length}');
      } catch (latin1Error) {
        AppLogger.log('❌ DEBUG: Latin-1 decode also failed: $latin1Error');
        throw Exception('Cannot decode metadata bytes: UTF-8 failed ($utf8Error), Latin-1 failed ($latin1Error)');
      }
    }
    
    // Try to parse JSON
    Map<String, dynamic> metadataContent;
    try {
      metadataContent = json.decode(metadataJson) as Map<String, dynamic>;
      AppLogger.log('🔍 DEBUG: Successfully parsed JSON, keys: ${metadataContent.keys.toList()}');
    } catch (jsonError) {
      AppLogger.log('❌ DEBUG: JSON parse failed: $jsonError');
      AppLogger.log('🔍 DEBUG: Failed JSON string: $metadataJson');
      throw Exception('Cannot parse metadata JSON: $jsonError');
    }
    
    final parseTime = DateTime.now().difference(parseStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: JSON parsing took ${parseTime}ms');
    
    final totalMetadataTime = DateTime.now().difference(metadataStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: Total metadata block decryption took ${totalMetadataTime}ms');
    AppLogger.log('FileCryptoService: Metadata block decrypted successfully');
    AppLogger.log('FileCryptoService: File info - Name: ${metadataContent['fileName']}, Size: ${metadataContent['fileSize']} bytes');
    
    // 🚀 PERFORMANCE: Include symmetric key in return for reuse
    // Don't clear symmetric key from memory - let caller handle it
    metadataContent['_symmetricKey'] = symmetricKey; // Hidden field for reuse
    
    return metadataContent;
  }

  /// 🚀 PERFORMANCE: Decrypt file using pre-decrypted symmetric key (avoid ECIES re-decryption)
  /// This should be used after decryptMetadataBlock() to reuse the symmetric key
  static Future<Uint8List> decryptFileWithSymmetricKey({
    required Map<String, dynamic> fileMetadata,
    required List<Uint8List> encryptedBlocks,
    required Uint8List symmetricKey, // 🚀 Reuse from metadata decryption
    Function(String)? onProgress, // Progress callback
  }) async {
    final fileDecryptStartTime = DateTime.now();
    AppLogger.log('⏱️ FileCryptoService: Starting OPTIMIZED file decryption with reused symmetric key...');
    AppLogger.log('✅ FileCryptoService: Using PRE-DECRYPTED symmetric key (${symmetricKey.length * 8}-bit) - SKIPPING ECIES!');
    
    onProgress?.call('Preparing decryption buffer...');
    await Future.delayed(Duration(milliseconds: 5)); // Yield control
    
    // Create a buffer for the full file
    final bufferSetupStartTime = DateTime.now();
    final fileSize = fileMetadata['fileSize'] is int 
        ? fileMetadata['fileSize'] as int
        : int.parse(fileMetadata['fileSize'].toString());
    
    if (fileSize <= 0) {
      AppLogger.log('❌ Invalid fileSize: $fileSize, using decrypted block size instead');
      // Try to get size from first decrypted block
      final firstBlock = await _decryptData(encryptedBlocks[0], symmetricKey);
      if (firstBlock == null || firstBlock.isEmpty) {
        throw Exception('Failed to determine file size: both metadata and decrypted block are invalid');
      }
      AppLogger.log('✅ Using decrypted block size: ${firstBlock.length} bytes');
      return firstBlock; // Return the decrypted block directly
    }
    
    final result = Uint8List(fileSize);
    final bufferSetupTime = DateTime.now().difference(bufferSetupStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: Buffer setup took ${bufferSetupTime}ms');
    AppLogger.log('FileCryptoService: Preparing buffer for $fileSize bytes');
    
    // Keep track of bytes written
    int bytesWritten = 0;
    
    // Decrypt each block and add to result
    final blocksDecryptStartTime = DateTime.now();
    for (int i = 0; i < encryptedBlocks.length; i++) {
      // Log input state before decrypting blocks
      AppLogger.log('DEBUG: fileMetadata=$fileMetadata');
      AppLogger.log('DEBUG: encryptedBlocks.length=${encryptedBlocks.length}');
      for (int i = 0; i < encryptedBlocks.length; i++) {
        AppLogger.log('DEBUG: encryptedBlocks[$i] type=${encryptedBlocks[i]?.runtimeType}, length=${encryptedBlocks[i]?.length}');
      }
      AppLogger.log('DEBUG: result type=${result.runtimeType}, result.length=${result.length}');
      AppLogger.log('DEBUG: bytesWritten initial=$bytesWritten');
      // Calculate progress
      final progressPercent = ((i + 1) / encryptedBlocks.length * 100).round();
      onProgress?.call('Decrypting block [1m[1m${i + 1}/${encryptedBlocks.length} ($progressPercent%)...[0m');
      await Future.delayed(Duration(milliseconds: 20)); // Yield control
      final blockDecryptStartTime = DateTime.now();
      AppLogger.log('FileCryptoService: Decrypting block ${i + 1}/${encryptedBlocks.length}');
      // Use direct decryption instead of isolate for now
      final decryptedBlock = await _decryptData(encryptedBlocks[i], symmetricKey);
      if (decryptedBlock == null) {
        AppLogger.log('❌ Decrypted block $i is null!');
        AppLogger.log('  encryptedBlock.length: \\${encryptedBlocks[i].length}');
        AppLogger.log('  symmetricKey.length: \\${symmetricKey.length}');
        throw Exception('Decrypted block $i is null');
      }
      final int bytesToCopy = math.min(decryptedBlock.length, (result.length - bytesWritten).toInt());
      if (bytesToCopy <= 0) {
        AppLogger.log('❌ Invalid bytesToCopy: $bytesToCopy at block $i, decryptedBlock.length=${decryptedBlock.length}, result.length=${result.length}, bytesWritten=$bytesWritten');
        throw Exception('Invalid bytesToCopy: $bytesToCopy at block $i');
      }
      result.setRange(bytesWritten, bytesWritten + bytesToCopy, decryptedBlock);
      bytesWritten += bytesToCopy;
      AppLogger.log('FileCryptoService: Block $i decrypted: ${decryptedBlock.length} bytes, total written: $bytesWritten');
    }
    
    final blocksDecryptTime = DateTime.now().difference(blocksDecryptStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: All blocks decryption took ${blocksDecryptTime}ms');
    
    AppLogger.log('FileCryptoService: OPTIMIZED file decryption complete: $bytesWritten bytes');
    
    // Debug: Show the first few bytes of decrypted data for small files
    if (result.length <= 100) {
      final preview = result.sublist(0, math.min(20, result.length));
      AppLogger.log('FileCryptoService: Small file decrypted preview (hex): ${preview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      
      // Try to decode as text
      try {
        final textContent = utf8.decode(result);
        AppLogger.log('FileCryptoService: Small file decrypted text: "$textContent"');
      } catch (e) {
        AppLogger.log('FileCryptoService: Cannot decode as UTF-8: $e');
        try {
          final charContent = String.fromCharCodes(result);
          AppLogger.log('FileCryptoService: Small file as char codes: "$charContent"');
        } catch (e2) {
          AppLogger.log('FileCryptoService: Cannot decode as characters either: $e2');
        }
      }
    }
    
    final totalFileDecryptTime = DateTime.now().difference(fileDecryptStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: Total OPTIMIZED file decryption took ${totalFileDecryptTime}ms');
    
    return result;
  }

  /// 🆕 Helper: decrypt a single AES-CBC (IV-prefixed) encrypted blob with a raw symmetric key
  static Future<Uint8List?> decryptRawBlockWithKey(Uint8List encryptedData, Uint8List key) async {
    return await _decryptData(encryptedData, key);
  }

  /// Decrypt a file that has been previously encrypted
  /// Requires the user's mnemonic to decrypt the symmetric key
  static Future<Uint8List> decryptFile({
    required Map<String, dynamic> fileMetadata,
    required List<Uint8List> encryptedBlocks,
    required String userPublicKey,
    required String mnemonic,
    Function(String)? onProgress,
  }) async {
    // 🚀 CACHE: Auto-maintain cache (clear expired entries periodically)
    _autoMaintainCache();
    
    final fileDecryptStartTime = DateTime.now();
    AppLogger.log('⏱️ FileCryptoService: Starting file decryption...');
    onProgress?.call('Checking access permissions...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    // Determine PRE mode
    final policyTag = (fileMetadata['policyTag'] ?? fileMetadata['PolicyTag']) as String?;
    final capsuleFor = (fileMetadata['capsuleFor'] ?? fileMetadata['CapsuleFor']) as String?;
    final ownerPubKey = (fileMetadata['ownerPubKey'] ?? fileMetadata['OwnerPubKey']) as String?;
    final encapsulatedForRecipientB64 = (fileMetadata['encapsulatedForRecipient'] ?? fileMetadata['EncapsulatedForRecipient']) as String?;

    Uint8List symmetricKey;
    
    final isPre = (capsuleFor == 'tag' && policyTag != null && policyTag.isNotEmpty);
    final isAuthor = ownerPubKey != null && ownerPubKey.toLowerCase() == userPublicKey.toLowerCase();

    if (isPre && !isAuthor && encapsulatedForRecipientB64 != null && encapsulatedForRecipientB64.isNotEmpty) {
      // PRE follower path
      AppLogger.log('FileCryptoService: PRE follower flow for file decryption');
      final capsuleForAuthor = base64Decode(encapsulatedForRecipientB64);
      
      onProgress?.call('Fetching rekey...');
      final rkB64 = await _fetchRekeyFromCentral(
        followerPubKey: userPublicKey,
        followingPubKey: ownerPubKey!,
        policyTag: policyTag!,
        mnemonic: mnemonic,
      );
      if (rkB64 == null) {
        throw Exception('Rekey not available yet');
      }
      final rk = base64Decode(rkB64);
      final pre = PreFfi.instance();
      final capsuleForFollower = pre.reencrypt(
        encapsulatedForAuthor: capsuleForAuthor,
        rekey: rk,
      );
      if (capsuleForFollower.isEmpty) {
        throw Exception('PRE re-encryption failed');
      }
      // Derive follower secret key
      final seed = bip39.mnemonicToSeed(mnemonic);
      final skFollower = sha256.convert(seed).bytes;
      final keyBytes = pre.decapsulateForRecipient(
        encapsulatedForRecipient: capsuleForFollower,
        skRecipient: Uint8List.fromList(skFollower),
        tag: policyTag,
      );
      if (keyBytes.isEmpty) {
        throw Exception('PRE decapsulation failed');
      }
      symmetricKey = keyBytes;
    } else {
      // ECIES path (author or non-PRE)
      final encryptedKeyString = fileMetadata['encryptedKey'] as String?;
      if (encryptedKeyString == null || encryptedKeyString.isEmpty) {
        throw Exception('No encrypted key found for this file');
      }
      final encryptedKey = base64Decode(encryptedKeyString);
      AppLogger.log('FileCryptoService: Found encrypted key: ${encryptedKey.length} bytes');
      
      onProgress?.call('Decrypting symmetric key...');
      await Future.delayed(Duration(milliseconds: 10));
      final keyDecryptStartTime = DateTime.now();
      symmetricKey = await _decryptSymmetricKeyWithPrivateKey(encryptedKey, mnemonic);
      final keyDecryptTime = DateTime.now().difference(keyDecryptStartTime).inMilliseconds;
      AppLogger.log('⏱️ FileCryptoService: File symmetric key decryption took ${keyDecryptTime}ms');
      AppLogger.log('FileCryptoService: Decrypted symmetric key: ${symmetricKey.length * 8}-bit');
    }
    
    // Note: Removed verification test code for production security
    
    onProgress?.call('Preparing decryption buffer...');
    await Future.delayed(Duration(milliseconds: 5)); // Yield control
    
    // Create a buffer for the full file
    final bufferSetupStartTime = DateTime.now();
    final fileSize = int.parse(fileMetadata['fileSize'].toString());
    final result = Uint8List(fileSize);
    final bufferSetupTime = DateTime.now().difference(bufferSetupStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: Buffer setup took ${bufferSetupTime}ms');
    AppLogger.log('FileCryptoService: Preparing buffer for $fileSize bytes');
    
    // Keep track of bytes written
    int bytesWritten = 0;
    
    // Decrypt each block and add to result
    final blocksDecryptStartTime = DateTime.now();
    for (int i = 0; i < encryptedBlocks.length; i++) {
      AppLogger.log('DEBUG: About to decrypt block $i, encryptedBlock.length=${encryptedBlocks[i]?.length}, type=${encryptedBlocks[i]?.runtimeType}');
      final decryptedBlock = await _decryptData(encryptedBlocks[i], symmetricKey);
      AppLogger.log('DEBUG: Decrypted block $i, decryptedBlock=${decryptedBlock?.runtimeType}, length=${decryptedBlock?.length}');
      if (decryptedBlock == null) {
        AppLogger.log('❌ Decrypted block $i is null!');
        AppLogger.log('  encryptedBlock.length: \\${encryptedBlocks[i]?.length}');
        AppLogger.log('  symmetricKey.length: \\${symmetricKey.length}');
        throw Exception('Decrypted block $i is null');
      }
      final int bytesToCopy = math.min(decryptedBlock.length, (result.length - bytesWritten).toInt());
      if (bytesToCopy <= 0) {
        AppLogger.log('❌ Invalid bytesToCopy: $bytesToCopy at block $i, decryptedBlock.length=${decryptedBlock.length}, result.length=${result.length}, bytesWritten=$bytesWritten');
        throw Exception('Invalid bytesToCopy: $bytesToCopy at block $i');
      }
      // Safely copy decrypted bytes into the destination buffer
      // Use setAll with a sublist to avoid issues with typed list views
      result.setAll(bytesWritten, decryptedBlock.sublist(0, bytesToCopy));
      bytesWritten += bytesToCopy;
      AppLogger.log('FileCryptoService: Block $i decrypted: ${decryptedBlock.length} bytes, total written: $bytesWritten');
    }
    
    final blocksDecryptTime = DateTime.now().difference(blocksDecryptStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: All blocks decryption took ${blocksDecryptTime}ms');
    
    AppLogger.log('FileCryptoService: File decryption complete: $bytesWritten bytes');
    
    // Debug: Show the first few bytes of decrypted data for small files
    if (result.length <= 100) {
      final preview = result.sublist(0, math.min(20, result.length));
      AppLogger.log('FileCryptoService: Small file decrypted preview (hex): ${preview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      
      // Try to decode as text
      try {
        final textContent = utf8.decode(result);
        AppLogger.log('FileCryptoService: Small file decrypted text: "$textContent"');
      } catch (e) {
        AppLogger.log('FileCryptoService: Cannot decode as UTF-8: $e');
        try {
          final charContent = String.fromCharCodes(result);
          AppLogger.log('FileCryptoService: Small file as char codes: "$charContent"');
        } catch (e2) {
          AppLogger.log('FileCryptoService: Cannot decode as characters either: $e2');
        }
      }
    }
    
    // Clear symmetric key from memory for security
    symmetricKey.fillRange(0, symmetricKey.length, 0);
    
    final totalFileDecryptTime = DateTime.now().difference(fileDecryptStartTime).inMilliseconds;
    AppLogger.log('⏱️ FileCryptoService: Total file decryption took ${totalFileDecryptTime}ms');
    
    return result;
  }

  static Future<String?> _fetchRekeyFromCentral({
    required String followerPubKey,
    required String followingPubKey,
    required String policyTag,
    required String mnemonic,
  }) async {
    try {
      // 1) Get PoP nonce
      final nonceResp = await http.get(Uri.parse('${AppConstants.apiBaseUrl}/policy/nonce?userPubKey=$followerPubKey'));
      if (nonceResp.statusCode != 200) return null;
      final nonce = (json.decode(nonceResp.body) as Map<String, dynamic>)['nonce'] as String?;
      if (nonce == null || nonce.isEmpty) return null;

      // 2) Sign nonce with follower's key
      final popSignature = await CryptoService.sign(nonce, mnemonic);

      // 3) Request rekey (mode=client)
      final method = 'POST';
      final pathForUrl = '/policy/fetch-rekey';
      final pathForSign = '/api/policy/fetch-rekey';
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final bodyJson = json.encode({
        'followerPubKey': followerPubKey,
        'followingPubKey': followingPubKey,
        'tag': policyTag,
        'mode': 'client',
        'proof': {
          'nonce': nonce,
          'signature': popSignature,
        }
      });
      final bodyBytes = utf8.encode(bodyJson);
      final bodyHashHex = sha256.convert(bodyBytes).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final sig = await CryptoService.sign('$method$pathForSign$ts$bodyHashHex', mnemonic);

      final resp = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}$pathForUrl'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': followerPubKey,
          'X-Timestamp': ts,
          'X-Signature': sig,
        },
        body: bodyJson,
      );
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      return data['rekey'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// AES-256-CBC encryption using webcrypto (matching server format)
  static Future<Uint8List> _encryptData(Uint8List data, Uint8List key) async {
    // Generate random IV
    final iv = Uint8List(16); // AES block size
    fillRandomBytes(iv);
    
    try {
      // Import the key for AES-CBC
      final aesKey = await AesCbcSecretKey.importRawKey(key);
      
      // Encrypt the data (CBC mode with PKCS7 padding)
      final encryptedData = await aesKey.encryptBytes(data, iv);
      
      // Prepend IV to encrypted data (standard format)
      final result = Uint8List.fromList([...iv, ...encryptedData]);
      AppLogger.log('FileCryptoService: Block encrypted: ${data.length} -> ${result.length} bytes');
      
      return result;
    } catch (e) {
      throw Exception('Block encryption failed');
    } finally {
      // Clear IV from memory (though it's not secret)
      iv.fillRange(0, iv.length, 0);
    }
  }

  /// AES-CBC decryption using webcrypto to match server format
  static Future<Uint8List> _decryptData(Uint8List encryptedData, Uint8List key) async {
    final decryptStartTime = DateTime.now();
    try {
      if (encryptedData == null) {
        AppLogger.log('❌ _decryptData: encryptedData is null!');
        throw Exception('_decryptData: encryptedData is null');
      }
      if (key == null) {
        AppLogger.log('❌ _decryptData: key is null!');
        throw Exception('_decryptData: key is null');
      }
      if (encryptedData.length < 16) {
        AppLogger.log('❌ _decryptData: encryptedData too short: \\${encryptedData.length}');
        AppLogger.log('  Hex: \\${encryptedData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        throw Exception('_decryptData: encryptedData too short');
      }
      // 🚀 CACHE: Re-enabled with validation
      final cachedBlock = _CacheManager.getCachedDecryptedBlock(encryptedData, key);
      if (cachedBlock != null) {
        final totalTime = DateTime.now().difference(decryptStartTime).inMilliseconds;
        AppLogger.log('⏱️ FileCryptoService: Block cache HIT took ${totalTime}ms');
        
        // 🔧 VERIFY CACHED BLOCK: Basic validation
        if (cachedBlock.isEmpty) {
          AppLogger.log('❌ CRITICAL: Cached block is empty! Removing corrupted cache entry.');
          final cacheKey = _CacheManager._generateBlockCacheKey(encryptedData, key);
          _CacheManager._removeDecryptedBlockCache(cacheKey);
        } else {
          return cachedBlock;
        }
      }
      
      // Extract IV from the beginning (C# server format: [IV][EncryptedData])
      final iv = encryptedData.sublist(0, 16);
      final cipherText = encryptedData.sublist(16);
      AppLogger.log('🔍 DEBUG: Cipher text length: ${cipherText.length}');
      
      // Validate key size
      if (key.length != 16 && key.length != 32) {
        throw Exception('Invalid key format: expected 16 or 32 bytes, got ${key.length}');
      }
      
      try {
        // 🔧 FIX: Use AES-CBC with proper PKCS7 padding to match C# server format
        final keyImportStartTime = DateTime.now();
        final aesCbcKey = await AesCbcSecretKey.importRawKey(key);
        final keyImportTime = DateTime.now().difference(keyImportStartTime).inMilliseconds;
        
        final actualDecryptStartTime = DateTime.now();
        
        // 🔧 CRITICAL FIX: Use decryptBytes directly with IV and cipherText
        final decryptedData = await aesCbcKey.decryptBytes(cipherText, iv);
        
        final actualDecryptTime = DateTime.now().difference(actualDecryptStartTime).inMilliseconds;
        final totalDecryptTime = DateTime.now().difference(decryptStartTime).inMilliseconds;
        
        AppLogger.log('⏱️ FileCryptoService: AES-CBC block decrypt: keyImport=${keyImportTime}ms, decrypt=${actualDecryptTime}ms, total=${totalDecryptTime}ms');
        AppLogger.log('FileCryptoService: Block decrypted: ${encryptedData.length} -> ${decryptedData.length} bytes');
        
        // 🐛 DEBUG: Check decrypted data format
        if (decryptedData.length <= 50) {
          final hexPreview = decryptedData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          AppLogger.log('🔍 DEBUG: AES-CBC decrypted data hex: $hexPreview');
          
          // Try to decode as UTF-8 if small enough
          try {
            final textPreview = utf8.decode(decryptedData);
            AppLogger.log('🔍 DEBUG: AES-CBC decrypted data as text: "$textPreview"');
          } catch (e) {
            AppLogger.log('🔍 DEBUG: AES-CBC decrypted data not UTF-8: $e');
          }
        } else {
          final preview = decryptedData.sublist(0, 20);
          final hexPreview = preview.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          AppLogger.log('🔍 DEBUG: AES-CBC decrypted data hex (first 20 bytes): $hexPreview...');
          
          // Try to decode first part as UTF-8
          try {
            final textPreview = utf8.decode(preview);
            AppLogger.log('🔍 DEBUG: AES-CBC decrypted data preview as text: "$textPreview"...');
          } catch (e) {
            AppLogger.log('🔍 DEBUG: AES-CBC decrypted data not UTF-8: $e');
          }
        }
        
        // 🚀 CACHE: Cache with validation
        if (decryptedData.isNotEmpty) {
          _CacheManager.cacheDecryptedBlock(encryptedData, key, decryptedData);
        } else {
          AppLogger.log('❌ WARNING: Not caching empty decrypted block');
        }
        
        return decryptedData;
        
      } catch (cbcError) {
        AppLogger.log('❌ DEBUG: AES-CBC failed: $cbcError');
        
        // 🔧 DEBUG: Try to understand why CBC failed
        AppLogger.log('🔍 DEBUG: Cipher text first 32 bytes: ${cipherText.length >= 32 ? cipherText.sublist(0, 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ') : 'N/A'}');
        AppLogger.log('🔍 DEBUG: Key hex: ${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        AppLogger.log('🔍 DEBUG: IV hex: ${iv.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        
        // 🚨 NO MORE CTR FALLBACK - We need proper CBC to work
        throw Exception('AES-CBC decryption failed: $cbcError. This indicates a format mismatch with server encryption.');
      }
    } catch (e, stack) {
      AppLogger.log('❌ _decryptData error: $e');
      AppLogger.log('Stack trace: $stack');
      rethrow;
    }
  }

  /// Generate a unique ID for a file
  static String _generateUniqueId() {
    final random = math.Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Calculate Merkle root hash from a list of content IDs
  static String _calculateMerkleRoot(List<String> contentIds) {
    if (contentIds.isEmpty) {
      return '';
    }
    
    if (contentIds.length == 1) {
      return contentIds[0];
    }
    
    final List<String> nextLevel = [];
    
    for (int i = 0; i < contentIds.length; i += 2) {
      if (i + 1 < contentIds.length) {
        // Hash pair of nodes
        final combined = contentIds[i] + contentIds[i + 1];
        final hash = sha256.convert(utf8.encode(combined)).toString();
        nextLevel.add(hash);
      } else {
        // Odd node, promote to next level
        nextLevel.add(contentIds[i]);
      }
    }
    
    // Recursively calculate the root
    return _calculateMerkleRoot(nextLevel);
  }

  /// Helper to determine MIME type from file name
  static String _getMimeType(String fileName) {
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
      default:
        return 'application/octet-stream';
    }
  }
  
  /// Helper to extract file extension
  static String _getFileExtension(String fileName) {
    return fileName.contains('.')
        ? fileName.split('.').last
        : '';
  }

  // PUBLIC TEST METHODS FOR DEBUGGING
  static Future<Uint8List> testEncryptData(Uint8List data, Uint8List key) => _encryptData(data, key);
  static Future<Uint8List> testDecryptData(Uint8List encryptedData, Uint8List key) => _decryptData(encryptedData, key);
  
  // PUBLIC ENCRYPTION METHODS FOR EXTERNAL USE
  static Future<Uint8List> encryptSymmetricKeyWithPublicKey(Uint8List symmetricKey, String publicKeyHex) => 
      _encryptSymmetricKeyWithPublicKey(symmetricKey, publicKeyHex);
  
  static Future<Uint8List> decryptSymmetricKeyWithPrivateKey(Uint8List encryptedData, String mnemonic) => 
      _decryptSymmetricKeyWithPrivateKey(encryptedData, mnemonic);

  /// Encrypt symmetric key with public key using proper ECIES (secure method)
  static Future<Uint8List> _encryptSymmetricKeyWithPublicKey(Uint8List symmetricKey, String publicKeyHex) async {
    try {
      // 🔧 RE-ENABLED: ECIES needed for file sharing to work
      final compressedPublicKeyHex = CryptoService.convertToCompressedPublicKey(publicKeyHex);
      AppLogger.log('FileCryptoService: Converted public key format: \\${publicKeyHex.length} -> \\${compressedPublicKeyHex.length} chars');
      // Use secure ECIES implementation with compressed key
      final encryptedData = await EciesService.encryptWithPublicKey(
        data: symmetricKey,
        publicKeyHex: compressedPublicKeyHex,
      );
      AppLogger.log('FileCryptoService: ECIES encryption successful: \\${encryptedData.length} bytes');
      return encryptedData;
    } catch (e) {
      AppLogger.log('FileCryptoService: ECIES failed: $e');
      throw Exception('ECIES encryption failed: $e');
    }
  }

  /// Decrypt symmetric key with private key using proper ECIES (secure method)
  static Future<Uint8List> _decryptSymmetricKeyWithPrivateKey(Uint8List encryptedData, String mnemonic) async {
    // Check cache first
    final cached = _CacheManager.getCachedSymmetricKey(encryptedData, mnemonic);
    if (cached != null) {
      AppLogger.log('✅ CACHE HIT: Using cached symmetric key');
      return cached;
    }
    
    // Use optimized ECIES
    final result = await _decryptEciesOptimized(encryptedData, mnemonic);
    
    // Cache the result
    _CacheManager.cacheSymmetricKey(encryptedData, mnemonic, result);
    
    return result;
  }

  /// 🚀 OPTIMIZED: ECIES decryption with isolate support for better performance
  static Future<Uint8List> _decryptEciesOptimized(Uint8List encryptedData, String mnemonic) async {
    final startTime = DateTime.now();
    
    try {
      // For small data, use current thread to avoid isolate overhead
      if (encryptedData.length < 100) {
        final result = await EciesService.decryptWithPrivateKey(
          encryptedData: encryptedData,
          mnemonic: mnemonic,
        );
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        AppLogger.log('⚡ ECIES FAST: ${encryptedData.length} bytes decrypted in ${duration}ms (current thread)');
        return result;
      }
      
      // For larger data, use isolate for better performance
      try {
        final result = await compute(_eciesDecryptInIsolate, {
          'encryptedData': encryptedData,
          'mnemonic': mnemonic,
        });
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        AppLogger.log('⚡ ECIES ISOLATE: ${encryptedData.length} bytes decrypted in ${duration}ms (isolate)');
        return result;
      } catch (isolateError) {
        AppLogger.log('⚠️ ECIES: Isolate failed (${isolateError}), falling back to current thread');
        // Fallback to current thread if isolate fails
        final result = await EciesService.decryptWithPrivateKey(
          encryptedData: encryptedData,
          mnemonic: mnemonic,
        );
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        AppLogger.log('⚡ ECIES FALLBACK: ${encryptedData.length} bytes decrypted in ${duration}ms (current thread)');
        return result;
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      AppLogger.log('❌ ECIES ERROR: Failed after ${duration}ms - $e');
      rethrow;
    }
  }
  
  /// Isolate function for ECIES decryption
  static Future<Uint8List> _eciesDecryptInIsolate(Map<String, dynamic> params) async {
    final encryptedData = params['encryptedData'] as Uint8List;
    final mnemonic = params['mnemonic'] as String;
    return await EciesService.decryptWithPrivateKey(
      encryptedData: encryptedData,
      mnemonic: mnemonic,
    );
  }

  // 🚀 CACHE MANAGEMENT: Public methods for cache management
  
  /// Clear all caches (call when user logs out or for security)
  static void clearCache() {
    _CacheManager.clearAllCaches();
  }
  
  /// Clear expired cache entries (call periodically)
  static void clearExpiredCache() {
    _CacheManager.clearExpiredCaches();
  }
  
  /// Get cache statistics
  static Map<String, dynamic> getCacheStats() {
    return _CacheManager.getCacheStats();
  }
  
  /// Auto-clear expired cache entries (called internally)
  static void _autoMaintainCache() {
    // 🔧 DISABLED: Don't randomly clear cache during normal operations
    // This was causing cache to be cleared even when valid, breaking performance
    return; // Early return - no auto maintenance
    
    // Clear expired entries every 100 cache operations (approximate)
    if (math.Random().nextInt(100) == 0) {
      _CacheManager.clearExpiredCaches();
    }
  }

  /// 🚀 TEST: Performance comparison between serial and parallel processing
  static Future<void> testParallelPerformance(
    List<Map<String, dynamic>> fileRequests,
    String mnemonic, {
    Function(String)? onProgress,
  }) async {
    if (fileRequests.isEmpty) return;
    
    AppLogger.log('🧪 PERFORMANCE TEST: Starting comparison between serial vs parallel processing...');
    AppLogger.log('📊 Testing with ${fileRequests.length} files');
    
    // Test serial processing
    final serialStartTime = DateTime.now();
    AppLogger.log('⏱️ SERIAL TEST: Starting sequential processing...');
    
    for (int i = 0; i < fileRequests.length; i++) {
      final request = fileRequests[i];
      final fileId = request['fileId'] ?? 'unknown';
      onProgress?.call('Serial processing file ${i + 1}/${fileRequests.length}: $fileId');
      
      try {
        final startTime = DateTime.now();
        await _decryptSingleFileWithTiming(request, mnemonic, 'Serial File ${i + 1}');
        final endTime = DateTime.now().difference(startTime).inMilliseconds;
        AppLogger.log('✅ Serial file ${i + 1} processed in ${endTime}ms');
      } catch (e) {
        AppLogger.log('❌ Serial file ${i + 1} failed: $e');
      }
    }
    
    final serialTotalTime = DateTime.now().difference(serialStartTime).inMilliseconds;
    AppLogger.log('⏱️ SERIAL TOTAL: ${serialTotalTime}ms (${(serialTotalTime / 1000).toStringAsFixed(1)}s)');
    
    // Clear cache between tests
    _CacheManager.clearAllCaches();
    await Future.delayed(Duration(milliseconds: 500));
    
    // Test parallel processing
    final parallelStartTime = DateTime.now();
    AppLogger.log('⏱️ PARALLEL TEST: Starting concurrent processing...');
    onProgress?.call('Starting parallel processing test...');
    
    try {
      final parallelResults = await decryptFilesParallel(
        fileRequests,
        mnemonic,
        maxConcurrency: 3,
        onProgress: onProgress,
      );
      
      final parallelTotalTime = DateTime.now().difference(parallelStartTime).inMilliseconds;
      AppLogger.log('⏱️ PARALLEL TOTAL: ${parallelTotalTime}ms (${(parallelTotalTime / 1000).toStringAsFixed(1)}s)');
      
      // Calculate improvement
      final improvement = ((serialTotalTime - parallelTotalTime) / serialTotalTime * 100);
      AppLogger.log('🚀 PERFORMANCE IMPROVEMENT: ${improvement.toStringAsFixed(1)}% faster');
      AppLogger.log('📈 Time saved: ${((serialTotalTime - parallelTotalTime) / 1000).toStringAsFixed(1)}s');
      
      final successCount = parallelResults.where((r) => r['success'] == true).length;
      AppLogger.log('✅ Parallel success rate: $successCount/${fileRequests.length} (${(successCount / fileRequests.length * 100).toStringAsFixed(1)}%)');
      
    } catch (e) {
      final parallelTotalTime = DateTime.now().difference(parallelStartTime).inMilliseconds;
      AppLogger.log('❌ PARALLEL TEST FAILED after ${parallelTotalTime}ms: $e');
    }
  }

  /// 🚀 IMPROVED: Process multiple files in parallel with enhanced batching
  static Future<List<Map<String, dynamic>>> decryptFilesParallel(
    List<Map<String, dynamic>> fileRequests,
    String mnemonic, {
    int maxConcurrency = 3, // Reduced for stability
    Function(String)? onProgress,
  }) async {
    if (fileRequests.isEmpty) return [];
    
    AppLogger.log('🚀 PARALLEL: Starting concurrent decryption of ${fileRequests.length} posts...');
    
    final results = <Map<String, dynamic>>[];
    int batchNumber = 1;
    
    // Process in batches to avoid overwhelming the system
    for (int i = 0; i < fileRequests.length; i += maxConcurrency) {
      final batchEnd = math.min(i + maxConcurrency, fileRequests.length);
      final batch = fileRequests.sublist(i, batchEnd);
      
      final batchStartTime = DateTime.now();
      AppLogger.log('⏱️ TIMING: Starting Parallel Batch $batchNumber...');
      onProgress?.call('Processing batch $batchNumber (${batch.length} posts)...');
      
      // Process this batch in parallel with proper error handling
      final batchFutures = batch.asMap().entries.map((entry) {
        final index = entry.key;
        final request = entry.value;
        return _decryptSingleFileWithTiming(request, mnemonic, 'Batch $batchNumber Post ${index + 1}');
      }).toList();
      
      try {
        final batchResults = await Future.wait(batchFutures);
        
        final batchTime = DateTime.now().difference(batchStartTime).inMilliseconds;
        AppLogger.log('⏱️ TIMING: Parallel Batch $batchNumber took ${batchTime}ms');
        
        results.addAll(batchResults);
        
        // Log batch success rate
        final successCount = batchResults.where((r) => r['success'] == true).length;
        AppLogger.log('✅ Batch $batchNumber: $successCount/${batch.length} successful');
        
      } catch (e) {
        final batchTime = DateTime.now().difference(batchStartTime).inMilliseconds;
        AppLogger.log('❌ Batch $batchNumber failed after ${batchTime}ms: $e');
        
        // Add error results for failed batch
        for (final request in batch) {
          results.add({
            'success': false,
            'fileId': request['fileId'] ?? 'unknown',
            'error': 'Batch processing failed: $e',
            'timing': batchTime,
          });
        }
      }
      
      batchNumber++;
      
      // Small delay between batches to prevent resource exhaustion
      if (batchNumber <= (fileRequests.length / maxConcurrency).ceil()) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
    
    return results;
  }

  /// Helper to decrypt a single file with timing
  static Future<Map<String, dynamic>> _decryptSingleFileWithTiming(
    Map<String, dynamic> request,
    String mnemonic,
    String label,
  ) async {
    final startTime = DateTime.now();
    final fileId = request['fileId'] ?? 'unknown';
    AppLogger.log('⏱️ TIMING: Starting Decrypt $label...');
    
    try {
      // Extract required parameters from request
      final fileMetadata = request['fileMetadata'] as Map<String, dynamic>;
      final encryptedBlocks = request['encryptedBlocks'] as List<Uint8List>;
      final userPublicKey = request['userPublicKey'] as String;
      
      final result = await decryptFile(
        fileMetadata: fileMetadata,
        encryptedBlocks: encryptedBlocks,
        userPublicKey: userPublicKey,
        mnemonic: mnemonic,
        onProgress: null, // Skip individual progress for parallel processing
      );
      
      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      AppLogger.log('⏱️ TIMING: Decrypt $label took ${totalTime}ms');
      
      return {
        'success': true,
        'fileId': fileId,
        'decryptedContent': result,
        'timing': totalTime,
      };
    } catch (e) {
      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      AppLogger.log('❌ ERROR: Decrypt $label failed after ${totalTime}ms: $e');
      return {
        'success': false,
        'fileId': fileId,
        'error': e.toString(),
        'timing': totalTime,
      };
    }
  }

  // 🔧 DEBUGGING: Temporarily disable cache for testing
  static bool _cacheDisabled = false;
  
  static void disableCache() {
    _cacheDisabled = true;
    _CacheManager.clearAllCaches();
    AppLogger.log('🔧 DEBUG: Cache disabled for testing');
  }
  
  static void enableCache() {
    _cacheDisabled = false;
    AppLogger.log('🔧 DEBUG: Cache re-enabled');
  }
  
  static bool get isCacheDisabled => _CacheManager._cacheDisabled;
  
  // 🚀 OPTIMIZATION: Pre-warm cache with common operations
  static Future<void> warmUpCache(String mnemonic) async {
    AppLogger.log('🔥 CACHE WARMUP: Starting performance optimizations...');
    final startTime = DateTime.now();
    
    try {
      // Pre-compute common operations that are expensive
      // This helps reduce first-time operation costs
      
      // Nothing specific to pre-compute for now, but we can add:
      // - Pre-generate key derivation
      // - Pre-load common symmetric keys
      // - Pre-initialize crypto libraries
      
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      AppLogger.log('🔥 CACHE WARMUP: Completed in ${duration}ms');
    } catch (e) {
      AppLogger.log('⚠️ CACHE WARMUP: Failed - $e');
    }
  }
  
  // 🧪 TEST: Cache behavior verification
  static void testCacheBehavior() {
    AppLogger.log('🧪 CACHE TEST: Starting cache behavior verification...');
    
    // Test symmetric key caching
    final testEncKey = Uint8List.fromList(List.generate(32, (i) => i));
    final testMnemonic = 'test mnemonic phrase';
    final testSymKey = Uint8List.fromList(List.generate(32, (i) => i + 100));
    
    AppLogger.log('🧪 Testing symmetric key cache...');
    _CacheManager.cacheSymmetricKey(testEncKey, testMnemonic, testSymKey);
    final retrievedKey = _CacheManager.getCachedSymmetricKey(testEncKey, testMnemonic);
    
    if (retrievedKey != null) {
      final match = retrievedKey.length == testSymKey.length && 
                   retrievedKey.every((b) => testSymKey.contains(b));
      AppLogger.log('✅ CACHE TEST: Symmetric key ${match ? "PASSED" : "FAILED"}');
    } else {
      AppLogger.log('❌ CACHE TEST: Symmetric key FAILED - no cached data retrieved');
    }
    
    // Test block caching
    final testBlock = Uint8List.fromList(List.generate(100, (i) => i % 256));
    final testDecrypted = Uint8List.fromList(List.generate(90, (i) => (i * 2) % 256));
    
    AppLogger.log('🧪 Testing block cache...');
    _CacheManager.cacheDecryptedBlock(testBlock, testSymKey, testDecrypted);
    final retrievedBlock = _CacheManager.getCachedDecryptedBlock(testBlock, testSymKey);
    
    if (retrievedBlock != null) {
      final match = retrievedBlock.length == testDecrypted.length;
      AppLogger.log('✅ CACHE TEST: Block cache ${match ? "PASSED" : "FAILED"}');
    } else {
      AppLogger.log('❌ CACHE TEST: Block cache FAILED - no cached data retrieved');
    }
    
    // Print cache stats
    final stats = _CacheManager.getCacheStats();
    AppLogger.log('📊 CACHE STATS: $stats');
    
    AppLogger.log('🧪 CACHE TEST: Verification completed');
  }
  
  // 🚀 PUBLIC API: Optimization methods for external use
  static void clearAllCaches() => _CacheManager.clearAllCaches();
  static void clearExpiredCaches() => _CacheManager.clearExpiredCaches();
  static Map<String, dynamic> getCacheStatistics() => _CacheManager.getCacheStats();
  
  /// 🚀 PUBLIC: Parallel symmetric key decryption for external callers
  static Future<List<Uint8List>> decryptMultipleSymmetricKeysParallel(
    List<Uint8List> encryptedKeys,
    String mnemonic, {
    int maxConcurrency = 3,
  }) async {
    if (encryptedKeys.isEmpty) return [];
    
    AppLogger.log('🚀 PUBLIC PARALLEL: Starting ${encryptedKeys.length} symmetric key decryptions with concurrency=$maxConcurrency');
    
    final results = <Uint8List>[];
    final batches = <List<Uint8List>>[];
    
    // Split into batches
    for (int i = 0; i < encryptedKeys.length; i += maxConcurrency) {
      final end = math.min(i + maxConcurrency, encryptedKeys.length);
      batches.add(encryptedKeys.sublist(i, end));
    }
    
    for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      final batch = batches[batchIndex];
      final batchStartTime = DateTime.now();
      
      AppLogger.log('🚀 PUBLIC PARALLEL: Processing batch ${batchIndex + 1}/${batches.length} with ${batch.length} keys');
      
      // Process batch in parallel
      final futures = batch.map((encryptedKey) async {
        try {
          // Check cache first
          final cached = _CacheManager.getCachedSymmetricKey(encryptedKey, mnemonic);
          if (cached != null) {
            AppLogger.log('✅ CACHE HIT: Symmetric key found in cache');
            return cached;
          }
          
          // Decrypt with optimized ECIES
          final startTime = DateTime.now();
          final decrypted = await _decryptEciesOptimized(encryptedKey, mnemonic);
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          
          AppLogger.log('🔓 ECIES: Decrypted symmetric key in ${elapsed}ms');
          
          // Cache the result
          _CacheManager.cacheSymmetricKey(encryptedKey, mnemonic, decrypted);
          
          return decrypted;
        } catch (e) {
          AppLogger.log('❌ Failed to decrypt symmetric key: $e');
          rethrow;
        }
      }).toList();
      
      // Wait for batch completion
      final batchResults = await Future.wait(futures);
      results.addAll(batchResults);
      
      final batchElapsed = DateTime.now().difference(batchStartTime).inMilliseconds;
      AppLogger.log('✅ PUBLIC PARALLEL: Batch ${batchIndex + 1} completed in ${batchElapsed}ms');
    }
    
    AppLogger.log('🎯 PUBLIC PARALLEL: Completed ${results.length}/${encryptedKeys.length} symmetric key decryptions');
    return results;
  }

  /// 🚀 PERFORMANCE: Check cache status for My Posts screen
  static void checkCacheStatus() {
    AppLogger.log('🔥 CACHE CHECK: Verifying cache status for My Posts...');
    final stats = _CacheManager.getCacheStats();
    AppLogger.log('📊 CACHE STATUS: ${stats['symmetricKeys']} symmetric keys, ${stats['blocks']} blocks cached');
    
    // Don't clear - just report status
    if (stats['symmetricKeys'] > 0) {
      AppLogger.log('✅ CACHE READY: Symmetric keys available for fast decryption');
    } else {
      AppLogger.log('⚠️ CACHE EMPTY: First load will be slower');
    }
  }

  /// 🆕 Create a public file (no encryption) for public posts
  /// This stores the file content in plain text blocks for public access
  static Future<Map<String, dynamic>> createPublicFile({
    required Uint8List fileData,
    required String fileName,
    required String ownerPublicKey,
    List<String>? sharedWithPublicKeys, // 🆕 Added support for sharing
    int blockSize = DEFAULT_BLOCK_SIZE,
    Function(String)? onProgress, // Progress callback
    String? fileType, // 'post', 'image', 'document', etc.
    List<Map<String, dynamic>>? relatedFiles, // For posts: attached media
    String encryptedType = 'public',
    String shareType = 'me',
    // 🆕 Storage contract ID
    String? contractId,
  }) async {
    AppLogger.log('FileCryptoService: Creating public file: $fileName (${fileData.length} bytes) - NO ENCRYPTION');
    
    // 🆕 Handle shared users
    final List<String> allRecipients = [ownerPublicKey];
    if (sharedWithPublicKeys != null && sharedWithPublicKeys.isNotEmpty) {
      // Add shared users (remove duplicates)
      for (final sharedKey in sharedWithPublicKeys) {
        if (!allRecipients.contains(sharedKey)) {
          allRecipients.add(sharedKey);
        }
      }
      AppLogger.log('FileCryptoService: Public file will be shared with ${allRecipients.length} users (owner + ${sharedWithPublicKeys.length} shared)');
    } else {
      AppLogger.log('FileCryptoService: Public file for owner only');
    }
    
    onProgress?.call('Creating public file structure...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    // Calculate number of content blocks needed (file data only)
    final contentBlockCount = (fileData.length / blockSize).ceil();
    AppLogger.log('FileCryptoService: Public file will be split into $contentBlockCount content blocks of $blockSize bytes');
    
    // 🆕 Generate unique fileIds for each recipient (zero-knowledge sharing)
    final List<String> fileIds = [];
    for (int i = 0; i < allRecipients.length; i++) {
      fileIds.add(_generateUniqueId());
    }
    final ownerFileId = fileIds[0]; // Owner always gets first fileId
    
    // Generate content block IDs (plain text blocks) - shared among all users
    final List<String> contentBlockIds = [];
    final List<String> contentBlockContentIds = [];
    
    for (int i = 0; i < contentBlockCount; i++) {
      contentBlockIds.add(_generateUniqueId());
    }
    
    onProgress?.call('Processing content blocks for public access...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    // Calculate content block hashes for metadata
    for (int blockIndex = 0; blockIndex < contentBlockCount; blockIndex++) {
      final int start = blockIndex * blockSize;
      final int end = math.min(start + blockSize, fileData.length);
      final Uint8List blockData = fileData.sublist(start, end);
      
      final blockHash = sha256.convert(blockData).bytes;
      final contentId = base64Encode(blockHash);
      contentBlockContentIds.add(contentId);
    }
    
    // 🆕 Create metadata blocks for each recipient (zero-knowledge sharing)
    onProgress?.call('Creating public metadata blocks for all recipients...');
    final List<Map<String, dynamic>> allBlocks = [];
    final List<Map<String, dynamic>> metadataEntries = [];
    
    for (int recipientIndex = 0; recipientIndex < allRecipients.length; recipientIndex++) {
      final recipientPublicKey = allRecipients[recipientIndex];
      final recipientFileId = fileIds[recipientIndex];
      final isOwner = recipientIndex == 0;
      
      AppLogger.log('FileCryptoService: Creating public metadata for recipient ${recipientIndex + 1}/${allRecipients.length}: ${recipientPublicKey.substring(0, 10)}... (fileId: $recipientFileId)');
      
      // 🔓 PUBLIC METADATA: Create metadata block with file information (PLAIN TEXT)
      final metadataBlockContent = {
        'fileName': fileName,
        'fileSize': fileData.length,
        'mimeType': _getMimeType(fileName),
        'fileExtension': _getFileExtension(fileName),
        'contentBlockCount': contentBlockCount,
        'contentBlockIds': contentBlockIds, // Same content blocks for all recipients
        'contentBlockContentIds': contentBlockContentIds,
        'contentMerkleRoot': _calculateMerkleRoot(contentBlockContentIds),
        'version': '1.0',
        'creationTime': DateTime.now().toIso8601String(),
        'isPublic': true, // 🆕 Mark as public file
        if (fileType != null) 'type': fileType,
        if (relatedFiles != null) 'relatedFiles': relatedFiles,
        'ownerPubKey': ownerPublicKey, // Always reference the original owner
        'recipientPubKey': recipientPublicKey, // Current recipient
        'isShared': !isOwner, // Mark if this is a shared copy
      };
      
      // Convert metadata to JSON and bytes (NO ENCRYPTION)
      final metadataJson = json.encode(metadataBlockContent);
      final metadataBytes = Uint8List.fromList(utf8.encode(metadataJson));
      final metadataBlockId = _generateUniqueId(); // Unique metadata block for each recipient
      
      AppLogger.log('FileCryptoService: Public metadata block for ${recipientPublicKey.substring(0, 10)}...: ${metadataBytes.length} bytes (PLAIN TEXT)');
      
      // Calculate metadata block hash
      final metadataBlockHash = sha256.convert(metadataBytes).bytes;
      final metadataContentId = base64Encode(metadataBlockHash);
      
      // Add metadata block for this recipient (index 0) - PLAIN TEXT
      allBlocks.add({
        'blockId': metadataBlockId,
        'blockIndex': 0,
        'totalBlocks': 1 + contentBlockCount,
        'size': metadataBytes.length,
        'encryptedSize': metadataBytes.length, // Same size for plain text
        'encryptedContent': metadataBytes, // 🔓 Store as plain text
        'contentId': metadataContentId,
        'isMetadataBlock': true,
        'isPublic': true, // 🆕 Mark block as public
        'recipientFileId': recipientFileId, // Link to specific recipient's fileId
      });
      
      // Create metadata entry for this recipient
      metadataEntries.add({
        'fileId': recipientFileId, // Unique fileId for each recipient
        'firstBlockId': metadataBlockId, // Unique metadata block for each recipient
        'recipientPubKey': recipientPublicKey,
        'ownerPubKey': ownerPublicKey, // 🆕 FIX: Add ownerPubKey for backend lookup
        'creationTime': DateTime.now().toIso8601String(),
        'encryptedKey': '', // 🔓 No encryption key needed for public files
        'isPublic': true, // 🆕 Mark as public file
        if (contractId != null && contractId.isNotEmpty) 'contractId': contractId,
        if (fileType != null) 'type': fileType,
        'encryptedType': encryptedType,
        'shareType': shareType,
      });
    }
    
    // Create content blocks (PLAIN TEXT) - shared among all users
    onProgress?.call('Creating public content blocks...');
    for (int contentBlockIndex = 0; contentBlockIndex < contentBlockCount; contentBlockIndex++) {
      final int start = contentBlockIndex * blockSize;
      final int end = math.min(start + blockSize, fileData.length);
      final Uint8List blockData = fileData.sublist(start, end);
      final blockId = contentBlockIds[contentBlockIndex];
      final contentId = contentBlockContentIds[contentBlockIndex];
      
      allBlocks.add({
        'blockId': blockId,
        'blockIndex': contentBlockIndex + 1, // 1-based
        'totalBlocks': 1 + contentBlockCount,
        'size': blockData.length,
        'encryptedSize': blockData.length, // Same size for plain text
        'encryptedContent': blockData, // 🔓 Store as plain text
        'contentId': contentId,
        'isMetadataBlock': false,
        'isPublic': true, // 🆕 Mark block as public
        'sharedContent': true, // Content blocks are shared among all recipients
      });
      
      final progressPercent = ((contentBlockIndex + 1) / contentBlockCount * 100).round();
      onProgress?.call('Creating public content block ${contentBlockIndex + 1}/$contentBlockCount ($progressPercent%)...');
    }
    
    AppLogger.log('FileCryptoService: Public file creation complete. Created ${allBlocks.length} blocks (${metadataEntries.length} metadata + $contentBlockCount content) - NO ENCRYPTION');
    AppLogger.log('FileCryptoService: Public file shared with ${allRecipients.length} users');
    
    return {
      'metadataEntries': metadataEntries, // 🆕 Multiple entries for sharing
      'blocks': allBlocks,
      'fileId': ownerFileId, // Return owner's fileId as primary
    };
  }

  /// 🆕 Load public file content (no decryption needed)
  /// This is used for public posts that are stored in plain text
  static Future<Map<String, dynamic>> loadPublicFile({
    required Uint8List metadataBlock,
    required List<Uint8List> contentBlocks,
    Function(String)? onProgress,
  }) async {
    AppLogger.log('FileCryptoService: Loading public file content (no decryption)...');
    onProgress?.call('Reading public file metadata...');
    await Future.delayed(Duration(milliseconds: 10)); // Yield control
    
    // Parse metadata block as plain text JSON
    String metadataString;
    try {
      metadataString = utf8.decode(metadataBlock);
    } catch (e) {
      throw Exception('Failed to decode public metadata: $e');
    }
    
    final metadataContent = json.decode(metadataString) as Map<String, dynamic>;
    AppLogger.log('FileCryptoService: Public metadata loaded: ${metadataContent.keys.toList()}');
    
    // Reassemble content blocks (plain text)
    onProgress?.call('Assembling public file content...');
    final fileSize = metadataContent['fileSize'] as int;
    final result = Uint8List(fileSize);
    
    int currentPosition = 0;
    for (int i = 0; i < contentBlocks.length; i++) {
      final block = contentBlocks[i];
      final bytesToCopy = math.min(block.length, fileSize - currentPosition);
      
      result.setRange(currentPosition, currentPosition + bytesToCopy, block);
      currentPosition += bytesToCopy;
      
      final progressPercent = ((i + 1) / contentBlocks.length * 100).round();
      onProgress?.call('Assembling content block ${i + 1}/${contentBlocks.length} ($progressPercent%)...');
    }
    
    AppLogger.log('FileCryptoService: Public file loaded successfully: ${result.length} bytes');
    
    // Return both metadata and content
    return {
      'metadata': metadataContent,
      'content': result,
      'isPublic': true,
    };
  }
}

// Thêm class phụ trợ cho task block
class _BlockEncryptTask {
  final int blockIndex;
  final String blockId;
  final String contentId;
  final Uint8List blockData;
  final Uint8List symmetricKey;
  final int totalBlocks;
  _BlockEncryptTask({
    required this.blockIndex,
    required this.blockId,
    required this.contentId,
    required this.blockData,
    required this.symmetricKey,
    required this.totalBlocks,
  });
} 
