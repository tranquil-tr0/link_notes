import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/note.dart';
import '../services/settings_service.dart';
import '../services/permission_service.dart';

/// Vault provider that reads notes and folders directly from the file system
/// 
/// This provider acts like a file explorer - it doesn't store any note content
/// or folder structures internally. Instead, it reads the current state from
/// the file system every time data is requested.
class VaultProvider extends ChangeNotifier {
  // ==================== STATE VARIABLES ====================
  
  // Current navigation state
  String _currentPath = '';
  List<String> _pathSegments = [];
  
  // Loading and error states
  bool _isLoading = false;
  String? _error;
  
  // Settings
  String? _vaultDirectory;
  bool _initialized = false;
  
  // ==================== GETTERS ====================
  
  /// String path of the vault directory
  String get vaultPath => _vaultDirectory ?? 'Error: Vault not initialized';

  /// Current folder path relative to vault root
  String get currentPath => _currentPath;
  
  /// Path segments for breadcrumb navigation
  List<String> get pathSegments => List.unmodifiable(_pathSegments);
  
  /// Loading state
  bool get isLoading => _isLoading;
  
  /// Current error message
  String? get error => _error;
  
  /// Whether provider is initialized
  bool get isInitialized => _initialized;
  
  /// Full path to current directory
  String get currentFullPath => _vaultDirectory != null 
      ? '$_vaultDirectory/$_currentPath'.replaceAll('//', '/')
      : '';
  
  /// Whether currently in root directory
  bool get isInRoot => _currentPath.isEmpty;
  
  // ==================== INITIALIZATION ====================
  
