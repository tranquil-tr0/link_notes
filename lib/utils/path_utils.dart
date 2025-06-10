/// Utility class for converting SAF (Storage Access Framework) URIs to human-readable paths
/// and handling path operations across different platforms.
///
/// This class provides methods to translate Android SAF URIs (which look like
/// `content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FNotes`)
/// into user-friendly display paths like `Documents/Notes`.
///
/// Key features:
/// - Converts SAF URIs to display-friendly paths for UI elements
/// - Extracts meaningful folder names from paths and URIs
/// - Generates breadcrumb segments for navigation
/// - Provides storage location descriptions for user information
/// - Handles both SAF URIs and traditional file paths consistently
///
/// Usage examples:
/// ```dart
/// // Convert SAF URI to display path
/// final displayPath = PathUtils.safUriToDisplayPath(safUri);
///
/// // Get folder name for UI display
/// final folderName = PathUtils.extractFolderName(path);
///
/// // Generate breadcrumb segments for navigation
/// final breadcrumbs = PathUtils.getBreadcrumbSegments(vaultPath, currentPath);
///
/// // Get user-friendly storage description
/// final description = PathUtils.getStorageLocationDescription(path);
/// ```
class PathUtils {
  /// Converts a SAF URI to a human-readable path for display purposes
  /// 
  /// Examples:
  /// - content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FNotes
  ///   -> Documents/Notes
  /// - content://com.android.providers.downloads.documents/tree/downloads%3A
  ///   -> Downloads
  /// - /storage/emulated/0/Documents/Notes
  ///   -> Documents/Notes (for regular paths, extracts meaningful part)
  static String safUriToDisplayPath(String? uri) {
    if (uri == null || uri.isEmpty) return 'Unknown Location';
    
    // If it's not a content URI, handle as regular path
    if (!uri.startsWith('content://')) {
      return _extractDisplayPathFromRegularPath(uri);
    }
    
    try {
      // Handle SAF content URIs
      if (uri.contains('externalstorage.documents')) {
        return _parseExternalStorageUri(uri);
      } else if (uri.contains('downloads.documents')) {
        return _parseDownloadsUri(uri);
      } else if (uri.contains('media.documents')) {
        return _parseMediaUri(uri);
      } else {
        // Generic fallback for unknown providers
        return _parseGenericContentUri(uri);
      }
    } catch (e) {
      // Fallback to a generic name if parsing fails
      return 'Selected Folder';
    }
  }
  
  /// Extracts a display-friendly name from a regular file system path
  static String _extractDisplayPathFromRegularPath(String path) {
    // Remove common Android storage prefixes
    final cleanPath = path
        .replaceFirst(RegExp(r'^/storage/emulated/\d+/'), '')
        .replaceFirst(RegExp(r'^/sdcard/'), '')
        .replaceFirst(RegExp(r'^/data/data/[^/]+/files/'), '');
    
    // If the path is now empty or very short, use the last directory name
    if (cleanPath.isEmpty || cleanPath.length < 3) {
      final segments = path.split('/');
      return segments.isNotEmpty ? segments.last : 'Root';
    }
    
    return cleanPath;
  }
  
  /// Parses external storage document URIs
  static String _parseExternalStorageUri(String uri) {
    // Extract the tree part after 'tree/'
    final treeMatch = RegExp(r'tree/(.+)').firstMatch(uri);
    if (treeMatch == null) return 'External Storage';
    
    final treePart = Uri.decodeComponent(treeMatch.group(1) ?? '');
    
    // Handle primary storage paths
    if (treePart.startsWith('primary:')) {
      final path = treePart.substring(8); // Remove 'primary:'
      return path.isEmpty ? 'Internal Storage' : path.replaceAll('%2F', '/');
    }
    
    // Handle SD card paths
    if (treePart.contains(':')) {
      final parts = treePart.split(':');
      if (parts.length >= 2) {
        final cardId = parts[0];
        final path = parts[1];
        final displayPath = path.isEmpty ? 'SD Card ($cardId)' : '$path (SD Card)';
        return displayPath.replaceAll('%2F', '/');
      }
    }
    
    return treePart.replaceAll('%2F', '/');
  }
  
  /// Parses downloads document URIs
  static String _parseDownloadsUri(String uri) {
    final treeMatch = RegExp(r'tree/(.+)').firstMatch(uri);
    if (treeMatch == null) return 'Downloads';
    
    final treePart = Uri.decodeComponent(treeMatch.group(1) ?? '');
    
    if (treePart.startsWith('downloads:')) {
      final path = treePart.substring(10); // Remove 'downloads:'
      return path.isEmpty ? 'Downloads' : 'Downloads/$path'.replaceAll('%2F', '/');
    }
    
    return 'Downloads';
  }
  
  /// Parses media document URIs
  static String _parseMediaUri(String uri) {
    final treeMatch = RegExp(r'tree/(.+)').firstMatch(uri);
    if (treeMatch == null) return 'Media';
    
    final treePart = Uri.decodeComponent(treeMatch.group(1) ?? '');
    
    if (treePart.contains(':')) {
      final parts = treePart.split(':');
      if (parts.length >= 2) {
        final mediaType = parts[0]; // e.g., 'image', 'video', 'audio'
        final path = parts[1];
        final displayPath = path.isEmpty ? _capitalizeFirst(mediaType) : '$path ($mediaType)';
        return displayPath.replaceAll('%2F', '/');
      }
    }
    
    return 'Media';
  }
  
