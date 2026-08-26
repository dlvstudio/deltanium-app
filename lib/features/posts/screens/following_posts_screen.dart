import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/features/feed/widgets/related_files_widget.dart';
import 'package:deltanium_app/features/posts/widgets/optimized_post_list.dart';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';


class FollowingPostsScreen extends StatefulWidget {
  const FollowingPostsScreen({Key? key}) : super(key: key);

  @override
  _FollowingPostsScreenState createState() => _FollowingPostsScreenState();
}

class _FollowingPostsScreenState extends State<FollowingPostsScreen> {
  final AuthService _authService = AuthService();
  
  bool _isLoading = true;
  String _loadingMessage = 'Loading following posts...';
  String? _errorMessage;
  String? _userPublicKey;
  String? _userMnemonic;
  
  List<Map<String, dynamic>> _storeNodes = [];
  Map<String, List<PostMetadata>> _postsByNode = {};
  
  // Performance tracking
  final Map<String, int> _timingLog = {};
  DateTime? _loadStartTime;
  
  @override
  void initState() {
    super.initState();
    // Check cache status when entering Following Posts
    FileCryptoService.checkCacheStatus();
    _loadUserInfo();
  }
  
  // Helper method to log timing
  void _logTiming(String operation, int milliseconds) {
    _timingLog[operation] = milliseconds;
    AppLogger.log('⏱️ TIMING: $operation took ${milliseconds}ms');
  }
  
  // Helper method to start timing
  DateTime _startTiming(String operation) {
    final startTime = DateTime.now();
    AppLogger.log('⏱️ TIMING: Starting $operation...');
    return startTime;
  }
  
  // Helper method to end timing
  void _endTiming(String operation, DateTime startTime) {
    final duration = DateTime.now().difference(startTime).inMilliseconds;
    _logTiming(operation, duration);
  }
  
