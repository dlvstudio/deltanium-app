import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/services/comment_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/features/feed/widgets/related_files_widget.dart';
import 'package:deltanium_app/widgets/confirm_storage_cost_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;

class PostCommentsSection extends StatefulWidget {
  final PostMetadata post;
  final String nodeEndpoint;
  final bool isDarkMode;
  final String? userPublicKey;
  final String? userMnemonic;

  const PostCommentsSection({
    Key? key,
    required this.post,
    required this.nodeEndpoint,
    required this.isDarkMode,
    this.userPublicKey,
    this.userMnemonic,
  }) : super(key: key);

  @override
  State<PostCommentsSection> createState() => _PostCommentsSectionState();
}

class _PostCommentsSectionState extends State<PostCommentsSection> {
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = false;
  bool _isExpanded = false;
  final TextEditingController _commentController = TextEditingController();
  bool _isPosting = false;
  String? _postingProgressMessage; // 🆕 Progress message for posting
  String _selectedShareType = 'author'; // 'author' or 'public'
  final ImagePicker _imagePicker = ImagePicker(); // 🆕 Image picker
  List<Map<String, dynamic>> _selectedMedia = []; // 🆕 Selected images
  final Map<String, bool> _imageDownloadStatus = {}; // 🆕 Track image download status
  StateSetter? _modalStateSetter; // 🆕 Store modal state setter for rebuilding

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    if (widget.userPublicKey == null || widget.userMnemonic == null) {
      return;
    }
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      AppLogger.log('PostCommentsSection: Loading comments for post ${widget.post.fileId}');
      final comments = await CommentService.getComments(
        postFileId: widget.post.fileId,
        nodeEndpoint: widget.nodeEndpoint,
        userPublicKey: widget.userPublicKey!,
        userMnemonic: widget.userMnemonic!,
      );

      AppLogger.log('PostCommentsSection: Received ${comments?.length ?? 0} comments from API');

