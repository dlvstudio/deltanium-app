import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/pre_ffi.dart';
import 'package:deltanium_app/services/pre_keys.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';

/// Service to sync followers and generate/upload PRE rekeys
/// Implements Option 3: Delegated Generation (Author generates rk locally)
class RekeySyncService {
  static const String _lastSyncKey = 'pre_rekey_last_sync_timestamp';
  
  /// Check for new followers and generate rekeys for them
  /// Should be called periodically (e.g., when app starts, or in background)
  static Future<void> syncFollowersAndGenerateRekeys({
    required String mnemonic,
    required String userPublicKey,
  }) async {
    try {
      AppLogger.log('🔄 REKEY_SYNC: Starting follower sync...');

      // Monthly PRE v2 rotation: everyone who follows now gets this month's followers key (people who left do not).
      await generateRekeysForTag(mnemonic: mnemonic, userPublicKey: userPublicKey, policyTag: PreKeys.followersTag());

      // 1. Get last sync timestamp
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
      
      AppLogger.log('🔄 REKEY_SYNC: Last sync timestamp: $lastSync');
      
      // 2. Fetch new followers from Central API
      final newFollowers = await _fetchNewFollowers(userPublicKey, mnemonic, lastSync);
      
      if (newFollowers.isEmpty) {
        AppLogger.log('✅ REKEY_SYNC: No new followers to process');
        return;
      }
      
      AppLogger.log('📋 REKEY_SYNC: Found ${newFollowers.length} new followers');
      
      // 3. Tags a new follower gets: PRE v2 followers tags of the last 12 months (recent posts), plus the v1
      //    yearly tag so old posts stay readable.
      final tags = [...PreKeys.recentFollowersTags(), 'followers:${DateTime.now().year}'];

      // 4. Generate rekeys for each new follower and tag
      final rekeys = <Map<String, String>>[];

      for (final follower in newFollowers) {
        final followerPubKey = follower['followerPubKey'] as String;
        for (final policyTag in tags) {
        try {
          AppLogger.log('🔑 REKEY_SYNC: Generating rekey for follower: ${followerPubKey.substring(0, 10)}...');
          
          // Generate rk(A→B) using PRE FFI
          final rkBytes = await _generateRekey(
            mnemonic: mnemonic,
            followerPubKey: followerPubKey,
            policyTag: policyTag,
          );
          
          if (rkBytes != null) {
            rekeys.add({
              'followerPubKey': followerPubKey,
              'tag': policyTag,
              'rk': base64.encode(rkBytes),
              'scope': 'tag',
            });
            
            AppLogger.log('✅ REKEY_SYNC: Generated rekey for ${followerPubKey.substring(0, 10)}...');
          } else {
            AppLogger.log('❌ REKEY_SYNC: Failed to generate rekey for ${followerPubKey.substring(0, 10)}...');
          }
        } catch (e) {
          AppLogger.log('❌ REKEY_SYNC: Error generating rekey for $followerPubKey ($policyTag): $e');
        }
        }
      }
      
      if (rekeys.isEmpty) {
        AppLogger.log('❌ REKEY_SYNC: No rekeys generated successfully');
        return;
      }
      
      // 5. Upload rekeys to Central API (batch)
      final uploaded = await _uploadRekeysBatch(
        userPublicKey: userPublicKey,
        mnemonic: mnemonic,
        rekeys: rekeys,
      );
      
      if (uploaded) {
        // 6. Update last sync timestamp
        final now = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
        await prefs.setInt(_lastSyncKey, now);
        
        AppLogger.log('✅ REKEY_SYNC: Successfully synced ${rekeys.length} rekeys');
      } else {
        AppLogger.log('❌ REKEY_SYNC: Failed to upload rekeys');
      }
    } catch (e) {
      AppLogger.log('❌ REKEY_SYNC: Error during sync: $e');
    }
  }
  
