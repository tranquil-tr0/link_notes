import 'package:flutter/foundation.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../services/file_service.dart';

/// State management provider for the notes application
/// 
/// This provider serves as the bridge between the FileService and UI components,
/// providing reactive state management with proper loading states and error handling.
class NotesProvider extends ChangeNotifier {
  final FileService _fileService = FileService.instance;

  // ==================== STATE VARIABLES ====================
  
  // Current folder and navigation state
  Folder? _currentFolder;
  Folder? _rootFolder;
  List<String> _currentPath = [];
  List<Folder> _breadcrumbs = [];
  
  // Notes and selection state
  List<Note> _notes = [];
  Note? _selectedNote;
  
  // Search state
  List<Note> _searchResults = [];
  String _searchQuery = '';
  bool _isSearching = false;
  
  // Loading and error states
  bool _isLoading = false;
  bool _isInitializing = false;
  String? _error;
  final Map<String, bool> _operationLoading = {};
  
  // ==================== GETTERS ====================
  
  /// Current folder being displayed
  Folder? get currentFolder => _currentFolder;
  
  /// Root folder of the vault
  Folder? get rootFolder => _rootFolder;
  
  /// Current navigation path as list of folder names
  List<String> get currentPath => List.unmodifiable(_currentPath);
  
  /// Breadcrumb navigation folders
  List<Folder> get breadcrumbs => List.unmodifiable(_breadcrumbs);
  
  /// Notes in the current folder
  List<Note> get notes => List.unmodifiable(_notes);
  
  /// Currently selected note
  Note? get selectedNote => _selectedNote;
  
  /// Search results
  List<Note> get searchResults => List.unmodifiable(_searchResults);
  
  /// Current search query
  String get searchQuery => _searchQuery;
  
  /// Whether search is active
  bool get isSearching => _isSearching;
  
  /// General loading state
  bool get isLoading => _isLoading;
  
  /// Whether the provider is initializing
  bool get isInitializing => _isInitializing;
  
  /// Current error message
  String? get error => _error;
  
  /// Check if a specific operation is loading
  bool isOperationLoading(String operation) => _operationLoading[operation] ?? false;
  
  /// Whether the vault has been initialized
  bool get isVaultInitialized => _rootFolder != null;
  
  /// Current folder path as string
  String get currentFolderPath => _currentPath.join('/');
  
  /// Whether currently in root folder
  bool get isInRootFolder => _currentPath.isEmpty;
  
  // ==================== INITIALIZATION ====================
  
  /// Initialize the vault and load the root folder
  Future<void> loadVault() async {
    if (_isInitializing) return;
    
    _setInitializing(true);
    _clearError();
    
    try {
      // Initialize the file service
      await _fileService.initialize();
      
      // Load the root folder
      _rootFolder = await _fileService.getRootFolder();
      
      // Set current folder to root
      _currentFolder = _rootFolder;
      _currentPath = [];
      _breadcrumbs = [];
      _notes = _currentFolder?.notes ?? [];
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to load vault: $e');
    } finally {
      _setInitializing(false);
    }
  }

  /// Change the vault directory and reinitialize
  Future<void> changeVaultDirectory(String newVaultPath) async {
    _setInitializing(true);
    _clearError();
    
    try {
      // Clear current state
      clearState();
      
      // Change vault directory in file service
      await _fileService.changeVaultDirectory(newVaultPath);
      
      // Load the new root folder
      _rootFolder = await _fileService.getRootFolder();
      
      // Set current folder to root
      _currentFolder = _rootFolder;
      _currentPath = [];
      _breadcrumbs = [];
      _notes = _currentFolder?.notes ?? [];
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to change vault directory: $e');
    } finally {
      _setInitializing(false);
    }
  }
  
