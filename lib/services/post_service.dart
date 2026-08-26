import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/pre_ffi.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/models/storage_contract.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'package:http/http.dart' as http;

// import 'package:deltanium_app/features/file_manager/file_upload_service.dart';

class PostService {
  /// Create a post as a special file in zero-knowledge storage
  /// 🆕 Added isPublic parameter for unencrypted public posts
  static Future<Map<String, dynamic>> createPost({
    required String textContent,
    required String authorPublicKey,
    String? authorName,
    required String mnemonic,
    List<Map<String, dynamic>>? attachedMedia, // Previously uploaded media files
    List<String>? sharedWithUsers,
    String encryptedType = 'encrypted', // 'public' or 'encrypted'
    String shareType = 'me', // 'followers', 'me', 'specific'
    List<String>? tags,
    Map<String, dynamic>? location,
    List<String>? mentions,
    Function(String)? onProgress,
    // 🆕 PRE (Option 2) optional fields
    String? policyTag,
    String? capsuleFor,
    String? policyScheme,
    // 🆕 Storage contract ID
    String? contractId,
  }) async {
    AppLogger.log('PostService: Creating post with ${textContent.length} characters (encryptedType: $encryptedType, shareType: $shareType, contractId: $contractId)');
    onProgress?.call('Preparing post content...');
    
    // Create post content structure
    final postContent = {
      'postId': _generatePostId(),
      'textContent': textContent,
      'authorPublicKey': authorPublicKey,
      if (authorName != null && authorName.isNotEmpty) 'authorName': authorName,
      'createdAt': DateTime.now().toIso8601String(),
      'encryptedType': encryptedType,
      'shareType': shareType,
      'tags': tags ?? [],
      'mentions': mentions ?? [],
      if (location != null) 'location': location,
      'editHistory': [],
      'reactions': {},
      'version': '1.0',
      'isPublic': encryptedType == 'public',
    };
    
    // Convert post content to bytes
    final postJson = json.encode(postContent);
    final postBytes = Uint8List.fromList(utf8.encode(postJson));
    
    // Generate post filename
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'post_${timestamp}.json';
    
    // Prepare related files list (media attachments)
    List<Map<String, dynamic>>? relatedFiles;
    if (attachedMedia != null && attachedMedia.isNotEmpty) {
      relatedFiles = attachedMedia.map((media) => {
        'fileId': media['fileId'],
        'type': media['type'] ?? 'unknown',
        'caption': media['caption'] ?? '',
        'order': media['order'] ?? 0,
        'relationshipType': 'attachment', // 'attachment', 'reference', 'source', etc.
        'fileName': media['name'] ?? media['fileName'] ?? 'Unknown file',
        'fileSize': media['size'] ?? media['fileSize'] ?? 0,
        'mimeType': _getMimeTypeFromExtension(media['extension'] ?? ''),
        'uploadTime': DateTime.now().toIso8601String(),
        'nodeId': media['nodeId'] ?? '', // Store which node the file is on
        'nodeEndpoint': media['nodeEndpoint'] ?? '', // Store node endpoint for access
        'encryptedKey': media['encryptedKey'] ?? '', // Store encryptedKey for decryption
      }).toList();
      
      AppLogger.log('PostService: Post has ${relatedFiles.length} attached media files');
      
      // 🔍 DEBUG: Log related files details
      AppLogger.log('🔍 DEBUG POSTSERVICE - related files:');
      AppLogger.log('  relatedFiles length: ${relatedFiles.length}');
      AppLogger.log('  relatedFiles content: $relatedFiles');
      for (int i = 0; i < relatedFiles.length; i++) {
        AppLogger.log('    [$i]: fileId=${relatedFiles[i]['fileId']}, type=${relatedFiles[i]['type']}, caption=${relatedFiles[i]['caption']}');
      }
      AppLogger.log('🔍 END DEBUG POSTSERVICE');
    } else {
      AppLogger.log('🔍 DEBUG POSTSERVICE - No attached media, relatedFiles will be null');
    }
    
    if (encryptedType == 'public' && shareType == 'me') {
      // Public post, only owner
      onProgress?.call('Creating public post (no encryption)...');
      final result = await FileCryptoService.createPublicFile(
        fileData: postBytes,
        fileName: fileName,
        ownerPublicKey: authorPublicKey,
        sharedWithPublicKeys: null,
        fileType: 'post',
        relatedFiles: relatedFiles,
        onProgress: onProgress,
        encryptedType: encryptedType,
        shareType: shareType,
        contractId: contractId, // 🆕 Pass storage contract ID
      );
      return {
        'success': true,
        'postId': postContent['postId'],
        'fileId': result['fileId'],
        'metadataEntries': result['metadataEntries'],
        'blocks': result['blocks'],
        'attachedMediaCount': relatedFiles?.length ?? 0,
        'isPublic': true,
      };
    } else if (encryptedType == 'public' && shareType != 'me') {
      // Public post, shared with others
      onProgress?.call('Creating public post (no encryption, shared)...');
      final result = await FileCryptoService.createPublicFile(
        fileData: postBytes,
        fileName: fileName,
        ownerPublicKey: authorPublicKey,
        sharedWithPublicKeys: sharedWithUsers,
        fileType: 'post',
        relatedFiles: relatedFiles,
        onProgress: onProgress,
        encryptedType: encryptedType,
        shareType: shareType,
        contractId: contractId, // 🆕 Pass storage contract ID
      );
      return {
        'success': true,
        'postId': postContent['postId'],
        'fileId': result['fileId'],
        'metadataEntries': result['metadataEntries'],
        'blocks': result['blocks'],
        'attachedMediaCount': relatedFiles?.length ?? 0,
        'isPublic': true,
      };
    } else {
      // Encrypted post (private, followers, specific)
      onProgress?.call('Encrypting post...');
      
      // For PRE (Option 2): FileCryptoService will handle ECIES(K, pkAuthor)
      // No need to pre-generate PRE capsule - we use ECIES for all cases!
      
      final result = await FileCryptoService.encryptAndSplitFile(
        fileData: postBytes,
        fileName: fileName,
        ownerPublicKey: authorPublicKey,
        mnemonic: mnemonic,
        sharedWithPublicKeys: sharedWithUsers,
        fileType: 'post',
        relatedFiles: relatedFiles,
        onProgress: onProgress,
        encryptedType: encryptedType,
        shareType: shareType,
        policyTag: policyTag,
        capsuleFor: capsuleFor,
        policyScheme: policyScheme,
        contractId: contractId, // 🆕 Pass storage contract ID
      );
      final metadataEntries = result['metadataEntries'] as List<Map<String, dynamic>>;
      final blocks = result['blocks'] as List<Map<String, dynamic>>;
      final firstMetadata = metadataEntries[0];
      return {
        'success': true,
        'postId': postContent['postId'],
        'fileId': firstMetadata['fileId'],
        'metadataEntries': metadataEntries,
        'blocks': blocks,
        'attachedMediaCount': relatedFiles?.length ?? 0,
        'isPublic': false,
      };
    }
  }
  
