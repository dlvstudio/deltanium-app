import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/auth_service.dart';


class UserService {
  final String baseUrl = AppConstants.apiBaseUrl;

  /// Signed headers when [publicKey] is the signed-in user: Central returns email and date of birth only to
  /// the profile's owner. Anyone else gets plain headers and the public projection.
  /// Signed as the owner when we hold the owner's key: the signed-in user's, or [ownerMnemonic] (restore,
  /// before anyone is signed in). The API only returns private fields such as the email to the owner.
  Future<Map<String, String>> _profileHeaders(String publicKey, {String? ownerMnemonic}) async {
    final headers = {'Content-Type': 'application/json'};
    try {
      final auth = ownerMnemonic == null ? await AuthService().getCurrentAuthInfo() : null;
      final mine = ownerMnemonic != null ? publicKey : auth?['publicKey'];
      final mnemonic = ownerMnemonic ?? auth?['mnemonic'];
      if (mine == null || mnemonic == null) return headers;
      if (CryptoService.normalizePublicKey(mine) != CryptoService.normalizePublicKey(publicKey)) return headers;
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final signature = await CryptoService.sign('GET/api/user/profile/$publicKey$timestamp', mnemonic);
      return {
        ...headers,
        'X-User-PubKey': CryptoService.normalizePublicKey(mine),
        'X-Timestamp': timestamp,
        'X-Signature': signature,
      };
    } catch (e) {
      AppLogger.log('Profile signing skipped: $e');
      return headers;
    }
  }

  // Get user profile using public key
  Future<UserProfile?> getUserProfile(String publicKey, {String? ownerMnemonic}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/profile/$publicKey'),
        headers: await _profileHeaders(publicKey, ownerMnemonic: ownerMnemonic),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UserProfile.fromJson(data);
      } else {
        AppLogger.log('Failed to get profile: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      AppLogger.log('Error fetching user profile: $e');
      return null;
    }
  }

  /// Update profile via signed PUT /user/profile/{publicKey}
  Future<UserProfile> updateProfile({
    required String publicKey,
    required String mnemonic,
    required String email,
    required String fullName,
    required DateTime dateOfBirth,
    String bio = '',
    String avatarUrl = '',
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final dobStr =
          '${dateOfBirth.year.toString().padLeft(4, '0')}-'
          '${dateOfBirth.month.toString().padLeft(2, '0')}-'
          '${dateOfBirth.day.toString().padLeft(2, '0')}';
      final signableData = '$email:$fullName:$dobStr:$timestamp';
      final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
      final signature = await CryptoService.sign(
        signableData,
        kIsWeb ? mnemonic : keyPair,
      );

      final body = {
        'publicKey': publicKey,
        'email': email,
        'fullName': fullName,
        'dateOfBirth': dateOfBirth.toIso8601String(),
        'bio': bio,
        'avatarUrl': avatarUrl,
        'signature': signature,
        'timestamp': timestamp,
      };

      final response = await http.put(
        Uri.parse('$baseUrl/user/profile/$publicKey'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return UserProfile.fromJson(data);
      }

      AppLogger.log(
        'Failed to update profile: ${response.statusCode} - ${response.body}',
      );
      final errBody = response.body.trim();
      throw Exception(errBody.isEmpty ? 'Update failed (${response.statusCode})' : errBody);
    } catch (e) {
      AppLogger.log('Error updating user profile: $e');
      rethrow;
    }
  }

  // Authenticate local user using stored mnemonic
  Future<Map<String, dynamic>?> authenticateLocalUser(String email, String mnemonic, String publicKey) async {
    try {
      // Generate current timestamp to use in authentication
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Create authentication message
      final message = '$email:$timestamp';
      
      // Sign the message using mnemonic
      final signature = await CryptoService.sign(message, mnemonic);
      
      // Create authentication request
      final authRequest = {
        'email': email,
        'publicKey': publicKey,
        'timestamp': timestamp,
        'signature': signature,
      };
      
      // Send authentication request
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(authRequest),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        AppLogger.log('Failed to authenticate: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      AppLogger.log('Error authenticating user: $e');
      return null;
    }
  }
} 
