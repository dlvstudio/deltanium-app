import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/features/feed/widgets/related_files_widget.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/features/posts/widgets/post_reactions_bar.dart';
import 'package:deltanium_app/features/posts/widgets/post_comments_section.dart';

// 🚀 OPTIMIZED: Separate widget to prevent unnecessary rebuilds during scrolling
class OptimizedPostCard extends StatelessWidget {
  final PostMetadata post;
  final String nodeEndpoint;
  final bool isDarkMode;
  final String? userPublicKey;
  final String? userMnemonic;
  final Function(String, String)? onFileDownload;
  final Function(String)? onFileRemove;

  const OptimizedPostCard({
    Key? key,
    required this.post,
    required this.nodeEndpoint,
    required this.isDarkMode,
    this.userPublicKey,
    this.userMnemonic,
    this.onFileDownload,
    this.onFileRemove,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If post is decrypted and has content, show as a proper post
    if (post.isDecrypted && post.textContent != null) {
      return RepaintBoundary(
        child: Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Post header with user info
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                      child: const Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayAuthorName(post),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDarkMode
                                  ? DeltaniumTheme.darkTextPrimaryColor
                                  : DeltaniumTheme.lightTextPrimaryColor,
                            ),
                          ),
                          Text(
                            _formatDate(post.creationTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? DeltaniumTheme.darkTextSecondaryColor
                                  : DeltaniumTheme.lightTextSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Show post privacy and ownership status with two separate tags
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // First tag: Privacy Status (PUBLIC/ENCRYPTED)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (post.encryptedType == 'public')
                                ? Colors.green // Public post
                                : Colors.red, // Encrypted post
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (post.encryptedType == 'public')
                                    ? Icons.public // Public post icon
                                    : Icons.lock, // Encrypted post icon
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (post.encryptedType == 'public')
                                    ? 'PUBLIC'
                                    : 'ENCRYPTED',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // Second tag: Ownership Status (MY POST/SHARED WITH ME)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isPostShared(post) ? Colors.blue : Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isPostShared(post) ? Icons.share : Icons.person,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isPostShared(post) ? 'SHARED WITH ME' : 'MY POST',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
                // Post content
                const SizedBox(height: 12),
                Text(
                  post.textContent!,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: isDarkMode
                        ? DeltaniumTheme.darkTextPrimaryColor
                        : DeltaniumTheme.lightTextPrimaryColor,
                  ),
                ),
                
                // Attached media info
                if (post.relatedFiles != null && post.relatedFiles!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  RelatedFilesWidget(
                    relatedFiles: post.relatedFiles!,
                    isDarkMode: isDarkMode,
                    userPublicKey: userPublicKey,
                    userMnemonic: userMnemonic,
                    postNodeEndpoint: nodeEndpoint,
                    onFileDownload: onFileDownload,
                    onFileRemove: onFileRemove,
                  ),
                ],
                
                // Tags (hashtags from post content)
                if (post.tags != null && post.tags!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: post.tags!.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
                
                // Post actions (like, comment, share)  
                const SizedBox(height: 16),
                Row(
                  children: [
                    PostReactionsBar(
                      post: post,
                      nodeEndpoint: nodeEndpoint,
                      isDarkMode: isDarkMode,
                      userPublicKey: userPublicKey,
                      userMnemonic: userMnemonic,
                    ),
                    const SizedBox(width: 24),
                    _buildPostAction(Icons.share_outlined, '0', isDarkMode),
                    const Spacer(),
                    Text(
                      'ID: ${post.fileId.substring(0, 8)}...',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: isDarkMode
                            ? DeltaniumTheme.darkTextSecondaryColor
                            : DeltaniumTheme.lightTextSecondaryColor,
                      ),
                    ),
                  ],
                ),
                
                // Comments section
                const SizedBox(height: 16),
                PostCommentsSection(
                  post: post,
                  nodeEndpoint: nodeEndpoint,
                  isDarkMode: isDarkMode,
                  userPublicKey: userPublicKey,
                  userMnemonic: userMnemonic,
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // Fallback for encrypted posts
    return RepaintBoundary(
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lock,
                    size: 24,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Encrypted Post',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Created ${_formatDate(post.creationTime)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? DeltaniumTheme.darkTextSecondaryColor
                                : DeltaniumTheme.lightTextSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Unable to decrypt post content. This may be due to encryption key issues.',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ID: ${post.fileId.substring(0, 8)}...',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _displayAuthorName(PostMetadata post) {
    // Prefer explicit authorName from decrypted content if available
    if (post.authorName != null && post.authorName!.trim().isNotEmpty) {
      return post.authorName!;
    }
    // Fall back: Show 'You' for owner, otherwise short owner key
    try {
      if (post.ownerPubKey != null && userPublicKey != null) {
        final owner = CryptoService.normalizePublicKey(post.ownerPubKey!);
        final current = CryptoService.normalizePublicKey(userPublicKey!);
        if (owner == current) return 'You';
        // Show shortened owner key as fallback
        return owner.substring(0, 8) + '...' + owner.substring(owner.length - 6);
      }
    } catch (_) {}
    return 'You';
  }

  Widget _buildPostAction(IconData icon, String count, bool isDarkMode) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDarkMode
              ? DeltaniumTheme.darkTextSecondaryColor
              : DeltaniumTheme.lightTextSecondaryColor,
        ),
        const SizedBox(width: 4),
        Text(
          count,
          style: TextStyle(
            fontSize: 14,
            color: isDarkMode
                ? DeltaniumTheme.darkTextSecondaryColor
                : DeltaniumTheme.lightTextSecondaryColor,
          ),
        ),
      ],
    );
  }
  
  // Check if post is shared with current user (vs owned by current user)
  bool _isPostShared(PostMetadata post) {
    // 🔧 FIX: Check if current user is the owner by comparing ownerPubKey from decrypted metadata
    // If we successfully decrypted the post, we can check the ownerPubKey field
    
    if (!post.isDecrypted) {
      // If post is not decrypted, we can't determine ownership reliably
      return true; // Show as SHARED to be safe
    }
    
    // Check against the ownerPubKey from decrypted metadata
    // The ownerPubKey field should be populated during decryption from metadata block
    final postOwnerPubKey = post.ownerPubKey;
    final currentUserPubKey = userPublicKey;
    
    if (postOwnerPubKey != null && currentUserPubKey != null) {
      // Compare normalized public keys
      final normalizedPostOwner = CryptoService.normalizePublicKey(postOwnerPubKey);
      final normalizedCurrentUser = CryptoService.normalizePublicKey(currentUserPubKey);
      
      // If current user is the owner, it's "MY POST", otherwise it's "SHARED"
      return normalizedPostOwner != normalizedCurrentUser;
    }
    
    // If we can't determine ownership, assume it's shared
    return true;
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
} 