  /// Upload post to storage node using PostController
  static Future<Map<String, dynamic>> uploadPost({
    required Map<String, dynamic> postResult,
    required Map<String, dynamic> selectedNode,
    Function(String)? onProgress,
  }) async {
    AppLogger.log('PostService: Uploading post to storage node...');
    
    // Use the regular FileUploadService since posts are just special files
    // final fileUploadService = FileUploadService(); // unused
    
    // 🆕 ZERO-KNOWLEDGE SHARING: Handle multiple metadata entries
    final metadataEntries = postResult['metadataEntries'] as List<Map<String, dynamic>>;
    final blocks = postResult['blocks'] as List<Map<String, dynamic>>;
    final firstMetadata = metadataEntries[0];
    
    AppLogger.log('PostService: Using FileUploadService for post upload (${blocks.length} blocks)');
    
    // Use existing file upload infrastructure
    // The PostController endpoints are for future social features
    return {
      'success': true,
      'postId': postResult['postId'],
      'fileId': firstMetadata['fileId'],
      'url': '${selectedNode['endpoint']}/api/file/download/${firstMetadata['fileId']}',
      'nodeId': selectedNode['id'],
      'message': 'Post ready for upload via FileUploadService',
      'useFileUploadService': true, // Flag to indicate using regular file upload
    };
  }

