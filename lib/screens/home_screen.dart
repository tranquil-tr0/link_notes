import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notes_provider.dart';
import '../models/note.dart';
import '../widgets/folder_tree_widget.dart';
import 'note_editor_screen.dart';

/// HomeScreen serves as the main interface for the notes app
/// 
/// Features:
/// - Split layout with folder tree (left) and notes grid (right)
/// - AppBar with search functionality and vault statistics
/// - Breadcrumb navigation showing current folder path
/// - Floating action buttons for creating notes and folders
/// - Loading states and error handling
/// - Responsive design for different screen sizes
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    
    // Initialize the vault when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notesProvider = context.read<NotesProvider>();
      if (!notesProvider.isVaultInitialized) {
        notesProvider.loadVault();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<NotesProvider>(
          builder: (context, notesProvider, child) {
            if (notesProvider.isInitializing) {
              return _buildInitializingScreen();
            }

            if (notesProvider.error != null) {
              return _buildErrorScreen(notesProvider);
            }

            if (!notesProvider.isVaultInitialized) {
              return _buildWelcomeScreen(notesProvider);
            }

            return _buildMainScreen(notesProvider);
          },
        ),
      ),
      floatingActionButton: Consumer<NotesProvider>(
        builder: (context, notesProvider, child) {
          if (!notesProvider.isVaultInitialized || notesProvider.isSearching) {
            return const SizedBox.shrink();
          }
          return _buildFloatingActionButtons(notesProvider);
        },
      ),
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

  Widget _buildErrorScreen(NotesProvider notesProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Vault',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              notesProvider.error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => notesProvider.loadVault(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen(NotesProvider notesProvider) {
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
              onPressed: () => notesProvider.loadVault(),
              icon: const Icon(Icons.folder_open),
              label: const Text('Initialize Vault'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainScreen(NotesProvider notesProvider) {
    return Column(
      children: [
        _buildAppBar(notesProvider),
        if (notesProvider.isSearching) _buildSearchResultsOverlay(notesProvider)
        else Expanded(child: _buildMainContent(notesProvider)),
      ],
    );
  }

  Widget _buildAppBar(NotesProvider notesProvider) {
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
              Text(
                'My Vault',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              _buildVaultStats(notesProvider),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () => notesProvider.refreshCurrentFolder(),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
              IconButton(
                onPressed: () {
                  // TODO: Open settings
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
                child: _buildSearchField(notesProvider),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _buildBreadcrumbs(notesProvider),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVaultStats(NotesProvider notesProvider) {
    final totalNotes = notesProvider.rootFolder?.totalNoteCount ?? 0;
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
  }

  Widget _buildSearchField(NotesProvider notesProvider) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search notes...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: notesProvider.isSearching
            ? IconButton(
                onPressed: () {
                  _searchController.clear();
                  notesProvider.clearSearch();
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
          notesProvider.searchNotes(query);
        } else {
          notesProvider.clearSearch();
        }
      },
      onTap: () {},
      onSubmitted: (_) {},
    );
  }

  Widget _buildBreadcrumbs(NotesProvider notesProvider) {
    if (notesProvider.breadcrumbs.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < notesProvider.breadcrumbs.length; i++) ...[
            InkWell(
              onTap: () => notesProvider.loadFolder(notesProvider.breadcrumbs[i]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: i == notesProvider.breadcrumbs.length - 1
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      i == 0 ? Icons.home : Icons.folder,
                      size: 16,
                      color: i == notesProvider.breadcrumbs.length - 1
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      notesProvider.breadcrumbs[i].name,
                      style: TextStyle(
                        color: i == notesProvider.breadcrumbs.length - 1
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: i == notesProvider.breadcrumbs.length - 1
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < notesProvider.breadcrumbs.length - 1)
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

  Widget _buildSearchResultsOverlay(NotesProvider notesProvider) {
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
                    'Search Results for "${notesProvider.searchQuery}"',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${notesProvider.searchResults.length} results',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: notesProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : notesProvider.searchResults.isEmpty
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
                          itemCount: notesProvider.searchResults.length,
                          itemBuilder: (context, index) {
                            final note = notesProvider.searchResults[index];
                            return _buildNoteListItem(note, notesProvider);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(NotesProvider notesProvider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isSmallScreen = screenWidth < 768;
        
        // Auto-collapse sidebar on small screens
        if (isSmallScreen && !_isSidebarCollapsed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _isSidebarCollapsed = true;
              _sidebarAnimationController.reverse();
            });
          });
        }
        
        if (_isSidebarCollapsed) {
          // Collapsed sidebar: show only the notes panel
          return _buildNotesPanel(notesProvider);
        } else {
          // Expanded sidebar: show both panels side by side
          return Row(
            children: [
              // Left panel: Folder tree with animation
              AnimatedBuilder(
                animation: _sidebarAnimation,
                builder: (context, child) {
                  return SizedBox(
                    width: 280 * _sidebarAnimation.value,
                    child: Opacity(
                      opacity: _sidebarAnimation.value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            right: BorderSide(
                              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                        ),
                        child: _sidebarAnimation.value > 0.3
                            ? _buildSidebarContent(notesProvider)
                            : const SizedBox(),
                      ),
                    ),
                  );
                },
              ),
              // Right panel: Notes grid
              Expanded(
                child: _buildNotesPanel(notesProvider),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildSidebarContent(NotesProvider notesProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Folders',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // Close button for small screens
              if (MediaQuery.of(context).size.width < 768)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isSidebarCollapsed = true;
                      _sidebarAnimationController.reverse();
                    });
                  },
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Close sidebar',
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FolderTreeWidget(
            rootFolder: notesProvider.rootFolder,
            currentFolder: notesProvider.currentFolder,
            onFolderSelected: (folder) {
              notesProvider.loadFolder(folder);
              // Auto-close sidebar on small screens after selection
              if (MediaQuery.of(context).size.width < 768) {
                setState(() {
                  _isSidebarCollapsed = true;
                  _sidebarAnimationController.reverse();
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNotesPanel(NotesProvider notesProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.note, size: 20),
              const SizedBox(width: 8),
              Text(
                'Notes in ${notesProvider.currentFolder?.name ?? "Vault"}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text(
                '${notesProvider.notes.length} notes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: notesProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : notesProvider.notes.isEmpty
                    ? _buildEmptyNotesState(notesProvider)
                    : _buildNotesGrid(notesProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyNotesState(NotesProvider notesProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.note_add, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No notes in this folder',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first note to get started',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showCreateNoteDialog(notesProvider),
            icon: const Icon(Icons.add),
            label: const Text('Create Note'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesGrid(NotesProvider notesProvider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate grid columns based on screen width
        final screenWidth = constraints.maxWidth;
        final cardWidth = 280.0;
        final crossAxisCount = (screenWidth / cardWidth).floor().clamp(1, 4);
        
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.2,
          ),
          itemCount: notesProvider.notes.length,
          itemBuilder: (context, index) {
            final note = notesProvider.notes[index];
            return _buildNoteCard(note, notesProvider);
          },
        );
      },
    );
  }

  Widget _buildNoteCard(Note note, NotesProvider notesProvider) {
    final isSelected = notesProvider.selectedNote?.id == note.id;
    
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      child: InkWell(
        onTap: () => notesProvider.selectNote(note),
        onDoubleTap: () {
          _navigateToNoteEditor(note);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Note title
              Text(
                note.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isSelected 
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Note preview
              Expanded(
                child: Text(
                  note.content,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isSelected 
                        ? Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7)
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              // Note metadata
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: isSelected 
                        ? Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.5)
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatDate(note.modifiedAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isSelected 
                            ? Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.5)
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 10,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 16,
                      color: isSelected 
                          ? Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.5)
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                    onSelected: (action) => _handleNoteAction(action, note, notesProvider),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoteListItem(Note note, NotesProvider notesProvider) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.note),
        title: Text(note.title),
        subtitle: Text(
          note.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _formatDate(note.modifiedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () => notesProvider.selectNote(note),
        onLongPress: () {
          // TODO: Show note options
        },
      ),
    );
  }

  Widget _buildFloatingActionButtons(NotesProvider notesProvider) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          onPressed: () => _showCreateFolderDialog(notesProvider),
          heroTag: "folder",
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
          child: const Icon(Icons.folder_open),
        ),
        const SizedBox(height: 16),
        FloatingActionButton(
          onPressed: () => _createNewNote(),
          heroTag: "note",
          child: const Icon(Icons.add),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _handleNoteAction(String action, Note note, NotesProvider notesProvider) {
    switch (action) {
      case 'edit':
        _navigateToNoteEditor(note);
        break;
      case 'delete':
        _showDeleteNoteDialog(note, notesProvider);
        break;
    }
  }

  void _showCreateNoteDialog(NotesProvider notesProvider) {
    final titleController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Note'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Note Title',
            hintText: 'Enter note title...',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty) {
                final title = titleController.text;
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => NoteEditorScreen(
                      initialTitle: title,
                      initialContent: '',
                    ),
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(NotesProvider notesProvider) {
    final nameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'Enter folder name...',
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
              if (nameController.text.isNotEmpty) {
                await notesProvider.createFolder(nameController.text);
                if (mounted) Navigator.of(context).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteNoteDialog(Note note, NotesProvider notesProvider) {
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
              await notesProvider.deleteNote(note);
              if (mounted) Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _navigateToNoteEditor(Note? note) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note),
      ),
    );
    
    // Refresh the current folder after returning from editor
    if (result != null && mounted) {
      final notesProvider = context.read<NotesProvider>();
      notesProvider.refreshCurrentFolder();
    }
  }

  void _createNewNote() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const NoteEditorScreen(),
      ),
    );
    
    // Refresh the current folder after returning from editor
    if (result != null && mounted) {
      final notesProvider = context.read<NotesProvider>();
      notesProvider.refreshCurrentFolder();
    }
  }
}