import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/app/router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io'; // Import for File operations on mobile
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/features/file_manager/file_upload_service.dart';
import 'package:deltanium_app/services/post_service.dart';
import 'package:deltanium_app/services/pre_service.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/widgets/confirm_storage_cost_dialog.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/services/request_signer.dart';

// import 'package:deltanium_app/services/user_discovery_service.dart';

class CreatePostScreen extends StatefulWidget {
  final UserProfile? userProfile;
  
  const CreatePostScreen({super.key, this.userProfile});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  String _loadingMessage = 'Processing...'; // Progress message
  final _imagePicker = ImagePicker();
  final String _apiBaseUrl = AppConstants.apiBaseUrl;  // Central API (includes /api)
  
  // Store media items with their type
  List<Map<String, dynamic>> _selectedMedia = [];
  
  // File sharing configuration
  List<String> _sharedWithPublicKeys = []; // List of public keys to share files with
  final _publicKeyController = TextEditingController();
  bool _showShareSection = false;
  
  // 🆕 Public post configuration removed in favor of shareType 'public'
  
  // Current user's public key and mnemonic
  String? get _userPublicKey => widget.userProfile?.publicKey;
  String? _userMnemonic;
  
  // Thêm enum và biến trạng thái
  String _shareType = 'followers'; // default to followers
  // 🆕 Followers sharing mode: Option 1 (per-recipient) vs Option 2 (PRE-tag)
  bool _followersUsePre = true; // default to Option 2 (PRE)
  