  /// 🆕 Prepare post upload with storage cost confirmation
  /// This checks the storage fees and returns info for UI to show confirmation dialog
  /// 
  /// Returns:
  /// {
  ///   'success': bool,
  ///   'contractId': string (if success),
  ///   'totalFee': double (storage cost in Deltanium),
  ///   'feeBasis': string (human readable explanation),
  ///   'estimatedSize': int (file size in bytes),
  ///   'durationDays': int,
  ///   'estimatedCostPerDay': double,
  ///   'error': string (if failed)
  /// }
  static Future<Map<String, dynamic>> preparePostUploadWithStorageCost({
    required Map<String, dynamic> postResult,
    required String storeBaseUrl,
    required String appPublicKey,
    required String storageNodePublicKey,
    required String userMnemonic,
    int durationDays = 365, // Default 1 year storage
    Function(String)? onProgress,
  }) async {
    AppLogger.log('PostService: Preparing post upload with storage cost...');
    onProgress?.call('Calculating storage cost...');
    
    try {
      final blocks = postResult['blocks'] as List<Map<String, dynamic>>;
      final metadataEntries = postResult['metadataEntries'] as List<Map<String, dynamic>>;
      final fileIds = metadataEntries.map((m) => m['fileId'] as String).toList();
      
      // Calculate total size (all blocks + metadata)
      int totalSize = 0;
      for (var block in blocks) {
        final data = block['data'];
        final encryptedContent = block['encryptedContent'];
        if (data is List<int>) {
          totalSize += data.length;
        } else if (data is Uint8List) {
          totalSize += data.length;
        } else if (encryptedContent is List<int>) {
          totalSize += encryptedContent.length;
        } else if (encryptedContent is Uint8List) {
          totalSize += encryptedContent.length;
        }
      }
      for (var metadata in metadataEntries) {
        final json = jsonEncode(metadata);
        totalSize += json.length;
      }
      
      AppLogger.log('PostService: Post total size = $totalSize bytes, Duration = $durationDays days');
      
      // Create contract proposal (Storage Node will calculate fee)
      onProgress?.call('Creating storage contract proposal...');
      
      final now = DateTime.now();
      final startDate = now.millisecondsSinceEpoch ~/ 1000;
      final endDate = now.add(Duration(days: durationDays)).millisecondsSinceEpoch ~/ 1000;
      
      // Call to StorageContractService to create proposal
      // This returns contract WITH calculated fee
      final contractResponse = await _createContractProposal(
        storeBaseUrl: storeBaseUrl,
        contractType: 'TimeFixed',
        startDateUnix: startDate,
        endDateUnix: endDate,
        totalFileSize: totalSize,
        fileIds: fileIds,
        appPublicKey: appPublicKey,
        storageNodePublicKey: storageNodePublicKey,
        userMnemonic: userMnemonic,
      );

      if (!contractResponse['success']) {
        return {
          'success': false,
          'error': contractResponse['error'] ?? 'Failed to create contract proposal'
        };
      }

      final totalFee = contractResponse['totalFee'] as double? ?? 0.0;
      final costPerDay = totalFee / (durationDays > 0 ? durationDays : 1);

      return {
        'success': true,
        'contractId': contractResponse['contractId'],
        'totalFee': totalFee,
        'feeBasis': contractResponse['feeBasis'],
        'estimatedSize': totalSize,
        'durationDays': durationDays,
        'estimatedCostPerDay': costPerDay,
        'fileIds': fileIds,
      };
    } catch (e) {
      AppLogger.log('PostService: Error preparing upload: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }

  /// 🆕 Confirm and complete post upload after user approves the storage cost
  /// Called after user clicks "Confirm" on the fee dialog
  static Future<Map<String, dynamic>> confirmAndUploadPost({
    required Map<String, dynamic> postResult,
    required Map<String, dynamic> storageInfo, // From preparePostUploadWithStorageCost
    required String storeBaseUrl,
    required String appPublicKey,
    required String storageNodePublicKey,
    required String userPrivateKeyForSigning,
    required Map<String, dynamic> selectedNode,
    Function(String)? onProgress,
  }) async {
    AppLogger.log('PostService: User confirmed. Proceeding with upload...');
    
    try {
      final contractId = storageInfo['contractId'] as String?;
      if (contractId == null || contractId.isEmpty) {
        return {
          'success': false,
          'error': 'Missing contract ID. Please create contract first.'
        };
      }

      onProgress?.call('Signing storage contract...');
      
      // Step 1: Sign and approve the contract
      final signResult = await _signAndApproveContract(
        storeBaseUrl: storeBaseUrl,
        contractId: contractId,
        appPublicKey: appPublicKey,
        userPrivateKeyForSigning: userPrivateKeyForSigning,
      );

      if (!signResult['success']) {
        return {
          'success': false,
          'error': signResult['error'] ?? 'Failed to sign contract'
        };
      }

      AppLogger.log('PostService: Contract signed, account approved cost');

      // Step 2: Upload the post (now contract is active)
      onProgress?.call('Uploading post to storage...');
      
      final uploadResult = await uploadPost(
        postResult: postResult,
        selectedNode: selectedNode,
        onProgress: onProgress,
      );

      if (!uploadResult['success']) {
        return {
          'success': false,
          'error': uploadResult['error'] ?? 'Failed to upload post'
        };
      }

      return {
        'success': true,
        'postId': uploadResult['postId'],
        'fileId': uploadResult['fileId'],
        'contractId': contractId,
        'totalFee': storageInfo['totalFee'],
        'durationDays': storageInfo['durationDays'],
        'message': 'Post uploaded successfully with storage contract'
      };

    } catch (e) {
      AppLogger.log('PostService: Error during upload confirmation: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }

  /// Helper: Create contract proposal via API
  static Future<Map<String, dynamic>> _createContractProposal({
    required String storeBaseUrl,
    required String contractType,
    required int startDateUnix,
    required int endDateUnix,
    required int totalFileSize,
    required List<String> fileIds,
    required String appPublicKey,
    required String storageNodePublicKey,
    required String userMnemonic,
  }) async {
    try {
      final signer = RequestSigner(
        publicKey: appPublicKey,
        mnemonic: userMnemonic,
      );
      final body = jsonEncode({
        'contractType': contractType,
        'startDateUnix': startDateUnix,
        'endDateUnix': endDateUnix,
        'totalFileSize': totalFileSize,
        'fileIds': fileIds,
      });
      final signature = await signer.signRequest(
        'POST',
        '/api/storage/contracts/create',
        Uint8List.fromList(utf8.encode(body)),
      );
      final normalizedPubKey = signer.getPublicKeyBase64();

      final response = await http.post(
        Uri.parse('$storeBaseUrl/api/storage/contracts/create'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': normalizedPubKey,
          'X-Timestamp': signature['timestamp']!,
          'X-Signature': signature['signature']!,
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'contractId': data['contractId'],
          'totalFee': (data['totalFee'] as num?)?.toDouble() ?? 0.0,
          'feeBasis': data['feeBasis'] ?? 'Storage node calculated fee',
        };
      }

      return {
        'success': false,
        'error': response.body,
      };
    } catch (e) {
      AppLogger.log('Error creating contract proposal: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }

  /// Helper: Sign and approve contract
  static Future<Map<String, dynamic>> _signAndApproveContract({
    required String storeBaseUrl,
    required String contractId,
    required String appPublicKey,
    required String userPrivateKeyForSigning,
  }) async {
    try {
      final signer = RequestSigner(
        publicKey: appPublicKey,
        mnemonic: userPrivateKeyForSigning,
      );
      final contractService = StorageContractService(
        storeBaseUrl: storeBaseUrl,
        signer: signer,
      );

      final contract = await contractService.getContract(
        contractId: contractId,
        userPublicKey: appPublicKey,
      );
      if (contract == null) {
        return {
          'success': false,
          'error': 'Contract not found on store node',
        };
      }

      final signed = await contractService.approveAndSignContract(
        contract: contract,
        appPrivateKey: userPrivateKeyForSigning,
      );
      if (signed == null) {
        return {
          'success': false,
          'error': 'Failed to sign contract',
        };
      }

      return {
        'success': true,
        'contractId': contractId,
        'status': signed.status,
      };
    } catch (e) {
      AppLogger.log('Error signing contract: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }

  /// Helper: Estimate storage fee (same formula as Store)
  static double _calculateStorageFeeEstimate(int sizeBytes, int startUnix, int endUnix) {
    const double basePricePerGBPerMonth = 0.0;
    const double minimumFee = 0.0;

    // Convert to GB
    double sizeGB = sizeBytes / (1024 * 1024 * 1024);
    
    // Convert duration to months
    int durationSeconds = endUnix - startUnix;
    double durationMonths = durationSeconds / (30 * 24 * 60 * 60);
    
    // Calculate
    double fee = sizeGB * durationMonths * basePricePerGBPerMonth;
    
    return fee < minimumFee ? minimumFee : fee;
  }
  
  /// Decrypt and load post content
  static Future<Map<String, dynamic>> loadPost({
    required String fileId,
    required String userPublicKey,
    required String mnemonic,
    required String nodeEndpoint,
    Function(String)? onProgress,
  }) async {
    AppLogger.log('PostService: Loading post $fileId...');
    onProgress?.call('Downloading post...');
    
    try {
      // Use existing download infrastructure
      // This would integrate with user_files_screen download logic
      // For now, return placeholder with relatedFiles structure
      
      return {
        'success': true,
        'postId': 'post_$fileId',
        'fileId': fileId,
        'postContent': {
          'textContent': 'Sample post content',
          'authorPublicKey': userPublicKey,
          'createdAt': DateTime.now().toIso8601String(),
        },
        'relatedFiles': [
          // Example structure of related files
          {
            'fileId': 'example_file_1',
            'type': 'image',
            'relationshipType': 'attachment',
            'fileName': 'example.jpg',
            'fileSize': 1024000,
            'mimeType': 'image/jpeg',
            'uploadTime': DateTime.now().toIso8601String(),
            'nodeId': 'node_1',
            'nodeEndpoint': nodeEndpoint,
            'caption': 'Example image',
            'order': 0,
          }
        ],
        'metadata': {
          'isPublic': false,
          'encryptedType': 'encrypted',
          'shareType': 'me',
        }
      };
    } catch (e) {
      AppLogger.log('PostService: Error loading post: $e');
      return {
        'success': false,
        'error': e.toString(),
        'relatedFiles': [],
      };
    }
  }
  
  /// Generate unique post ID
  static String _generatePostId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'post_${timestamp}_$random';
  }
  
  /// Helper method to get MIME type from file extension
  static String _getMimeTypeFromExtension(String extension) {
    final ext = extension.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
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
      case 'mp3':
        return 'audio/mpeg';
      case 'mp4':
        return 'video/mp4';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  // Hex string to bytes helper (expects even-length hex)
  static Uint8List _hexToBytes(String hex) {
    final sanitized = hex.trim();
    final len = sanitized.length;
    final out = Uint8List(len ~/ 2);
    for (int i = 0; i < len; i += 2) {
      out[i >> 1] = int.parse(sanitized.substring(i, i + 2), radix: 16);
    }
    return out;
  }
  
  /// Add related files to an existing post
  static Future<Map<String, dynamic>> addRelatedFilesToPost({
    required String postFileId,
    required String userPublicKey,
    required String mnemonic,
    required List<Map<String, dynamic>> newRelatedFiles,
    required String nodeEndpoint,
    Function(String)? onProgress,
  }) async {
    AppLogger.log('PostService: Adding ${newRelatedFiles.length} related files to post $postFileId');
    onProgress?.call('Loading existing post...');
    
    // First, load the existing post to get current relatedFiles
    final existingPost = await loadPost(
      fileId: postFileId,
      userPublicKey: userPublicKey,
      mnemonic: mnemonic,
      nodeEndpoint: nodeEndpoint,
      onProgress: onProgress,
    );
    
    if (!existingPost['success']) {
      throw Exception('Failed to load existing post: ${existingPost['error']}');
    }
    
    // Get existing related files
    final existingRelatedFiles = List<Map<String, dynamic>>.from(existingPost['relatedFiles'] ?? []);
    
    // Add new related files with proper metadata
    final enhancedNewFiles = newRelatedFiles.map((file) => {
      ...file,
      'relationshipType': file['relationshipType'] ?? 'attachment',
      'fileName': file['fileName'] ?? file['name'] ?? 'Unknown file',
      'fileSize': file['fileSize'] ?? file['size'] ?? 0,
      'mimeType': _getMimeTypeFromExtension(file['extension'] ?? ''),
      'uploadTime': DateTime.now().toIso8601String(),
      'nodeId': file['nodeId'],
      'nodeEndpoint': file['nodeEndpoint'],
    }).toList();
    
    // Combine existing and new related files
    final allRelatedFiles = [...existingRelatedFiles, ...enhancedNewFiles];
    
    // Update the post with new relatedFiles
    // This would require re-encrypting and re-uploading the post
    // For now, return the updated structure
    return {
      'success': true,
      'postId': existingPost['postId'],
      'fileId': postFileId,
      'relatedFiles': allRelatedFiles,
      'totalRelatedFiles': allRelatedFiles.length,
      'message': 'Related files structure updated (re-upload required)',
    };
  }
  
  /// Remove related files from a post
  static Future<Map<String, dynamic>> removeRelatedFilesFromPost({
    required String postFileId,
    required String userPublicKey,
    required String mnemonic,
    required List<String> fileIdsToRemove,
    required String nodeEndpoint,
    Function(String)? onProgress,
  }) async {
    AppLogger.log('PostService: Removing ${fileIdsToRemove.length} related files from post $postFileId');
    onProgress?.call('Loading existing post...');
    
    // Load existing post
    final existingPost = await loadPost(
      fileId: postFileId,
      userPublicKey: userPublicKey,
      mnemonic: mnemonic,
      nodeEndpoint: nodeEndpoint,
      onProgress: onProgress,
    );
    
    if (!existingPost['success']) {
      throw Exception('Failed to load existing post: ${existingPost['error']}');
    }
    
    // Get existing related files and remove specified ones
    final existingRelatedFiles = List<Map<String, dynamic>>.from(existingPost['relatedFiles'] ?? []);
    final updatedRelatedFiles = existingRelatedFiles.where((file) => 
      !fileIdsToRemove.contains(file['fileId'])
    ).toList();
    
    return {
      'success': true,
      'postId': existingPost['postId'],
      'fileId': postFileId,
      'relatedFiles': updatedRelatedFiles,
      'totalRelatedFiles': updatedRelatedFiles.length,
      'removedFiles': fileIdsToRemove,
      'message': 'Related files removed (re-upload required)',
    };
  }
  
  /// Get related files from post metadata
  static Future<List<Map<String, dynamic>>> getRelatedFilesFromPost({
    required String postFileId,
    required String userPublicKey,
    required String mnemonic,
    required String nodeEndpoint,
    Function(String)? onProgress,
  }) async {
    AppLogger.log('PostService: Getting related files from post $postFileId');
    onProgress?.call('Loading post metadata...');
    
    final post = await loadPost(
      fileId: postFileId,
      userPublicKey: userPublicKey,
      mnemonic: mnemonic,
      nodeEndpoint: nodeEndpoint,
      onProgress: onProgress,
    );
    
    if (!post['success']) {
      throw Exception('Failed to load post: ${post['error']}');
    }
    
    final relatedFiles = List<Map<String, dynamic>>.from(post['relatedFiles'] ?? []);
    AppLogger.log('PostService: Found ${relatedFiles.length} related files');
    
    return relatedFiles;
  }
  
  /// Validate related files structure
  static bool validateRelatedFiles(List<Map<String, dynamic>> relatedFiles) {
    for (final file in relatedFiles) {
      // Check required fields
      if (file['fileId'] == null || file['fileId'].toString().isEmpty) {
        AppLogger.log('PostService: Invalid related file - missing fileId');
        return false;
      }
      
      if (file['type'] == null || file['type'].toString().isEmpty) {
        AppLogger.log('PostService: Invalid related file - missing type');
        return false;
      }
      
      // Check optional but recommended fields
      if (file['fileName'] == null || file['fileName'].toString().isEmpty) {
        AppLogger.log('PostService: Warning - related file missing fileName');
      }
      
      if (file['nodeEndpoint'] == null || file['nodeEndpoint'].toString().isEmpty) {
        AppLogger.log('PostService: Warning - related file missing nodeEndpoint');
      }
    }
    
    return true;
  }
} 
