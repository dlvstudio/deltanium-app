import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/screens/login/login_screen.dart';
import 'package:deltanium_app/screens/home/home_screen.dart';
import 'package:deltanium_app/features/profile/screens/profile_screen.dart';
import 'package:deltanium_app/features/profile/screens/local_user_profile_screen.dart';
import 'package:deltanium_app/features/settings/screens/settings_screen.dart';
import 'package:deltanium_app/features/search/screens/search_screen.dart';
import 'package:deltanium_app/features/notifications/screens/notifications_screen.dart';
import 'package:deltanium_app/features/messages/screens/messages_screen.dart';
import 'package:deltanium_app/features/messages/screens/chat_conversation_screen.dart';
import 'package:deltanium_app/features/create_post/screens/create_post_screen.dart';
import 'package:deltanium_app/features/local_user/local_user_home_screen.dart';
import 'package:deltanium_app/features/file_manager/screens/secure_file_upload_screen.dart';
import 'package:deltanium_app/features/landing/screens/landing_screen.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/data/mock/mock_data.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/config/constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/services/app_logger.dart';


final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

// Define route names as constants for easy reference
class AppRoutes {
  static const String landing = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String profile = '/profile';
  static const String localUserProfile = '/profile/me';
  static const String settings = '/settings';
  static const String search = '/search';
  static const String notifications = '/notifications';
  static const String messages = '/messages';
  static const String chatConversation = '/messages/chat';
  static const String createPost = '/create-post';
  static const String localUserHome = '/app';
  static const String secureFileUpload = '/secure-file-upload';
}

// Helper function to convert MockUser to UserProfile
UserProfile _getUserProfile() {
  // Create a default UserProfile from the first mock user
  final mockUser = MockData.users.first;
  return UserProfile(
    id: mockUser.id,
    email: mockUser.email,
    publicKey: mockUser.publicKey,
    fullName: mockUser.displayName,
    bio: mockUser.bio,
    avatarUrl: mockUser.profileImageUrl,
    isVerified: mockUser.isVerified,
    followers: List<String>.filled(mockUser.followersCount, ''),
    following: List<String>.filled(mockUser.followingCount, ''),
  );
}

// This function gets the saved user from the AuthService to add session persistence
Future<UserProfile?> getSavedUserProfile() async {
  try {
    final authService = AuthService();
    // Only get the current user, DO NOT auto-login from saved users
    var savedUser = await authService.getCurrentAuthInfo();
    if (savedUser != null) {
      AppLogger.log("Router: Found user: \\${savedUser['email']}");
      // Convert the saved user data to a UserProfile
      return UserProfile(
        email: savedUser['email'] ?? '',
        publicKey: savedUser['publicKey'] ?? '',
      );
    }
    AppLogger.log("Router: No saved user found");
    return null;
  } catch (e) {
    AppLogger.log("Error getting saved user profile: $e");
    return null;
  }
}

// Get current user profile (only from current auth, no auto-login)
Future<UserProfile?> _getCurrentUserProfile() async {
  try {
    final authService = AuthService();
    final currentUser = await authService.getCurrentAuthInfo();
    
    if (currentUser != null) {
      // Fetch latest profile from Central API to populate fullName/dateOfBirth/avatarUrl
      try {
        final pubKey = currentUser['publicKey'] ?? '';
        final resp = await http.get(Uri.parse('${AppConstants.apiBaseUrl}/user/profile/$pubKey'));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return UserProfile.fromJson(data);
        }
      } catch (_) {}
      // Fallback to minimal local info
      return UserProfile(
        email: currentUser['email'] ?? '',
        publicKey: currentUser['publicKey'] ?? '',
      );
    }
    
    return null;
  } catch (e) {
    AppLogger.log("Error getting current user profile: $e");
    return null;
  }
}