      if (comments != null && mounted) {
        // Decrypt and load comment content
        // Use a Set to deduplicate comments by FileId (since encrypted comments may have multiple metadata entries)
        final seenFileIds = <String>{};
        final decryptedComments = <Map<String, dynamic>>[];
        
        for (final comment in comments) {
          try {
            final fileId = comment['FileId'] as String? ?? comment['fileId'] as String;
            if (fileId == null || seenFileIds.contains(fileId)) {
              // Skip duplicates
              continue;
            }
            seenFileIds.add(fileId);
            
            final commentContent = await _loadCommentContent(comment);
            if (commentContent != null) {
              // 🆕 Determine if comment is public for tag display
              final commentIsPublic = comment['IsPublic'] == true || 
                                      comment['isPublic'] == true || 
                                      (comment['EncryptedType'] as String? ?? '').toLowerCase() == 'public' ||
                                      (comment['encryptedType'] as String? ?? '').toLowerCase() == 'public' ||
                                      (comment['ShareType'] as String? ?? '').toLowerCase() == 'public' ||
                                      (comment['shareType'] as String? ?? '').toLowerCase() == 'public';
              
              decryptedComments.add({
                ...comment,
                'text': commentContent['text'],
                'commenterPublicKey': commentContent['commenterPublicKey'],
                'createdAt': commentContent['createdAt'],
                'relatedFiles': commentContent['relatedFiles'], // 🆕 Add relatedFiles
                'isPublic': commentIsPublic, // 🆕 Add isPublic flag for tag display
                'shareType': commentIsPublic ? 'public' : 'author', // 🆕 Add shareType for tag display
              });
              AppLogger.log('PostCommentsSection: Successfully loaded comment $fileId');
            } else {
              AppLogger.log('PostCommentsSection: Failed to load content for comment $fileId');
            }
          } catch (e) {
            final fileId = comment['FileId'] as String? ?? comment['fileId'] as String ?? 'unknown';
            AppLogger.log('PostCommentsSection: Error loading comment $fileId: $e');
          }
        }
        
        AppLogger.log('PostCommentsSection: Loaded ${decryptedComments.length} comments (deduplicated from ${comments.length} metadata entries)');
        
        setState(() {
          _comments = decryptedComments;
          _isLoading = false;
        });
      } else if (mounted) {
        AppLogger.log('PostCommentsSection: No comments data returned');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.log('PostCommentsSection: Error loading comments: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Load comments with retry logic (useful after posting a new comment)
  Future<void> _loadCommentsWithRetry({int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      if (i > 0) {
        // Wait before retry
        await Future.delayed(Duration(milliseconds: 500 * i));
      }
      
      final previousCount = _comments.length;
      await _loadComments();
      
      // If we got more comments, we're done
      if (_comments.length > previousCount) {
        AppLogger.log('PostCommentsSection: Successfully loaded new comments after ${i + 1} attempt(s)');
        return;
      }
    }
    
    // Final attempt - just reload normally
    await _loadComments();
  }

  Future<Map<String, dynamic>?> _loadCommentContent(Map<String, dynamic> comment) async {
    try {
      // Handle both PascalCase (from backend) and camelCase
      final isPublic = comment['IsPublic'] == true || comment['isPublic'] == true || 
                       comment['EncryptedType'] == 'public' || comment['encryptedType'] == 'public';
      final firstBlockId = comment['FirstBlockId'] as String? ?? comment['firstBlockId'] as String?;
      final fileId = comment['FileId'] as String? ?? comment['fileId'] as String;

      if (firstBlockId == null || firstBlockId.isEmpty) {
        return null;
      }

      // Get block 0 (comment content)
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final blockPath = '/api/file/block/$fileId/0';
      final bodyHash = '';
      final dataToSign = '$method$blockPath$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, widget.userMnemonic!);

      final response = await http.get(
        Uri.parse('${widget.nodeEndpoint}$blockPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(widget.userPublicKey!),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );

      if (response.statusCode != 200) {
        return null;
      }

      if (isPublic) {
        // Public comment - plaintext
        final content = json.decode(utf8.decode(response.bodyBytes));
        return Map<String, dynamic>.from(content);
      } else {
        // Encrypted comment - decrypt
        // Handle both PascalCase (from backend) and camelCase
        final encryptedKeyBase64 = comment['EncryptedKey'] as String? ?? comment['encryptedKey'] as String?;
        AppLogger.log('PostCommentsSection: Loading encrypted comment $fileId, EncryptedKey type: ${encryptedKeyBase64.runtimeType}, length: ${encryptedKeyBase64?.length ?? 0}');
        
        if (encryptedKeyBase64 == null || encryptedKeyBase64.isEmpty) {
          AppLogger.log('PostCommentsSection: Missing EncryptedKey for comment $fileId. Comment keys: ${comment.keys.toList()}');
          return null;
        }

        try {
          // Step 1: Decrypt symmetric key
          final encryptedKey = base64Decode(encryptedKeyBase64);
          AppLogger.log('PostCommentsSection: Decoded EncryptedKey, length: ${encryptedKey.length}');
          
          final symmetricKey = await FileCryptoService.decryptSymmetricKeyWithPrivateKey(
            encryptedKey,
            widget.userMnemonic!,
          );
          AppLogger.log('PostCommentsSection: Decrypted symmetric key, length: ${symmetricKey.length}');

          // Step 2: Decrypt block 0 (metadata block) to get contentBlockIds
          final encryptedMetadata = response.bodyBytes;
          AppLogger.log('PostCommentsSection: Encrypted metadata block length: ${encryptedMetadata.length}');
          
          final decryptedMetadata = await FileCryptoService.testDecryptData(
            encryptedMetadata,
            symmetricKey,
          );
          AppLogger.log('PostCommentsSection: Decrypted metadata length: ${decryptedMetadata.length}');

          final metadataJson = json.decode(utf8.decode(decryptedMetadata));
          AppLogger.log('PostCommentsSection: Metadata keys: ${metadataJson.keys.toList()}');
          
          // Step 3: Get contentBlockIds from metadata
          final contentBlockIds = metadataJson['contentBlockIds'] as List<dynamic>? ?? [];
          if (contentBlockIds.isEmpty) {
            AppLogger.log('PostCommentsSection: No contentBlockIds found in metadata');
            return null;
          }
          
          // Step 4: Download and decrypt content block (block 1, index 0 in contentBlockIds)
          final contentBlockId = contentBlockIds[0] as String;
          AppLogger.log('PostCommentsSection: Downloading content block: $contentBlockId');
          
          final contentTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          final contentMethod = 'GET';
          final contentBlockPath = '/api/file/block/$contentBlockId'; // Use blockId directly
          final contentBodyHash = '';
          final contentDataToSign = '$contentMethod$contentBlockPath$contentTimestamp$contentBodyHash';
          final contentSignature = await CryptoService.sign(contentDataToSign, widget.userMnemonic!);

          final contentResponse = await http.get(
            Uri.parse('${widget.nodeEndpoint}$contentBlockPath'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(widget.userPublicKey!),
              'X-Timestamp': contentTimestamp,
              'X-Signature': contentSignature,
            },
          );

          if (contentResponse.statusCode != 200) {
            AppLogger.log('PostCommentsSection: Failed to download content block: ${contentResponse.statusCode}');
            return null;
          }

          // Step 5: Decrypt content block
          final encryptedContent = contentResponse.bodyBytes;
          AppLogger.log('PostCommentsSection: Encrypted content block length: ${encryptedContent.length}');
          
          final decryptedContent = await FileCryptoService.testDecryptData(
            encryptedContent,
            symmetricKey,
          );
          AppLogger.log('PostCommentsSection: Decrypted content length: ${decryptedContent.length}');

          final content = json.decode(utf8.decode(decryptedContent));
          AppLogger.log('PostCommentsSection: Successfully decrypted comment $fileId, content keys: ${content.keys.toList()}');
          return Map<String, dynamic>.from(content);
        } catch (e, stackTrace) {
          AppLogger.log('PostCommentsSection: Error decrypting comment $fileId: $e');
          AppLogger.log('PostCommentsSection: Stack trace: $stackTrace');
          return null;
        }
      }
    } catch (e) {
      AppLogger.log('PostCommentsSection: Error loading comment content: $e');
      return null;
    }
  }

  Future<bool> _postComment({VoidCallback? onStateChanged}) async {
    if (_commentController.text.trim().isEmpty) {
      return false;
    }
    if (widget.userPublicKey == null || widget.userMnemonic == null) {
      return false;
    }

    setState(() {
      _isPosting = true;
    });
    // Notify modal to rebuild immediately
    _modalStateSetter?.call(() {});
    onStateChanged?.call();

    try {
      // Pre-generate IDs early so they can be included in the contract
      final ids = CommentService.generateIds();
      final fileId = ids['fileId']!;
      final firstBlockId = ids['firstBlockId']!;

      // Step 1: Prepare contract and get fee info
      final storageInfo = await CommentService.prepareCommentWithStorageCost(
        nodeEndpoint: widget.nodeEndpoint,
        userPublicKey: widget.userPublicKey!,
        userMnemonic: widget.userMnemonic!,
        storageNodePublicKey: '', // Store fills its own key
        commentText: _commentController.text.trim(),
        fileId: fileId,
      );

      if (storageInfo['success'] != true) {
        AppLogger.log('PostCommentsSection: Failed to prepare storage cost: ${storageInfo['error']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to prepare comment: ${storageInfo['error']}')),
          );
        }
        return false;
      }

      final totalFee = (storageInfo['totalFee'] as num?)?.toDouble() ?? 0.0;
      final contractId = storageInfo['contractId'] as String?;

      // Step 2: Show fee confirmation (skip if free/zero)
      bool confirmed = totalFee <= 0;
      if (!confirmed && mounted) {
        final completer = Completer<bool>();
        ConfirmStorageCostDialog.show(
          context: context,
          totalFee: totalFee,
          durationDays: storageInfo['durationDays'] as int? ?? 365,
          costPerDay: (storageInfo['estimatedCostPerDay'] as num?)?.toDouble() ?? 0.0,
          estimatedSizeBytes: storageInfo['estimatedSize'] as int? ?? 500,
          feeBasis: storageInfo['feeBasis'] as String? ?? 'Comment storage fee',
          onConfirm: () => completer.complete(true),
          onCancel: () => completer.complete(false),
        );
        confirmed = await completer.future;
      }

      if (!confirmed) return false;

      // Step 3: Sign contract
      if (contractId != null) {
        final signed = await CommentService.signContract(
          nodeEndpoint: widget.nodeEndpoint,
          contractId: contractId,
          userPublicKey: widget.userPublicKey!,
          userMnemonic: widget.userMnemonic!,
        );
        if (!signed) {
          AppLogger.log('PostCommentsSection: Failed to sign contract');
          return false;
        }
      }

      // Step 4: Send comment with contractId
      // Get post owner public key
      final postOwnerPubKey = widget.post.ownerPubKey;

      final success = await CommentService.sendComment(
        postFileId: widget.post.fileId,
        nodeEndpoint: widget.nodeEndpoint,
        commentText: _commentController.text.trim(),
        userPublicKey: widget.userPublicKey!,
        userMnemonic: widget.userMnemonic!,
        postOwnerPublicKey: postOwnerPubKey,
        shareType: _selectedShareType,
        attachedMedia: _selectedMedia.isNotEmpty ? _selectedMedia : null, // 🆕 Pass attached media
        contractId: contractId, // 🆕 Pass contractId
        fileId: fileId,
        firstBlockId: firstBlockId,
        onProgress: (message) {
          if (mounted) {
            setState(() {
              _postingProgressMessage = message;
            });
            // Notify modal to rebuild with new progress
            _modalStateSetter?.call(() {});
            onStateChanged?.call();
          }
        },
      );

      if (success && mounted) {
        // Clear input and media
        _commentController.clear();
        setState(() {
          _selectedMedia.clear(); // 🆕 Clear selected media
          _postingProgressMessage = null; // Clear progress message
        });
        // Notify modal to rebuild with cleared media
        _modalStateSetter?.call(() {});
        onStateChanged?.call();
        // Wait a bit for backend to process the comment before reloading
        await Future.delayed(Duration(milliseconds: 500));
        await _loadCommentsWithRetry(); // Reload comments with retry
        // Notify modal to rebuild with reloaded comments
        setState(() {
          // Trigger rebuild to show new comments
        });
        _modalStateSetter?.call(() {});
        onStateChanged?.call();
      } else if (mounted) {
        setState(() {
          _postingProgressMessage = null; // Clear progress message on error
        });
        onStateChanged?.call(); // Notify modal to rebuild
      }
      return success;
    } catch (e) {
      AppLogger.log('PostCommentsSection: Error posting comment: $e');
      if (mounted) {
        setState(() {
          _postingProgressMessage = null; // Clear progress message on error
        });
        onStateChanged?.call(); // Notify modal to rebuild
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
          _postingProgressMessage = null; // Clear progress message when done
        });
        // Notify modal to rebuild when done
        _modalStateSetter?.call(() {});
        onStateChanged?.call();
      }
    }
  }

  Future<void> _showCommentDialog() async {
    final shareType = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Comment visibility'),
                subtitle: Text('Who can see this comment?'),
              ),
              RadioListTile<String>(
                title: Text('Only post author'),
                subtitle: Text('Only the post owner can see this comment'),
                value: 'author',
                groupValue: _selectedShareType,
                onChanged: (value) {
                  setState(() {
                    _selectedShareType = value!;
                  });
                  Navigator.pop(context, value);
                },
              ),
              RadioListTile<String>(
                title: Text('Public'),
                subtitle: Text('Everyone can see this comment'),
                value: 'public',
                groupValue: _selectedShareType,
                onChanged: (value) {
                  setState(() {
                    _selectedShareType = value!;
                  });
                  Navigator.pop(context, value);
                },
              ),
            ],
          ),
        );
      },
    );

    if (shareType != null) {
      _selectedShareType = shareType;
    }
  }

  // 🆕 Pick image from gallery
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      
      if (image != null) {
        if (_selectedMedia.length < 4) {
          try {
            // Extract file extension from name or path
            final fileName = image.name;
            final extension = fileName.contains('.') 
                ? fileName.split('.').last.toLowerCase()
                : 'jpg';
            
            // Determine mime type from extension
            final mimeType = extension == 'png' 
                ? 'image/png' 
                : extension == 'gif'
                    ? 'image/gif'
                    : 'image/jpeg';
            
            final imageData = {
              'type': 'image',
              'name': fileName,
              'extension': extension,
              'mimeType': mimeType,
              'isLocal': true,
            };
            
            if (kIsWeb) {
              final bytes = await image.readAsBytes();
              imageData['bytes'] = bytes;
              imageData['previewUrl'] = image.path;
            } else {
              imageData['path'] = image.path;
            }
            
            AppLogger.log('PostCommentsSection: Added image to selection: $fileName, extension: $extension, path: ${image.path}');
            
            setState(() {
              _selectedMedia.add(imageData);
            });
          } catch (e) {
            AppLogger.log('PostCommentsSection: Error processing image: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error processing image: $e')),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Maximum 4 images allowed')),
            );
          }
        }
      }
    } catch (e) {
      AppLogger.log('PostCommentsSection: Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🆕 Show comment count button - opens modal instead of inline
        InkWell(
          onTap: () {
            _showCommentsModal(context);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.comment_outlined,
                  size: 18,
                  color: widget.isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
                SizedBox(width: 8),
                Text(
                  _isLoading 
                      ? 'Loading comments...'
                      : '${_comments.length} comment${_comments.length != 1 ? 's' : ''}',
                  style: TextStyle(
                    color: widget.isDarkMode
                        ? DeltaniumTheme.darkTextSecondaryColor
                        : DeltaniumTheme.lightTextSecondaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_right,
                  size: 20,
                  color: widget.isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 🆕 Show comments in a modal popup
  void _showCommentsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? DeltaniumTheme.backgroundDark
                  : DeltaniumTheme.backgroundLight,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setModalState) {
                  // Store callback to trigger rebuilds
                  _modalStateSetter = setModalState;
                  return Stack(
                    children: [
                      Column(
                        children: [
                          // Handle bar
                          Container(
                            margin: EdgeInsets.only(top: 12, bottom: 8),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: widget.isDarkMode
                                  ? DeltaniumTheme.darkDividerColor
                                  : DeltaniumTheme.lightDividerColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          // Header with post info
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Text(
                                  'Comments',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: widget.isDarkMode
                                        ? DeltaniumTheme.darkTextPrimaryColor
                                        : DeltaniumTheme.lightTextPrimaryColor,
                                  ),
                                ),
                                Spacer(),
                                IconButton(
                                  icon: Icon(Icons.close),
                                  onPressed: () => Navigator.pop(context),
                                  color: widget.isDarkMode
                                      ? DeltaniumTheme.darkTextSecondaryColor
                                      : DeltaniumTheme.lightTextSecondaryColor,
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: widget.isDarkMode
                                ? DeltaniumTheme.darkDividerColor
                                : DeltaniumTheme.lightDividerColor,
                          ),
                          // Scrollable comments list
                          Expanded(
                            child: _buildCommentsList(scrollController: scrollController),
                          ),
                          // Comment input at bottom (fixed)
        if (widget.userPublicKey != null && widget.userMnemonic != null)
          Container(
                              padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                              margin: EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? DeltaniumTheme.surfaceDark
                  : DeltaniumTheme.surfaceLight,
                                border: Border(
                                  top: BorderSide(
                                    color: widget.isDarkMode
                                        ? DeltaniumTheme.darkDividerColor
                                        : DeltaniumTheme.lightDividerColor,
                                  ),
                                ),
            ),
            child: Column(
                                mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                                  // 🆕 Show selected images above input field
                                  if (_selectedMedia.isNotEmpty) ...[
                                    Container(
                                      height: 100,
                                      margin: EdgeInsets.only(bottom: 12),
                                      padding: EdgeInsets.symmetric(vertical: 4),
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _selectedMedia.length,
                                        itemBuilder: (context, index) {
                                          final media = _selectedMedia[index];
                                          return Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Stack(
                                              children: [
                                                Container(
                                                  width: 80,
                                                  height: 80,
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: widget.isDarkMode
                                                          ? DeltaniumTheme.darkDividerColor
                                                          : DeltaniumTheme.lightDividerColor,
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: kIsWeb && media.containsKey('bytes')
                                                        ? Image.memory(
                                                            Uint8List.fromList(media['bytes'] as List<int>),
                                                            fit: BoxFit.cover,
                                                          )
                                                        : !kIsWeb && media.containsKey('path')
                                                            ? Image.file(
                                                                File(media['path']),
                                                                fit: BoxFit.cover,
                                                              )
                                                            : Icon(Icons.image),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 0,
                                                  right: 0,
                                                  child: IconButton(
                                                    icon: Icon(Icons.close, size: 18),
                                                    color: Colors.red,
                                                    onPressed: () {
                                                      setState(() {
                                                        _selectedMedia.removeAt(index);
                                                      });
                                                      // Force modal to rebuild
                                                      setModalState(() {});
                                                    },
                                                    padding: EdgeInsets.zero,
                                                    constraints: BoxConstraints(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        decoration: InputDecoration(
                          hintText: 'Write a comment...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: widget.isDarkMode
                                  ? DeltaniumTheme.darkDividerColor
                                  : DeltaniumTheme.lightDividerColor,
                            ),
                          ),
                          filled: true,
                          fillColor: widget.isDarkMode
                              ? DeltaniumTheme.backgroundDark
                              : DeltaniumTheme.backgroundLight,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        maxLines: null,
                        enabled: !_isPosting,
                      ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.image),
                      color: widget.isDarkMode
                          ? DeltaniumTheme.primaryTan
                          : DeltaniumTheme.primaryBrown,
                                        onPressed: _isPosting ? null : () async {
                                          await _pickImage();
                                          // Force modal to rebuild to show selected images
                                          AppLogger.log('PostCommentsSection: Rebuilding modal after image pick, _selectedMedia.length=${_selectedMedia.length}');
                                          setModalState(() {});
                                        },
                      tooltip: 'Add image',
                    ),
                    IconButton(
                      icon: Icon(
                        _selectedShareType == 'public' ? Icons.public : Icons.lock,
                        color: widget.isDarkMode
                            ? DeltaniumTheme.primaryTan
                            : DeltaniumTheme.primaryBrown,
                      ),
                      onPressed: _showCommentDialog,
                      tooltip: _selectedShareType == 'public' ? 'Public comment' : 'Only post author',
                    ),
                    IconButton(
                      icon: _isPosting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.send),
                                        onPressed: _isPosting ? null : () async {
                                          // Store setModalState for use in _postComment
                                          _modalStateSetter = setModalState;
                                          final success = await _postComment(
                                            onStateChanged: () {
                                              // Rebuild modal whenever state changes
                                              setModalState(() {});
                                            },
                                          );
                                        },
                      color: widget.isDarkMode
                          ? DeltaniumTheme.primaryTan
                          : DeltaniumTheme.primaryBrown,
                    ),
                  ],
                ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      // 🆕 Loading overlay with progress message
                      if (_isPosting)
                          Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.all(24),
                            decoration: BoxDecoration(
                                color: widget.isDarkMode
                            ? DeltaniumTheme.surfaceDark
                            : DeltaniumTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          if (_postingProgressMessage != null) ...[
                            SizedBox(height: 16),
                            Text(
                              _postingProgressMessage!,
                              style: TextStyle(
                                color: widget.isDarkMode
                                    ? DeltaniumTheme.darkTextPrimaryColor
                                    : DeltaniumTheme.lightTextPrimaryColor,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsList({ScrollController? scrollController}) {
    if (_isLoading) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_comments.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No comments yet',
          style: TextStyle(
            color: widget.isDarkMode
                ? DeltaniumTheme.darkTextSecondaryColor
                : DeltaniumTheme.lightTextSecondaryColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.all(16),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: _buildCommentItem(_comments[index]),
        );
      },
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final text = comment['text'] as String? ?? 'Comment text not available';
    final createdAt = comment['createdAt'] as String?;
    final commenterPubKey = comment['commenterPublicKey'] as String? ?? comment['OwnerPubKey'] as String?;
    
    // 🆕 Determine if comment is public or encrypted
    final isPublic = comment['IsPublic'] == true || 
                     comment['isPublic'] == true || 
                     (comment['EncryptedType'] as String? ?? '').toLowerCase() == 'public' ||
                     (comment['encryptedType'] as String? ?? '').toLowerCase() == 'public' ||
                     (comment['ShareType'] as String? ?? '').toLowerCase() == 'public' ||
                     (comment['shareType'] as String? ?? '').toLowerCase() == 'public';
    
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? DeltaniumTheme.surfaceDark
            : DeltaniumTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: widget.isDarkMode
                    ? DeltaniumTheme.primaryTan.withOpacity(0.3)
                    : DeltaniumTheme.primaryBrown.withOpacity(0.3),
                child: Text(
                  (commenterPubKey?.substring(0, 2) ?? 'U').toUpperCase(),
                  style: TextStyle(fontSize: 12),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                      commenterPubKey?.substring(0, 10) ?? 'Unknown',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: widget.isDarkMode
                            ? DeltaniumTheme.darkTextPrimaryColor
                            : DeltaniumTheme.lightTextPrimaryColor,
                      ),
                          ),
                        ),
                        // 🆕 Tag to show comment type
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPublic
                                ? Colors.green.withOpacity(0.2)
                                : Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isPublic
                                  ? Colors.green.withOpacity(0.5)
                                  : Colors.blue.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPublic ? Icons.public : Icons.lock,
                                size: 12,
                                color: isPublic
                                    ? Colors.green
                                    : Colors.blue,
                              ),
                              SizedBox(width: 4),
                              Text(
                                isPublic ? 'PUBLIC' : 'ENCRYPTED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isPublic
                                      ? Colors.green
                                      : Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (createdAt != null)
                      Text(
                        _formatDate(createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDarkMode
                              ? DeltaniumTheme.darkTextSecondaryColor
                              : DeltaniumTheme.lightTextSecondaryColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: widget.isDarkMode
                  ? DeltaniumTheme.darkTextPrimaryColor
                  : DeltaniumTheme.lightTextPrimaryColor,
            ),
          ),
          // 🆕 Show attached images (smaller size for comments)
          if (comment['relatedFiles'] != null && (comment['relatedFiles'] as List).isNotEmpty) ...[
            SizedBox(height: 8),
            _buildCommentImages(List<Map<String, dynamic>>.from(comment['relatedFiles'] as List)),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentImages(List<Map<String, dynamic>> relatedFiles) {
    // Filter only images
    final imageFiles = relatedFiles.where((file) {
      final fileType = file['type'] as String? ?? 'unknown';
      final mimeType = file['mimeType'] as String? ?? 'application/octet-stream';
      return fileType == 'image' || mimeType.toString().startsWith('image/');
    }).toList();

    if (imageFiles.isEmpty) {
      return SizedBox.shrink();
    }

    // Use RelatedFilesWidget to handle download and display
    return RelatedFilesWidget(
      relatedFiles: imageFiles,
      isDarkMode: widget.isDarkMode,
      userPublicKey: widget.userPublicKey,
      userMnemonic: widget.userMnemonic,
      postNodeEndpoint: widget.nodeEndpoint,
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}