  /// TOKENOMICS_V2 §9: give every paying subscriber of the current month (and the author)
  /// a rekey for `subscribers:YYYY-MM`. Remembers who already got one this epoch.
  static Future<void> syncSubscriberRekeys({
    required String mnemonic,
    required String userPublicKey,
  }) async {
    try {
      final tag = PreKeys.subscribersTag(); // PRE v2: a key per month, so a past month's subscriber cannot read later posts
      final prefs = await SharedPreferences.getInstance();
      final doneKey = 'pre_rekey_subscribers_done_$tag';
      final done = (prefs.getStringList(doneKey) ?? const <String>[]).toSet();
      final subscribers = await WalletService.getSubscribers();
      final targets = {userPublicKey, ...subscribers}.where((pk) => !done.contains(pk)).toList();
      if (targets.isEmpty) return;

      final rekeys = <Map<String, String>>[];
      for (final pk in targets) {
        final rk = await _generateRekey(mnemonic: mnemonic, followerPubKey: pk, policyTag: tag);
        if (rk != null) {
          rekeys.add({'followerPubKey': pk, 'tag': tag, 'rk': base64.encode(rk), 'scope': 'tag'});
        }
      }
      if (rekeys.isEmpty) return;
      final uploaded = await _uploadRekeysBatch(
        userPublicKey: userPublicKey,
        mnemonic: mnemonic,
        rekeys: rekeys,
      );
      if (uploaded) {
        done.addAll(rekeys.map((r) => r['followerPubKey']!));
        await prefs.setStringList(doneKey, done.toList());
        AppLogger.log('✅ REKEY_SYNC: ${rekeys.length} subscriber rekeys for $tag');
      }
    } catch (e) {
      AppLogger.log('❌ REKEY_SYNC: subscriber sync error: $e');
    }
  }

  /// Generate a single rekey for a follower
  /// Returns rk(A→B) bytes
  static Future<Uint8List?> _generateRekey({
    required String mnemonic,
    required String followerPubKey,
    required String policyTag,
  }) async {
    try {
      // Get author's private key from mnemonic (32 bytes)
      // Same method as EciesService._getPrivateKeyFromMnemonic
      // Per-tag author key for PRE v2 tags, the wallet key for v1 tags.
      final skAuthor = PreKeys.authorSecret(mnemonic, policyTag);
      
      // Convert follower public key hex to bytes
      final followerPkBytes = _hexToBytes(followerPubKey);
      
      // Generate rekey using PRE FFI: rk(A→B, tag)
      final pre = PreFfi.instance();
      final rkBytes = pre.generateRekey(
        skAuthor: skAuthor,
        pkRecipient: followerPkBytes,
        tag: policyTag,
      );
      
      return rkBytes;
    } catch (e) {
      AppLogger.log('❌ REKEY_GEN: Error generating rekey: $e');
      return null;
    }
  }
  
