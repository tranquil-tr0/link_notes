import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'; // Add FlutterQuill import for localizations
import 'package:provider/provider.dart';
import 'providers/vault_provider.dart';
import 'screens/directory_screen.dart';
import 'screens/vault_setup_screen.dart';
import 'services/settings_service.dart';
import 'services/markdown_conversion_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Add a small delay to ensure platform channels are ready
  await Future.delayed(const Duration(milliseconds: 50));
  
  try {
    // Initialize settings service with error handling
    await SettingsService.instance.initialize();
    
    // Initialize markdown conversion service
    MarkdownConversionService.initialize();
  } catch (e) {
    // Log the error but don't crash the app
    debugPrint('Warning: Failed to initialize services: $e');
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
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate, // Add FlutterQuill localizations delegate
        ],
        supportedLocales: const [
          Locale('en', ''), // English, no country code
        ],
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
      
      setState(() {
        _isFirstLaunch = isFirstLaunch || !hasVaultDirectory;
        _isCheckingSetup = false;
      });
    } catch (e) {
      setState(() {
        _isFirstLaunch = true;
        _isCheckingSetup = false;
      });
    }
  }

  void _onSetupComplete() {
    setState(() {
      _isFirstLaunch = false;
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

    if (_isFirstLaunch) {
      return VaultSetupScreen(onSetupComplete: _onSetupComplete);
    }

    return const DirectoryScreen();
  }
}