  Future<void> _loadUserInfo() async {
    final startTime = _startTiming('Load User Info');
    
    final authInfo = await _authService.getCurrentAuthInfo();
    if (authInfo != null) {
      setState(() {
        _userPublicKey = authInfo['publicKey'];
        _userMnemonic = authInfo['mnemonic'];
      });
      
      _endTiming('Load User Info', startTime);
      _loadFollowingPosts();
    } else {
      _endTiming('Load User Info', startTime);
      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be logged in to view following posts';
      });
    }
  }
  
  Future<void> _loadFollowingPosts() async {
    if (_userPublicKey == null || _userMnemonic == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Missing user credentials';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Loading following posts...';
      _errorMessage = null;
      _loadStartTime = DateTime.now();
    });

    try {
      // Use the default node directly
      const nodeEndpoint = 'http://localhost:5001';
      setState(() {
        _loadingMessage = 'Loading posts from followers...';
      });

      final nodeStartTime = _startTiming('Load Following Posts');
      
      // Get posts with shareType = "followers"
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final path = '/api/post/followers-feed';
      final bodyHash = ''; // Empty body for GET request
      
      // Create data to sign
      final dataToSign = '$method$path$timestamp$bodyHash';
      
      // Generate signature
      final signature = await CryptoService.sign(dataToSign, _userMnemonic!);
      
      final _httpStart = DateTime.now();
      AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint$path' + ' START ' + _httpStart.toIso8601String());
      final postsResponse = await http.get(
        Uri.parse('$nodeEndpoint$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(_userPublicKey!),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      AppLogger.log('🌐 HTTP GET ' + '$nodeEndpoint$path' + ' END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_httpStart).inMilliseconds.toString() + 'ms) code=' + postsResponse.statusCode.toString());
      
      _endTiming('Load Following Posts', nodeStartTime);

      if (postsResponse.statusCode == 200) {
        final responseBody = json.decode(postsResponse.body);
        AppLogger.log('Following posts response: $responseBody');
        
        // Handle the API response format
        List<dynamic> postsJson;
        if (responseBody is Map<String, dynamic> && responseBody.containsKey('posts')) {
          postsJson = responseBody['posts'] as List<dynamic>;
          AppLogger.log('Received ${postsJson.length} following posts');
        } else if (responseBody is List<dynamic>) {
          postsJson = responseBody;
          AppLogger.log('Received ${postsJson.length} following posts (direct array)');
        } else {
          throw Exception('Unexpected response format: ${responseBody.runtimeType}');
        }

        // Try to decrypt each post
        final List<PostMetadata> decryptedPosts = [];
        
        for (final post in postsJson) {
          try {
            // Create PostMetadata object using fromJson factory
            final postMetadata = PostMetadata.fromJson(post as Map<String, dynamic>);
            
            final decryptedPost = await MyPostsScreen.tryDecryptPostStatic(
              postMetadata,
              nodeEndpoint,
              _userMnemonic!,
              currentUserPublicKey: _userPublicKey!,
            );
            
            if (decryptedPost != null) {
              decryptedPosts.add(decryptedPost);
            }
          } catch (e) {
            AppLogger.log('Failed to process post: $e');
            // Continue with next post
          }
        }

        setState(() {
          // Provide node mapping so UI can resolve endpoint for image downloads
          _storeNodes = [
            {
              'id': 'main',
              'endpoint': nodeEndpoint,
            }
          ];
          _postsByNode = {'main': decryptedPosts};
          _isLoading = false;
          
          if (_loadStartTime != null) {
            final totalTime = DateTime.now().difference(_loadStartTime!).inMilliseconds;
            _logTiming('Total Load Time', totalTime);
          }
        });
      } else {
        throw Exception('Failed to load following posts: ${postsResponse.statusCode}');
      }

    } catch (e) {
      AppLogger.log('Error loading following posts: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load following posts: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _loadingMessage,
              style: TextStyle(
                color: isDarkMode
                    ? DeltaniumTheme.darkTextSecondaryColor
                    : DeltaniumTheme.lightTextSecondaryColor,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextPrimaryColor
                      : DeltaniumTheme.lightTextPrimaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadFollowingPosts,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return _buildPostsList(isDarkMode);
  }

  Widget _buildPostsList(bool isDarkMode) {
    return OptimizedPostList(
      postsByNode: _postsByNode,
      storeNodes: _storeNodes,
      isDarkMode: isDarkMode,
      userPublicKey: _userPublicKey,
      userMnemonic: _userMnemonic,
      onRefresh: _loadFollowingPosts,
      emptyMessage: 'No following posts found',
      emptySubMessage: 'Follow more users to see their posts here',
    );
  }

  Widget _buildPostCard(PostMetadata post, String nodeEndpoint, bool isDarkMode) {
    // If post is decrypted and has content, show as a proper post
    if (post.isDecrypted && post.textContent != null) {
      return Card(
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
                          post.ownerPubKey?.substring(0, 8) ?? 'Unknown',
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
                          color: post.encryptedType == 'public'
                              ? Colors.green // Public post
                              : Colors.red, // Encrypted post
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              post.encryptedType == 'public'
                                  ? Icons.public // Public post icon
                                  : Icons.lock, // Encrypted post icon
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              post.encryptedType == 'public'
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
                      
                      // Second tag: Following Post
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people,
                              size: 12,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'FOLLOWING',
                              style: TextStyle(
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
              
              // Related files (if any)
              if (post.attachedMedia != null && post.attachedMedia!.isNotEmpty) ...[
                const SizedBox(height: 12),
                RelatedFilesWidget(
                  relatedFiles: post.attachedMedia!.map((media) => {
                    'fileId': media['fileId'] ?? 'unknown',
                    'type': media['type'] ?? 'unknown',
                    'relationshipType': 'attachment',
                    'fileName': media['caption'] ?? 'Unknown file',
                    'fileSize': 0, // Size not available in current structure
                    'mimeType': 'application/octet-stream',
                    'uploadTime': DateTime.now().toIso8601String(),
                    'nodeId': 'unknown',
                    'nodeEndpoint': 'unknown',
                    'caption': media['caption'] ?? '',
                    'order': media['order'] ?? 0,
                  }).toList(),
                  isDarkMode: isDarkMode,
                  postNodeEndpoint: nodeEndpoint,
                  onFileDownload: (fileId, nodeEndpoint) {
                    // TODO: Implement file download
                    AppLogger.log('Downloading file $fileId from $nodeEndpoint');
                  },
                  onFileRemove: (fileId) {
                    // TODO: Implement file removal
                    AppLogger.log('Removing file $fileId from post');
                  },
                ),
              ],
              
              // Post actions
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildPostAction(Icons.favorite_border, '0', isDarkMode),
                  _buildPostAction(Icons.chat_bubble_outline, '0', isDarkMode),
                  _buildPostAction(Icons.repeat, '0', isDarkMode),
                  _buildPostAction(Icons.share_outlined, '0', isDarkMode),
                ],
              ),
              
              // Post metadata
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
      );
    }

    // If post is not decrypted or has no content, show placeholder
    return const SizedBox.shrink();
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<List<Map<String, dynamic>>> _fetchAvailableNodes() async {
    try {
      final _httpStart = DateTime.now();
      AppLogger.log('🌐 HTTP GET /api/storenode/list START ' + _httpStart.toIso8601String());
      final storeNodesResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/storenode/list'),
      );
      AppLogger.log('🌐 HTTP GET /api/storenode/list END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_httpStart).inMilliseconds.toString() + 'ms) code=' + storeNodesResponse.statusCode.toString());

      if (storeNodesResponse.statusCode != 200) {
        throw Exception('Failed to fetch storage nodes');
      }

      final List<dynamic> storeNodesJson = json.decode(storeNodesResponse.body);
      return storeNodesJson.map((node) => Map<String, dynamic>.from(node)).toList();
    } catch (e) {
      AppLogger.log('Error fetching storage nodes: $e');
      return [];
    }
  }
} 
