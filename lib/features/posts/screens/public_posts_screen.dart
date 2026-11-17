import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/features/posts/widgets/optimized_post_list.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/store_node_directory.dart';


class PublicPostsScreen extends StatefulWidget {
  const PublicPostsScreen({Key? key}) : super(key: key);

  @override
  State<PublicPostsScreen> createState() => _PublicPostsScreenState();
}

class _PublicPostsScreenState extends State<PublicPostsScreen> {
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  String _loadingMessage = 'Loading public posts...';
  String? _errorMessage;
  String? _userPublicKey;
  String? _userMnemonic;

  List<Map<String, dynamic>> _storeNodes = [];
  Map<String, List<PostMetadata>> _postsByNode = {};

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final authInfo = await _authService.getCurrentAuthInfo();
    if (authInfo != null) {
      setState(() {
        _userPublicKey = authInfo['publicKey'];
        _userMnemonic = authInfo['mnemonic'];
      });
      _loadPublicPosts();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be logged in to view public posts';
      });
    }
  }

  Future<void> _loadPublicPosts() async {
    if (_userPublicKey == null || _userMnemonic == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Missing user credentials';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Loading public posts...';
      _errorMessage = null;
    });

    try {
      // 1) Fetch store nodes from Central API
      final availableNodes = await StoreNodeDirectory.listNodes();
      AppLogger.log('🗂️ Public feed: found ${availableNodes.length} store nodes');

      final Map<String, List<PostMetadata>> postsByNode = {};
      final List<Map<String, dynamic>> storeNodes = [];

      // 2) Query each node for public feed
      for (final node in availableNodes) {
        final nodeEndpoint = node['endpoint'] as String;
        try {
          final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          const method = 'GET';
          const path = '/api/post/public-feed';
          const bodyHash = '';
          final dataToSign = '$method$path$timestamp$bodyHash';
          final signature = await CryptoService.sign(dataToSign, _userMnemonic!);
          final httpStart = DateTime.now();
          AppLogger.log('🌐 HTTP GET $nodeEndpoint$path START ${httpStart.toIso8601String()}');
          final response = await http.get(
            Uri.parse('$nodeEndpoint$path'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(_userPublicKey!),
              'X-Timestamp': timestamp,
              'X-Signature': signature,
            },
          );
          AppLogger.log(
            '🌐 HTTP GET $nodeEndpoint$path END ${DateTime.now().toIso8601String()} '
            '(${DateTime.now().difference(httpStart).inMilliseconds}ms) code=${response.statusCode}',
          );
          if (response.statusCode != 200) continue;
          final responseBody = json.decode(response.body);
          AppLogger.log('📝 public-feed raw ($nodeEndpoint): $responseBody');
          List<dynamic> postsJson;
          if (responseBody is Map<String, dynamic> && responseBody.containsKey('posts')) {
            postsJson = responseBody['posts'] as List<dynamic>;
          } else if (responseBody is List<dynamic>) {
            postsJson = responseBody;
          } else {
            continue;
          }
          final List<PostMetadata> publicPosts = [];
          int parsed = 0;
          int decryptedCount = 0;
          for (final post in postsJson) {
            try {
              final meta = PostMetadata.fromJson(post as Map<String, dynamic>);
              parsed++;
              final dec = await MyPostsScreen.tryDecryptPostStatic(
                meta,
                nodeEndpoint,
                _userMnemonic!,
                currentUserPublicKey: _userPublicKey!,
              );
              if (dec != null && dec.encryptedType == 'public') {
                publicPosts.add(dec);
                decryptedCount++;
              }
            } catch (_) {}
          }
          AppLogger.log('✅ node ' + nodeEndpoint + ': parsed=' + parsed.toString() + ', decryptedPublic=' + decryptedCount.toString());
          if (publicPosts.isNotEmpty) {
            final nodeId = (node['id'] as String?) ?? 'node_${storeNodes.length}';
            storeNodes.add({'id': nodeId, 'endpoint': nodeEndpoint});
            postsByNode[nodeId] = publicPosts;
          }
        } catch (e) {
          AppLogger.log('❌ Error loading public-feed from ' + nodeEndpoint + ': ' + e.toString());
        }
      }

      // 3) Update state
      setState(() {
        _storeNodes = storeNodes;
        _postsByNode = postsByNode;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load public posts: ${e.toString()}';
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
            Text(_loadingMessage),
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
              Text(_errorMessage!),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadPublicPosts, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return OptimizedPostList(
      postsByNode: _postsByNode,
      storeNodes: _storeNodes,
      isDarkMode: isDarkMode,
      userPublicKey: _userPublicKey,
      userMnemonic: _userMnemonic,
      onRefresh: _loadPublicPosts,
      emptyMessage: 'No public posts found',
      emptySubMessage: 'Be the first to create a public post!',
    );
  }
}
