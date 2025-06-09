import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static SettingsService? _instance;
  late SharedPreferences _prefs;
  bool _initialized = false;

  static const String _vaultDirectoryKey = 'vault_directory';
  static const String _isFirstLaunchKey = 'is_first_launch';

  SettingsService._();

  /// Singleton instance
  static SettingsService get instance {
    _instance ??= SettingsService._();
    return _instance!;
  }

  /// Initialize the settings service
  Future<void> initialize() async {
    if (_initialized) return;
    
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  /// Ensures the service is initialized
  void _ensureInitialized() {
    if (!_initialized) {
      throw Exception('SettingsService not initialized. Call initialize() first.');
    }
  }

  /// Get the stored vault directory path
  String? getVaultDirectory() {
    _ensureInitialized();
    return _prefs.getString(_vaultDirectoryKey);
  }

  /// Set the vault directory path
  Future<bool> setVaultDirectory(String path) async {
    _ensureInitialized();
    return await _prefs.setString(_vaultDirectoryKey, path);
  }

  /// Check if this is the first app launch
  bool isFirstLaunch() {
    _ensureInitialized();
    return _prefs.getBool(_isFirstLaunchKey) ?? true;
  }

  /// Mark that the first launch has been completed
  Future<bool> setFirstLaunchCompleted() async {
    _ensureInitialized();
    return await _prefs.setBool(_isFirstLaunchKey, false);
  }

  /// Clear all settings (useful for testing or reset)
  Future<bool> clearAllSettings() async {
    _ensureInitialized();
    return await _prefs.clear();
  }

  /// Check if vault directory is configured
  bool hasVaultDirectory() {
    _ensureInitialized();
    final directory = getVaultDirectory();
    return directory != null && directory.isNotEmpty;
  }
}