  /// Initialize the vault provider
  Future<void> initialize() async {
    if (_initialized) return;
    
    _setLoading(true);
    _clearError();
    
    try {
      // Check storage permissions first
      final permissionService = PermissionService.instance;
      bool hasPermission = await permissionService.hasStoragePermission();
      
      if (!hasPermission) {
        // Request permissions
        hasPermission = await permissionService.requestStoragePermission();
        
        if (!hasPermission) {
          // Check if permanently denied
          final isPermanentlyDenied = await permissionService.isPermissionPermanentlyDenied();
          if (isPermanentlyDenied) {
            throw Exception('Storage permissions are permanently denied. Please enable them in Settings > Apps > Link Notes > Permissions');
          } else {
            throw Exception('Storage permissions are required to access your notes');
          }
        }
      }
      
      // Get vault directory from settings
      await SettingsService.instance.initialize();
      _vaultDirectory = SettingsService.instance.getVaultDirectory();
      
      if (_vaultDirectory == null || _vaultDirectory!.isEmpty) {
        throw Exception('No vault directory configured');
      }
      
      // Verify vault directory exists
      final vaultDir = Directory(_vaultDirectory!);
      if (!await vaultDir.exists()) {
        throw Exception('Vault directory does not exist: $_vaultDirectory');
      }
      
      _initialized = true;
      notifyListeners();
    } catch (e) {
      _setError('Failed to initialize vault: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Refresh permissions and re-initialize if needed
  Future<void> refreshPermissions() async {
    _setLoading(true);
    _clearError();
    
    try {
      final permissionService = PermissionService.instance;
      bool hasPermission = await permissionService.hasStoragePermission();
      
      if (!hasPermission) {
        // Try to request permissions again
        hasPermission = await permissionService.requestStoragePermission();
        
        if (!hasPermission) {
          // Check if permanently denied
          final isPermanentlyDenied = await permissionService.isPermissionPermanentlyDenied();
          if (isPermanentlyDenied) {
            throw Exception('Storage permissions are permanently denied. Please enable them in Settings > Apps > Link Notes > Permissions');
          } else {
            throw Exception('Storage permissions are required to access your notes');
          }
        }
      }
      
      // If we got permissions, clear any existing errors and notify listeners
      _clearError();
      notifyListeners();
    } catch (e) {
      _setError('Failed to refresh permissions: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Change vault directory
  Future<void> changeVaultDirectory(String newPath) async {
    _setLoading(true);
    _clearError();
    
    try {
      // Verify new directory exists
      final vaultDir = Directory(newPath);
      if (!await vaultDir.exists()) {
        throw Exception('Directory does not exist: $newPath');
      }
      
      // Update settings
      await SettingsService.instance.setVaultDirectory(newPath);
      
      // Reset state
      _vaultDirectory = newPath;
      _currentPath = '';
      _pathSegments = [];
      _initialized = true;
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to change vault directory: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  // ==================== NAVIGATION ====================
  
  /// Navigate to a specific path
  Future<void> navigateToPath(String path) async {
    if (!_initialized) return;
    
    _setLoading(true);
    _clearError();
    
    try {
      // Normalize path
      path = path.startsWith('/') ? path.substring(1) : path;
      path = path.endsWith('/') && path.isNotEmpty ? path.substring(0, path.length - 1) : path;
      
      // Verify path exists
      final fullPath = path.isEmpty ? _vaultDirectory! : '$_vaultDirectory/$path';
      final directory = Directory(fullPath);
      
      if (!await directory.exists()) {
        throw Exception('Directory does not exist: $path');
      }
      
      // Update navigation state
      _currentPath = path;
      _pathSegments = path.isEmpty ? [] : path.split('/');
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to navigate to path: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Navigate to parent directory
  Future<void> navigateToParent() async {
    if (isInRoot) return;
    
    final parentSegments = _pathSegments.take(_pathSegments.length - 1).toList();
    final parentPath = parentSegments.join('/');
    await navigateToPath(parentPath);
  }
  
  /// Navigate to root directory
  Future<void> navigateToRoot() async {
    await navigateToPath('');
  }
  
  /// Navigate to a subfolder
  Future<void> navigateToSubfolder(String folderName) async {
    final newPath = _currentPath.isEmpty ? folderName : '$_currentPath/$folderName';
    await navigateToPath(newPath);
  }
  
  // ==================== DATA FETCHING ====================
  
  /// Get all notes in the current directory (non-recursive)
  Future<List<Note>> getCurrentNotes() async {
    if (!_initialized || _vaultDirectory == null) return [];
    
    try {
      // Check permissions before attempting to read files
      final permissionService = PermissionService.instance;
      final hasPermission = await permissionService.hasStoragePermission();
      
      if (!hasPermission) {
        debugPrint('Storage permission denied - cannot read notes');
        _setError('Storage permission required to read notes. Please grant permission in app settings.');
        return [];
      }
      
      final directory = Directory(currentFullPath);
      if (!await directory.exists()) return [];
      
      final notes = <Note>[];
      
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final note = await Note.fromFile(entity);
            notes.add(note);
          } catch (e) {
            // Skip files that can't be parsed as notes
            debugPrint('Could not parse note from ${entity.path}: $e');
          }
        }
      }
      
      // Sort notes by title
      notes.sort((a, b) => a.title.compareTo(b.title));
      return notes;
    } catch (e) {
      debugPrint('Error fetching notes: $e');
      _setError('Failed to read notes: $e');
      return [];
    }
  }
  
  /// Get all folders in the current directory (non-recursive)
  Future<List<String>> getCurrentFolders() async {
    if (!_initialized || _vaultDirectory == null) return [];
    
    try {
      // Check permissions before attempting to read directories
      final permissionService = PermissionService.instance;
      final hasPermission = await permissionService.hasStoragePermission();
      
      if (!hasPermission) {
        debugPrint('Storage permission denied - cannot read folders');
        _setError('Storage permission required to read folders. Please grant permission in app settings.');
        return [];
      }
      
      final directory = Directory(currentFullPath);
      if (!await directory.exists()) return [];
      
      final folders = <String>[];
      
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          final folderName = entity.path.split(Platform.pathSeparator).last;
          folders.add(folderName);
        }
      }
      
      // Sort folders alphabetically
      folders.sort();
      return folders;
    } catch (e) {
      debugPrint('Error fetching folders: $e');
      _setError('Failed to read folders: $e');
      return [];
    }
  }
  
  /// Get a specific note by filename
  Future<Note?> getNote(String filename) async {
    if (!_initialized || _vaultDirectory == null) return null;
    
    try {
      final notePath = filename.endsWith('.md') ? filename : '$filename.md';
      final fullPath = '$currentFullPath/$notePath';
      final file = File(fullPath);
      
      if (!await file.exists()) return null;
      
      return await Note.fromFile(file);
    } catch (e) {
      debugPrint('Error fetching note $filename: $e');
      return null;
    }
  }
  
  /// Search for notes in the current directory and all subdirectories
  Future<List<Note>> searchNotes(String query) async {
    if (!_initialized || _vaultDirectory == null || query.trim().isEmpty) {
      return [];
    }
    
    try {
      final searchResults = <Note>[];
      final searchQuery = query.toLowerCase();
      
      // Search in current directory and all subdirectories
      await _searchInDirectory(Directory(currentFullPath), searchQuery, searchResults);
      
      // Sort by relevance (title matches first, then content matches)
      searchResults.sort((a, b) {
        final aTitleMatch = a.title.toLowerCase().contains(searchQuery);
        final bTitleMatch = b.title.toLowerCase().contains(searchQuery);
        
        if (aTitleMatch && !bTitleMatch) return -1;
        if (!aTitleMatch && bTitleMatch) return 1;
        
        return a.title.compareTo(b.title);
      });
      
      return searchResults;
    } catch (e) {
      debugPrint('Error searching notes: $e');
      return [];
    }
  }
  
  /// Recursively search for notes in a directory
  Future<void> _searchInDirectory(Directory directory, String query, List<Note> results) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final note = await Note.fromFile(entity);
            final titleMatch = note.title.toLowerCase().contains(query);
            final contentMatch = note.content.toLowerCase().contains(query);
            
            if (titleMatch || contentMatch) {
              results.add(note);
            }
          } catch (e) {
            // Skip files that can't be parsed
          }
        } else if (entity is Directory) {
          // Recursively search subdirectories
          await _searchInDirectory(entity, query, results);
        }
      }
    } catch (e) {
      // Skip directories that can't be read
    }
  }
  
