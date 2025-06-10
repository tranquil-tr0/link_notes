import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

/// Service for handling file system permissions
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  static PermissionService get instance => _instance;

  /// Check if storage permissions are granted
  Future<bool> hasStoragePermission() async {
    if (kIsWeb) return true; // Web doesn't need storage permissions

    if (Platform.isAndroid) {
      return await Permission.photos.isGranted &&
          await Permission.videos.isGranted &&
          await Permission.audio.isGranted;
    } else if (Platform.isIOS) {
      // iOS doesn't require explicit storage permissions for app documents
      return true;
    }

    return false;
  }

  /// Request storage permissions
  Future<bool> requestStoragePermission() async {
    if (kIsWeb) return true; // Web doesn't need storage permissions

    if (Platform.isAndroid) {
      final androidInfo = await _getAndroidSdkVersion();

      if (androidInfo >= 33) {
        // Android 13+ (API 33+) - Request media permissions
        final Map<Permission, PermissionStatus> statuses = await [
          Permission.photos,
          Permission.videos,
          Permission.audio,
        ].request();

        return statuses.values.every((status) => status.isGranted);
      } else if (androidInfo >= 30) {
        // Android 11-12 (API 30-32) - Request manage external storage
        final status = await Permission.manageExternalStorage.request();
        return status.isGranted;
      } else {
        // Android 10 and below (API 29 and below)
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    } else if (Platform.isIOS) {
      // iOS doesn't require explicit storage permissions for app documents
      return true;
    }

    return false;
  }

  /// Check if we should show permission rationale
  Future<bool> shouldShowPermissionRationale() async {
    if (kIsWeb || Platform.isIOS) return false;

    if (Platform.isAndroid) {
      final androidInfo = await _getAndroidSdkVersion();

      // if (androidInfo >= 33) {
      //   return await Permission.photos.shouldShowRequestRationale ||
      //          await Permission.videos.shouldShowRequestRationale ||
      //          await Permission.audio.shouldShowRequestRationale;
      // } else if (androidInfo >= 30) {
      //   return await Permission.manageExternalStorage.shouldShowRequestRationale;
      // } else {
      //   return await Permission.storage.shouldShowRequestRationale;
      // }
      if (androidInfo >= 33) {
        return await Permission.photos.shouldShowRequestRationale ||
            await Permission.videos.shouldShowRequestRationale ||
            await Permission.audio.shouldShowRequestRationale;
      }
      if (androidInfo >= 30) {
        return await Permission
            .manageExternalStorage
            .shouldShowRequestRationale;
      } else {
        return await Permission.storage.shouldShowRequestRationale;
      }
    }

    return false;
  }

  /// Check if permissions are permanently denied
  Future<bool> isPermissionPermanentlyDenied() async {
    if (kIsWeb || Platform.isIOS) return false;

    if (Platform.isAndroid) {
      final androidInfo = await _getAndroidSdkVersion();

      if (androidInfo >= 33) {
        return await Permission.photos.isPermanentlyDenied ||
            await Permission.videos.isPermanentlyDenied ||
            await Permission.audio.isPermanentlyDenied;
      } else if (androidInfo >= 30) {
        return await Permission.manageExternalStorage.isPermanentlyDenied;
      } else {
        return await Permission.storage.isPermanentlyDenied;
      }
    }

    return false;
  }

  /// Open app settings for manual permission grant
  Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      debugPrint('Failed to open app settings: $e');
      return false;
    }
  }

  /// Get Android SDK version (mock implementation)
  /// In a real app, you might use device_info_plus package
  Future<int> _getAndroidSdkVersion() async {
    try {
      // This is a simplified approach - you might want to use device_info_plus
      // for more accurate version detection
      return 33; // Assume modern Android for now
    } catch (e) {
      return 29; // Fallback to older Android
    }
  }

  /// Get permission status description for user-friendly messages
  String getPermissionStatusDescription(bool hasPermission) {
    if (hasPermission) {
      return 'Storage permissions are granted. You can read and write notes.';
    } else {
      return 'Storage permissions are required to read and write your notes. Please grant permission to continue.';
    }
  }

  /// Get detailed permission requirements message
  String getPermissionRequirementsMessage() {
    if (Platform.isAndroid) {
      return 'This app needs storage access to read and write your markdown notes. '
          'We will only access the specific folders you choose for your notes vault.';
    } else if (Platform.isIOS) {
      return 'This app needs access to documents to read and write your markdown notes. '
          'Your notes will be stored in your chosen directory.';
    } else {
      return 'File access is required to manage your notes.';
    }
  }
}
