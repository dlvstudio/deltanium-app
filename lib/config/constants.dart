class AppConstants {
  // API URLs
  static const String baseUrl = 'https://api.deltanium.com';
  static const String apiVersion = 'v1';
  static const String apiBaseUrl = String.fromEnvironment(
    'CENTRAL_API_BASE',
    defaultValue: 'http://127.0.0.1:5002/api',
  );
  
  // Endpoints
  static const String authEndpoint = '$apiBaseUrl/auth';
  static const String postsEndpoint = '$apiBaseUrl/posts';
  static const String usersEndpoint = '$apiBaseUrl/users';
  static const String mediaEndpoint = '$apiBaseUrl/media';
  
  // Storage Keys
  static const String tokenKey = 'deltanium_auth_token';
  static const String userDataKey = 'deltanium_user_data';
  static const String themePreferenceKey = 'deltanium_theme_preference';
  
  // Authentication
  static const int tokenExpirationDays = 30;
  static const int minimumPasswordLength = 8;
  
  // Social Features
  static const int maxPostLength = 1000;
  static const int maxCommentLength = 500;
  static const int defaultPostsPerPage = 10;
  
  // Media
  static const int maxImageSize = 10 * 1024 * 1024; // 10MB
  static const int maxVideoSize = 100 * 1024 * 1024; // 100MB
  static const List<String> supportedImageFormats = ['jpg', 'jpeg', 'png', 'gif'];
  static const List<String> supportedVideoFormats = ['mp4', 'mov', 'avi'];
  
  // App Settings
  static const String appName = 'Deltanium';
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '1';
  static const String supportEmail = 'support@deltanium.com';
  
  // Animation Durations
  static const Duration shortAnimationDuration = Duration(milliseconds: 200);
  static const Duration mediumAnimationDuration = Duration(milliseconds: 350);
  static const Duration longAnimationDuration = Duration(milliseconds: 500);
} 