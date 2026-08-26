import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/models/user_discovery.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/blockchain_tx_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';


class UserDiscoveryService {
  static String get baseUrl => AppConstants.apiBaseUrl; // includes /api
  final AuthService _authService = AuthService();

  /// Search for users by display name or public key
  Future<List<DiscoveredUser>> searchUsers(String query) async {
    try {
      if (query.trim().isEmpty) {
        return [];
      }

      final authInfo = await _authService.getCurrentAuthInfo();
      if (authInfo == null) {
        throw Exception('User not authenticated');
      }

      final userPublicKey = authInfo['publicKey'] as String;
      final mnemonic = authInfo['mnemonic'] as String;

      // Create authenticated request - match create post logic
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final path = '/user/search?q=${Uri.encodeComponent(query)}';
      final bodyHash = ''; // Empty for GET requests

      // Sign exactly Request.Path + QueryString (server route is /api/...)
      final pathForSigning = '/api$path';
      final dataToSign = '$method$pathForSigning$timestamp$bodyHash';
      
      // Generate signature like create post
      final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
      final signature = await CryptoService.sign(dataToSign, kIsWeb ? mnemonic : keyPair);

      final _httpStart = DateTime.now();
      AppLogger.log('🌐 HTTP GET ' + '$baseUrl$path' + ' START ' + _httpStart.toIso8601String());
      final response = await http.get(
        Uri.parse('$baseUrl$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
          'Content-Type': 'application/json',
        },
      );
      AppLogger.log('🌐 HTTP GET ' + '$baseUrl$path' + ' END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_httpStart).inMilliseconds.toString() + 'ms) code=' + response.statusCode.toString());

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> usersJson = responseData['users'] ?? [];
        
        return usersJson.map((userJson) => DiscoveredUser.fromJson(userJson)).toList();
      } else {
        AppLogger.log('User search failed: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      AppLogger.log('Error searching users: $e');
      return [];
    }
  }

  /// Get recently registered users (last 10)
  Future<List<DiscoveredUser>> getRecentUsers() async {
    try {
      final authInfo = await _authService.getCurrentAuthInfo();
      if (authInfo == null) {
        throw Exception('User not authenticated');
      }

      final userPublicKey = authInfo['publicKey'] as String;
      final mnemonic = authInfo['mnemonic'] as String;

      // Create authenticated request - match create post logic
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final path = '/user/recent?limit=10';
      final bodyHash = ''; // Empty for GET requests

      // Sign exactly Request.Path + QueryString (server route is /api/...)
      final pathForSigning = '/api$path';
      final dataToSign = '$method$pathForSigning$timestamp$bodyHash';
      
      // Generate signature like create post
      final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
      final signature = await CryptoService.sign(dataToSign, kIsWeb ? mnemonic : keyPair);

      final _httpStart = DateTime.now();
      AppLogger.log('🌐 HTTP GET ' + '$baseUrl$path' + ' START ' + _httpStart.toIso8601String());
      final response = await http.get(
        Uri.parse('$baseUrl$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
          'Content-Type': 'application/json',
        },
      );
      AppLogger.log('🌐 HTTP GET ' + '$baseUrl$path' + ' END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_httpStart).inMilliseconds.toString() + 'ms) code=' + response.statusCode.toString());

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> usersJson = responseData['users'] ?? [];
        
        return usersJson.map((userJson) => DiscoveredUser.fromJson(userJson)).toList();
      } else {
        AppLogger.log('Recent users fetch failed: ${response.statusCode} - ${response.body}');
        return _generateMockRecentUsers(); // Fallback to mock data
      }
    } catch (e) {
      AppLogger.log('Error fetching recent users: $e');
      return _generateMockRecentUsers(); // Fallback to mock data
    }
  }

