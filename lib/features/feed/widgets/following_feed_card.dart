import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/services/following_feed_service.dart';

class FollowingFeedCard extends StatelessWidget {
  final FollowingPost post;
  final VoidCallback? onLikePressed;
  final VoidCallback? onCommentPressed;
  final VoidCallback? onSharePressed;
  final VoidCallback? onRetweetPressed;

  const FollowingFeedCard({
    super.key,
    required this.post,
    this.onLikePressed,
    this.onCommentPressed,
    this.onSharePressed,
    this.onRetweetPressed,
  });

  // Simple time formatting function
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: DeltaniumTheme.spacingMedium,
        vertical: DeltaniumTheme.spacingSmall,
      ),
      elevation: 1,
      color: isDarkMode 
          ? DeltaniumTheme.surfaceDark 
          : DeltaniumTheme.surfaceLight,
      child: InkWell(
        onTap: () {
          // Navigate to post details
        },
        child: Padding(
          padding: const EdgeInsets.all(DeltaniumTheme.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with profile info
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile image
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isDarkMode 
                        ? DeltaniumTheme.primaryTan 
                        : DeltaniumTheme.primaryBrown,
                    backgroundImage: post.authorAvatarUrl != null 
                        ? NetworkImage(post.authorAvatarUrl!) 
                        : null,
                    child: post.authorAvatarUrl == null
                        ? Text(
                            post.authorDisplayName.isNotEmpty 
                                ? post.authorDisplayName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  
                  const SizedBox(width: DeltaniumTheme.spacingSmall),
                  
                  // Author info and metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Author name and time
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                post.authorDisplayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isDarkMode 
                                      ? DeltaniumTheme.darkTextPrimaryColor 
                                      : DeltaniumTheme.lightTextPrimaryColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatTimeAgo(post.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode 
                                    ? DeltaniumTheme.darkTextSecondaryColor 
                                    : DeltaniumTheme.lightTextSecondaryColor,
                              ),
                            ),
                          ],
                        ),
                        
                        // Public key (shortened)
                        Text(
                          post.shortAuthorKey,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: isDarkMode 
                                ? DeltaniumTheme.darkTextSecondaryColor 
                                : DeltaniumTheme.lightTextSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Privacy indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: post.isPublic ? Colors.green : Colors.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          post.isPublic ? Icons.public : Icons.share,
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          post.isPublic ? 'PUBLIC' : 'SHARED',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: DeltaniumTheme.spacingSmall),
              
              // Post content
              Text(
                post.textContent,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: isDarkMode 
                      ? DeltaniumTheme.darkTextPrimaryColor 
                      : DeltaniumTheme.lightTextPrimaryColor,
                ),
              ),
              
              // Tags
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: DeltaniumTheme.spacingSmall),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: post.tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDarkMode 
                          ? DeltaniumTheme.primaryTan.withOpacity(0.2)
                          : DeltaniumTheme.primaryBrown.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '#$tag',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode 
                            ? DeltaniumTheme.primaryTan 
                            : DeltaniumTheme.primaryBrown,
                      ),
                    ),
                  )).toList(),
                ),
              ],
              
              // Attached media indicator
              if (post.attachedMedia != null && post.attachedMedia!.isNotEmpty) ...[
                const SizedBox(height: DeltaniumTheme.spacingSmall),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDarkMode 
                        ? DeltaniumTheme.surfaceDark.withOpacity(0.5)
                        : DeltaniumTheme.surfaceLight.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkMode
                          ? DeltaniumTheme.darkDividerColor
                          : DeltaniumTheme.lightDividerColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.attachment,
                        size: 16,
                        color: isDarkMode 
                            ? DeltaniumTheme.darkTextSecondaryColor 
                            : DeltaniumTheme.lightTextSecondaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.attachedMedia!.length} attachment(s)',
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
              
              const SizedBox(height: DeltaniumTheme.spacingMedium),
              
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildActionButton(
                    context,
                    icon: Icons.favorite_border,
                    label: 'Like',
                    onPressed: onLikePressed,
                    isDarkMode: isDarkMode,
                  ),
                  _buildActionButton(
                    context,
                    icon: Icons.comment_outlined,
                    label: 'Comment',
                    onPressed: onCommentPressed,
                    isDarkMode: isDarkMode,
                  ),
                  _buildActionButton(
                    context,
                    icon: Icons.repeat,
                    label: 'Repost',
                    onPressed: onRetweetPressed,
                    isDarkMode: isDarkMode,
                  ),
                  _buildActionButton(
                    context,
                    icon: Icons.share_outlined,
                    label: 'Share',
                    onPressed: onSharePressed,
                    isDarkMode: isDarkMode,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool isDarkMode,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isDarkMode 
                  ? DeltaniumTheme.darkTextSecondaryColor 
                  : DeltaniumTheme.lightTextSecondaryColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
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
    );
  }
} 