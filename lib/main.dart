import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/data/mock/mock_data.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/app_logger.dart';

// Add home screen
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deltanium'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Log out the user
              final authService = AuthService();
              await authService.logout();
              // Navigate to login screen
              context.go(AppRoutes.login);
            },
          ),
        ],
      ),
      body: const Center(
        child: Text('Welcome to Deltanium!'),
      ),
    );
  }
}

void main() async {
  // Đăng ký SecureRandom cho pointycastle (fix RegistryFactoryException)
  final _ = SecureRandom('Fortuna');
  
  // Ensure Flutter is properly initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize AppLogger to write all logs to file
  await AppLogger.init();
  
  // Set preferred orientations to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Ensure mock data is initialized before app starts
  MockData.initialize();
  AppLogger.log("Main: Mock data initialized with ${MockData.users.length} users");
  
  // Print all users to verify data is available
  for (var user in MockData.users) {
    AppLogger.log("User available in main: ${user.email}");
  }
  
  // Configure the router with the correct initial route and user session
  final appRouter = await configureRouter();
  
  // Run the app with the configured router
  runApp(DeltaniumApp(router: appRouter));
}

class DeltaniumApp extends StatelessWidget {
  final GoRouter router;
  
  const DeltaniumApp({
    super.key,
    required this.router,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Deltanium',
      theme: ThemeData(
        primarySwatch: Colors.brown,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.brown,
        brightness: Brightness.dark,
      ),
      routerConfig: router,
    );
  }
}