  /// Convert hex string to bytes
  static Uint8List _hexToBytes(String hex) {
    final cleaned = hex.startsWith('0x') ? hex.substring(2) : hex;
    return Uint8List.fromList(
      List<int>.generate(
        cleaned.length ~/ 2,
        (i) => int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }
  
  /// Fetch new followers from Central API since last sync
  static Future<List<Map<String, dynamic>>> _fetchNewFollowers(
    String userPublicKey,
    String mnemonic,
    int sinceTimestamp,
  ) async {
    try {
      // Build URL with query param
      final url = sinceTimestamp > 0
          ? '${AppConstants.apiBaseUrl}/user/new-followers?sinceTimestamp=$sinceTimestamp'
          : '${AppConstants.apiBaseUrl}/user/new-followers';
      
      // Create signed request
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final path = '/api/user/new-followers${sinceTimestamp > 0 ? '?sinceTimestamp=$sinceTimestamp' : ''}';
      final bodyHash = '';
      
      final dataToSign = '$method$path$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, mnemonic);
      
      // Make request
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final followers = data['followers'] as List<dynamic>? ?? [];
        return followers.map((f) => Map<String, dynamic>.from(f)).toList();
      } else {
        AppLogger.log('❌ FETCH_FOLLOWERS: API returned ${response.statusCode}: ${response.body}');
        return [];
      }
    } catch (e) {
      AppLogger.log('❌ FETCH_FOLLOWERS: Error fetching new followers: $e');
      return [];
    }
  }
  
  /// Upload rekeys batch to Central API
  static Future<bool> _uploadRekeysBatch({
    required String userPublicKey,
    required String mnemonic,
    required List<Map<String, String>> rekeys,
  }) async {
    try {
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'POST';
      final path = '/api/policy/upload-rekeys-batch';
      
      final bodyJson = json.encode({
        'rekeys': rekeys,
      });
      
      AppLogger.log('📤 UPLOAD_REKEYS: Body to send (${bodyJson.length} chars): ${bodyJson.substring(0, math.min(200, bodyJson.length))}...');
      
      // Calculate SHA256 hash of body (hex format)
      final bodyBytes = utf8.encode(bodyJson);
      final bodyHashBytes = sha256.convert(bodyBytes).bytes;
      final bodyHash = bodyHashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      
      AppLogger.log('📤 UPLOAD_REKEYS: Body hash: $bodyHash');
      
      final dataToSign = '$method$path$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, mnemonic);
      
      AppLogger.log('📤 UPLOAD_REKEYS: Sending POST to ${AppConstants.apiBaseUrl}/policy/upload-rekeys-batch');
      
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/policy/upload-rekeys-batch'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
        body: bodyJson,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final count = data['count'] as int? ?? 0;
        AppLogger.log('✅ UPLOAD_REKEYS: Successfully uploaded $count rekeys');
        return true;
      } else {
        AppLogger.log('❌ UPLOAD_REKEYS: API returned ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e) {
      AppLogger.log('❌ UPLOAD_REKEYS: Error uploading rekeys: $e');
      return false;
    }
  }
  
  /// Check if followers need rekeys for a specific tag
  /// Returns list of follower public keys that need rekeys
  static Future<List<String>> getFollowersWithoutRekey({
    required String userPublicKey,
    required String mnemonic,
    required String tag,
  }) async {
    try {
      final url = '${AppConstants.apiBaseUrl}/user/followers-without-rekey?tag=$tag';
      
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final method = 'GET';
      final path = '/api/user/followers-without-rekey?tag=$tag';
      final bodyHash = '';
      
      final dataToSign = '$method$path$timestamp$bodyHash';
      final signature = await CryptoService.sign(dataToSign, mnemonic);
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
          'X-Timestamp': timestamp,
          'X-Signature': signature,
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final followers = data['followers'] as List<dynamic>? ?? [];
        return followers.map((f) => f.toString()).toList();
      } else {
        AppLogger.log('❌ FOLLOWERS_WITHOUT_REKEY: API returned ${response.statusCode}: ${response.body}');
        return [];
      }
    } catch (e) {
      AppLogger.log('❌ FOLLOWERS_WITHOUT_REKEY: Error: $e');
      return [];
    }
  }
  
  /// Generate and upload rekeys for all existing followers for a new tag
  /// Used when creating a post with a new policy tag
  static Future<void> generateRekeysForTag({
    required String mnemonic,
    required String userPublicKey,
    required String policyTag,
  }) async {
    try {
      AppLogger.log('🔄 REKEY_TAG: Generating rekeys for tag: $policyTag');
      
      // Get followers who don't have rekeys for this tag
      final followers = await getFollowersWithoutRekey(
        userPublicKey: userPublicKey,
        mnemonic: mnemonic,
        tag: policyTag,
      );
      
      if (followers.isEmpty) {
        AppLogger.log('✅ REKEY_TAG: All followers already have rekeys for $policyTag');
        return;
      }
      
      AppLogger.log('📋 REKEY_TAG: Generating rekeys for ${followers.length} followers');
      
      // Generate rekeys
      final rekeys = <Map<String, String>>[];
      
      for (final followerPubKey in followers) {
        try {
          final rkBytes = await _generateRekey(
            mnemonic: mnemonic,
            followerPubKey: followerPubKey,
            policyTag: policyTag,
          );
          
          if (rkBytes != null) {
            rekeys.add({
              'followerPubKey': followerPubKey,
              'tag': policyTag,
              'rk': base64.encode(rkBytes),
              'scope': 'tag',
            });
          }
        } catch (e) {
          AppLogger.log('❌ REKEY_TAG: Error for $followerPubKey: $e');
        }
      }
      
      if (rekeys.isEmpty) {
        AppLogger.log('❌ REKEY_TAG: No rekeys generated');
        return;
      }
      
      // Upload batch
      await _uploadRekeysBatch(
        userPublicKey: userPublicKey,
        mnemonic: mnemonic,
        rekeys: rekeys,
      );
      
      AppLogger.log('✅ REKEY_TAG: Completed rekey generation for $policyTag');
    } catch (e) {
      AppLogger.log('❌ REKEY_TAG: Error: $e');
    }
  }
}