  /// Refresh the current folder from the file system
  Future<void> refreshCurrentFolder() async {
    if (_currentFolder == null) return;
    
    _setLoading(true);
    _clearError();
    
    try {
      // Reload the current folder
      await _currentFolder!.refresh();
      _notes = _currentFolder!.notes;
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to refresh folder: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  // ==================== FOLDER NAVIGATION ====================
  
  /// Load and navigate to a specific folder
  Future<void> loadFolder(Folder folder) async {
    _setLoading(true);
    _clearError();
    
    try {
      // Refresh folder contents
      await folder.refresh();
      
      // Update current folder state
      _currentFolder = folder;
      _notes = folder.notes;
      
      // Update navigation state
      _updateNavigationState(folder);
      
      // Clear selection when changing folders
      _selectedNote = null;
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to load folder: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Navigate to a folder by path
  Future<void> navigateToPath(List<String> path) async {
    if (_rootFolder == null) return;
    
    _setLoading(true);
    _clearError();
    
    try {
      Folder targetFolder = _rootFolder!;
      
      // Navigate through the path
      for (final folderName in path) {
        final subfolder = targetFolder.findSubfolder(folderName);
        if (subfolder == null) {
          throw Exception('Folder not found: $folderName');
        }
        targetFolder = subfolder;
      }
      
      await loadFolder(targetFolder);
    } catch (e) {
      _setError('Failed to navigate to path: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Navigate to parent folder
  Future<void> navigateToParent() async {
    if (_currentFolder?.parent != null) {
      await loadFolder(_currentFolder!.parent!);
    } else if (!isInRootFolder && _rootFolder != null) {
      await loadFolder(_rootFolder!);
    }
  }
  
  /// Navigate to root folder
  Future<void> navigateToRoot() async {
    if (_rootFolder != null) {
      await loadFolder(_rootFolder!);
    }
  }
  
  /// Update navigation state based on current folder
  void _updateNavigationState(Folder folder) {
    _currentPath = folder.pathHierarchy.skip(1).toList(); // Skip root folder name
    _breadcrumbs = [];
    
    // Build breadcrumb trail
    Folder? current = folder;
    final trail = <Folder>[];
    
    while (current != null) {
      trail.insert(0, current);
      current = current.parent;
    }
    
    _breadcrumbs = trail;
  }
  
  // ==================== NOTE OPERATIONS ====================
  
  /// Create a new note in the current folder
  Future<Note?> createNote({
    required String title,
    String content = '',
    String? folderId,
  }) async {
    const operation = 'createNote';
    _setOperationLoading(operation, true);
    _clearError();
    
    try {
      final targetFolderId = folderId ?? (_currentFolder?.name);
      
      final note = await _fileService.createNote(
        title: title,
        content: content,
        folderId: targetFolderId,
      );
      
      // Add note to current folder if it's the target folder
      if (_currentFolder?.name == targetFolderId || folderId == null) {
        _currentFolder?.addNote(note);
        _notes = _currentFolder?.notes ?? [];
      }
      
      notifyListeners();
      return note;
    } catch (e) {
      _setError('Failed to create note: $e');
      return null;
    } finally {
      _setOperationLoading(operation, false);
    }
  }
  
  /// Update an existing note
  Future<Note?> updateNote(Note note, {String? newTitle, String? newContent}) async {
    const operation = 'updateNote';
    _setOperationLoading(operation, true);
    _clearError();
    
    try {
      final updatedNote = await _fileService.updateNote(
        note,
        newTitle: newTitle,
        newContent: newContent,
      );
      
      // Update note in current folder
      if (_currentFolder != null) {
        _currentFolder!.addNote(updatedNote); // This replaces existing note
        _notes = _currentFolder!.notes;
      }
      
      // Update selected note if it's the same note
      if (_selectedNote?.id == note.id) {
        _selectedNote = updatedNote;
      }
      
      notifyListeners();
      return updatedNote;
    } catch (e) {
      _setError('Failed to update note: $e');
      return null;
    } finally {
      _setOperationLoading(operation, false);
    }
  }
  
  /// Delete a note
  Future<bool> deleteNote(Note note) async {
    const operation = 'deleteNote';
    _setOperationLoading(operation, true);
    _clearError();
    
    try {
      final success = await _fileService.deleteNote(note.filePath);
      
      if (success) {
        // Remove note from current folder
        _currentFolder?.removeNoteInstance(note);
        _notes = _currentFolder?.notes ?? [];
        
        // Clear selection if deleted note was selected
        if (_selectedNote?.id == note.id) {
          _selectedNote = null;
        }
        
        notifyListeners();
      }
      
      return success;
    } catch (e) {
      _setError('Failed to delete note: $e');
      return false;
    } finally {
      _setOperationLoading(operation, false);
    }
  }
  
  /// Select a note
  void selectNote(Note? note) {
    _selectedNote = note;
    notifyListeners();
  }
  
  // ==================== FOLDER OPERATIONS ====================
  
  /// Create a new folder
  Future<Folder?> createFolder(String folderName, {String? parentPath}) async {
    const operation = 'createFolder';
    _setOperationLoading(operation, true);
    _clearError();
    
    try {
      final targetParentPath = parentPath ?? _currentFolder?.path;
      
      final folder = await _fileService.createFolder(
        folderName,
        parentPath: targetParentPath,
      );
      
      // Add folder to current folder if it's the parent
      if (_currentFolder?.path == targetParentPath || parentPath == null) {
        _currentFolder?.addSubfolder(folder);
      }
      
      // Refresh root folder to maintain consistency
      if (_rootFolder != null) {
        await _rootFolder!.refresh();
      }
      
      notifyListeners();
      return folder;
    } catch (e) {
      _setError('Failed to create folder: $e');
      return null;
    } finally {
      _setOperationLoading(operation, false);
    }
  }
  
  /// Delete a folder
  Future<bool> deleteFolder(Folder folder) async {
    const operation = 'deleteFolder';
    _setOperationLoading(operation, true);
    _clearError();
    
    try {
      final success = await _fileService.deleteFolder(folder.path);
      
      if (success) {
        // Remove folder from parent
        folder.parent?.removeSubfolderInstance(folder);
        
        // Navigate to parent if we're deleting current folder
        if (_currentFolder?.path == folder.path && folder.parent != null) {
          await loadFolder(folder.parent!);
        }
        
        // Refresh root folder to maintain consistency
        if (_rootFolder != null) {
          await _rootFolder!.refresh();
        }
        
        notifyListeners();
      }
      
      return success;
    } catch (e) {
      _setError('Failed to delete folder: $e');
      return false;
    } finally {
      _setOperationLoading(operation, false);
    }
  }
  
  /// Get all folders in the vault
  Future<List<Folder>> getAllFolders() async {
    try {
      if (_rootFolder == null) return [];
      return _rootFolder!.getAllSubfolders();
    } catch (e) {
      _setError('Failed to get folders: $e');
      return [];
    }
  }
  
  // ==================== SEARCH OPERATIONS ====================
  
  /// Search for notes across the vault
  Future<void> searchNotes(String query) async {
    if (query.trim().isEmpty) {
      clearSearch();
      return;
    }
    
    _isSearching = true;
    _searchQuery = query;
    _setLoading(true);
    _clearError();
    
    try {
      _searchResults = await _fileService.searchNotes(query);
      notifyListeners();
    } catch (e) {
      _setError('Failed to search notes: $e');
      _searchResults = [];
    } finally {
      _setLoading(false);
    }
  }
  
  /// Clear search results and exit search mode
  void clearSearch() {
    _isSearching = false;
    _searchQuery = '';
    _searchResults = [];
    notifyListeners();
  }
  
  /// Get recent notes
  Future<List<Note>> getRecentNotes({int limit = 10}) async {
    try {
      return await _fileService.getRecentNotes(limit: limit);
    } catch (e) {
      _setError('Failed to get recent notes: $e');
      return [];
    }
  }
  
  // ==================== STATE MANAGEMENT HELPERS ====================
  
  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  /// Set initializing state
  void _setInitializing(bool initializing) {
    _isInitializing = initializing;
    notifyListeners();
  }
  
  /// Set operation-specific loading state
  void _setOperationLoading(String operation, bool loading) {
    _operationLoading[operation] = loading;
    notifyListeners();
  }
  
  /// Set error message
  void _setError(String error) {
    _error = error;
    debugPrint('NotesProvider Error: $error');
    notifyListeners();
  }
  
  /// Clear error message
  void _clearError() {
    _error = null;
  }
  
  /// Clear all state (useful for logout/reset scenarios)
  void clearState() {
    _currentFolder = null;
    _rootFolder = null;
    _currentPath = [];
    _breadcrumbs = [];
    _notes = [];
    _selectedNote = null;
    _searchResults = [];
    _searchQuery = '';
    _isSearching = false;
    _isLoading = false;
    _isInitializing = false;
    _error = null;
    _operationLoading.clear();
    notifyListeners();
  }
  
  // ==================== UTILITY METHODS ====================
  
  /// Get vault statistics
  Future<Map<String, dynamic>> getVaultStats() async {
    try {
      return await _fileService.getVaultStats();
    } catch (e) {
      _setError('Failed to get vault stats: $e');
      return {};
    }
  }
  
  /// Check if vault is valid
  Future<bool> isVaultValid() async {
    try {
      return await _fileService.isVaultValid();
    } catch (e) {
      return false;
    }
  }
  
  @override
  void dispose() {
    // Clean up any resources if needed
    _operationLoading.clear();
    super.dispose();
  }
}