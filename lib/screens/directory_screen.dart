import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
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
  bool _wasInitialized = false;
  bool _isStatsExpanded = false;

  // Google Keep inspired colors for note cards
  static const List<Color> _keepColors = [
    Color(0xFFFFF9C4), // Light Yellow
    Color(0xFFF8BBD9), // Light Pink
    Color(0xFFE1F5FE), // Light Blue
    Color(0xFFE8F5E8), // Light Green
    Color(0xFFFFF3E0), // Light Orange
    Color(0xFFF3E5F5), // Light Purple
    Color(0xFFEDE7F6), // Light Indigo
    Color(0xFFFCE4EC), // Light Rose
    Color(0xFFE0F2F1), // Light Teal
    Color(0xFFFFF8E1), // Light Amber
  ];

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
              bottom: false,
              child: Builder(
                builder: (context) {
                  if (!vaultProvider.isInitialized && vaultProvider.isLoading) {
                    return _buildInitializingScreen();
                  }

                  if (vaultProvider.error != null) {
                    return _buildErrorScreen(vaultProvider);
                  }

                  if (!vaultProvider.isInitialized) {
                    //throw an error
                    debugPrint('In directory screen, but vault provider is not initialized.');
                    return Center(
                      child: Text(
                        'Vault is not initialized. Try setting up again.',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    );
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
          Text('Initializing Vault...', style: TextStyle(fontSize: 18)),
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

  Widget _buildMainScreen(VaultProvider vaultProvider) {
    return Column(
      children: [
        _buildAppBar(vaultProvider),
        Expanded(child: _buildMainContent(vaultProvider)),
      ],
    );
  }

  Widget _buildAppBar(VaultProvider vaultProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
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
      child: Row(
        children: [
          // 1. Breadcrumbs (left)
          Expanded(flex: 3, child: _buildBreadcrumbs(vaultProvider)),

          // 2. Search (center-left)
          _buildSearchButton(vaultProvider),

          // 3. Vault Stats (center-right)
          _buildVaultStats(vaultProvider),

          // 4. Settings (right)
          _buildSettingsButton(),
        ],
      ),
    );
  }

  Widget _buildVaultStats(VaultProvider vaultProvider) {
    return FutureBuilder<Map<String, int>>(
      future: vaultProvider.getVaultStats(),
      builder: (context, snapshot) {
        final totalNotes = snapshot.data?['totalNotes'] ?? 0;
        final totalFolders = snapshot.data?['totalFolders'] ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Base collapsed state - always visible
            GestureDetector(
              onTap: () {
                setState(() {
                  _isStatsExpanded = !_isStatsExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
              ),
            ),
            // Expanded overlay state
            if (_isStatsExpanded)
              Positioned(
                top: 0,
                left: -7,

                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isStatsExpanded = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: FutureBuilder<List<dynamic>>(
                      future: Future.wait([
                        vaultProvider.getCurrentNotes(),
                        vaultProvider.getCurrentFolders(),
                      ]),
                      builder: (context, currentSnapshot) {
                        final currentNotes = currentSnapshot.hasData
                            ? (currentSnapshot.data![0] as List).length
                            : 0;
                        final currentFolders = currentSnapshot.hasData
                            ? (currentSnapshot.data![1] as List).length
                            : 0;

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$totalNotes total notes',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$currentNotes notes here',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$totalFolders total folders',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$currentFolders folders here',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsButton() {
    return IconButton(
      onPressed: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const SettingsScreen()));
      },
      icon: const Icon(Icons.settings),
      tooltip: 'Settings',
    );
  }

  Widget _buildSearchButton(VaultProvider vaultProvider) {
    return IconButton(
      onPressed: () {
        setState(() {

        });
      },
      icon: const Icon(Icons.search),
      tooltip: 'Search notes',
    );
  }

  void _performSearch(VaultProvider vaultProvider, String query) async {
    setState(() {
      _isSearching = true;

    });

    try {
      final results = await vaultProvider.searchNotes(query);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
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
                      i == 0
                          ? Icons.home
                          : (i == 1 ? Icons.folder_special : Icons.folder),
                      size: 16,
                      color: i == segments.length - 1
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        segments[i],
                        style: TextStyle(
                          color: i == segments.length - 1
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
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

  Widget _buildMainContent(VaultProvider vaultProvider) {
    return FutureBuilder<List<Note>>(
      future: vaultProvider.getCurrentNotes(),
      builder: (context, notesSnapshot) {
        if (notesSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (notesSnapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error loading directory: ${notesSnapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => vaultProvider.refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return FutureBuilder<List<String>>(
          future: vaultProvider.getCurrentFolders(),
          builder: (context, foldersSnapshot) {
            if (foldersSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (foldersSnapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error loading directory: ${foldersSnapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => vaultProvider.refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final notes = notesSnapshot.data ?? [];
            final folders = foldersSnapshot.data ?? [];

            return _buildDirectoryContents(vaultProvider, notes, folders);
          },
        );
      },
    );
  }

  Widget _buildDirectoryContents(
    VaultProvider vaultProvider,
    List<Note> notes,
    List<String> folders,
  ) {
    return Container(
      child: notes.isEmpty && folders.isEmpty
          ? _buildEmptyDirectoryState(vaultProvider)
          : _buildDirectoryGrid(vaultProvider, notes, folders),
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

  Widget _buildDirectoryGrid(
    VaultProvider vaultProvider,
    List<Note> notes,
    List<String> folders,
  ) {
    // Combine folders and notes for display
    final allItems = <dynamic>[...folders, ...notes];

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: MasonryGridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        itemCount: allItems.length,
        itemBuilder: (context, index) {
          final item = allItems[index];

          if (item is String) {
            // It's a folder
            return _buildKeepStyleFolderCard(vaultProvider, item);
          } else if (item is Note) {
            // It's a note
            return _buildKeepStyleNoteCard(item);
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildKeepStyleFolderCard(VaultProvider vaultProvider, String folderName) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.yellow[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          vaultProvider.navigateToSubfolder(folderName);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder,
                    size: 20,
                    color: Colors.orange[700],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTapDown: (details) {
                      _showFolderContextMenu(context, details.globalPosition, vaultProvider, folderName);
                    },
                    child: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                folderName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[800],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Folder',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeepStyleNoteCard(Note note) {
    // Random-ish color based on note title hash for variety
    final colorIndex = note.title.hashCode.abs() % _keepColors.length;
    final cardColor = _keepColors[colorIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the height needed for the text content
        final cardHeight = _calculateNoteCardHeight(note, context, constraints.maxWidth);
        
        return Container(
          height: cardHeight,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => NoteEditorScreen(note: note),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with title and menu
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          note.title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTapDown: (details) {
                          _showNoteContextMenu(context, details.globalPosition, note);
                        },
                        child: Icon(
                          Icons.more_vert,
                          size: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Content preview
                  Expanded(
                    child: Text(
                      note.content,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                        height: 1.3,
                      ),
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Footer with timestamp
                  if (cardHeight > 140) ...[
                    const SizedBox(height: 8),
                    Text(
                      _formatDate(note.modifiedAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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
        content: Text(
          'Are you sure you want to delete "$folderName" and all its contents?',
        ),
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

  double _calculateNoteCardHeight(Note note, BuildContext context, double cardWidth) {
    // Create a TextPainter to measure the actual text height
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w500,
      color: Colors.grey[800],
    ) ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    
    final contentStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.grey[700],
      height: 1.3,
    ) ?? const TextStyle(fontSize: 12, height: 1.3);

    final timestampStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.grey[600],
      fontSize: 11,
    ) ?? const TextStyle(fontSize: 11);

    // Calculate available width for text (accounting for padding and menu icon)
    const horizontalPadding = 24.0; // 12px padding on each side
    const menuIconWidth = 18.0 + 8.0; // icon width + some spacing
    final availableWidth = cardWidth - horizontalPadding - menuIconWidth;

    // Measure title height (max 2 lines)
    final titlePainter = TextPainter(
      text: TextSpan(text: note.title, style: titleStyle),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    );
    titlePainter.layout(maxWidth: availableWidth);
    final titleHeight = titlePainter.size.height;

    // Calculate how many complete lines of content can fit
    final singleLineContentPainter = TextPainter(
      text: TextSpan(text: 'A', style: contentStyle),
      textDirection: TextDirection.ltr,
    );
    singleLineContentPainter.layout();
    final lineHeight = singleLineContentPainter.size.height;

    // Measure full content to determine how many lines it would need
    final fullContentPainter = TextPainter(
      text: TextSpan(text: note.content, style: contentStyle),
      textDirection: TextDirection.ltr,
    );
    fullContentPainter.layout(maxWidth: availableWidth);
    final totalContentLines = (fullContentPainter.size.height / lineHeight).ceil();

    // Calculate available space for content within the 250px limit
    const verticalPadding = 24.0; // 12px top + 12px bottom
    const titleToContentSpacing = 8.0;
    const contentToTimestampSpacing = 8.0;
    const timestampHeight = 15.0; // Approximate height for timestamp
    
    final maxContentHeight = 250.0 - verticalPadding - titleHeight - titleToContentSpacing - contentToTimestampSpacing - timestampHeight;
    final maxContentLines = (maxContentHeight / lineHeight).floor();
    
    // Determine actual lines to show (complete lines only)
    final actualContentLines = totalContentLines.clamp(1, maxContentLines);
    final actualContentHeight = actualContentLines * lineHeight;
    
    // Calculate final height
    final finalHeight = verticalPadding + titleHeight + titleToContentSpacing + actualContentHeight + contentToTimestampSpacing + timestampHeight;
    
    // Clamp the height between minimum and maximum
    return finalHeight.clamp(80.0, 250.0);
  }

  void _showFolderContextMenu(BuildContext context, Offset position, VaultProvider vaultProvider, String folderName) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red[600]),
              const SizedBox(width: 8),
              const Text('Delete'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _showDeleteFolderDialog(vaultProvider, folderName);
      }
    });
  }

  void _showNoteContextMenu(BuildContext context, Offset position, Note note) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18, color: Colors.blue[600]),
              const SizedBox(width: 8),
              const Text('Edit'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red[600]),
              const SizedBox(width: 8),
              const Text('Delete'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'edit') {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => NoteEditorScreen(note: note),
          ),
        );
      } else if (value == 'delete') {
        _showDeleteNoteDialog(note);
      }
    });
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