  List<String> _followers = [];
  bool _isLoadingFollowers = false;
  String _encryptedType = 'encrypted'; // 'public' hoặc 'encrypted'
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadUserCredentials();
    });
    
    // Validate we have the user's public key
    if (_userPublicKey == null) {
      AppLogger.log('WARNING: No user public key available - uploads may fail');
    } else {
      AppLogger.log('Using user public key: ${_userPublicKey!.substring(0, 10)}...');
    }
  }
  
  // Load user credentials from local storage
  Future<void> _loadUserCredentials() async {
    if (_userPublicKey == null) return;
    
    try {
      final savedUsers = await CryptoService.getSavedUsers();
      final user = savedUsers.firstWhere(
        (u) => u['pubkey'] == _userPublicKey,
        orElse: () => <String, dynamic>{}, // Return empty map instead of null
      );
      
      if (user.isNotEmpty) { // Check if map is not empty
        setState(() {
          _userMnemonic = user['mnemonic'] as String;
        });
        AppLogger.log('Loaded user mnemonic from local storage');
        // If default is followers, preload followers list
        if (_shareType == 'followers') {
          setState(() { _isLoadingFollowers = true; });
          try {
            final followers = await _fetchFollowers();
            setState(() {
              _followers = followers;
              _isLoadingFollowers = false;
            });
          } catch (e) {
            setState(() { _isLoadingFollowers = false; });
          }
        }
      } else {
        AppLogger.log('WARNING: No saved credentials found for public key ${_userPublicKey!.substring(0, 10)}...');
      }
    } catch (e) {
      AppLogger.log('Error loading user credentials: $e');
    }
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _publicKeyController.dispose();
    super.dispose();
  }
  
  void _addMedia() async {
    // Show modal to choose between camera, gallery or file
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            // Only show file option on mobile, not on web due to initialization issues
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Attach a file'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            // Web also uses file_picker (withData=true), no dart:html
            if (kIsWeb)
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Attach a file'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _pickImage(ImageSource source) async {
    try {
      // macOS: FilePicker is used for images due to image_picker camera limitations
      if (!kIsWeb && Platform.isMacOS) {
        await _pickImageFileWithFilePicker();
        return;
      }
      // In web, camera source doesn't work well, so let's handle that
      if (kIsWeb && source == ImageSource.camera) {
        // Show a message that camera isn't supported on web
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera capture is not fully supported in web browsers. Using gallery instead.'),
            duration: Duration(seconds: 3),
          ),
        );
        // Force gallery mode on web
        source = ImageSource.gallery;
      }
      
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
      );
      
      if (image != null) {
        if (_selectedMedia.length < 4) {
          try {
            // For all platforms, add basic image data
            final imageData = {
              'type': 'image',
              'name': image.name,
              'isLocal': true,
            };
            
            if (kIsWeb) {
              // For web, we need to read the bytes for memory display
              try {
                final bytes = await image.readAsBytes();
                imageData['bytes'] = bytes;
                imageData['previewUrl'] = image.path; // Blob URL on web
                
    setState(() {
                  _selectedMedia.add(imageData);
                });
                
                AppLogger.log('Added image on web: ${image.name}, size: ${bytes.length} bytes');
              } catch (e) {
                AppLogger.log('Error reading image bytes: $e');
                // Fallback to placeholder image on web if bytes reading fails
                setState(() {
                  _selectedMedia.add({
                    'type': 'image',
                    'name': 'web_image.jpg',
                    'isLocal': false,
                    'previewAsset': 'assets/images/avatar_placeholder.png',
                  });
                });
              }
            } else {
              // For mobile platforms
              imageData['path'] = image.path;
              setState(() {
                _selectedMedia.add(imageData);
              });
            }
          } catch (e) {
            AppLogger.log('Error processing image: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error processing image: $e')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 4 media items allowed')),
          );
        }
      }
    } catch (e) {
      AppLogger.log('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _pickImageFileWithFilePicker() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
        onFileLoading: (status) => print('Image picking status (macOS): $status'),
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (_selectedMedia.length < 4) {
          setState(() {
            _selectedMedia.add({
              'type': 'image',
              'name': file.name,
              'isLocal': true,
              'bytes': file.bytes,
              'path': file.path,
            });
          });
          AppLogger.log('Added image via FilePicker: ${file.name}, size=${file.bytes?.length ?? 0}');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 4 media items allowed')),
          );
        }
      }
    } catch (e) {
      AppLogger.log('Error picking image via FilePicker: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to pick image: $e')),
      );
    }
  }
  
  Future<void> _pickFile() async {
    try {
      // Set specific options for file picker to avoid initialization issues
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: kIsWeb, // Ensure we get the bytes data for web
        onFileLoading: (FilePickerStatus status) => print('File picking status: $status'),
      );
      
      if (result != null && result.files.isNotEmpty) {
        if (_selectedMedia.length < 4) {
          final file = result.files.first;
          final fileName = file.name;
          
          if (kIsWeb) {
            // For web, use the bytes data from the file
            if (file.bytes != null) {
              setState(() {
                _selectedMedia.add({
                  'type': 'file',
                  'name': fileName,
                  'isLocal': true,
                  'bytes': file.bytes,
                  'extension': file.extension ?? 'unknown',
                  'size': file.size,
                });
              });
              
              AppLogger.log('File picked on web: $fileName, size: ${file.size} bytes');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not read file data')),
              );
            }
          } else {
            // For mobile platforms
            if (file.path != null) {
              setState(() {
                _selectedMedia.add({
                  'type': 'file',
                  'path': file.path!,
                  'name': fileName,
                  'isLocal': true,
                });
              });
            }
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 4 media items allowed')),
          );
        }
      }
    } catch (e) {
      AppLogger.log('Error picking file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e')),
      );
    }
  }
  
  // Removed dart:html path; web uses file_picker via _pickFile
  
  void _removeMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }
  
  

  
  
  // Toggle share section visibility
  void _toggleShareSection() {
    setState(() {
      _showShareSection = !_showShareSection;
    });
  }
  
  // Extract hashtags from text content
  List<String> _extractTags(String text) {
    final RegExp tagRegex = RegExp(r'#\w+');
    final matches = tagRegex.allMatches(text);
    return matches.map((match) => match.group(0)!).toList();
  }

  Future<bool> _confirmStorageCostDialog(Map<String, dynamic> storageInfo) async {
    if (!mounted) return false;
    final completer = Completer<bool>();
    ConfirmStorageCostDialog.show(
      context: context,
      totalFee: (storageInfo['totalFee'] as num?)?.toDouble() ?? 0.0,
      durationDays: storageInfo['durationDays'] as int? ?? 0,
      costPerDay: (storageInfo['estimatedCostPerDay'] as num?)?.toDouble() ?? 0.0,
      estimatedSizeBytes: storageInfo['estimatedSize'] as int? ?? 0,
      feeBasis: storageInfo['feeBasis'] as String? ?? 'Storage fee calculated by node',
      onConfirm: () => completer.complete(true),
      onCancel: () => completer.complete(false),
    );
    return completer.future;
  }

  Future<void> _signStorageContract({
    required String storeBaseUrl,
    required String contractId,
  }) async {
    if (_userPublicKey == null || _userMnemonic == null) {
      throw Exception('Missing user credentials for contract signing');
    }
    final signer = RequestSigner(
      publicKey: _userPublicKey!,
      mnemonic: _userMnemonic!,
    );
    final contractService = StorageContractService(
      storeBaseUrl: storeBaseUrl,
      signer: signer,
    );
    final contract = await contractService.getContract(
      contractId: contractId,
      userPublicKey: _userPublicKey!,
    );
    if (contract == null) {
      throw Exception('Storage contract not found');
    }
    final signed = await contractService.approveAndSignContract(
      contract: contract,
      appPrivateKey: _userMnemonic!,
    );
    if (signed == null || signed.status.toLowerCase() != 'active') {
      throw Exception('Failed to sign storage contract');
    }
  }
  
  Future<void> _createPost() async {
    final userProfile = widget.userProfile;
    String? createdPostId;
    String? createdFileId;
    String? createdNodeId;
    String? createdShareType;
    String? createdEncryptedType;
    AppLogger.log('DEBUG: _shareType at start of _createPost: [32m[1m[4m$_shareType[0m');
    // Validate if there's content to post
    if (_textController.text.trim().isEmpty && _selectedMedia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your post cannot be empty'),
          backgroundColor: DeltaniumTheme.errorColor,
        ),
      );
      return;
    }
    
    // Check if user public key is available
    if (_userPublicKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to create post: User authentication missing'),
          backgroundColor: DeltaniumTheme.errorColor,
        ),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      AppLogger.log('DEBUG: Starting create post process');
      AppLogger.log('Creating post with text: \\${_textController.text}');
      AppLogger.log('With media: \\${_selectedMedia.length} items');
      
      // ==== SỬA ĐOẠN NÀY: Luôn xác định allRecipients đúng theo _shareType ====
      final bool usePre = _shareType == 'followers' && _followersUsePre;
      final List<String> allRecipients = _shareType == 'followers'
          ? (usePre
              // Option 2 (PRE): do NOT clone per follower; only owner entry
              ? [_userPublicKey!]
              // Option 1 (per-recipient): clone to each follower
              : [_userPublicKey!, ..._followers.where((f) => f != _userPublicKey)])
          : _shareType == 'public'
              ? [_userPublicKey!]
              : [_userPublicKey!]; // "me" thì chỉ mình
      AppLogger.log('DEBUG: _shareType at start of _createPost: \\$_shareType');
      AppLogger.log('DEBUG: allRecipients:');
      for (var f in allRecipients) {
        AppLogger.log('  Recipient: ' + f);
      }
      // ===============================================================
      
      if (_selectedMedia.isNotEmpty) {
        // 1. Get available store nodes
        AppLogger.log('DEBUG: Fetching available store nodes...');
        final storeNodes = await _fetchStoreNodes();
        AppLogger.log('DEBUG: Received ${storeNodes.length} store nodes');
        
        if (storeNodes.isEmpty) {
          throw Exception('No available storage nodes found');
        }
        
        AppLogger.log('Found ${storeNodes.length} available store nodes');
        
        // 2. Select a node to use
        final selectedNode = _selectNode(storeNodes);
        AppLogger.log('Selected node: ${selectedNode['endpoint']}');
        
        // 3. Use the user's public key for authentication instead of node's key
        AppLogger.log('DEBUG: Setting up authentication with user key...');
        AppLogger.log('DEBUG: Using user public key: ${_userPublicKey!.substring(0, 10)}...');
        
        // TODO: In production, should get the mnemonic from secure storage
        // For demo, using test mnemonic - in real app would use stored user mnemonic
        // const clientMnemonic = "demo_client_key"; 
        
        // 4. Upload media files
        AppLogger.log('DEBUG: Beginning media upload process...');
        final uploadedMedia = <Map<String, dynamic>>[];
        
        for (final media in _selectedMedia) {
          try {
            AppLogger.log('DEBUG: Uploading media item: ${media['name']}');
            final uploadResult = await _uploadMediaToNode(
              media: media,
              node: selectedNode,
              publicKey: _userPublicKey!, // Use user's public key instead of node's
              mnemonic: _userMnemonic!, // Use loaded mnemonic
              onProgress: (message) {
                setState(() {
                  _loadingMessage = message;
                });
              },
            );
            
            AppLogger.log('DEBUG: Media upload completed. Result: $uploadResult');
            
            uploadedMedia.add({
              'fileId': uploadResult['fileId'],
              'name': media['name'] ?? 'Unnamed file',
              'type': media['type'] ?? 'file',
              'url': '${selectedNode['endpoint']}/api/file/download/${uploadResult['fileId']}',
              'nodeId': selectedNode['id'],
              'nodeEndpoint': selectedNode['endpoint'], // Add node endpoint
              'size': media['size'] ?? 0, // Add file size
              'extension': media['extension'] ?? 'unknown', // Add file extension
              'encryptedKey': uploadResult['encryptedKey'], // 🆕 Add encryptedKey from upload result
            });
            
            // Register with central API
            AppLogger.log('DEBUG: Registering file with central API...');
            await _registerFileWithAPI(
              fileId: uploadResult['fileId'],
              fileName: media['name'] ?? 'Unnamed file',
              fileType: media['type'] ?? 'file',
              nodeId: selectedNode['id'],
              publicKey: _userPublicKey!, // Use user's public key
            );
            AppLogger.log('DEBUG: File registered with central API');
          } catch (e) {
            AppLogger.log('Error uploading media: $e');
            // Continue with next file instead of failing entire post
          }
        }
        
        // 5. Create the post with uploaded media using PostService
        AppLogger.log('Successfully uploaded ${uploadedMedia.length} files');
        
        // Log sharing information
        if (_sharedWithPublicKeys.isNotEmpty) {
          AppLogger.log('Files shared with ${_sharedWithPublicKeys.length} additional users');
          for (int i = 0; i < _sharedWithPublicKeys.length; i++) {
            AppLogger.log('  Shared with user ${i + 1}: ${_sharedWithPublicKeys[i].substring(0, 10)}...');
          }
        }
        
        // 🆕 Create post as special file with attached media
        setState(() {
          _loadingMessage = 'Creating post...';
        });
        
        // 🔍 DEBUG: Log attached media before creating post
        AppLogger.log('🔍 DEBUG CREATE POST - attached media:');
        AppLogger.log('  uploadedMedia length: ${uploadedMedia.length}');
        AppLogger.log('  uploadedMedia content: $uploadedMedia');
        if (uploadedMedia.isNotEmpty) {
          final relatedFilesForPost = uploadedMedia.map((media) => {
            'fileId': media['fileId'],
            'type': media['type'],
            'caption': media['name'],
            'order': uploadedMedia.indexOf(media),
          }).toList();
          AppLogger.log('  relatedFilesForPost: $relatedFilesForPost');
          AppLogger.log('  relatedFilesForPost length: ${relatedFilesForPost.length}');
        }
        AppLogger.log('🔍 END DEBUG CREATE POST');
        
        final String? policyTag = (_shareType == 'followers' && _followersUsePre)
            ? 'followers:${DateTime.now().year}'
            : null;
        final postResult = await PostService.createPost(
          textContent: _textController.text,
          authorPublicKey: _userPublicKey!,
          authorName: widget.userProfile?.fullName,
          mnemonic: _userMnemonic!,
          attachedMedia: uploadedMedia.isNotEmpty
              ? uploadedMedia.map((media) => {
                  'fileId': media['fileId'],
                  'type': media['type'],
                  'caption': media['name'],
                  'order': uploadedMedia.indexOf(media),
                  'nodeEndpoint': media['nodeEndpoint'], // 🆕 Include nodeEndpoint
                  'nodeId': media['nodeId'], // 🆕 Include nodeId
                  'size': media['size'], // 🆕 Include file size
                  'extension': media['extension'], // 🆕 Include file extension
                  'encryptedKey': media['encryptedKey'], // 🆕 Include encryptedKey if available
                }).toList()
              : null,
          sharedWithUsers: allRecipients,
          encryptedType: _encryptedType,
          shareType: _shareType,
          tags: _extractTags(_textController.text),
          // 🆕 PRE fields (Option 2)
          policyTag: policyTag,
          capsuleFor: policyTag != null ? 'tag' : null,
          policyScheme: policyTag != null ? 'CPRE' : null,
          onProgress: (message) {
            setState(() {
              _loadingMessage = message;
            });
          },
        );
        
        AppLogger.log('Post created successfully: ${postResult['postId']}');
        AppLogger.log('Post has ${postResult['attachedMediaCount']} attached media files');

        // 🆕 Prepare storage cost + contract proposal before upload
        setState(() {
          _loadingMessage = 'Calculating storage cost...';
        });
        final storageInfo = await PostService.preparePostUploadWithStorageCost(
          postResult: postResult,
          storeBaseUrl: selectedNode['endpoint'],
          appPublicKey: _userPublicKey!,
          storageNodePublicKey: selectedNode['publicKey'] ?? '',
          userMnemonic: _userMnemonic!,
          onProgress: (message) {
            setState(() {
              _loadingMessage = message;
            });
          },
        );
        if (storageInfo['success'] != true) {
          throw Exception(storageInfo['error'] ?? 'Failed to calculate storage cost');
        }

        setState(() {
          _loadingMessage = 'Awaiting fee confirmation...';
        });
        final confirmed = await _confirmStorageCostDialog(storageInfo);
        if (!confirmed) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload cancelled')),
          );
          return;
        }

        setState(() {
          _loadingMessage = 'Signing storage contract...';
        });
        final contractId = storageInfo['contractId'] as String? ?? '';
        if (contractId.isEmpty) {
          throw Exception('Missing contractId from storage proposal');
        }
        await _signStorageContract(
          storeBaseUrl: selectedNode['endpoint'],
          contractId: contractId,
        );

        // 🆕 Upload the post to storage node manually using the encrypted data
        setState(() {
          _loadingMessage = 'Uploading post to storage...';
        });
        
        // 🆕 ZERO-KNOWLEDGE SHARING: Handle multiple metadata entries
        final metadataEntries = postResult['metadataEntries'] as List<Map<String, dynamic>>;
        final postBlocks = postResult['blocks'] as List<Map<String, dynamic>>;
        final postFileId = postResult['fileId'] as String;
        createdPostId = postResult['postId']?.toString();
        createdFileId = postFileId;
        createdNodeId = selectedNode['id']?.toString();
        createdShareType = _shareType;
        createdEncryptedType = _encryptedType;
        
        // Ensure contractId is embedded in metadata for store/blocker submission
        for (final entry in metadataEntries) {
          entry['contractId'] = contractId;
          entry['type'] ??= 'post';
          entry['shareType'] ??= _shareType;
        }

        // Upload metadata entries (one for each user with access)
        for (int i = 0; i < metadataEntries.length; i++) {
          final metadataEntry = metadataEntries[i];
          final metadataJson = json.encode(metadataEntry);
          
          AppLogger.log('🔍 DEBUG: Uploading metadata entry ${i + 1}: fileId=${metadataEntry['fileId']}, firstBlockId=${metadataEntry['firstBlockId']}');
          
          setState(() {
            _loadingMessage = 'Uploading metadata entry ${i + 1}/${metadataEntries.length}...';
          });
          
          final metadataUploadResult = await _uploadContent(
            nodeEndpoint: selectedNode['endpoint'],
            path: '/api/file/upload-metadata-raw',
            content: Uint8List.fromList(utf8.encode(metadataJson)),
            fileName: '${postFileId}_metadata_${i}.json',
            contentType: 'application/json',
            publicKey: _userPublicKey!,
            mnemonic: _userMnemonic!,
          );
          
          if (metadataUploadResult['success'] != true) {
            throw Exception('Failed to upload post metadata entry ${i + 1}: ${metadataUploadResult['error']}');
          }
        }
        
        // 🔧 FIX: Upload blocks với fileId tương ứng với metadata entry
        // Block 0 (metadata blocks) - mỗi user có fileId riêng (upload riêng biệt)
        // Content blocks (1+) - chỉ upload 1 lần với fileId của owner
        
        final ownerFileId = metadataEntries[0]['fileId'] as String; // Owner's fileId for content blocks
        
        // Separate metadata blocks (index 0) and content blocks (index > 0)
        final List<Map<String, dynamic>> metadataBlocks = [];
        final List<Map<String, dynamic>> contentBlocks = [];
        
        for (final block in postBlocks) {
          final blockIndex = block['blockIndex'] as int;
          final isMetadataBlock = block['isMetadataBlock'] as bool? ?? false;
          
          // Use both flags to be safe: isMetadataBlock OR blockIndex == 0
          if (isMetadataBlock || blockIndex == 0) {
            metadataBlocks.add(block);
          } else {
            contentBlocks.add(block);
          }
        }
        
        AppLogger.log('🔍 DEBUG: Separated ${metadataBlocks.length} metadata blocks, ${contentBlocks.length} content blocks');
        
        // 🔍 DEBUG: Print all blocks to see structure
        for (int i = 0; i < postBlocks.length; i++) {
          final block = postBlocks[i];
          AppLogger.log('🔍 DEBUG: Block $i - blockId: ${block['blockId']}, blockIndex: ${block['blockIndex']}, isMetadata: ${block['isMetadataBlock']}');
        }
        
        // Upload metadata blocks first (one for each user)
        for (int i = 0; i < metadataBlocks.length; i++) {
          final block = metadataBlocks[i];
          final blockId = block['blockId'] as String;
          final blockIndex = block['blockIndex'] as int; // Should be 0
          final encryptedContent = block['encryptedContent'] as Uint8List;
          
          // Find the corresponding metadata entry for this block
          Map<String, dynamic>? foundMetadata;
          try {
            foundMetadata = metadataEntries.firstWhere(
              (entry) => entry['firstBlockId'] == blockId,
            );
          } catch (e) {
            // For public posts or when no match found, use first entry
            AppLogger.log('🔍 DEBUG: No metadata found for blockId: $blockId, using first entry');
            foundMetadata = metadataEntries[0];
          }
          final fileIdForBlock = foundMetadata['fileId'] as String;
          
          setState(() {
            _loadingMessage = 'Uploading metadata block ${i + 1}/${metadataBlocks.length}...';
          });
          
          AppLogger.log('🔍 DEBUG: Metadata block - blockId: $blockId, fileIdForBlock: $fileIdForBlock');
          AppLogger.log('🔍 DEBUG: correspondingMetadata: $foundMetadata');
          
          final blockUploadResult = await _uploadContent(
            nodeEndpoint: selectedNode['endpoint'],
            path: '/api/file/upload-file-block-raw',
            content: encryptedContent,
            fileName: blockId,
            contentType: 'application/octet-stream',
            publicKey: _userPublicKey!,
            mnemonic: _userMnemonic!,
            extraHeaders: {
              'X-Block-Id': blockId,
              'X-File-Id': fileIdForBlock, // Use respective user's fileId
              'X-Block-Index': blockIndex.toString(),
              if (contractId != null) 'X-Contract-Id': contractId, // 🆕 Pass ContractId
            },
          );
          
          if (blockUploadResult['success'] != true) {
            throw Exception('Failed to upload metadata block $blockIndex: ${blockUploadResult['error']}');
          }
        }
        
        // Upload content blocks (shared among all users, use owner's fileId)
        for (int i = 0; i < contentBlocks.length; i++) {
          final block = contentBlocks[i];
          final blockId = block['blockId'] as String;
          final blockIndex = block['blockIndex'] as int; // Should be > 0
          final encryptedContent = block['encryptedContent'] as Uint8List;
          
          setState(() {
            _loadingMessage = 'Uploading content block ${i + 1}/${contentBlocks.length}...';
          });
          
          AppLogger.log('🔍 DEBUG: Content block - blockId: $blockId, fileIdForBlock: $ownerFileId');
          
          final blockUploadResult = await _uploadContent(
            nodeEndpoint: selectedNode['endpoint'],
            path: '/api/file/upload-file-block-raw',
            content: encryptedContent,
            fileName: blockId,
            contentType: 'application/octet-stream',
            publicKey: _userPublicKey!,
            mnemonic: _userMnemonic!,
            extraHeaders: {
              'X-Block-Id': blockId,
              'X-File-Id': ownerFileId, // Always use owner's fileId for content blocks
              'X-Block-Index': blockIndex.toString(),
              if (contractId != null) 'X-Contract-Id': contractId, // 🆕 Pass ContractId
            },
          );
          
          if (blockUploadResult['success'] != true) {
            throw Exception('Failed to upload content block $blockIndex: ${blockUploadResult['error']}');
          }
        }
        
        AppLogger.log('Post uploaded successfully to storage node: $postFileId');

        // 🆕 PRE Option2: Generate & upload rekeys for current followers
        if (_shareType == 'followers' && _followersUsePre) {
          try {
            setState(() { _loadingMessage = 'Publishing PRE tag and uploading rekeys...'; });
            final pre = PreService();
            final tag = pre.buildPolicyTagForYear();
            // Include self (author) to generate rk_{A->A} so author can view PRE posts in Following
            final followerList = _followers.toList();
            final results = await pre.generateAndUploadRekeys(
              apiBaseUrl: _apiBaseUrl,
              authorPubKey: _userPublicKey!,
              mnemonic: _userMnemonic!,
              followerPubKeys: followerList,
              tag: tag,
            );
            final okCount = results.values.where((v) => v).length;
            AppLogger.log('PRE rekeys uploaded: $okCount/${results.length}');
          } catch (e) {
            AppLogger.log('PRE rekeys upload error: $e');
          }
        }
      } else {
        // Text-only post using PostService
        AppLogger.log('DEBUG: Text-only post, no media to upload');
        
        // 1. Get available store nodes for text post too
        AppLogger.log('DEBUG: Fetching available store nodes for text post...');
        final storeNodes = await _fetchStoreNodes();
        AppLogger.log('DEBUG: Received ${storeNodes.length} store nodes for text post');
        
        if (storeNodes.isEmpty) {
          throw Exception('No available storage nodes found');
        }
        
        // 2. Select a node to use
        final selectedNode = _selectNode(storeNodes);
        AppLogger.log('Selected node for text post: ${selectedNode['endpoint']}');
        
        setState(() {
          _loadingMessage = 'Creating text post...';
        });
        
        final String? policyTag = (_shareType == 'followers' && _followersUsePre)
            ? 'followers:${DateTime.now().year}'
            : null;
        final postResult = await PostService.createPost(
          textContent: _textController.text,
          authorPublicKey: _userPublicKey!,
          mnemonic: _userMnemonic!,
          attachedMedia: null, // No media attachments
          sharedWithUsers: allRecipients, // SỬA: luôn truyền đúng recipient
          encryptedType: _encryptedType,
          shareType: _shareType,
          tags: _extractTags(_textController.text),
          // 🆕 PRE fields (Option 2)
          policyTag: policyTag,
          capsuleFor: policyTag != null ? 'tag' : null,
          policyScheme: policyTag != null ? 'CPRE' : null,
          onProgress: (message) {
            setState(() {
              _loadingMessage = message;
            });
          },
        );
        
        AppLogger.log('Text post created successfully: ${postResult['postId']}');

        // 🆕 Prepare storage cost + contract proposal before upload
        setState(() {
          _loadingMessage = 'Calculating storage cost...';
        });
        final storageInfo = await PostService.preparePostUploadWithStorageCost(
          postResult: postResult,
          storeBaseUrl: selectedNode['endpoint'],
          appPublicKey: _userPublicKey!,
          storageNodePublicKey: selectedNode['publicKey'] ?? '',
          userMnemonic: _userMnemonic!,
          onProgress: (message) {
            setState(() {
              _loadingMessage = message;
            });
          },
        );
        if (storageInfo['success'] != true) {
          throw Exception(storageInfo['error'] ?? 'Failed to calculate storage cost');
        }

        setState(() {
          _loadingMessage = 'Awaiting fee confirmation...';
        });
        final confirmed = await _confirmStorageCostDialog(storageInfo);
        if (!confirmed) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload cancelled')),
          );
          return;
        }

        setState(() {
          _loadingMessage = 'Signing storage contract...';
        });
        final contractId = storageInfo['contractId'] as String? ?? '';
        if (contractId.isEmpty) {
          throw Exception('Missing contractId from storage proposal');
        }
        await _signStorageContract(
          storeBaseUrl: selectedNode['endpoint'],
          contractId: contractId,
        );

        // 🆕 Upload the text post to storage node
        setState(() {
          _loadingMessage = 'Uploading text post to storage...';
        });
        
        // 🆕 ZERO-KNOWLEDGE SHARING: Handle multiple metadata entries
        final metadataEntries = postResult['metadataEntries'] as List<Map<String, dynamic>>;
        final postBlocks = postResult['blocks'] as List<Map<String, dynamic>>;
        final postFileId = postResult['fileId'] as String;
        createdPostId = postResult['postId']?.toString();
        createdFileId = postFileId;
        createdNodeId = selectedNode['id']?.toString();
        createdShareType = _shareType;
        createdEncryptedType = _encryptedType;
        
        // Ensure contractId is embedded in metadata for store/blocker submission
        for (final entry in metadataEntries) {
          entry['contractId'] = contractId;
          entry['type'] ??= 'post';
          entry['shareType'] ??= _shareType;
        }

        // Upload metadata entries (one for each user with access)
        for (int i = 0; i < metadataEntries.length; i++) {
          final metadataEntry = metadataEntries[i];
          final metadataJson = json.encode(metadataEntry);
          
          AppLogger.log('🔍 DEBUG TEXT: Uploading metadata entry ${i + 1}: fileId=${metadataEntry['fileId']}, firstBlockId=${metadataEntry['firstBlockId']}');
          
          setState(() {
            _loadingMessage = 'Uploading text post metadata entry ${i + 1}/${metadataEntries.length}...';
          });
          
          final metadataUploadResult = await _uploadContent(
            nodeEndpoint: selectedNode['endpoint'],
            path: '/api/file/upload-metadata-raw',
            content: Uint8List.fromList(utf8.encode(metadataJson)),
            fileName: '${postFileId}_metadata_${i}.json',
            contentType: 'application/json',
            publicKey: _userPublicKey!,
            mnemonic: _userMnemonic!,
          );
          
          if (metadataUploadResult['success'] != true) {
            throw Exception('Failed to upload text post metadata entry ${i + 1}: ${metadataUploadResult['error']}');
          }
        }
        
        // 🔧 FIX: Upload blocks với fileId tương ứng với metadata entry (same as above)
        final ownerFileId = metadataEntries[0]['fileId'] as String; // Owner's fileId for content blocks
        
        // Separate metadata blocks (index 0) and content blocks (index > 0)
        final List<Map<String, dynamic>> metadataBlocks = [];
        final List<Map<String, dynamic>> contentBlocks = [];
        
        for (final block in postBlocks) {
          final blockIndex = block['blockIndex'] as int;
          final isMetadataBlock = block['isMetadataBlock'] as bool? ?? false;
          
          // Use both flags to be safe: isMetadataBlock OR blockIndex == 0
          if (isMetadataBlock || blockIndex == 0) {
            metadataBlocks.add(block);
          } else {
            contentBlocks.add(block);
          }
        }
        
        AppLogger.log('🔍 DEBUG TEXT: Separated ${metadataBlocks.length} metadata blocks, ${contentBlocks.length} content blocks');
        
        // 🔍 DEBUG: Print all blocks to see structure
        for (int i = 0; i < postBlocks.length; i++) {
          final block = postBlocks[i];
          AppLogger.log('🔍 DEBUG TEXT: Block $i - blockId: ${block['blockId']}, blockIndex: ${block['blockIndex']}, isMetadata: ${block['isMetadataBlock']}');
        }
        
        // Upload metadata blocks first (one for each user)
        for (int i = 0; i < metadataBlocks.length; i++) {
          final block = metadataBlocks[i];
          final blockId = block['blockId'] as String;
          final blockIndex = block['blockIndex'] as int; // Should be 0
          final encryptedContent = block['encryptedContent'] as Uint8List;
          
          // Find the corresponding metadata entry for this block
          Map<String, dynamic>? foundMetadata;
          try {
            foundMetadata = metadataEntries.firstWhere(
              (entry) => entry['firstBlockId'] == blockId,
            );
          } catch (e) {
            // For public posts or when no match found, use first entry
            AppLogger.log('🔍 DEBUG: No metadata found for blockId: $blockId, using first entry');
            foundMetadata = metadataEntries[0];
          }
          final fileIdForBlock = foundMetadata['fileId'] as String;
          
          setState(() {
            _loadingMessage = 'Uploading text metadata block ${i + 1}/${metadataBlocks.length}...';
          });
          
          AppLogger.log('🔍 DEBUG TEXT: Metadata block - blockId: $blockId, fileIdForBlock: $fileIdForBlock');
          AppLogger.log('🔍 DEBUG TEXT: correspondingMetadata: $foundMetadata');
          
          final blockUploadResult = await _uploadContent(
            nodeEndpoint: selectedNode['endpoint'],
            path: '/api/file/upload-file-block-raw',
            content: encryptedContent,
            fileName: blockId,
            contentType: 'application/octet-stream',
            publicKey: _userPublicKey!,
            mnemonic: _userMnemonic!,
            extraHeaders: {
              'X-Block-Id': blockId,
              'X-File-Id': fileIdForBlock, // Use respective user's fileId
              'X-Block-Index': blockIndex.toString(),
              if (contractId != null) 'X-Contract-Id': contractId, // 🆕 Pass ContractId
            },
          );
          
          if (blockUploadResult['success'] != true) {
            throw Exception('Failed to upload text metadata block $blockIndex: ${blockUploadResult['error']}');
          }
        }
        
        // Upload content blocks (shared among all users, use owner's fileId)
        for (int i = 0; i < contentBlocks.length; i++) {
          final block = contentBlocks[i];
          final blockId = block['blockId'] as String;
          final blockIndex = block['blockIndex'] as int; // Should be > 0
          final encryptedContent = block['encryptedContent'] as Uint8List;
          
          setState(() {
            _loadingMessage = 'Uploading text content block ${i + 1}/${contentBlocks.length}...';
          });
          
          AppLogger.log('🔍 DEBUG TEXT: Content block - blockId: $blockId, fileIdForBlock: $ownerFileId');
          
          final blockUploadResult = await _uploadContent(
            nodeEndpoint: selectedNode['endpoint'],
            path: '/api/file/upload-file-block-raw',
            content: encryptedContent,
            fileName: blockId,
            contentType: 'application/octet-stream',
            publicKey: _userPublicKey!,
            mnemonic: _userMnemonic!,
            extraHeaders: {
              'X-Block-Id': blockId,
              'X-File-Id': ownerFileId, // Always use owner's fileId for content blocks
              'X-Block-Index': blockIndex.toString(),
              if (contractId != null) 'X-Contract-Id': contractId, // 🆕 Pass ContractId
            },
          );
          
          if (blockUploadResult['success'] != true) {
            throw Exception('Failed to upload text content block $blockIndex: ${blockUploadResult['error']}');
          }
        }
        
        AppLogger.log('Text post uploaded successfully to storage node: $postFileId');

        // 🆕 PRE Option2: Generate & upload rekeys for current followers
        if (_shareType == 'followers' && _followersUsePre) {
          try {
            setState(() { _loadingMessage = 'Publishing PRE tag and uploading rekeys...'; });
            final pre = PreService();
            final tag = pre.buildPolicyTagForYear();
            final followerList = _followers.where((f) => f != _userPublicKey).toList();
            final results = await pre.generateAndUploadRekeys(
              apiBaseUrl: _apiBaseUrl,
              authorPubKey: _userPublicKey!,
              mnemonic: _userMnemonic!,
              followerPubKeys: followerList,
              tag: tag,
            );
            final okCount = results.values.where((v) => v).length;
            AppLogger.log('PRE rekeys uploaded: $okCount/${results.length}');
          } catch (e) {
            AppLogger.log('PRE rekeys upload error: $e');
          }
        }
      }
      
      if (!mounted) return;

      if (createdPostId != null && createdFileId != null && createdNodeId != null) {
        AppLogger.log('Post created; blockchain submission handled by Store node.');
      }
      
      // Show success message
      final String successMessage = _sharedWithPublicKeys.isNotEmpty
          ? 'Post created successfully! Files shared with ${_sharedWithPublicKeys.length} additional users.'
          : 'Post created successfully!';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
          duration: Duration(seconds: _sharedWithPublicKeys.isNotEmpty ? 4 : 2),
        ),
      );
      
      // Return to home screen
      context.go(AppRoutes.localUserHome, extra: userProfile);
    } catch (e) {
      AppLogger.log('Error creating post: $e');
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create post: ${e.toString()}'),
          backgroundColor: DeltaniumTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Helper methods for file uploads
  
  // Fetch available store nodes
  Future<List<Map<String, dynamic>>> _fetchStoreNodes() async {
    try {
        AppLogger.log('DEBUG: Making HTTP request to: $_apiBaseUrl/storenode/list');
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/storenode/list'),
      );
      
      AppLogger.log('DEBUG: Response status code: ${response.statusCode}');
      AppLogger.log('DEBUG: Response body: ${response.body}');
      
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch store nodes: ${response.statusCode}');
      }
      
      final List<dynamic> nodesJson = json.decode(response.body);
      return nodesJson.map((node) => Map<String, dynamic>.from(node)).toList();
    } catch (e) {
      AppLogger.log('DEBUG: Error in _fetchStoreNodes: $e');
      // For demo purposes, return a mock node if API fails
      return [
        {
          'id': 'mock-node-1',
          'publicKey': 'mock-public-key',
          'endpoint': 'http://localhost:5001',
        }
      ];
    }
  }
  
  // Select a node from available nodes (random selection for now)
  Map<String, dynamic> _selectNode(List<Map<String, dynamic>> nodes) {
    // Simple random selection - could be improved with node health checks, etc.
    final random = Random();
    return nodes[random.nextInt(nodes.length)];
  }
  
  // Upload media to a storage node
  Future<Map<String, dynamic>> _uploadMediaToNode({
    required Map<String, dynamic> media,
    required Map<String, dynamic> node,
    required String publicKey,
    required String mnemonic,
    Function(String)? onProgress, // Progress callback
  }) async {
    final String fileName = (media['name'] as String?) ?? 'file.dat';
    
    try {
      // Step 1: Prepare file data
      late Uint8List fileBytes;
      if (kIsWeb && media.containsKey('bytes')) {
        final bytes = media['bytes'] as List<int>;
        fileBytes = Uint8List.fromList(bytes);
      } else if (!kIsWeb && media.containsKey('path')) {
        final path = media['path'] as String;
        fileBytes = await File(path).readAsBytes();
      } else {
        throw Exception('Cannot read file bytes');
      }
      
      AppLogger.log('Uploading file: $fileName (${fileBytes.length} bytes) using FileUploadService');
      
      // Use proper FileUploadService to handle encryption and splitting
      AppLogger.log('CreatePost: Using FileUploadService for proper file splitting and encryption');
      
      final fileUploadService = FileUploadService();
      
      // Determine PRE policy for followers
      final String? mediaPolicyTag = (_shareType == 'followers' && _followersUsePre)
          ? 'followers:${DateTime.now().year}'
          : null;
      final String? mediaCapsuleFor = mediaPolicyTag != null ? 'tag' : null;
      final String? mediaPolicyScheme = mediaPolicyTag != null ? 'CPRE' : null;
      
      final uploadResult = await fileUploadService.uploadEncryptedFile(
            fileData: fileBytes,
            fileName: fileName,
            publicKey: publicKey,
            mnemonic: mnemonic,
            sharedWithUsers: _sharedWithPublicKeys.isNotEmpty ? _sharedWithPublicKeys : null, // Share with selected users
            selectedNode: node,
            onProgress: onProgress, // Pass progress callback
            fileType: 'file', // 🆕 Regular files get type='file' (vs posts get type='post')
            shareType: _shareType,
            policyTag: mediaPolicyTag,
            capsuleFor: mediaCapsuleFor,
            policyScheme: mediaPolicyScheme,
          );
      
      if (uploadResult['success'] != true) {
        throw Exception('FileUploadService failed: ${uploadResult['error']}');
      }

      if (uploadResult['blockchainSubmitted'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Metadata uploaded, but blockchain submission failed. Will retry in background.'),
          ),
        );
      }
      
      AppLogger.log('CreatePost: File uploaded successfully with ${uploadResult['blockCount']} blocks');
      
      return {
        'fileId': uploadResult['fileId'],
        'fileName': uploadResult['fileName'],
        'fileSize': uploadResult['fileSize'],
        'url': uploadResult['url'],
        'blockCount': uploadResult['blockCount'],
        'encryptedKey': uploadResult['encryptedKey'], // 🆕 Add encryptedKey from upload result
      };
    } catch (e) {
      AppLogger.log('Error in file upload: $e');
      rethrow;
    }
  }
  
  // Helper method to handle the common upload logic
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
      final mnemonicToUse = _userMnemonic;
      if (mnemonicToUse == null) {
        throw Exception('No user credentials available for signing');
      }

      final uri = Uri.parse('$nodeEndpoint$path');
      AppLogger.log('DEBUG: Creating request to $uri');

      // Calculate content hash for signing - use SHA256 as in C# demo
      final digest = await CryptoService.hashSHA256(content);
      final bodyHash = base64.encode(digest);
      AppLogger.log('DEBUG: Raw content bytes length: ${content.length}');
      AppLogger.log('DEBUG: Content hash (base64): ${bodyHash}');

      // Generate signature components - format exactly like C# RequestSigner
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'POST'; // Must be uppercase
      final pathForSigning = Uri.parse(path).path;
      final buffer = StringBuffer();
      buffer.write(method);
      buffer.write(pathForSigning);
      buffer.write(timestamp);
      buffer.write(bodyHash);
      final dataToSign = buffer.toString();
      AppLogger.log('DEBUG: Data being signed: ${dataToSign}');
      AppLogger.log('DEBUG: Data bytes length: ${utf8.encode(dataToSign).length}');

      // Generate a key pair from mnemonic
      final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonicToUse);
      String signature;
      try {
        signature = await CryptoService.sign(dataToSign, kIsWeb ? mnemonicToUse : keyPair);
        AppLogger.log('DEBUG: Generated signature: ${signature}');
      } catch (e) {
        AppLogger.log('DEBUG: Error during signing: ${e}');
        rethrow;
      }

      // Use http.Request for raw body (not multipart)
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

      AppLogger.log('DEBUG: Request headers:');
      request.headers.forEach((key, value) {
        AppLogger.log('  ${key}: ${value}');
      });

      AppLogger.log('DEBUG: Sending request...');
      final response = await request.send();
      final resp = await http.Response.fromStream(response);

      AppLogger.log('DEBUG: Response status: ${resp.statusCode}');
      AppLogger.log('DEBUG: Response body: ${resp.body}');

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
      AppLogger.log('DEBUG: Exception in _uploadContent: ${e}');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  

  // Register the file with the central API
  Future<void> _registerFileWithAPI({
    required String fileId,
    required String fileName,
    required String fileType,
    required String nodeId,
    required String publicKey,
  }) async {
    try {
      // 🔧 FIX: Normalize to compressed format for API consistency
      final normalizedPublicKey = CryptoService.convertToCompressedPublicKey(publicKey);
      
      final storedFileData = {
        'fileId': fileId,
        'ownerPublicKey': normalizedPublicKey, // Use compressed format
        'storeNodeId': nodeId,
        'fileName': fileName,
        'fileType': fileType,
        'fileSize': 0, // Size would be available from upload response
        'createdAt': DateTime.now().toIso8601String(),
      };
      
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/storedfile/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(storedFileData),
      );
      
      if (response.statusCode != 200) {
        AppLogger.log('Warning: Failed to register file with API: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('Warning: Error registering file: $e');
      // Non-fatal error - file is already on the store node
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final userProfile = widget.userProfile;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 700;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go(AppRoutes.localUserHome, extra: userProfile),
        ),
        title: Text(
          'Deltanium',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _createPost,
              style: ElevatedButton.styleFrom(
                shape: const StadiumBorder(),
                backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                foregroundColor: DeltaniumTheme.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Post', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 520 : double.infinity,
                ),
                child: Card(
                  elevation: 4,
                  margin: EdgeInsets.symmetric(vertical: 32, horizontal: isDesktop ? 0 : 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row: Avatar + Input + Post button
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(
                              radius: 24,
                              backgroundImage: AssetImage('assets/images/avatar_placeholder.png'),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                focusNode: _focusNode,
                                maxLines: null,
                                decoration: const InputDecoration(
                                  hintText: "What's happening?",
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_selectedMedia.isNotEmpty) _buildMediaPreview(),
                        const SizedBox(height: 12),
                        _buildShareTypeOptions(),
                        const SizedBox(height: 8),
                        
                        const SizedBox(height: 8),
                        _buildBottomToolbar(isDarkMode),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _loadingMessage,
                          style: const TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildMediaPreview() {
    if (_selectedMedia.length == 1) {
      return _buildSingleMediaPreview();
    } else {
      return _buildGridMediaPreview();
    }
  }
  
  Widget _buildSingleMediaPreview() {
    final mediaItem = _selectedMedia.first;
    
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildMediaItem(mediaItem, 200, double.infinity),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: _buildRemoveMediaButton(0),
        ),
      ],
    );
  }
  
  Widget _buildGridMediaPreview() {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final crossAxisCount = isDesktop ? 4 : 2;
    final itemSize = isDesktop ? 120.0 : 160.0;
    final spacing = isDesktop ? 16.0 : 12.0;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: 0.85,
      ),
      itemCount: _selectedMedia.length,
      itemBuilder: (context, index) {
        final mediaItem = _selectedMedia[index];
        return _MediaCard(
          mediaItem: mediaItem,
          size: itemSize,
          onRemove: () => _removeMedia(index),
        );
      },
    );
  }
  
  Widget _buildMediaItem(Map<String, dynamic> mediaItem, double height, double width) {
    final bool isLocal = mediaItem['isLocal'] ?? false;
    
    if (mediaItem['type'] == 'image') {
      if (isLocal) {
        // For web platform
        if (kIsWeb) {
          if (mediaItem.containsKey('previewUrl')) {
            // Use the preview URL directly for web images
            return Image.network(
              mediaItem['previewUrl'],
              fit: BoxFit.cover,
              height: height,
              width: width,
              errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
            );
          } else if (mediaItem.containsKey('bytes')) {
            // If we have the bytes, use them directly
            return Image.memory(
              mediaItem['bytes'],
              fit: BoxFit.cover,
              height: height,
              width: width,
              errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
            );
          } else {
            return _buildImagePreviewPlaceholder();
          }
        } else {
          // For mobile platforms - need path
          if (mediaItem.containsKey('path')) {
            return Image.file(
              File(mediaItem['path']),
              fit: BoxFit.cover,
              height: height,
              width: width,
              errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
            );
          } else {
            return _buildErrorPlaceholder();
          }
        }
      } else {
        // Remote image - both platforms can use network image
        final path = mediaItem['previewUrl'] ?? mediaItem['path'];
        if (path != null) {
          return Image.network(
            path,
            fit: BoxFit.cover,
            height: height,
            width: width,
            errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
          );
        } else {
          return _buildErrorPlaceholder();
        }
      }
    } else if (mediaItem['type'] == 'file') {
      // Check if it's an image file we can preview
      if (mediaItem.containsKey('previewUrl') && 
          mediaItem.containsKey('extension') &&
          ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(
            (mediaItem['extension'] as String).toLowerCase())) {
        // Show image preview for image files
        return Stack(
          children: [
            Image.network(
              mediaItem['previewUrl'],
                fit: BoxFit.cover,
              height: height,
              width: width,
              errorBuilder: (c, e, s) => _buildFileIcon(mediaItem, height, width),
              ),
            // Overlay indicating it's a file
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.file_present,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        );
      } else {
        // Regular file display
        return _buildFileIcon(mediaItem, height, width);
      }
    } else {
      return _buildErrorPlaceholder();
    }
  }
  
  Widget _buildFileIcon(Map<String, dynamic> mediaItem, double height, double width) {
    // Get file icon based on extension
    IconData fileIcon = Icons.insert_drive_file;
    Color iconColor = Colors.grey[600]!;
    
    if (mediaItem.containsKey('extension')) {
      final ext = (mediaItem['extension'] as String).toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
        fileIcon = Icons.image;
        iconColor = Colors.blue[400]!;
      } else if (['pdf'].contains(ext)) {
        fileIcon = Icons.picture_as_pdf;
        iconColor = Colors.red[400]!;
      } else if (['doc', 'docx'].contains(ext)) {
        fileIcon = Icons.description;
        iconColor = Colors.blue[700]!;
      } else if (['xls', 'xlsx'].contains(ext)) {
        fileIcon = Icons.table_chart;
        iconColor = Colors.green[700]!;
      } else if (['mp3', 'wav', 'ogg'].contains(ext)) {
        fileIcon = Icons.audio_file;
        iconColor = Colors.purple[400]!;
      } else if (['mp4', 'mov', 'avi', 'webm'].contains(ext)) {
        fileIcon = Icons.video_file;
        iconColor = Colors.red[700]!;
      } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
        fileIcon = Icons.folder_zip;
        iconColor = Colors.amber[700]!;
      } else if (['txt', 'csv'].contains(ext)) {
        fileIcon = Icons.text_snippet;
        iconColor = Colors.blueGrey[600]!;
      }
    }
    
    // Calculate file size for display
    String fileSize = '';
    if (mediaItem.containsKey('size')) {
      final size = mediaItem['size'] as int;
      if (size < 1024) {
        fileSize = '$size B';
      } else if (size < 1024 * 1024) {
        fileSize = '${(size / 1024).toStringAsFixed(1)} KB';
      } else {
        fileSize = '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    }
    
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            fileIcon,
            size: 40,
            color: iconColor,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              mediaItem['name'] ?? 'File',
              style: TextStyle(
                color: Colors.grey[800],
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (fileSize.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              fileSize,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildErrorPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(
          Icons.broken_image,
          color: Colors.grey,
          size: 40,
        ),
      ),
    );
  }
  
  Widget _buildRemoveMediaButton(int index) {
    return GestureDetector(
      onTap: () => _removeMedia(index),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(4),
        child: const Icon(
          Icons.close,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }
  
  Widget _buildBottomToolbar(bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDarkMode 
                ? DeltaniumTheme.darkDividerColor 
                : DeltaniumTheme.lightDividerColor,
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image_outlined),
              color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              onPressed: _addMedia,
            ),
            // 🔧 FIX: Always show share button for both posts and media
            IconButton(
              icon: Icon(
                _sharedWithPublicKeys.isNotEmpty ? Icons.share : Icons.share_outlined,
                color: _sharedWithPublicKeys.isNotEmpty 
                    ? (isDarkMode ? Colors.green[300] : Colors.green[700])
                    : (isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown),
              ),
              onPressed: _toggleShareSection,
              tooltip: _selectedMedia.isNotEmpty ? 'Share files with others' : 'Share post with others',
            ),
            IconButton(
              icon: const Icon(Icons.gif_box_outlined),
              color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.ballot_outlined),
              color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined),
              color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.schedule_outlined),
              color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.place_outlined),
              color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              onPressed: () {},
            ),
            
            const Spacer(),
            
            // Character counter
            Builder(
              builder: (context) {
                final count = _textController.text.length;
                final remainingCount = 280 - count;
                final color = remainingCount < 0 
                    ? DeltaniumTheme.errorColor 
                    : remainingCount < 20 
                        ? DeltaniumTheme.warningColor 
                        : isDarkMode 
                            ? DeltaniumTheme.darkTextSecondaryColor 
                            : DeltaniumTheme.lightTextSecondaryColor;
                
                return Text(
                  remainingCount < 20 ? remainingCount.toString() : '',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildImagePreviewPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(
          Icons.image,
          color: Colors.grey,
          size: 40,
        ),
      ),
    );
  }
  
  

  

  

  Widget _buildShareTypeOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chia sẻ với:', style: TextStyle(fontWeight: FontWeight.bold)),
        Row(
          children: [
            Radio<String>(
              value: 'me',
              groupValue: _shareType,
              onChanged: (val) {
                setState(() {
                  _shareType = val!;
                  _encryptedType = 'encrypted';
                });
              },
            ),
            const Text('Chỉ mình tôi'),
            Radio<String>(
              value: 'followers',
              groupValue: _shareType,
              onChanged: (val) async {
                setState(() {
                  _shareType = val!;
                  _isLoadingFollowers = true;
                  _encryptedType = 'encrypted';
                  _followersUsePre = true;
                });
                final followers = await _fetchFollowers();
                AppLogger.log('DEBUG: Followers fetched:');
                for (var f in followers) {
                  AppLogger.log('  Follower: ' + f);
                }
                setState(() {
                  _followers = followers;
                  _isLoadingFollowers = false;
                });
              },
            ),
            const Text('Follower'),
            Radio<String>(
              value: 'public',
              groupValue: _shareType,
              onChanged: (val) {
                setState(() {
                  _shareType = val!;
                  _encryptedType = 'public';
                  _showShareSection = false;
                });
              },
            ),
            const Text('Public'),
          ],
        ),
        if (_shareType == 'followers' && _isLoadingFollowers)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Đang tải danh sách follower...'),
              ],
            ),
          ),
        if (_shareType == 'followers' && !_isLoadingFollowers)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 4, bottom: 4),
            child: _followers.isEmpty
                ? Text('Bạn chưa có follower nào. Chỉ những người đang theo dõi bạn tại thời điểm đăng bài mới xem được bài này.', style: TextStyle(color: Colors.orange, fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Số follower: ${_followers.length}', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      ..._followers.take(5).map((pubkey) => Row(
                        children: [
                          const CircleAvatar(radius: 12, backgroundImage: NetworkImage('https://api.dicebear.com/7.x/identicon/svg?seed=')),
                          const SizedBox(width: 8),
                          Text(pubkey.length > 16 ? pubkey.substring(0, 8) + '...' + pubkey.substring(pubkey.length - 6) : pubkey, style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ],
                      )),
                      if (_followers.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('+${_followers.length - 5} follower khác...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }

  Future<List<String>> _fetchFollowers() async {
    if (_userPublicKey == null || _userMnemonic == null) return [];
    // apiBaseUrl đã bao gồm '/api', nên URL phải là '<base>/user/followers'
    // nhưng phần ký phải dùng đường dẫn đầy đủ '/api/user/followers' để khớp backend
    final pathForUrl = '/user/followers';
    final pathForSign = '/api/user/followers';
    final url = '$_apiBaseUrl$pathForUrl';
    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    final method = 'GET';
    final bodyHash = '';
    final dataToSign = '$method$pathForSign$timestamp$bodyHash';
    String signature;
    try {
      signature = await CryptoService.sign(dataToSign, _userMnemonic!);
    } catch (e) {
      AppLogger.log('Error signing for followers: $e');
      return [];
    }
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-User-PubKey': _userPublicKey!,
          'X-Timestamp': timestamp,
          'X-Signature': signature,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('users')) {
          final users = data['users'] as List<dynamic>;
          return users.map((u) => u['publicKey'] as String).toList();
        }
      }
      AppLogger.log('Followers API error: ${response.statusCode} - ${response.body}');
      return [];
    } catch (e) {
      AppLogger.log('Error fetching followers: $e');
      return [];
    }
  }
}

