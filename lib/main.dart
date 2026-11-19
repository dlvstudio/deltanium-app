import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/config/network.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/data/mock/mock_data.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/dltp/dltp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pointycastle/pointycastle.dart';

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
              final authService = AuthService();
              await authService.logout();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ],
      ),
      body: const Center(child: Text('Welcome to Deltanium!')),
    );
  }
}

/// Desktop / mobile builds route requests for nodes with a DLTP (TCP) endpoint over TCP.
void main() => runWithDltp(_main);

Future<void> _main() async {
  final _ = SecureRandom('Fortuna');

  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.init();
  await appLang.load();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Brand.ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  MockData.initialize();
  AppLogger.log('Main: Mock data initialized with ${MockData.users.length} users');

  final appRouter = await configureRouter();
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
      title: Network.isMainnet ? 'Deltanium' : 'Deltanium (${Network.name})',
      debugShowCheckedModeBanner: false,
      builder: Network.isMainnet
          ? null
          // A strip above the app instead of a corner ribbon, so it never covers buttons in the app bar.
          : (context, child) => Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  children: [
                    Material(
                      color: Colors.deepOrange,
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: 20,
                          width: double.infinity,
                          child: Center(
                            child: Text(
                              'TESTNET · ${Network.name} · test coins only',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
      theme: DeltaniumTheme.lightTheme,
      darkTheme: DeltaniumTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
