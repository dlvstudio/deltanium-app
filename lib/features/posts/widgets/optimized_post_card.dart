import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/feed/widgets/related_files_widget.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/features/posts/widgets/post_comments_section.dart';
import 'package:deltanium_app/features/posts/widgets/post_reactions_bar.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: Brand.panel,
            borderRadius: BorderRadius.circular(Brand.radius + 6),
            border: Border.all(color: Brand.line),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Brand.sand.withValues(alpha: 0.18),
                      child: Icon(
                        Icons.person_rounded,
                        color: Brand.sand,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayAuthorName(post),
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Brand.text,
                            ),
                          ),
                          Text(
                            _formatDate(post.creationTime),
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: Brand.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: [
                          _statusChip(
                            label: post.encryptedType == 'public' ? 'Public' : 'Encrypted',
                            icon: post.encryptedType == 'public'
                                ? Icons.public_rounded
                                : Icons.lock_rounded,
                            accent: post.encryptedType == 'public'
                                ? Brand.moss
                                : Brand.danger,
                          ),
                          _statusChip(
                            label: _isPostShared(post) ? 'Shared' : 'Yours',
                            icon: _isPostShared(post)
                                ? Icons.share_rounded
                                : Icons.person_rounded,
                            accent: Brand.sand,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  post.textContent!,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    height: 1.5,
                    color: Brand.text,
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
                
                if (post.tags != null && post.tags!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: post.tags!
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Brand.sand.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(Brand.radius),
                              border: Border.all(color: Brand.line),
                            ),
                            child: Text(
                              tag,
                              style: GoogleFonts.manrope(
                                color: Brand.sand,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 14),
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
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        color: Brand.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brand.panel,
          borderRadius: BorderRadius.circular(Brand.radius + 6),
          border: Border.all(color: Brand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_rounded, size: 22, color: Brand.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Encrypted post',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Brand.text,
                        ),
                      ),
                      Text(
                        'Created ${_formatDate(post.creationTime)}',
                        style: GoogleFonts.manrope(fontSize: 12, color: Brand.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Unable to decrypt this post. You may not have access, or the key material is missing.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.45,
                color: Brand.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
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