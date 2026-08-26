import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/models/user_discovery.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/pre_service.dart';
import 'package:deltanium_app/features/posts/screens/my_posts_screen.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';


class FollowingPost {
  final String fileId;
  final String authorPublicKey;
  final String authorDisplayName;
  final String? authorAvatarUrl;
  final String textContent;
  final DateTime createdAt;
  final String visibility;
  final List<String> tags;
  final List<dynamic>? attachedMedia;
  final bool isPublic;
  final bool isDecrypted;

  FollowingPost({
    required this.fileId,
    required this.authorPublicKey,
    required this.authorDisplayName,
    this.authorAvatarUrl,
    required this.textContent,
    required this.createdAt,
    required this.visibility,
    this.tags = const [],
    this.attachedMedia,
    this.isPublic = false,
    this.isDecrypted = false,
  });

  String get shortAuthorKey {
    return '${authorPublicKey.substring(0, 8)}...${authorPublicKey.substring(authorPublicKey.length - 8)}';
  }
}

class FollowingFeedService {
  final AuthService _authService = AuthService();
  final String _apiBaseUrl = AppConstants.apiBaseUrl; // Central API (includes /api)

  /// Get posts shared with followers that the current user can access
  Future<List<FollowingPost>> getFollowingFeed({int limit = 20}) async {
    try {
      AppLogger.log('📰 Fetching followers-feed from all store nodes...');
      // 1. Get auth info for API calls
      final authInfo = await _authService.getCurrentAuthInfo();
      if (authInfo == null) {
        throw Exception('User not authenticated');
      }
      final currentUserPubKey = authInfo['publicKey'] as String;
      final mnemonic = authInfo['mnemonic'] as String;

      // 2. Fetch store nodes from central API
      final nodesResponse = await http.get(Uri.parse('$_apiBaseUrl/storenode/list'));
      if (nodesResponse.statusCode != 200) {
        throw Exception('Failed to fetch store nodes');
      }
      final List<dynamic> nodesJson = json.decode(nodesResponse.body);
      final List<String> nodeEndpoints = nodesJson.map<String>((node) => node['endpoint'] as String).toList();
      AppLogger.log('🗂️ Found ${nodeEndpoints.length} store nodes');

      List<FollowingPost> allPosts = [];
      for (final endpoint in nodeEndpoints) {
        try {
          final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          final method = 'GET';
          final path = '/api/post/followers-feed';
          final url = '$endpoint$path';
          final bodyHash = '';
          final dataToSign = '$method$path$timestamp$bodyHash';
          final signature = await CryptoService.sign(dataToSign, mnemonic);

          final response = await http.get(
            Uri.parse(url),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPubKey),
              'X-Timestamp': timestamp,
              'X-Signature': signature,
            },
          );

          if (response.statusCode != 200) {
            AppLogger.log('❌ Failed to fetch followers-feed from $endpoint: \\${response.statusCode}');
            continue;
          }

          final responseData = json.decode(response.body);
          final List<dynamic> posts = responseData['posts'] ?? [];
          AppLogger.log('📝 $endpoint: received \\${posts.length} posts');

          // Giải mã từng post (giống My posts)
          for (final post in posts) {
            try {
              // Prefer explicit owner/author keys. If PRE post lacks them, derive pkA from PRE bundle.
              String authorPk = (post['ownerPubKey'] ?? post['authorPublicKey'] ?? '') as String? ?? '';
              final capsuleFor = (post['capsuleFor'] ?? post['CapsuleFor']) as String?;
              final policyTag = (post['policyTag'] ?? post['PolicyTag']) as String?;
              if ((authorPk.isEmpty || authorPk.length < 66) && capsuleFor == 'tag' && policyTag != null) {
                try {
                  final b64 = (post['encryptedKey'] ?? post['EncryptedKey']) as String?;
                  if (b64 != null && b64.isNotEmpty) {
                    final bundle = base64Decode(b64);
                    final pre = PreService();
                    final pkABytes = pre.extractAuthorPkFromBundle(bundle);
                    if (pkABytes != null && pkABytes.isNotEmpty) {
                      authorPk = pkABytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
                    }
                  }
                } catch (_) {}
              }
              if (authorPk.isEmpty) {
                authorPk = (post['recipientPubKey'] ?? '') as String? ?? '';
              }
              final authorInfo = DiscoveredUser(
                publicKey: authorPk,
                displayName: authorPk,
                avatarUrl: null,
                joinDate: DateTime.now(),
              );
              final postObj = await _loadPostContent(post, currentUserPubKey, mnemonic, authorInfo, endpoint);
              if (postObj != null) allPosts.add(postObj);
            } catch (e) {
              AppLogger.log('❌ Error loading post content: $e');
            }
          }
        } catch (e) {
          AppLogger.log('❌ Error loading followers-feed from $endpoint: $e');
        }
      }
      // Sort all posts by createdAt desc
      allPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return allPosts;
    } catch (e) {
      AppLogger.log('❌ Error loading followers-feed: $e');
      return [];
    }
  }

  /// Fetch posts from a specific user that the current user can access
  // _fetchUserPosts: unused helper removed to satisfy lints

  /// Load and decrypt/parse post content
  Future<FollowingPost?> _loadPostContent(
    Map<String, dynamic> postFile,
    String currentUserPubKey,
    String mnemonic,
    DiscoveredUser authorInfo,
    String nodeEndpoint,
  ) async {
    try {
      final fileId = postFile['fileId'] as String;
      final isPublic = postFile['isPublic'] as bool? ?? false;
      final creationTime = DateTime.parse(postFile['creationTime'] as String);

      if (isPublic) {
        return await _loadPublicPost(fileId, currentUserPubKey, mnemonic, authorInfo, creationTime, nodeEndpoint);
      } else {
        return await _loadPrivatePost(fileId, currentUserPubKey, mnemonic, authorInfo, creationTime, postFile, nodeEndpoint);
      }
    } catch (e) {
      AppLogger.log('❌ Error loading post content: $e');
      return null;
    }
  }

  /// Load public post content (no decryption needed)
  Future<FollowingPost?> _loadPublicPost(
    String fileId,
    String currentUserPubKey,
    String mnemonic,
    DiscoveredUser authorInfo,
    DateTime creationTime,
    String nodeEndpoint,
  ) async {
    try {
      // Download metadata block (index 0) - plain text for public posts
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final path = '/api/file/block/$fileId/0';
      final bodyHash = '';
      
      final dataToSign = '$method$path$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, mnemonic);
      
      final metadataResponse = await http.get(
        Uri.parse('$nodeEndpoint$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPubKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      
      if (metadataResponse.statusCode != 200) {
        return null;
      }
      
      // Parse metadata as plain text JSON
      // final metadataString = utf8.decode(metadataResponse.bodyBytes); // not used for public flow here
      
      // Download content block (index 1) - plain text for public posts
      final contentPath = '/api/file/block/$fileId/1';
      final contentDataToSign = '$method$contentPath$timestamp$bodyHash';
      final contentSignature = await CryptoService.sign(contentDataToSign, mnemonic);
      
      final contentResponse = await http.get(
        Uri.parse('$nodeEndpoint$contentPath'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPubKey),
          'X-Timestamp': timestamp,
          'X-Signature': contentSignature,
        },
      );
      
      if (contentResponse.statusCode != 200) {
        return null;
      }
      
      // Parse content as plain text JSON
      final postContentString = utf8.decode(contentResponse.bodyBytes);
      final postData = json.decode(postContentString);
      
      return FollowingPost(
        fileId: fileId,
        authorPublicKey: authorInfo.publicKey,
        authorDisplayName: authorInfo.displayName ?? authorInfo.shortPublicKey,
        authorAvatarUrl: authorInfo.avatarUrl,
        textContent: postData['textContent'] ?? '',
        createdAt: creationTime,
        visibility: postData['visibility'] ?? 'public',
        tags: List<String>.from(postData['tags'] ?? []),
        attachedMedia: postData['attachedMedia'],
        isPublic: true,
        isDecrypted: true,
      );
    } catch (e) {
      AppLogger.log('❌ Error loading public post $fileId: $e');
      return null;
    }
  }

  /// Helper: Dùng chung logic giải mã post như My Posts
  Future<PostMetadata?> _decryptPostAsMyPosts({
    required String fileId,
    required String? encryptedKey,
    required String? recipientPubKey,
    required String nodeEndpoint,
    required String mnemonic,
    required DateTime creationTime,
    required String currentUserPubKey,
  }) async {
    final postMeta = PostMetadata(
      fileId: fileId,
      fileName: null,
      fileSize: '0',
      creationTime: creationTime,
      fileExtension: null,
      isDecrypted: false,
      textContent: null,
      attachedMedia: null,
      visibility: null,
      tags: null,
      firstBlockId: null,
      encryptedKey: encryptedKey,
      recipientPubKey: recipientPubKey,
      ownerPubKey: null,
    );
    // Gọi hàm giải mã của My Posts
    return await MyPostsScreen.tryDecryptPostStatic(
      postMeta,
      nodeEndpoint,
      mnemonic,
      currentUserPublicKey: currentUserPubKey,
    );
  }

  /// Load private post content (decrypt if shared with current user)
  Future<FollowingPost?> _loadPrivatePost(
    String fileId,
    String currentUserPubKey,
    String mnemonic,
    DiscoveredUser authorInfo,
    DateTime creationTime,
    Map<String, dynamic> postFile,
    String nodeEndpoint,
  ) async {
    try {
      final encryptedKey = postFile['encryptedKey'] ?? postFile['EncryptedKey'];
      final recipientPubKey = postFile['recipientPubKey'] ?? postFile['RecipientPubKey'];
      final capsuleForRaw = (postFile['capsuleFor'] ?? postFile['CapsuleFor']) as String?;
      final capsuleFor = capsuleForRaw?.toLowerCase();
      final policyTag = (postFile['policyTag'] ?? postFile['PolicyTag']) as String?;
      final firstBlockId = (postFile['firstBlockId'] ?? postFile['FirstBlockId']) as String?;

      if (encryptedKey != null && (capsuleFor == null || capsuleFor != 'tag')) {
        // Option 1: per-recipient ECIES
        final postMeta = await _decryptPostAsMyPosts(
          fileId: fileId,
          encryptedKey: encryptedKey,
          recipientPubKey: recipientPubKey,
          nodeEndpoint: nodeEndpoint,
          mnemonic: mnemonic,
          creationTime: creationTime,
          currentUserPubKey: currentUserPubKey,
        );
        if (postMeta == null || !postMeta.isDecrypted) return null;
        return FollowingPost(
          fileId: postMeta.fileId,
          authorPublicKey: authorInfo.publicKey,
          authorDisplayName: authorInfo.displayName ?? authorInfo.shortPublicKey,
          authorAvatarUrl: authorInfo.avatarUrl,
          textContent: postMeta.textContent ?? '',
          createdAt: postMeta.creationTime,
          visibility: postMeta.visibility ?? 'followers',
          tags: postMeta.tags ?? <String>[],
          attachedMedia: postMeta.attachedMedia,
          isPublic: false,
          isDecrypted: true,
        );
      }

      // Option 2: PRE (tag-based)
      if (capsuleFor == 'tag' && policyTag is String && policyTag.isNotEmpty) {
        try {
          final pre = PreService();
          // 1) Get transform token (proxy mode)
          final token = await pre.fetchTransformToken(
            _apiBaseUrl,
            CryptoService.normalizePublicKey(currentUserPubKey),
            // Must pass the author's key (owner/author), not recipient
            authorInfo.publicKey,
            policyTag,
            mnemonic,
            fileId: fileId,
          );
          if (token == null || token.isEmpty) {
            AppLogger.log('❌ PRE: Failed to obtain transform token');
            return null;
          }

          // 2) Ask Store to re-encrypt bundle for B
          final reencBundle = await pre.requestProxyReencrypt(
            nodeEndpoint,
            fileId,
            policyTag,
            token,
            CryptoService.normalizePublicKey(currentUserPubKey),
            mnemonic,
          );
          if (reencBundle == null) {
            AppLogger.log('❌ PRE: Store re-encrypt returned null');
            return null;
          }

          // 3) Decapsulate on client to recover K (not yet implemented in Flutter)
          final symmetricKey = await pre.decapsulateAndRecoverKey(reencBundle, mnemonic, policyTag: policyTag);
          if (symmetricKey == null || symmetricKey.isEmpty) {
            AppLogger.log('❌ PRE: Decapsulation not available in Flutter yet');
            return null;
          }

          // 4) Download and decrypt metadata block (index 0) using firstBlockId, then fetch content by contentBlockIds
          if (firstBlockId == null || firstBlockId.isEmpty) {
            AppLogger.log('❌ PRE: Missing firstBlockId in feed item');
            return null;
          }
          final ts0 = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          const method0 = 'GET';
          final metaPath = '/api/file/block/$firstBlockId'; // direct block by ID
          const bodyHash0 = '';
          final sign0 = await CryptoService.sign('$method0$metaPath$ts0$bodyHash0', mnemonic);
          final metaResp = await http.get(
            Uri.parse('$nodeEndpoint$metaPath'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPubKey),
              'X-Timestamp': ts0,
              'X-Signature': sign0,
            },
          );
          if (metaResp.statusCode != 200) {
            AppLogger.log('❌ PRE: Failed to download metadata block: ${metaResp.statusCode}');
            return null;
          }
          final metaDecrypted = await FileCryptoService.decryptRawBlockWithKey(metaResp.bodyBytes, symmetricKey);
          if (metaDecrypted == null) return null;
          final metaJson = utf8.decode(metaDecrypted);
          final meta = json.decode(metaJson) as Map<String, dynamic>;

          final List<dynamic> contentBlockIds = (meta['contentBlockIds'] as List?) ?? const [];
          if (contentBlockIds.isEmpty) {
            AppLogger.log('❌ PRE: No contentBlockIds found in metadata');
            return null;
          }
          final firstContentBlockId = contentBlockIds.first as String;

          // Fetch and decrypt first content block
          final ts1 = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
          const method1 = 'GET';
          final contentPath = '/api/file/block/$firstContentBlockId';
          const bodyHash1 = '';
          final sign1 = await CryptoService.sign('$method1$contentPath$ts1$bodyHash1', mnemonic);
          final contentResp = await http.get(
            Uri.parse('$nodeEndpoint$contentPath'),
            headers: {
              'X-User-PubKey': CryptoService.normalizePublicKey(currentUserPubKey),
              'X-Timestamp': ts1,
              'X-Signature': sign1,
            },
          );
          if (contentResp.statusCode != 200) {
            AppLogger.log('❌ PRE: Failed to download content block by id: ${contentResp.statusCode}');
            return null;
          }
          final contentDecrypted = await FileCryptoService.decryptRawBlockWithKey(contentResp.bodyBytes, symmetricKey);
          if (contentDecrypted == null) return null;
          final postJson = utf8.decode(contentDecrypted);
          final postData = json.decode(postJson);
          return FollowingPost(
            fileId: fileId,
            authorPublicKey: authorInfo.publicKey,
            authorDisplayName: authorInfo.displayName ?? authorInfo.shortPublicKey,
            authorAvatarUrl: authorInfo.avatarUrl,
            textContent: postData['textContent'] ?? '',
            createdAt: creationTime,
            visibility: postData['visibility'] ?? 'followers',
            tags: List<String>.from(postData['tags'] ?? []),
            attachedMedia: postData['attachedMedia'],
            isPublic: false,
            isDecrypted: true,
          );
        } catch (e) {
          AppLogger.log('❌ PRE: Error loading PRE post $fileId: $e');
          return null;
        }
      }

      AppLogger.log('📨 Private post $fileId missing encryptedKey and no PRE policy');
      return null;
    } catch (e) {
      AppLogger.log('❌ Error loading private post $fileId: $e');
      return null;
    }
  }
} 
