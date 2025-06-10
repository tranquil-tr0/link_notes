import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vault_provider.dart';
import '../models/note.dart';
import '../utils/path_utils.dart';
import 'note_editor_screen.dart';
import 'settings_screen.dart';

/// DirectoryScreen serves as the main interface for the notes app
///
/// Features:
/// - File explorer-like interface showing current directory contents
/// - Real-time file system reading with no internal data storage
/// - Breadcrumb navigation for folder traversal
/// - Search functionality across the vault
/// - Floating action buttons for creating notes and folders
/// - Proper back navigation handling to parent directories
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Note> _searchResults = [];
  bool _isSearchLoading = false;
  bool _wasInitialized = false;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize the vault when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vaultProvider = context.read<VaultProvider>();
      if (!vaultProvider.isInitialized) {
        vaultProvider.initialize();
      }
      _wasInitialized = vaultProvider.isInitialized;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VaultProvider>(
      builder: (context, vaultProvider, child) {
        // Check if vault provider was re-initialized (e.g., after directory change)
        if (_wasInitialized && !vaultProvider.isInitialized) {
          // VaultProvider was reset, clear our state
          setState(() {
            _isSearching = false;
            _searchResults.clear();
            _isSearchLoading = false;
            _searchController.clear();
          });
        } else if (!_wasInitialized && vaultProvider.isInitialized) {
          // VaultProvider just got initialized, refresh our view
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
        
        // Update our tracking of initialization state
        _wasInitialized = vaultProvider.isInitialized;
        
        return PopScope(
          canPop: vaultProvider.isInRoot,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop && !vaultProvider.isInRoot) {
              await vaultProvider.navigateToParent();
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: Builder(
                builder: (context) {
                  if (!vaultProvider.isInitialized && vaultProvider.isLoading) {
                    return _buildInitializingScreen();
                  }

                  if (vaultProvider.error != null) {
                    return _buildErrorScreen(vaultProvider);
                  }

                  if (!vaultProvider.isInitialized) {
                    return _buildWelcomeScreen(vaultProvider);
                  }

                  return _buildMainScreen(vaultProvider);
                },
              ),
            ),
            floatingActionButton: Builder(
              builder: (context) {
                if (!vaultProvider.isInitialized || _isSearching) {
                  return const SizedBox.shrink();
                }
                return _buildFloatingActionButtons(vaultProvider);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildInitializingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Initializing Vault...',
            style: TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen(VaultProvider vaultProvider) {
    final error = vaultProvider.error!;
    final isPermissionError = error.toLowerCase().contains('permission');
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPermissionError ? Icons.folder_special : Icons.error_outline,
              size: 64,
              color: isPermissionError ? Colors.orange : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              isPermissionError ? 'Permission Required' : 'Error Loading Vault',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (isPermissionError) ...[
              ElevatedButton.icon(
                onPressed: () {
                  vaultProvider.refreshPermissions();
                },
                icon: const Icon(Icons.security),
                label: const Text('Grant Permissions'),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: () {
                // Re-initialize VaultProvider and navigate to fresh DirectoryScreen
                vaultProvider.initialize();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const DirectoryScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen(VaultProvider vaultProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_outlined,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to Link Notes',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Your personal knowledge management system',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                vaultProvider.initialize();
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Initialize Vault'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainScreen(VaultProvider vaultProvider) {
    return Column(
      children: [
        _buildAppBar(vaultProvider),
        if (_isSearching) _buildSearchResultsOverlay()
        else Expanded(child: _buildMainContent(vaultProvider)),
      ],
    );
  }

  Widget _buildAppBar(VaultProvider vaultProvider) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top row: Vault name and actions
          Row(
            children: [
              const Icon(Icons.folder, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Vault',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (vaultProvider.vaultDisplayName != 'No Vault')
                      Text(
                        vaultProvider.vaultDisplayName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Spacer(),
              _buildVaultStats(vaultProvider),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () {
                  vaultProvider.refresh();
                },
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search bar and breadcrumbs
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildSearchField(vaultProvider),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _buildBreadcrumbs(vaultProvider),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVaultStats(VaultProvider vaultProvider) {
    return FutureBuilder<Map<String, int>>(
      future: vaultProvider.getVaultStats(),
      builder: (context, snapshot) {
        final totalNotes = snapshot.data?['totalNotes'] ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '$totalNotes notes',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchField(VaultProvider vaultProvider) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search notes...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _isSearching
            ? IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _isSearching = false;
                    _searchResults = [];
                  });
                },
                icon: const Icon(Icons.clear),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (query) {
        if (query.isNotEmpty) {
          _performSearch(vaultProvider, query);
        } else {
          setState(() {
            _isSearching = false;
            _searchResults = [];
          });
        }
      },
    );
  }

  void _performSearch(VaultProvider vaultProvider, String query) async {
    setState(() {
      _isSearching = true;
      _isSearchLoading = true;
    });
    
    try {
      final results = await vaultProvider.searchNotes(query);
      setState(() {
        _searchResults = results;
        _isSearchLoading = false;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearchLoading = false;
      });
    }
  }

  Widget _buildBreadcrumbs(VaultProvider vaultProvider) {
    // Use PathUtils to generate proper breadcrumb segments
    final segments = PathUtils.getBreadcrumbSegments(
      vaultProvider.vaultPath,
      vaultProvider.currentPath,
    );
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < segments.length; i++) ...[
            InkWell(
              onTap: () {
                if (i == 0) {
                  vaultProvider.navigateToRoot();
                } else if (i == 1) {
                  // Navigate to vault root
                  vaultProvider.navigateToRoot();
                } else {
                  // Navigate to specific path within vault
                  final pathSegments = segments.skip(2).take(i - 1).toList();
                  final path = pathSegments.join('/');
                  vaultProvider.navigateToPath(path);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: i == segments.length - 1
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      i == 0 ? Icons.home : (i == 1 ? Icons.folder_special : Icons.folder),
                      size: 16,
                      color: i == segments.length - 1
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        segments[i],
                        style: TextStyle(
                          color: i == segments.length - 1
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: i == segments.length - 1
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < segments.length - 1)
              Icon(
                Icons.chevron_right,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResultsOverlay() {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Search Results for "${_searchController.text}"',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${_searchResults.length} results',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isSearchLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 48, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No notes found'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final note = _searchResults[index];
                            return _buildNoteListItem(note);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(VaultProvider vaultProvider) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadCurrentDirectoryContents(vaultProvider),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error loading directory: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => vaultProvider.refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        
        final data = snapshot.data ?? {};
        final notes = data['notes'] as List<Note>? ?? [];
        final folders = data['folders'] as List<String>? ?? [];
        
        return _buildDirectoryContents(vaultProvider, notes, folders);
      },
    );
  }

  Future<Map<String, dynamic>> _loadCurrentDirectoryContents(VaultProvider vaultProvider) async {
    final notes = await vaultProvider.getCurrentNotes();
    final folders = await vaultProvider.getCurrentFolders();
    return {'notes': notes, 'folders': folders};
  }

  Widget _buildDirectoryContents(VaultProvider vaultProvider, List<Note> notes, List<String> folders) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_open, size: 20),
              const SizedBox(width: 8),
              Text(
                vaultProvider.vaultDisplayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text(
                '${folders.length} folders • ${notes.length} notes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: notes.isEmpty && folders.isEmpty
                ? _buildEmptyDirectoryState(vaultProvider)
                : _buildDirectoryGrid(vaultProvider, notes, folders),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDirectoryState(VaultProvider vaultProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Empty Directory',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first note or folder to get started',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showCreateNoteDialog(vaultProvider),
                icon: const Icon(Icons.note_add),
                label: const Text('Create Note'),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => _showCreateFolderDialog(vaultProvider),
                icon: const Icon(Icons.folder_open),
                label: const Text('Create Folder'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryGrid(VaultProvider vaultProvider, List<Note> notes, List<String> folders) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final cardWidth = 280.0;
        final crossAxisCount = (screenWidth / cardWidth).floor().clamp(1, 4);
        
        // Combine folders and notes for display
        final allItems = <dynamic>[...folders, ...notes];
        
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.2,
          ),
          itemCount: allItems.length,
          itemBuilder: (context, index) {
            final item = allItems[index];
            
            if (item is String) {
              // It's a folder
              return _buildFolderCard(vaultProvider, item);
            } else if (item is Note) {
              // It's a note
              return _buildNoteCard(item);
            }
            
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  Widget _buildFolderCard(VaultProvider vaultProvider, String folderName) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          vaultProvider.navigateToSubfolder(folderName);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder,
                    size: 24,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _showDeleteFolderDialog(vaultProvider, folderName);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folderName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Folder',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => NoteEditorScreen(note: note),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.note,
                    size: 20,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => NoteEditorScreen(note: note),
                          ),
                        );
                      } else if (value == 'delete') {
                        _showDeleteNoteDialog(note);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        note.content,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Modified ${_formatDate(note.modifiedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoteListItem(Note note) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.note),
        title: Text(
          note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          note.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _formatDate(note.modifiedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => NoteEditorScreen(note: note),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFloatingActionButtons(VaultProvider vaultProvider) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: "create_folder",
          onPressed: () => _showCreateFolderDialog(vaultProvider),
          tooltip: 'Create Folder',
          child: const Icon(Icons.folder_open),
        ),
        const SizedBox(height: 16),
        FloatingActionButton(
          heroTag: "create_note",
          onPressed: () => _showCreateNoteDialog(vaultProvider),
          tooltip: 'Create Note',
          child: const Icon(Icons.add),
        ),
      ],
    );
  }

  void _showCreateNoteDialog(VaultProvider vaultProvider) {
    showDialog(
      context: context,
      builder: (context) {
        final titleController = TextEditingController();
        return AlertDialog(
          title: const Text('Create New Note'),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Note Title',
              hintText: 'Enter note title',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  Navigator.of(context).pop();
                  final note = await vaultProvider.createNote(title: title);
                  if (note != null && mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => NoteEditorScreen(note: note),
                      ),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _showCreateFolderDialog(VaultProvider vaultProvider) {
    showDialog(
      context: context,
      builder: (context) {
        final nameController = TextEditingController();
        return AlertDialog(
          title: const Text('Create New Folder'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Folder Name',
              hintText: 'Enter folder name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(context).pop();
                  await vaultProvider.createFolder(name);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteNoteDialog(Note note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final vaultProvider = context.read<VaultProvider>();
              await vaultProvider.deleteNote(note);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderDialog(VaultProvider vaultProvider, String folderName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Are you sure you want to delete "$folderName" and all its contents?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await vaultProvider.deleteFolder(folderName);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}