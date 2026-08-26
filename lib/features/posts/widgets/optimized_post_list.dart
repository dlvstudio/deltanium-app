import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/features/posts/widgets/optimized_post_card.dart';
import 'package:deltanium_app/services/app_logger.dart';


class OptimizedPostList extends StatefulWidget {
  final Map<String, List<PostMetadata>> postsByNode;
  final List<Map<String, dynamic>> storeNodes;
  final bool isDarkMode;
  final String? userPublicKey;
  final String? userMnemonic;
  final VoidCallback onRefresh;
  final String emptyMessage;
  final String emptySubMessage;

  const OptimizedPostList({
    Key? key,
    required this.postsByNode,
    required this.storeNodes,
    required this.isDarkMode,
    this.userPublicKey,
    this.userMnemonic,
    required this.onRefresh,
    required this.emptyMessage,
    required this.emptySubMessage,
  }) : super(key: key);

  @override
  State<OptimizedPostList> createState() => _OptimizedPostListState();
}

class _OptimizedPostListState extends State<OptimizedPostList> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, bool> _visiblePosts = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.postsByNode.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.article_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                widget.emptyMessage,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDarkMode
                      ? DeltaniumTheme.darkTextPrimaryColor
                      : DeltaniumTheme.lightTextPrimaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.emptySubMessage,
                style: TextStyle(
                  color: widget.isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: widget.onRefresh,
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    // Flatten all posts from all nodes into a single list
    final List<Map<String, dynamic>> allPostsWithNode = [];
    for (final nodeId in widget.postsByNode.keys) {
      final nodePosts = widget.postsByNode[nodeId] ?? [];
      final node = widget.storeNodes.firstWhere(
        (n) => n['id'] == nodeId, 
        orElse: () => {'endpoint': ''}
      );
      final nodeEndpoint = node['endpoint'] as String? ?? '';
      for (final post in nodePosts) {
        allPostsWithNode.add({'post': post, 'nodeEndpoint': nodeEndpoint});
      }
    }
    
    // Sort posts by creation time (newest first)
    allPostsWithNode.sort((a, b) => 
      (b['post'] as PostMetadata).creationTime.compareTo((a['post'] as PostMetadata).creationTime)
    );

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 0),
        itemCount: allPostsWithNode.length,
        // 🚀 PERFORMANCE OPTIMIZATIONS
        cacheExtent: 1000, // Cache more items for smoother scrolling
        addAutomaticKeepAlives: false, // Don't keep items alive when off-screen
        addRepaintBoundaries: true, // Add repaint boundaries for better performance
        itemBuilder: (context, index) {
          final post = allPostsWithNode[index]['post'] as PostMetadata;
          final nodeEndpoint = allPostsWithNode[index]['nodeEndpoint'] as String;
          
          return RepaintBoundary(
            child: Column(
              children: [
                OptimizedPostCard(
                  key: ValueKey(post.fileId), // 🚀 OPTIMIZATION: Add key for better ListView performance
                  post: post,
                  nodeEndpoint: nodeEndpoint,
                  isDarkMode: widget.isDarkMode,
                  userPublicKey: widget.userPublicKey,
                  userMnemonic: widget.userMnemonic,
                  onFileDownload: (fileId, nodeEndpoint) {
                    // TODO: Implement file download
                    AppLogger.log('Downloading file $fileId from $nodeEndpoint');
                  },
                  onFileRemove: (fileId) {
                    // TODO: Implement file removal
                    AppLogger.log('Removing file $fileId from post');
                  },
                ),
                if (index < allPostsWithNode.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: widget.isDarkMode
                        ? DeltaniumTheme.darkDividerColor
                        : DeltaniumTheme.lightDividerColor,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
} 