  /// Parses generic content URIs as fallback
  static String _parseGenericContentUri(String uri) {
    // Try to extract authority for a more meaningful name
    final authorityMatch = RegExp(r'content://([^/]+)').firstMatch(uri);
    if (authorityMatch != null) {
      final authority = authorityMatch.group(1) ?? '';
      
      // Extract a user-friendly name from the authority
      if (authority.contains('externalstorage')) return 'External Storage';
      if (authority.contains('downloads')) return 'Downloads';
      if (authority.contains('media')) return 'Media';
      if (authority.contains('documents')) return 'Documents';
      
      // Generic fallback with authority name
      final cleanAuthority = authority
          .replaceAll('com.android.', '')
          .replaceAll('.documents', '')
          .replaceAll('.providers', '');
      return _capitalizeFirst(cleanAuthority);
    }
    
    return 'Selected Folder';
  }
  
  /// Gets a short display name for the vault location
  /// This is useful for showing in app bars or settings
  static String getVaultDisplayName(String? vaultPath) {
    if (vaultPath == null || vaultPath.isEmpty) return 'No Vault';

    final displayPath = safUriToDisplayPath(vaultPath);

    final lastSlash = displayPath.lastIndexOf('/');
    if (lastSlash != -1 && lastSlash < displayPath.length - 1) {
      return displayPath.substring(lastSlash + 1);
    }
    return displayPath;
  }
  
  /// Gets breadcrumb segments from a SAF URI or regular path
  /// Returns a list of path segments suitable for breadcrumb navigation
  static List<String> getBreadcrumbSegments(String? basePath, String? currentPath) {
    if (basePath == null || basePath.isEmpty) return ['Home'];
    
    final List<String> segments = [];
    
    // Add base path segment
    final baseDisplayName = safUriToDisplayPath(basePath);
    if (baseDisplayName != 'Unknown Location' && baseDisplayName.isNotEmpty) {
      // For the root vault, use a friendly name
      // TODO: consider configurable to display the name or "Vault"
      segments.add(_getVaultRootName(baseDisplayName));
    }
    
    // Add current path segments if different from base
    if (currentPath != null && currentPath.isNotEmpty) {
      final pathSegments = currentPath.split('/').where((s) => s.isNotEmpty);
      segments.addAll(pathSegments);
    }
    
    return segments;
  }
  
  /// Gets a friendly name for the vault root
  static String _getVaultRootName(String displayPath) {
    // If the path looks like a typical folder name, use it as-is
    if (!displayPath.contains('/') && displayPath.length < 20) {
      return displayPath;
    }
    
    // For longer paths, extract the most meaningful part
    final segments = displayPath.split('/');
    if (segments.isNotEmpty) {
      final lastSegment = segments.last;
      if (lastSegment.isNotEmpty && lastSegment.length < 20) {
        return lastSegment;
      }
    }
    
    return 'Vault';
  }
  
  /// Converts a SAF URI to a path-like string for internal use
  /// This maintains the structure for navigation but makes it more readable
  static String safUriToInternalPath(String? uri) {
    if (uri == null || uri.isEmpty) return '';
    
    // If it's already a regular path, return as-is
    if (!uri.startsWith('content://')) return uri;
    
    // For SAF URIs, create a path-like representation
    final displayPath = safUriToDisplayPath(uri);
    return '/$displayPath';
  }
  
  /// Checks if a path is a SAF URI
  static bool isSafUri(String? path) {
    return path != null && path.startsWith('content://');
  }
  
  /// Extracts the folder name from any path or URI
  static String extractFolderName(String? path) {
    if (path == null || path.isEmpty) return 'Unknown';
    
    if (isSafUri(path)) {
      final displayPath = safUriToDisplayPath(path);
      final segments = displayPath.split('/').where((s) => s.isNotEmpty).toList();
      return segments.isNotEmpty ? segments.last : 'Root';
    } else {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      return segments.isNotEmpty ? segments.last : 'Root';
    }
  }
  
  /// Capitalizes the first letter of a string
  static String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
  
  /// Gets a user-friendly description of the storage location
  static String getStorageLocationDescription(String? path) {
    if (path == null || path.isEmpty) return 'No storage location selected';
    
    if (isSafUri(path)) {
      if (path.contains('externalstorage.documents')) {
        if (path.contains('primary:')) {
          return 'Internal storage';
        } else {
          return 'External storage (SD card)';
        }
      } else if (path.contains('downloads.documents')) {
        return 'Downloads folder';
      } else if (path.contains('media.documents')) {
        return 'Media storage';
      } else {
        return 'Custom storage location';
      }
    } else {
      return 'Local file system';
    }
  }
}

extension ListExtension<T> on List<T> {
  List<T> takeLast(int count) {
    if (count >= length) return this;
    return sublist(length - count);
  }
}