// Function to configure the router with the correct initial route based on authentication
Future<GoRouter> configureRouter() async {
  // Check if we have a saved user
  final savedUser = await getSavedUserProfile();
  
  // Determine the initial location
  // If user is already logged in, go directly to app, otherwise show landing page
  final initialLocation = savedUser != null ? AppRoutes.localUserHome : AppRoutes.landing;
  
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: initialLocation,
    debugLogDiagnostics: true,
    // Add a redirect to check authentication for protected routes
    redirect: (context, state) async {
      AppLogger.log("Router redirect: ${state.matchedLocation}");
      
      // Check real-time authentication status (not cached)
      final authService = AuthService();
      final currentUser = await authService.getCurrentAuthInfo();
      
      AppLogger.log("Router redirect - current user: ${currentUser?['email'] ?? 'null'}");
      
      // Protected routes - redirect to login if not authenticated
      final protectedRoutes = [
        AppRoutes.localUserHome,
        AppRoutes.localUserProfile,
        AppRoutes.createPost,
        AppRoutes.secureFileUpload,
        AppRoutes.messages,
        AppRoutes.chatConversation,
      ];
      
      if (protectedRoutes.contains(state.matchedLocation)) {
        if (currentUser == null) {
          AppLogger.log("Router: No current user, redirecting to login");
          return AppRoutes.login;
        }
        AppLogger.log("Router: User authenticated, allowing access to ${state.matchedLocation}");
      }
      
      // Allow the navigation to proceed
      return null;
    },
    routes: [
      // Landing page route (NEW)
      GoRoute(
        path: AppRoutes.landing,
        name: 'landing',
        builder: (context, state) => const LandingScreen(),
      ),
      
      // Login route
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      
      // Home route
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(child: Placeholder()),
      ),
      
      // Local user home route
      GoRoute(
        path: AppRoutes.localUserHome,
        name: 'localUserHome',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is UserProfile) {
            return HomeScreen(child: LocalUserHomeScreen(userProfile: extra));
          }
          
          // Use FutureBuilder to get current user profile
          return FutureBuilder<UserProfile?>(
            future: _getCurrentUserProfile(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              
              if (snapshot.hasData && snapshot.data != null) {
                return HomeScreen(child: LocalUserHomeScreen(userProfile: snapshot.data!));
              }
              
              // This should not happen since redirect should have caught it
              return const Scaffold(
                body: Center(
                  child: Text('Authentication required'),
                ),
              );
            },
          );
        },
      ),
      
      // Profile routes
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        builder: (context, state) {
          final userId = state.uri.queryParameters['id'];
          return ProfileScreen(userId: userId);
        },
      ),
      
      // Local user profile route
      GoRoute(
        path: AppRoutes.localUserProfile,
        name: 'localUserProfile',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is UserProfile) {
            return LocalUserProfileScreen(userProfile: extra);
          }
          
          // Use FutureBuilder to get current user profile
          return FutureBuilder<UserProfile?>(
            future: _getCurrentUserProfile(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              
              if (snapshot.hasData && snapshot.data != null) {
                return LocalUserProfileScreen(userProfile: snapshot.data!);
              }
              
              // Fallback
              return LocalUserProfileScreen(userProfile: _getUserProfile());
            },
          );
        },
      ),
      
      // Settings route
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      
      // Search route
      GoRoute(
        path: AppRoutes.search,
        name: 'search',
        builder: (context, state) => const SearchScreen(),
      ),
      
      // Notifications route
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      
      // Messages route
      GoRoute(
        path: AppRoutes.messages,
        name: 'messages',
        builder: (context, state) => const MessagesScreen(),
      ),
      
      // Chat conversation route
      GoRoute(
        path: AppRoutes.chatConversation,
        name: 'chatConversation',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ChatConversationScreen(
            conversationId: extra?['conversationId'] ?? '',
            otherPubKey: extra?['otherPubKey'] ?? '',
            otherName: extra?['otherName'] ?? 'User',
          );
        },
      ),
      
      // Create post route
      GoRoute(
        path: AppRoutes.createPost,
        name: 'createPost',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is UserProfile) {
            return CreatePostScreen(userProfile: extra);
          }
          
          // Use FutureBuilder to get current user profile
          return FutureBuilder<UserProfile?>(
            future: _getCurrentUserProfile(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              
              if (snapshot.hasData && snapshot.data != null) {
                return CreatePostScreen(userProfile: snapshot.data!);
              }
              
              // Fallback
              return const CreatePostScreen();
            },
          );
        },
      ),
      
      // Secure File Upload route
      GoRoute(
        path: AppRoutes.secureFileUpload,
        name: 'secureFileUpload',
        builder: (context, state) => const SecureFileUploadScreen(),
      ),
    ],
    
    // Error handling for unknown routes
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(
        title: const Text('Page Not Found'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '404',
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text('Path not found: ${state.uri.path}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.localUserHome),
              child: const Text('Go to Home'),
            ),
          ],
        ),
      ),
    ),
  );
}

// Create a temporary router to use before the actual one is configured
final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.login,
  routes: [
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    ),
    GoRoute(
      path: AppRoutes.localUserHome,
      builder: (context, state) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    ),
  ],
); 
