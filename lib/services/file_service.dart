import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import '../models/folder.dart';
import 'settings_service.dart';

class FileService {
  static FileService? _instance;
  late String _vaultPath;
  bool _initialized = false;

  FileService._();

  /// Singleton instance
  static FileService get instance {
    _instance ??= FileService._();
    return _instance!;
  }

  /// Initialize the file service and set up the vault directory
  Future<void> initialize({String? customVaultPath}) async {
    if (_initialized) return;

    try {
      // Try to initialize settings service first, but don't fail if it doesn't work
      try {
        await SettingsService.instance.initialize();
      } catch (settingsError) {
        // Log warning but continue with default behavior
        print('Warning: SettingsService initialization failed: $settingsError');
      }
      
      if (customVaultPath != null) {
        _vaultPath = customVaultPath;
      } else {
        // Try to get vault path from settings first
        String? savedVaultPath;
        try {
          savedVaultPath = SettingsService.instance.getVaultDirectory();
        } catch (e) {
          // Settings service not available, use default
          savedVaultPath = null;
        }
        
        if (savedVaultPath != null && savedVaultPath.isNotEmpty) {
          _vaultPath = savedVaultPath;
        } else {
          // Fallback to default location in documents directory
          final documentsDir = await getApplicationDocumentsDirectory();
          _vaultPath = documentsDir.path;
        }
      }

      // Create vault directory if it doesn't exist
      final vaultDir = Directory(_vaultPath);
      if (!await vaultDir.exists()) {
        await vaultDir.create(recursive: true);
      }

      _initialized = true;
    } catch (e) {
      throw Exception('Failed to initialize FileService: $e');
    }
  }

  /// Change the vault directory and reinitialize
  Future<void> changeVaultDirectory(String newVaultPath) async {
    try {
      _initialized = false;
      _vaultPath = newVaultPath;
      
      // Create new vault directory if it doesn't exist
      final vaultDir = Directory(_vaultPath);
      if (!await vaultDir.exists()) {
        await vaultDir.create(recursive: true);
      }

      _initialized = true;
    } catch (e) {
      throw Exception('Failed to change vault directory: $e');
    }
  }

  /// Check if vault directory is configured
  bool hasVaultDirectoryConfigured() {
    try {
      return SettingsService.instance.hasVaultDirectory();
    } catch (e) {
      // If settings service is not available, assume no vault directory is configured
      return false;
    }
  }

  /// Check if this is the first launch
  bool isFirstLaunch() {
    try {
      return SettingsService.instance.isFirstLaunch();
    } catch (e) {
      // If settings service is not available, assume it's the first launch
      return true;
    }
  }

  /// Gets the vault path
  String get vaultPath {
    _ensureInitialized();
    return _vaultPath;
  }

  /// Ensures the service is initialized
  void _ensureInitialized() {
    if (!_initialized) {
      throw Exception('FileService not initialized. Call initialize() first.');
    }
  }

  // ==================== NOTE OPERATIONS ====================

  /// Creates a new note
  Future<Note> createNote({
    required String title,
    String content = '',
    String? folderId,
    String? customPath,
  }) async {
    _ensureInitialized();

    try {
      // Determine file path - always place directly in vault directory
      String filePath;
      if (customPath != null) {
        filePath = customPath;
      } else {
        // Generate unique file name from title
        final fileName = await _generateUniqueFileName(title, _vaultPath);
        filePath = '$_vaultPath/$fileName.md';
      }

      // Create note instance with filename as ID
      final now = DateTime.now();
      final note = Note(
        id: filePath.split('/').last.replaceAll('.md', ''),
        title: title,
        content: content,
        filePath: filePath,
        createdAt: now,
        modifiedAt: now,
      );

      // Save to file
      await note.toFile();

      return note;
    } catch (e) {
      throw Exception('Failed to create note: $e');
    }
  }

  /// Reads a note from file
  Future<Note> readNote(String filePath) async {
    _ensureInitialized();

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Note file does not exist: $filePath');
      }