  /// Get users that the current user is following
  Future<List<DiscoveredUser>> getFollowingUsers() async {
    try {
      final authInfo = await _authService.getCurrentAuthInfo();
      if (authInfo == null) {
        throw Exception('User not authenticated');
      }

      final userPublicKey = authInfo['publicKey'] as String;
      final mnemonic = authInfo['mnemonic'] as String;

      // Create authenticated request - match create post logic
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final path = '/user/following?limit=10';
      final bodyHash = ''; // Empty for GET requests

      // Sign exactly Request.Path + QueryString (server route is /api/...)
      final pathForSigning = '/api$path';
      final dataToSign = '$method$pathForSigning$timestamp$bodyHash';
      
      // Generate signature like create post
      final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
      final signature = await CryptoService.sign(dataToSign, kIsWeb ? mnemonic : keyPair);

      final _httpStart = DateTime.now();
      AppLogger.log('🌐 HTTP GET ' + '$baseUrl$path' + ' START ' + _httpStart.toIso8601String());
      final response = await http.get(
        Uri.parse('$baseUrl$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
          'Content-Type': 'application/json',
        },
      );
      AppLogger.log('🌐 HTTP GET ' + '$baseUrl$path' + ' END ' + DateTime.now().toIso8601String() + ' (' + DateTime.now().difference(_httpStart).inMilliseconds.toString() + 'ms) code=' + response.statusCode.toString());

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> usersJson = responseData['users'] ?? [];
        
        return usersJson.map((userJson) => DiscoveredUser.fromJson(userJson)).toList();
      } else {
        AppLogger.log('Following users fetch failed: ${response.statusCode} - ${response.body}');
        return _generateMockFollowingUsers(); // Fallback to mock data
      }
    } catch (e) {
      AppLogger.log('Error fetching following users: $e');
      return _generateMockFollowingUsers(); // Fallback to mock data
    }
  }

  /// Follow a user
  Future<bool> followUser(String publicKey) async {
    try {
      final authInfo = await _authService.getCurrentAuthInfo();
      if (authInfo == null) {
        throw Exception('User not authenticated');
      }

      final userPublicKey = authInfo['publicKey'] as String;
      final mnemonic = authInfo['mnemonic'] as String;

      // Create simple follow action to sign (with timestamp for blockchain)
      final followTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
      final followAction = {
        'action': 'follow',
        'follower': userPublicKey,
        'following': publicKey,
        'timestamp': followTimestamp.toString(),
      };
      
      // Sign the follow action
      final actionToSign = json.encode(followAction);
      AppLogger.log('[FOLLOW] Action to sign: $actionToSign');
      
      final followSignature = await CryptoService.sign(actionToSign, mnemonic);
      AppLogger.log('[FOLLOW] Follow signature: $followSignature');

      final requestBody = json.encode({
        'targetPublicKey': publicKey,
        'signature': followSignature,
        'signedData': actionToSign,
        'timestamp': followTimestamp,
      });

      // Create authenticated request - match create post logic
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'POST';
      final path = '/user/follow';
      
      // Calculate body hash like create post
      final bodyBytes = utf8.encode(requestBody);
      final bodyHashBytes = sha256.convert(bodyBytes).bytes;
      final bodyHash = bodyHashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // Sign exactly Request.Path (server route is /api/...)
      final pathForSigning = Uri.parse('/api$path').path;
      final dataToSign = '$method$pathForSigning$timestamp$bodyHash';

      AppLogger.log('[FOLLOW] Data to sign for auth: $dataToSign');
      final authSignature = await CryptoService.sign(dataToSign, mnemonic);

      final response = await http.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': userPublicKey,
          'X-Timestamp': timestamp,
          'X-Signature': authSignature,
        },
        body: requestBody,
      );

      AppLogger.log('[FOLLOW] Response: ${response.statusCode} - ${response.body}');
      if (response.statusCode == 200) {
        await BlockchainTxService.submitTx(
          type: 'Follow',
          from: userPublicKey,
          to: publicKey,
          data: {
            'follower': userPublicKey,
            'following': publicKey,
          },
          fee: 1,
          mnemonic: mnemonic,
        );
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.log('[FOLLOW] Error: $e');
      return false;
    }
  }

  /// Unfollow a user
  Future<bool> unfollowUser(String publicKey) async {
    try {
      final authInfo = await _authService.getCurrentAuthInfo();
      if (authInfo == null) {
        throw Exception('User not authenticated');
      }

      final userPublicKey = authInfo['publicKey'] as String;
      final mnemonic = authInfo['mnemonic'] as String;

      final requestBody = json.encode({
        'targetPublicKey': publicKey,
      });

      // Create authenticated request - match create post logic
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'POST';
      final path = '/user/unfollow';
      
      // Calculate body hash like create post
      final bodyBytes = utf8.encode(requestBody);
      final bodyHashBytes = sha256.convert(bodyBytes).bytes;
      final bodyHash = bodyHashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toLowerCase();

      // Sign exactly Request.Path (server route is /api/...)
      final pathForSigning = Uri.parse('/api$path').path;
      final dataToSign = '$method$pathForSigning$timestamp$bodyHash';
      
      // Generate signature like create post
      final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
      final signature = await CryptoService.sign(dataToSign, kIsWeb ? mnemonic : keyPair);

      final response = await http.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        AppLogger.log('Successfully unfollowed user: $publicKey');
        await BlockchainTxService.submitTx(
          type: 'Unfollow',
          from: userPublicKey,
          to: publicKey,
          data: {
            'follower': userPublicKey,
            'following': publicKey,
          },
          fee: 1,
          mnemonic: mnemonic,
        );
        return true;
      } else {
        AppLogger.log('Unfollow user failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      AppLogger.log('Error unfollowing user: $e');
      return false;
    }
  }

  /// Generate mock recent users for testing when API is not available
  List<DiscoveredUser> _generateMockRecentUsers() {
    final now = DateTime.now();
    return [
      DiscoveredUser(
        publicKey: '021d35556bed51e3767caf6e34c22f99ba6d14d07dc086b114b746fa632ad74775',
        displayName: 'Alice Crypto',
        bio: 'Blockchain enthusiast and developer 🚀',
        joinDate: now.subtract(Duration(days: 1)),
        postsCount: 12,
        followersCount: 45,
        followingCount: 23,
        lastActive: now.subtract(Duration(minutes: 15)),
      ),
      DiscoveredUser(
        publicKey: '03ed8e4b9d3d8d0641a90f0eb86055daf48459023b9f328763fca41789dfc56f96',
        displayName: 'Bob Web3',
        bio: 'DeFi researcher and investor',
        joinDate: now.subtract(Duration(days: 2)),
        postsCount: 8,
        followersCount: 32,
        followingCount: 41,
        lastActive: now.subtract(Duration(hours: 2)),
      ),
      DiscoveredUser(
        publicKey: '02a4b7c9d8e5f1234567890abcdef1234567890abcdef1234567890abcdef123',
        displayName: 'Charlie NFT',
        bio: 'Digital artist creating unique NFTs',
        joinDate: now.subtract(Duration(days: 3)),
        postsCount: 25,
        followersCount: 78,
        followingCount: 15,
        lastActive: now.subtract(Duration(hours: 6)),
      ),
      DiscoveredUser(
        publicKey: '031a2b3c4d5e6f789012345678901234567890123456789012345678901234567',
        displayName: 'Diana DAO',
        bio: 'Building the future of decentralized governance',
        joinDate: now.subtract(Duration(days: 4)),
        postsCount: 19,
        followersCount: 56,
        followingCount: 34,
        lastActive: now.subtract(Duration(days: 1)),
      ),
      DiscoveredUser(
        publicKey: '029f8e7d6c5b4a39281764530192847365019284736501928473650192847365',
        displayName: 'Ethan Smart',
        bio: 'Smart contract developer and auditor',
        joinDate: now.subtract(Duration(days: 5)),
        postsCount: 31,
        followersCount: 89,
        followingCount: 52,
        lastActive: now.subtract(Duration(hours: 12)),
      ),
    ];
  }

  /// Generate mock following users for testing when API is not available
  List<DiscoveredUser> _generateMockFollowingUsers() {
    final now = DateTime.now();
    return [
      DiscoveredUser(
        publicKey: '021d35556bed51e3767caf6e34c22f99ba6d14d07dc086b114b746fa632ad74775',
        displayName: 'Alice Crypto',
        bio: 'Blockchain enthusiast and developer 🚀',
        joinDate: now.subtract(Duration(days: 30)),
        postsCount: 45,
        followersCount: 156,
        followingCount: 78,
        isFollowing: true,
        lastActive: now.subtract(Duration(minutes: 30)),
      ),
      DiscoveredUser(
        publicKey: '03ed8e4b9d3d8d0641a90f0eb86055daf48459023b9f328763fca41789dfc56f96',
        displayName: 'Bob Web3',
        bio: 'DeFi researcher and investor',
        joinDate: now.subtract(Duration(days: 45)),
        postsCount: 23,
        followersCount: 89,
        followingCount: 112,
        isFollowing: true,
        lastActive: now.subtract(Duration(hours: 4)),
      ),
      DiscoveredUser(
        publicKey: '02a4b7c9d8e5f1234567890abcdef1234567890abcdef1234567890abcdef123',
        displayName: 'Charlie NFT',
        bio: 'Digital artist creating unique NFTs',
        joinDate: now.subtract(Duration(days: 60)),
        postsCount: 67,
        followersCount: 234,
        followingCount: 45,
        isFollowing: true,
        lastActive: now.subtract(Duration(hours: 8)),
      ),
    ];
  }

  // Helper method to generate GUID like C#
  String _generateGuid() {
    final uuid = Uuid();
    return uuid.v4();
  }
} 
