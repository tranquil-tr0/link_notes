import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/vault_provider.dart';
import 'screens/directory_screen.dart';
import 'screens/vault_setup_screen.dart';
import 'services/settings_service.dart';
import 'services/permission_service.dart';
import 'widgets/permission_request_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Add a small delay to ensure platform channels are ready
  await Future.delayed(const Duration(milliseconds: 50));
  
  try {
    // Initialize settings service with error handling
    await SettingsService.instance.initialize();
  } catch (e) {
    // Log the error but don't crash the app
    debugPrint('Warning: Failed to initialize SettingsService: $e');
    // The app can still function with default settings
  }
  
  runApp(const LinkNotesApp());
}

class LinkNotesApp extends StatelessWidget {
  const LinkNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => VaultProvider(),
      child: MaterialApp(
        title: 'Link Notes',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
          cardTheme: const CardThemeData(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            elevation: 2,
            highlightElevation: 4,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
          cardTheme: const CardThemeData(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            elevation: 2,
            highlightElevation: 4,
          ),
        ),
        themeMode: ThemeMode.system,
        home: const AppRouter(),
      ),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _isFirstLaunch = true;
  bool _isCheckingSetup = true;
  bool _hasPermissions = false;

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  void _checkSetupStatus() async {
    try {
      await SettingsService.instance.initialize();
      final isFirstLaunch = SettingsService.instance.isFirstLaunch();
      final hasVaultDirectory = SettingsService.instance.hasVaultDirectory();
      
      // Check permissions
      final permissionService = PermissionService.instance;
      final hasPermissions = await permissionService.hasStoragePermission();
      
      setState(() {
        _isFirstLaunch = isFirstLaunch || !hasVaultDirectory;
        _hasPermissions = hasPermissions;
        _isCheckingSetup = false;
      });
    } catch (e) {
      setState(() {
        _isFirstLaunch = true;
        _hasPermissions = false;
        _isCheckingSetup = false;
      });
    }
  }

  void _onSetupComplete() {
    setState(() {
      _isFirstLaunch = false;
    });
  }

  void _onPermissionGranted() {
    setState(() {
      _hasPermissions = true;
    });
  }

  void _onPermissionDenied() {
    setState(() {
      _hasPermissions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSetup) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Check permissions first, regardless of setup status
    if (!_hasPermissions) {
      return Scaffold(
        body: PermissionRequestWidget(
          onPermissionGranted: _onPermissionGranted,
          onPermissionDenied: _onPermissionDenied,
        ),
      );
    }

    if (_isFirstLaunch) {
      return VaultSetupScreen(onSetupComplete: _onSetupComplete);
    }

    return const DirectoryScreen();
  }
}