      return await Note.fromFile(file);
    } catch (e) {
      throw Exception('Failed to read note: $e');
    }
  }

  /// Updates an existing note
  Future<Note> updateNote(Note note, {
    String? newTitle,
    String? newContent,
  }) async {
    _ensureInitialized();

    try {
      // Check if title changed and filename needs to be updated
      String filePath = note.filePath;
      if (newTitle != null && newTitle != note.title) {
        final directory = note.directoryPath;
        final newFileName = await _generateUniqueFileName(newTitle, directory);
        final newFilePath = '$directory/$newFileName.md';
        
        // If the filename would change, move the file
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

      return updatedNote;
    } catch (e) {
      throw Exception('Failed to update note: $e');
    }
  }

  /// Deletes a note
  Future<bool> deleteNote(String filePath) async {
    _ensureInitialized();

    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('Failed to delete note: $e');
    }
  }

  /// Moves a note to a different folder
  Future<Note> moveNote(Note note, String newFolderPath) async {
    _ensureInitialized();

    try {
      final oldFile = File(note.filePath);
      final fileName = await _generateUniqueFileName(note.title, newFolderPath);
      final newFilePath = '$newFolderPath/$fileName.md';
      final newFile = File(newFilePath);

      // Create destination directory if it doesn't exist
      await newFile.parent.create(recursive: true);

      // Copy file to new location
      await oldFile.copy(newFilePath);

      // Delete old file
      await oldFile.delete();

      // Return updated note with new file path
      return note.copyWith(
        filePath: newFilePath,
        modifiedAt: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to move note: $e');
    }
  }

  // ==================== FOLDER OPERATIONS ====================

  /// Creates a new folder
  Future<Folder> createFolder(String folderName, {String? parentPath}) async {
    _ensureInitialized();

    try {
      final folderPath = parentPath != null 
          ? '$parentPath/$folderName'
          : '$_vaultPath/$folderName';

      final directory = Directory(folderPath);
      if (await directory.exists()) {
        throw Exception('Folder already exists: $folderPath');
      }

      await directory.create(recursive: true);

      return Folder(
        name: folderName,
        path: folderPath,
      );
    } catch (e) {
      throw Exception('Failed to create folder: $e');
    }
  }

  /// Deletes a folder and all its contents
  Future<bool> deleteFolder(String folderPath) async {
    _ensureInitialized();

    try {
      final directory = Directory(folderPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('Failed to delete folder: $e');
    }
  }

  /// Lists all folders in the vault
  Future<List<Folder>> listFolders({String? parentPath}) async {
    _ensureInitialized();

    try {
      final searchPath = parentPath ?? _vaultPath;
      final directory = Directory(searchPath);
      
      if (!await directory.exists()) {
        return [];
      }

      final folders = <Folder>[];
      
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          try {
            final folder = await Folder.fromDirectory(entity.path, recursive: false);
            folders.add(folder);
          } catch (e) {
            // Warning: Could not load folder - handle gracefully
            // Note: In production, consider using a proper logging framework
          }
        }
      }

      folders.sort((a, b) => a.name.compareTo(b.name));
      return folders;
    } catch (e) {
      throw Exception('Failed to list folders: $e');
    }
  }

  /// Gets the root folder with all contents
  Future<Folder> getRootFolder() async {
    _ensureInitialized();

    try {
      return await Folder.fromDirectory(_vaultPath, recursive: true);
    } catch (e) {
      throw Exception('Failed to get root folder: $e');
    }
  }

  /// Gets a specific folder by path
  Future<Folder?> getFolder(String folderPath) async {
    _ensureInitialized();

    try {
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        return null;
      }

      return await Folder.fromDirectory(folderPath, recursive: true);
    } catch (e) {
      throw Exception('Failed to get folder: $e');
    }
  }

  /// Renames a folder
  Future<Folder> renameFolder(String oldPath, String newName) async {
    _ensureInitialized();

    try {
      final oldDirectory = Directory(oldPath);
      if (!await oldDirectory.exists()) {
        throw Exception('Folder does not exist: $oldPath');
      }

      final parentPath = oldPath.substring(0, oldPath.lastIndexOf('/'));
      final newPath = '$parentPath/$newName';
      
      await oldDirectory.rename(newPath);

      return await Folder.fromDirectory(newPath, recursive: true);
    } catch (e) {
      throw Exception('Failed to rename folder: $e');
    }
  }

  // ==================== SEARCH OPERATIONS ====================

  /// Searches for notes by title or content
  Future<List<Note>> searchNotes(String query, {bool caseSensitive = false}) async {
    _ensureInitialized();

    try {
      final rootFolder = await getRootFolder();
      final allNotes = rootFolder.getAllNotes();
      
      final searchQuery = caseSensitive ? query : query.toLowerCase();
      
      return allNotes.where((note) {
        final title = caseSensitive ? note.title : note.title.toLowerCase();
        final content = caseSensitive ? note.content : note.content.toLowerCase();
        
        return title.contains(searchQuery) || content.contains(searchQuery);
      }).toList();
    } catch (e) {
      throw Exception('Failed to search notes: $e');
    }
  }

  /// Gets all notes in the vault
  Future<List<Note>> getAllNotes() async {
    _ensureInitialized();

    try {
      final rootFolder = await getRootFolder();
      return rootFolder.getAllNotes();
    } catch (e) {
      throw Exception('Failed to get all notes: $e');
    }
  }

  /// Gets recently modified notes
  Future<List<Note>> getRecentNotes({int limit = 10}) async {
    _ensureInitialized();

    try {
      final allNotes = await getAllNotes();
      allNotes.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      
      return allNotes.take(limit).toList();
    } catch (e) {
      throw Exception('Failed to get recent notes: $e');
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Generates a file name from the note title
  String _generateFileName(String title) {
    // Sanitize the title to be a valid filename
    final sanitizedTitle = title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '') // Remove invalid file characters
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
    
    // If the sanitized title is empty, use a default name
    if (sanitizedTitle.isEmpty) {
      return 'Untitled';
    }
    
    return sanitizedTitle;
  }

  /// Generates a unique file name by checking for existing files
  Future<String> _generateUniqueFileName(String title, String directory) async {
    final baseFileName = _generateFileName(title);
    final baseFile = File('$directory/$baseFileName.md');
    
    // If the base filename doesn't exist, use it
    if (!await baseFile.exists()) {
      return baseFileName;
    }
    
    // If it exists, append a number to make it unique
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

  /// Checks if the vault is properly initialized
  Future<bool> isVaultValid() async {
    try {
      _ensureInitialized();
      final vaultDir = Directory(_vaultPath);
      return await vaultDir.exists();
    } catch (e) {
      return false;
    }
  }

  /// Gets vault statistics
  Future<Map<String, dynamic>> getVaultStats() async {
    _ensureInitialized();

    try {
      final rootFolder = await getRootFolder();
      final allNotes = rootFolder.getAllNotes();
      final allFolders = rootFolder.getAllSubfolders();

      return {
        'totalNotes': allNotes.length,
        'totalFolders': allFolders.length,
        'vaultPath': _vaultPath,
        'lastModified': allNotes.isNotEmpty
            ? allNotes
                .map((n) => n.modifiedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b)
                .toIso8601String()
            : null,
      };
    } catch (e) {
      throw Exception('Failed to get vault stats: $e');
    }
  }

  /// Exports vault structure as JSON
  Future<Map<String, dynamic>> exportVaultStructure() async {
    _ensureInitialized();

    try {
      final rootFolder = await getRootFolder();
      
      return {
        'vault_path': _vaultPath,
        'exported_at': DateTime.now().toIso8601String(),
        'structure': _folderToJson(rootFolder),
      };
    } catch (e) {
      throw Exception('Failed to export vault structure: $e');
    }
  }

  /// Converts folder structure to JSON
  Map<String, dynamic> _folderToJson(Folder folder) {
    return {
      'name': folder.name,
      'path': folder.path,
      'notes': folder.notes.map((note) => note.toJson()).toList(),
      'subfolders': folder.subfolders.map((subfolder) => _folderToJson(subfolder)).toList(),
    };
  }
}