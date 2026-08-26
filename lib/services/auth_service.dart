import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/models/registration_response.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deltanium_app/services/app_logger.dart';


class AuthService {
  final String baseUrl = AppConstants.apiBaseUrl;
  static const String CURRENT_USER_KEY = 'current_user';

  Future<bool> verifyRegistration(String publicKey) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/verify/$publicKey'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as bool;
      } else {
        throw Exception('Failed to verify registration: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }
  
  /// Get current authentication information
  /// Returns a map with email, mnemonic, and publicKey if available
  /// Does NOT auto-login from saved users - use autoLoginFromSavedUsers() for that
  Future<Map<String, String>?> getCurrentAuthInfo() async {
    try {
      // Only get the current user from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final currentUserJson = prefs.getString(CURRENT_USER_KEY);
      
      if (currentUserJson != null) {
        AppLogger.log('Found current user in SharedPreferences');
        return Map<String, String>.from(json.decode(currentUserJson));
      }
      
      // No current user found
      AppLogger.log('No current user found');
      return null;
    } catch (e) {
      AppLogger.log('Error getting current auth info: $e');
      return null;
    }
  }

  /// Auto-login from saved users (only use during app startup/login screen)
  Future<Map<String, String>?> autoLoginFromSavedUsers() async {
    try {
      // Check if we have any saved users
      final savedUsers = await CryptoService.getSavedUsers();
      
      if (savedUsers.isEmpty) {
        AppLogger.log('No saved users found for auto-login');
        return null;
      }
      
      // Use the first saved user
      final currentUser = savedUsers.first;
      
      // Save this user as the current user
      await setCurrentUser({
        'email': currentUser['email'] as String,
        'mnemonic': currentUser['mnemonic'] as String,
        'publicKey': currentUser['pubkey'] as String,
      });
      
      AppLogger.log('Auto-logged in user: ${currentUser['email']}');
      
      return {
        'email': currentUser['email'] as String,
        'mnemonic': currentUser['mnemonic'] as String,
        'publicKey': currentUser['pubkey'] as String,
      };
    } catch (e) {
      AppLogger.log('Error during auto-login: $e');
      return null;
    }
  }
  
  /// Set the current user
  Future<bool> setCurrentUser(Map<String, String> userData) async {
    try {
      AppLogger.log('Setting current user: ${userData['email']}');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(CURRENT_USER_KEY, json.encode(userData));
      return true;
    } catch (e) {
      AppLogger.log('Error setting current user: $e');
      return false;
    }
  }
  
  /// Save authentication information
  Future<bool> saveAuthInfo(String email, String mnemonic, String publicKey) async {
    try {
      // 🔧 FIX: Normalize public key to compressed format before saving
      final normalizedPublicKey = CryptoService.normalizePublicKey(publicKey);
      AppLogger.log('AuthService.saveAuthInfo: Normalized key ${publicKey.length} -> ${normalizedPublicKey.length} chars');
      
      // First save the user's credentials
      await CryptoService.saveUser(email, mnemonic, normalizedPublicKey);
      
      // Then set as current user
      final userData = {
        'email': email,
        'mnemonic': mnemonic,
        'publicKey': normalizedPublicKey, // Use normalized compressed key
      };
      
      return await setCurrentUser(userData);
    } catch (e) {
      AppLogger.log('Error saving auth info: $e');
      return false;
    }
  }
  
  /// Logout - remove current user
  Future<bool> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(CURRENT_USER_KEY);
      AppLogger.log('Logged out user');
      return true;
    } catch (e) {
      AppLogger.log('Error logging out: $e');
      return false;
    }
  }

  /// Complete logout - remove current user and all saved users
  Future<bool> completeLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(CURRENT_USER_KEY);
      await CryptoService.clearSavedUsers();
      AppLogger.log('Completely logged out - all user data cleared');
      return true;
    } catch (e) {
      AppLogger.log('Error during complete logout: $e');
      return false;
    }
  }
} 
