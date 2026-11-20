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
import 'package:http/http.dart' as http;
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/features/file_manager/file_upload_service.dart';
import 'package:deltanium_app/services/post_service.dart';
import 'package:deltanium_app/services/pre_service.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/widgets/confirm_storage_cost_dialog.dart';
import 'package:deltanium_app/services/storage_contract_service.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:deltanium_app/services/pre_ffi.dart';
import 'package:deltanium_app/features/create_post/post_publisher.dart';
import 'package:deltanium_app/services/pre_keys.dart';

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
  // Web: followers posts need Umbral PRE (dart:ffi) — not available yet.
  String _shareType = PreFfi.isSupported ? 'followers' : 'public';
  // Option 2 PRE-tag (native only). Web must not create followers posts for now.
  bool _followersUsePre = true;
  // TOKENOMICS_V2 §9: subscribers-only posts use the `subscribers:YYYY-MM` PRE tag.
  bool _subscribersOnly = false;
  // PRE v2 (per-tag author keys, monthly tags): see PreKeys.
  String get _preTag => _subscribersOnly ? PreKeys.subscribersTag() : PreKeys.followersTag();
  
  List<String> _followers = [];
  bool _isLoadingFollowers = false;
  String _encryptedType = PreFfi.isSupported ? 'encrypted' : 'public';
  
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

  Future<void> _createPost() async {
    final userProfile = widget.userProfile;
    if (_shareType == 'followers' && !PreFfi.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Creating followers posts is not available on web yet. Use Public or Me, or the native app.'),
          backgroundColor: DeltaniumTheme.errorColor,
        ),
      );
      return;
    }
    if (_textController.text.trim().isEmpty && _selectedMedia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your post cannot be empty'), backgroundColor: DeltaniumTheme.errorColor),
      );
      return;
    }
    if (_userPublicKey == null || _userMnemonic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to create post: User authentication missing'),
          backgroundColor: DeltaniumTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final me = _userPublicKey!;
      final usePre = _shareType == 'followers' && _followersUsePre;
      // PRE: one metadata entry for the author, followers get re-encryption keys. Without PRE: one per follower.
      final recipients = _shareType == 'followers' && !usePre
          ? [me, ..._followers.where((f) => f != me)]
          : [me];
      // Re-encryption keys include the author (rk A->A) so the author also reads PRE posts in Following.
      final rekeyFor = !usePre
          ? <String>[]
          : <String>{me, ...(_subscribersOnly ? await WalletService.getSubscribers() : _followers)}.toList();

      final media = <PostMediaInput>[];
      for (final m in _selectedMedia) {
        final Uint8List bytes;
        if (kIsWeb && m.containsKey('bytes')) {
          bytes = Uint8List.fromList(m['bytes'] as List<int>);
        } else if (!kIsWeb && m.containsKey('path')) {
          bytes = await File(m['path'] as String).readAsBytes();
        } else {
          AppLogger.log('Skipping attachment without bytes: ${m['name']}');
          continue;
        }
        media.add(PostMediaInput(
          bytes: bytes,
          name: (m['name'] as String?) ?? 'file.dat',
          type: (m['type'] as String?) ?? 'file',
          extension: (m['extension'] as String?) ?? 'unknown',
        ));
      }

      final publisher = PostPublisher(
        publicKey: me,
        mnemonic: _userMnemonic!,
        confirmStorage: _confirmStorageCostDialog,
        onProgress: (message) {
          if (mounted) setState(() => _loadingMessage = message);
        },
        onWarning: (message) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        },
      );
      await publisher.publish(PostPublishRequest(
        text: _textController.text,
        media: media,
        shareType: _shareType,
        encryptedType: _encryptedType,
        recipients: recipients,
        sharedWithPublicKeys: _sharedWithPublicKeys,
        preTag: usePre ? _preTag : null,
        rekeyFor: rekeyFor,
        authorName: userProfile?.fullName,
        tags: _extractTags(_textController.text),
      ));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_sharedWithPublicKeys.isNotEmpty
              ? 'Post created successfully! Files shared with ${_sharedWithPublicKeys.length} additional users.'
              : 'Post created successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: _sharedWithPublicKeys.isNotEmpty ? 4 : 2),
        ),
      );
      context.go(AppRoutes.localUserHome, extra: userProfile);
    } on PostPublishCancelled {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload cancelled')));
    } catch (e) {
      AppLogger.log('Error creating post: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create post: ${e.toString()}'), backgroundColor: DeltaniumTheme.errorColor),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
        Text(tr('share.with'), style: const TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Each choice keeps its radio and label together when the row wraps on a narrow screen.
            Row(mainAxisSize: MainAxisSize.min, children: [
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
            Text(tr('share.me')),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
            Radio<String>(
              value: 'followers',
              groupValue: _shareType,
              onChanged: !PreFfi.isSupported
                  ? null
                  : (val) async {
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
            Text(
              tr('share.followers'),
              style: TextStyle(
                color: PreFfi.isSupported ? null : Colors.grey,
              ),
            ),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
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
            Text(tr('share.public')),
            ]),
          ],
        ),
        if (!PreFfi.isSupported)
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 4, bottom: 4),
            child: Text(
              tr('share.followersWebNote'),
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ),
        if (_shareType == 'followers' && PreFfi.isSupported)
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 8),
            value: _subscribersOnly,
            onChanged: (v) => setState(() => _subscribersOnly = v ?? false),
            title: Text(tr('share.subscribersOnly')),
            subtitle: Text(tr('share.subscribersOnlyNote', {'tag': PreKeys.subscribersTag()})),
          ),
        if (_shareType == 'followers' && _isLoadingFollowers)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text(tr('share.loadingFollowers')),
              ],
            ),
          ),
        if (_shareType == 'followers' && !_isLoadingFollowers)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 4, bottom: 4),
            child: _followers.isEmpty
                ? Text(tr('share.noFollowers'), style: const TextStyle(color: Colors.orange, fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('share.followerCount', {'n': '${_followers.length}'}), style: const TextStyle(fontWeight: FontWeight.w500)),
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
                          child: Text(tr('share.moreFollowers', {'n': '${_followers.length - 5}'}), style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
