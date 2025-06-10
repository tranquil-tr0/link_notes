import 'dart:io';
import 'dart:convert'; // For utf8 encoding/decoding
import 'package:flutter/foundation.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart'; // Import SafDocumentFile
import 'package:saf_stream/saf_stream.dart'; // Import saf_stream
import 'package:shared_preferences/shared_preferences.dart';

/// Service for handling file system permissions using Storage Access Framework
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  static PermissionService get instance => _instance;

  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream(); // Initialize SafStream
  static const String _safUriKey = 'saf_vault_uri';
  static const String _hasPermissionKey = 'has_saf_permission';

  /// Check if we have persistent SAF permissions for the vault directory
  Future<bool> hasStoragePermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasPermission = prefs.getBool(_hasPermissionKey) ?? false;
      final safUri = prefs.getString(_safUriKey);

      if (!hasPermission || safUri == null) {
        return false;
      }

      // Verify the URI is still accessible using saf_util
      try {
        final hasReadPermission = await _safUtil.hasPersistedPermission(
          safUri,
          checkRead: true,
          checkWrite: true, // Check for both read and write permissions
        );
        return hasReadPermission;
      } catch (e) {
        debugPrint('Error checking persisted permissions: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Error checking storage permission: $e');
      return false;
    }
  }

  /// Request Storage Access Framework permissions for a directory
  Future<bool> requestStoragePermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    try {
      // Open SAF directory picker with write and persistable permissions
      final directory = await _safUtil.pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      
      if (directory == null) {
        debugPrint('User cancelled SAF directory selection');
        return false;
      }

      // Store the URI and permission status
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_safUriKey, directory.uri);
      await prefs.setBool(_hasPermissionKey, true);

      debugPrint('SAF permission granted for URI: ${directory.uri}');
      debugPrint('Directory name: ${directory.name}');
      return true;
    } catch (e) {
      debugPrint('Error requesting SAF permission: $e');
      return false;
    }
  }

  /// Get the SAF URI for the vault directory
  Future<String?> getVaultSafUri() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_safUriKey);
    } catch (e) {
      debugPrint('Error getting SAF URI: $e');
      return null;
    }
  }

  /// Get the vault directory as a SafDocumentFile
  Future<SafDocumentFile?> getVaultDirectory() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final safUri = await getVaultSafUri();
      if (safUri == null) return null;

      return await _safUtil.documentFileFromUri(safUri, true);
    } catch (e) {
      debugPrint('Error getting vault directory: $e');
      return null;
    }
  }

  /// Set the SAF URI for the vault directory
  Future<void> setVaultSafUri(String safUri) async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_safUriKey, safUri);
      await prefs.setBool(_hasPermissionKey, true);
    } catch (e) {
      debugPrint('Error setting SAF URI: $e');
    }
  }

  /// Check if we should show permission rationale
  Future<bool> shouldShowPermissionRationale() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    
    // For SAF, we always show rationale since it's user-initiated
    return !(await hasStoragePermission());
  }

  /// Check if permissions are permanently denied
  Future<bool> isPermissionPermanentlyDenied() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    
    // SAF permissions can't be permanently denied in the same way
    // as regular permissions since they're always user-granted
    return false;
  }

  /// Open app settings for manual permission grant
  Future<bool> openSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    
    try {
      // For SAF, we should request permission again rather than opening settings
      return await requestStoragePermission();
    } catch (e) {
      debugPrint('Failed to request SAF permission: $e');
      return false;
    }
  }

  /// Release SAF permissions and clear stored data
  /// Note: This only clears the app's internal tracking of permissions.
  /// The system-level SAF permissions will remain until manually removed by the user.
  Future<void> releasePermissions() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Clear local storage - this removes the app's tracking of the permission
      await prefs.remove(_safUriKey);
      await prefs.remove(_hasPermissionKey);
      debugPrint('Cleared local SAF permission storage');
      
      // Note: The actual SAF permission remains in the system and will be visible
      // in Android Settings > Apps > [Your App] > Permissions > External Storage
      // Users can manually remove these permissions from there if desired.
      debugPrint('Note: System-level SAF permission remains active. Users can remove it manually from app settings.');
    } catch (e) {
      debugPrint('Error releasing SAF permissions: $e');
    }
  }

  /// Change vault directory with cleanup of old internal references
  /// Note: This doesn't revoke system-level permissions, only clears internal tracking
  Future<bool> changeVaultDirectoryWithCleanup() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    try {
      // Get current URI before changing (for logging purposes)
      final oldSafUri = await getVaultSafUri();
      
      // Request new directory permission
      final granted = await requestStoragePermission();
      if (!granted) {
        return false;
      }
      
      // Log the change for debugging
      if (oldSafUri != null) {
        final newSafUri = await getVaultSafUri();
        if (newSafUri != null && oldSafUri != newSafUri) {
          debugPrint('Changed SAF directory from: $oldSafUri to: $newSafUri');
          debugPrint('Note: Old system-level SAF permission remains active until manually removed by user');
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('Error changing vault directory with cleanup: $e');
      return false;
    }
  }

  /// Get permission status description for user-friendly messages
  String getPermissionStatusDescription(bool hasPermission) {
    if (hasPermission) {
      return 'Storage access is granted. You can read and write notes in your selected folder.';
    } else {
      return 'Storage access is required to read and write your notes. Please select a folder to continue.';
    }
  }

  /// Get detailed permission requirements message
  String getPermissionRequirementsMessage() {
    if (Platform.isAndroid) {
      return 'This app uses Android\'s Storage Access Framework to securely access your chosen folder. '
          'You\'ll be asked to select a directory where your notes will be stored. '
          'This ensures your privacy and gives you full control over where your notes are kept.';
    } else if (Platform.isIOS) {
      return 'This app needs access to documents to read and write your markdown notes. '
          'Your notes will be stored in your chosen directory.';
    } else {
      return 'File access is required to manage your notes.';
    }
  }

  /// List files and directories in the SAF directory
  Future<List<SafDocumentFile>> listSafContents() async {
    if (kIsWeb || !Platform.isAndroid) return [];

    try {
      final safUri = await getVaultSafUri();
      if (safUri == null) return [];

      return await _safUtil.list(safUri);
    } catch (e) {
      debugPrint('Error listing SAF contents: $e');
      return [];
    }
  }

  /// Create a new file using SAF
  Future<SafDocumentFile?> createSafFile(String fileName, String content) async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final safUri = await getVaultSafUri();
      if (safUri == null) return null;

      // Create the directory path if fileName contains subdirectories
      final pathParts = fileName.split('/');
      String currentUri = safUri;
      
      // Create nested directories if needed
      if (pathParts.length > 1) {
        final directories = pathParts.take(pathParts.length - 1).toList();
        final finalDir = await _safUtil.mkdirp(currentUri, directories);
        currentUri = finalDir.uri;
      }

      final actualFileName = pathParts.last;
      
      debugPrint('Creating file: $actualFileName in $currentUri');
      
      await _safStream.writeFileBytes(
        currentUri,
        actualFileName,
        'text/markdown', // Assuming markdown files
        utf8.encode(content),
      );

      // After writing, get the SafDocumentFile for the newly created file
      return await _safUtil.child(currentUri, [actualFileName]);

    } catch (e) {
      debugPrint('Error creating SAF file: $e');
      return null;
    }
  }

  /// Check if a file or directory exists
  Future<bool> existsSaf(String name, {bool isDir = false}) async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final safUri = await getVaultSafUri();
      if (safUri == null) return false;

      final child = await _safUtil.child(safUri, [name]);
      return child != null;
    } catch (e) {
      debugPrint('Error checking SAF existence: $e');
      return false;
    }
  }

  /// Get a child file or directory
  Future<SafDocumentFile?> getChild(String name) async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final safUri = await getVaultSafUri();
      if (safUri == null) return null;

      return await _safUtil.child(safUri, [name]);
    } catch (e) {
      debugPrint('Error getting SAF child: $e');
      return null;
    }
  }

  /// Get a child file or directory by path
  Future<SafDocumentFile?> getChildByPath(List<String> pathParts) async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final safUri = await getVaultSafUri();
      if (safUri == null) return null;

      return await _safUtil.child(safUri, pathParts);
    } catch (e) {
      debugPrint('Error getting SAF child by path: $e');
      return null;
    }
  }

  /// Create nested directories
  Future<SafDocumentFile?> createDirectories(List<String> pathParts) async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final safUri = await getVaultSafUri();
      if (safUri == null) return null;

      return await _safUtil.mkdirp(safUri, pathParts);
    } catch (e) {
      debugPrint('Error creating SAF directories: $e');
      return null;
    }
  }

  /// Delete a file using SAF
  Future<bool> deleteSafFile(SafDocumentFile file) async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      await _safUtil.delete(file.uri, file.isDir);
      return true;
    } catch (e) {
      debugPrint('Error deleting SAF file: $e');
      return false;
    }
  }

  /// Rename a file using SAF
  Future<SafDocumentFile?> renameSafFile(SafDocumentFile file, String newName) async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      return await _safUtil.rename(file.uri, file.isDir, newName);
    } catch (e) {
      debugPrint('Error renaming SAF file: $e');
      return null;
    }
  }
  /// Read a file using SAF
  Future<String?> readSafFile(SafDocumentFile file) async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final fileBytes = await _safStream.readFileBytes(file.uri);
      return utf8.decode(fileBytes);
    } catch (e) {
      debugPrint('Error reading SAF file: $e');
      return null;
    }
  }
}
