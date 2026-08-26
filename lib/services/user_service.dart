import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/app_logger.dart';


class UserService {
  final String baseUrl = AppConstants.apiBaseUrl;

  // Get user profile using public key
  Future<UserProfile?> getUserProfile(String publicKey) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/profile/$publicKey'),
        headers: {
          'Content-Type': 'application/json',
        },
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
