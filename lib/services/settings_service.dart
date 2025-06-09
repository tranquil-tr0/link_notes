import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static SettingsService? _instance;
  SharedPreferences? _prefs;
  bool _initialized = false;
  bool _initializationFailed = false;

  static const String _vaultDirectoryKey = 'vault_directory';
  static const String _isFirstLaunchKey = 'is_first_launch';
  
  // In-memory fallback storage when SharedPreferences fails
  final Map<String, dynamic> _fallbackStorage = {};

  SettingsService._();

  /// Singleton instance
  static SettingsService get instance {
    _instance ??= SettingsService._();
    return _instance!;
  }

  /// Initialize the settings service
  Future<void> initialize() async {
    if (_initialized) return;
    
    // Retry mechanism for platform channel initialization
    int retryCount = 0;
    const maxRetries = 5;
    const baseDelay = Duration(milliseconds: 100);
    
    while (retryCount < maxRetries) {
      try {
        // Add exponential backoff
        if (retryCount > 0) {
          final delay = Duration(milliseconds: baseDelay.inMilliseconds * (1 << retryCount));
          await Future.delayed(delay);
        }
        
        _prefs = await SharedPreferences.getInstance();
        _initialized = true;
        _initializationFailed = false;
        
        // Migrate fallback data to SharedPreferences if any exists
        if (_fallbackStorage.isNotEmpty) {
          await _migrateFallbackData();
        }
        
        return;
      } catch (e) {
        retryCount++;
        print('SharedPreferences initialization attempt $retryCount failed: $e');
        
        if (retryCount >= maxRetries) {
          print('SharedPreferences initialization failed permanently. Using fallback storage.');
          _initialized = true; // Mark as initialized but with fallback
          _initializationFailed = true;
          return;
        }
      }
    }
  }
  
  /// Migrate data from fallback storage to SharedPreferences
  Future<void> _migrateFallbackData() async {
    if (_prefs == null || _fallbackStorage.isEmpty) return;
    
    try {
      for (final entry in _fallbackStorage.entries) {
        if (entry.value is String) {
          await _prefs!.setString(entry.key, entry.value);
        } else if (entry.value is bool) {
          await _prefs!.setBool(entry.key, entry.value);
        } else if (entry.value is int) {
          await _prefs!.setInt(entry.key, entry.value);
        } else if (entry.value is double) {
          await _prefs!.setDouble(entry.key, entry.value);
        }
      }
      _fallbackStorage.clear();
    } catch (e) {
      print('Failed to migrate fallback data: $e');
    }
  }

  /// Ensures the service is initialized
  void _ensureInitialized() {
    if (!_initialized || _prefs == null) {
      throw Exception('SettingsService not initialized. Call initialize() first.');
    }
  }

  /// Check if the service is properly initialized
  bool get isInitialized => _initialized;
  
  /// Check if using fallback storage
  bool get isUsingFallback => _initializationFailed;

  /// Get the stored vault directory path
  String? getVaultDirectory() {
    if (!isInitialized) return null;
    
    if (_initializationFailed) {
      return _fallbackStorage[_vaultDirectoryKey] as String?;
    }
    
    return _prefs?.getString(_vaultDirectoryKey);
  }

  /// Set the vault directory path
  Future<bool> setVaultDirectory(String path) async {
    if (!isInitialized) return false;
    
    if (_initializationFailed) {
      _fallbackStorage[_vaultDirectoryKey] = path;
      return true;
    }
    
    try {
      return await _prefs!.setString(_vaultDirectoryKey, path);
    } catch (e) {
      print('Failed to save vault directory to SharedPreferences, using fallback: $e');
      _fallbackStorage[_vaultDirectoryKey] = path;
      return true;
    }
  }

  /// Check if this is the first app launch
  bool isFirstLaunch() {
    if (!isInitialized) return true; // Default to first launch if not initialized
    
    if (_initializationFailed) {
      return _fallbackStorage[_isFirstLaunchKey] as bool? ?? true;
    }
    
    return _prefs?.getBool(_isFirstLaunchKey) ?? true;
  }

  /// Mark that the first launch has been completed
  Future<bool> setFirstLaunchCompleted() async {
    if (!isInitialized) return false;
    
    if (_initializationFailed) {
      _fallbackStorage[_isFirstLaunchKey] = false;
      return true;
    }
    
    try {
      return await _prefs!.setBool(_isFirstLaunchKey, false);
    } catch (e) {
      print('Failed to save first launch status to SharedPreferences, using fallback: $e');
      _fallbackStorage[_isFirstLaunchKey] = false;
      return true;
    }
  }

  /// Clear all settings (useful for testing or reset)
  Future<bool> clearAllSettings() async {
    if (!isInitialized) return false;
    
    if (_initializationFailed) {
      _fallbackStorage.clear();
      return true;
    }
    
    try {
      final success = await _prefs!.clear();
      _fallbackStorage.clear(); // Clear fallback too
      return success;
    } catch (e) {
      print('Failed to clear SharedPreferences, clearing fallback only: $e');
      _fallbackStorage.clear();
      return true;
    }
  }

  /// Check if vault directory is configured
  bool hasVaultDirectory() {
    if (!isInitialized) return false;
    final directory = getVaultDirectory();
    return directory != null && directory.isNotEmpty;
  }
}