class _MediaCard extends StatefulWidget {
  final Map<String, dynamic> mediaItem;
  final double size;
  final VoidCallback onRemove;
  const _MediaCard({required this.mediaItem, required this.size, required this.onRemove});

  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = widget.mediaItem['type'] == 'image' ||
        (widget.mediaItem['type'] == 'file' &&
            ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp']
                .contains((widget.mediaItem['extension'] ?? '').toLowerCase()));
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (_hovering)
              BoxShadow(
                color: theme.primaryColor.withOpacity(0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
          border: Border.all(
            color: _hovering
                ? theme.primaryColor.withOpacity(0.5)
                : theme.dividerColor.withOpacity(0.2),
            width: 1.2,
          ),
        ),
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            // Media preview
            Center(
              child: SizedBox(
                width: widget.size - 24,
                height: widget.size - 36,
                child: isImage
                    ? _buildMediaPreview(widget.mediaItem)
                    : _buildFileIcon(widget.mediaItem),
              ),
            ),
            // Remove button (show on hover or always on mobile)
            Positioned(
              top: 6,
              right: 6,
              child: AnimatedOpacity(
                opacity: _hovering || Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS ? 1 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: widget.onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 18, color: Colors.black54),
                    ),
                  ),
                ),
              ),
            ),
            // File name and size
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.mediaItem['name'] ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    if (widget.mediaItem['size'] != null)
                      Text(
                        _formatFileSize(widget.mediaItem['size']),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.hintColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview(Map<String, dynamic> mediaItem) {
    if (mediaItem['previewUrl'] != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          mediaItem['previewUrl'],
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => _buildFileIcon(mediaItem),
        ),
      );
    } else if (mediaItem['bytes'] != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          mediaItem['bytes'],
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => _buildFileIcon(mediaItem),
        ),
      );
    }
    return _buildFileIcon(mediaItem);
  }

  Widget _buildFileIcon(Map<String, dynamic> mediaItem, [double? size]) {
    IconData fileIcon = Icons.insert_drive_file;
    Color iconColor = Colors.grey[600]!;
    final ext = (mediaItem['extension'] ?? '').toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      fileIcon = Icons.image;
      iconColor = Colors.blue[400]!;
    } else if (['pdf'].contains(ext)) {
      fileIcon = Icons.picture_as_pdf;
      iconColor = Colors.red[400]!;
    } else if (['doc', 'docx'].contains(ext)) {
      fileIcon = Icons.description;
      iconColor = Colors.blue[700]!;
    } else if (['xls', 'xlsx'].contains(ext)) {
      fileIcon = Icons.table_chart;
      iconColor = Colors.green[700]!;
    } else if (['mp3', 'wav', 'ogg'].contains(ext)) {
      fileIcon = Icons.audio_file;
      iconColor = Colors.purple[400]!;
    } else if (['mp4', 'mov', 'avi', 'webm'].contains(ext)) {
      fileIcon = Icons.video_file;
      iconColor = Colors.red[700]!;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      fileIcon = Icons.folder_zip;
      iconColor = Colors.amber[700]!;
    } else if (['txt', 'csv'].contains(ext)) {
      fileIcon = Icons.text_snippet;
      iconColor = Colors.blueGrey[600]!;
    }
    return Icon(fileIcon, size: size ?? 40, color: iconColor);
  }

  String _formatFileSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
} 
