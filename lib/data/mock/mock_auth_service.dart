import 'dart:async';
import 'package:deltanium_app/data/mock/mock_data.dart';
import 'package:deltanium_app/services/app_logger.dart';


class MockAuthService {
  // Singleton pattern
  static final MockAuthService _instance = MockAuthService._internal();
  factory MockAuthService() => _instance;
  MockAuthService._internal() {
    // Ensure instance is initialized with data
    AppLogger.log("MockAuthService initialized with ${MockData.users.length} users");
  }

  // Current logged in user
  MockUser? _currentUser;
  final _authController = StreamController<MockUser?>.broadcast();

  // Get current user
  MockUser? get currentUser => _currentUser;
  Stream<MockUser?> get authStateChanges => _authController.stream;

  // Direct login without any validation - for testing
  Future<MockUser?> directLogin(String email) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      // Debug print all available users
      AppLogger.log("Available users:");
      for (var user in MockData.users) {
        AppLogger.log("User: ${user.email}");
      }
      
      // Try to find user
      for (var user in MockData.users) {
        if (user.email.toLowerCase() == email.toLowerCase()) {
          _currentUser = user;
          _authController.add(user);
          AppLogger.log("Login successful for: ${user.displayName}");
          return user;
        }
      }
      
      AppLogger.log("No user found with email: $email");
      return null;
    } catch (e) {
      AppLogger.log("Error during direct login: $e");
      return null;
    }
  }

  // Login with email and password
  Future<MockUser?> login(String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    
    // Print debug info
    AppLogger.log("Login attempt with email: $email");
    AppLogger.log("Available users: ${MockData.users.length}");
    
    // Find user with matching email - ignore password for mock
    try {
      // Try manual search first
      for (var user in MockData.users) {
        if (user.email.toLowerCase() == email.toLowerCase()) {
          _currentUser = user;
          _authController.add(user);
          AppLogger.log("Login successful for: ${user.displayName}");
          return user;
        }
      }
      
      // Fallback to firstWhere
      final user = MockData.users.firstWhere(
        (user) => user.email.toLowerCase() == email.toLowerCase()
      );
      _currentUser = user;
      _authController.add(user);
      return user;
    } catch (e) {
      // User not found
      AppLogger.log("Login failed: $e");
      return null;
    }
  }

  // Login with username
  Future<MockUser?> loginWithUsername(String username, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    
    try {
      final user = MockData.users.firstWhere((user) => user.username == username);
      _currentUser = user;
      _authController.add(user);
      return user;
    } catch (e) {
      // User not found
      return null;
    }
  }

  // Login directly with user ID (for testing)
  Future<MockUser?> loginWithUserId(String userId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      final user = MockData.users.firstWhere((user) => user.id == userId);
      _currentUser = user;
      _authController.add(user);
      return user;
    } catch (e) {
      return null;
    }
  }

  // Logout
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = null;
    _authController.add(null);
    AppLogger.log("User logged out");
  }

  // Register (for mock, this just returns a predefined user)
  Future<MockUser?> register(String email, String username, String password) async {
    await Future.delayed(const Duration(seconds: 1));
    
    // Check if email or username already exists
    final emailExists = MockData.users.any((user) => user.email == email);
    final usernameExists = MockData.users.any((user) => user.username == username);
    
    if (emailExists || usernameExists) {
      return null; // Registration failed
    }
    
    // In a real app, would create a new user in the database
    // For mock, just return the first user
    final user = MockData.users.first;
    _currentUser = user;
    _authController.add(user);
    return user;
  }
  
  // Dispose resources when done
  void dispose() {
    _authController.close();
  }
} 