  /// Get vault statistics
  Future<Map<String, int>> getVaultStats() async {
    if (!_initialized || _vaultDirectory == null) {
      return {'totalNotes': 0, 'totalFolders': 0};
    }
    
    try {
      int totalNotes = 0;
      int totalFolders = 0;
      
      await _countItemsInDirectory(Directory(_vaultDirectory!), (notes, folders) {
        totalNotes += notes;
        totalFolders += folders;
      });
      
      return {'totalNotes': totalNotes, 'totalFolders': totalFolders};
    } catch (e) {
      debugPrint('Error getting vault stats: $e');
      return {'totalNotes': 0, 'totalFolders': 0};
    }
  }
  
  /// Recursively count notes and folders
  Future<void> _countItemsInDirectory(Directory directory, Function(int notes, int folders) callback) async {
    try {
      int notes = 0;
      int folders = 0;
      
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          notes++;
        } else if (entity is Directory) {
          folders++;
          // Recursively count in subdirectories
          await _countItemsInDirectory(entity, callback);
        }
      }
      
      callback(notes, folders);
    } catch (e) {
      // Skip directories that can't be read
    }
  }
  
  // ==================== FILE OPERATIONS ====================
  
  /// Create a new note in the current directory
  Future<Note?> createNote({required String title, String content = ''}) async {
    if (!_initialized || _vaultDirectory == null) return null;
    
    try {
      // Generate unique filename
      final fileName = await _generateUniqueFileName(title, currentFullPath);
      final filePath = '$currentFullPath/$fileName.md';
      
      // Create note
      final now = DateTime.now();
      final note = Note(
        id: fileName,
        title: title,
        content: content,
        filePath: filePath,
        createdAt: now,
        modifiedAt: now,
      );
      
      // Save to file
      await note.toFile();
      
      notifyListeners(); // Refresh UI
      return note;
    } catch (e) {
      _setError('Failed to create note: $e');
      return null;
    }
  }
  
  /// Update an existing note
  Future<Note?> updateNote(Note note, {String? newTitle, String? newContent}) async {
    if (!_initialized) return null;
    
    try {
      String filePath = note.filePath;
      
      // Handle title change (may require file rename)
      if (newTitle != null && newTitle != note.title) {
        final directory = note.directoryPath;
        final newFileName = await _generateUniqueFileName(newTitle, directory);
        final newFilePath = '$directory/$newFileName.md';
        
        if (newFilePath != note.filePath) {
          final oldFile = File(note.filePath);
          if (await oldFile.exists()) {
            await oldFile.rename(newFilePath);
            filePath = newFilePath;
          }
        }
      }
      
      final updatedNote = note.copyWith(
        title: newTitle ?? note.title,
        content: newContent ?? note.content,
        filePath: filePath,
        modifiedAt: DateTime.now(),
      );
      
      await updatedNote.toFile();
      
      notifyListeners(); // Refresh UI
      return updatedNote;
    } catch (e) {
      _setError('Failed to update note: $e');
      return null;
    }
  }
  
  /// Delete a note
  Future<bool> deleteNote(Note note) async {
    if (!_initialized) return false;
    
    try {
      final file = File(note.filePath);
      if (await file.exists()) {
        await file.delete();
        notifyListeners(); // Refresh UI
        return true;
      }
      return false;
    } catch (e) {
      _setError('Failed to delete note: $e');
      return false;
    }
  }
  
  /// Create a new folder in the current directory
  Future<bool> createFolder(String folderName) async {
    if (!_initialized || _vaultDirectory == null) return false;
    
    try {
      final folderPath = '$currentFullPath/$folderName';
      final directory = Directory(folderPath);
      
      if (await directory.exists()) {
        _setError('Folder already exists: $folderName');
        return false;
      }
      
      await directory.create();
      notifyListeners(); // Refresh UI
      return true;
    } catch (e) {
      _setError('Failed to create folder: $e');
      return false;
    }
  }
  
  /// Delete a folder and all its contents
  Future<bool> deleteFolder(String folderName) async {
    if (!_initialized || _vaultDirectory == null) return false;
    
    try {
      final folderPath = '$currentFullPath/$folderName';
      final directory = Directory(folderPath);
      
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        notifyListeners(); // Refresh UI
        return true;
      }
      return false;
    } catch (e) {
      _setError('Failed to delete folder: $e');
      return false;
    }
  }
  
  // ==================== UTILITY METHODS ====================
  
  /// Generate a unique filename for a note
  Future<String> _generateUniqueFileName(String title, String directory) async {
    // Sanitize title for filename
    final baseFileName = title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    if (baseFileName.isEmpty) {
      return 'Untitled';
    }
    
    // Check if file exists
    final baseFile = File('$directory/$baseFileName.md');
    if (!await baseFile.exists()) {
      return baseFileName;
    }
    
    // Generate numbered version
    int counter = 1;
    while (true) {
      final numberedFileName = '$baseFileName $counter';
      final numberedFile = File('$directory/$numberedFileName.md');
      
      if (!await numberedFile.exists()) {
        return numberedFileName;
      }
      
      counter++;
    }
  }
  
  /// Refresh the current view
  void refresh() {
    notifyListeners();
  }
  
  // ==================== STATE MANAGEMENT HELPERS ====================
  
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }
  
  void _clearError() {
    _error = null;
  }
}