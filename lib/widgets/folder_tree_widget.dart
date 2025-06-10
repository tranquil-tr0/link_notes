import 'package:flutter/material.dart';
import '../models/folder.dart';

/// A widget that displays a hierarchical tree of folders
/// 
/// Features:
/// - Expandable folder tree with indentation
/// - Current folder highlighting
/// - Folder selection callbacks
/// - Loading states for folder operations
/// - Material Design styling
class FolderTreeWidget extends StatefulWidget {
  final Folder? rootFolder;
  final Folder? currentFolder;
  final Function(Folder) onFolderSelected;

  const FolderTreeWidget({
    super.key,
    required this.rootFolder,
    this.currentFolder,
    required this.onFolderSelected,
  });

  @override
  State<FolderTreeWidget> createState() => _FolderTreeWidgetState();
}

class _FolderTreeWidgetState extends State<FolderTreeWidget> {
  final Set<String> _expandedFolders = <String>{};

  @override
  void initState() {
    super.initState();
    // Auto-expand the path to current folder
    if (widget.currentFolder != null && widget.rootFolder != null) {
      _expandPathToFolder(widget.currentFolder!);
    }
  }

  @override
  void didUpdateWidget(FolderTreeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update expanded state when current folder changes
    if (widget.currentFolder != oldWidget.currentFolder &&
        widget.currentFolder != null) {
      _expandPathToFolder(widget.currentFolder!);
    }
  }

  /// Expands all folders in the path to the given folder
  void _expandPathToFolder(Folder folder) {
    Folder? current = folder;
    while (current != null) {
      _expandedFolders.add(current.path);
      current = current.parent;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rootFolder == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No folders available'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        _buildFolderNode(widget.rootFolder!, 0),
      ],
    );
  }

  Widget _buildFolderNode(Folder folder, int depth) {
    final isExpanded = _expandedFolders.contains(folder.path);
    final isCurrentFolder = widget.currentFolder?.path == folder.path;
    final hasSubfolders = folder.subfolders.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFolderItem(folder, depth, isExpanded, isCurrentFolder, hasSubfolders),
        if (isExpanded && hasSubfolders)
          ...folder.subfolders.map(
            (subfolder) => _buildFolderNode(subfolder, depth + 1),
          ),
      ],
    );
  }

  Widget _buildFolderItem(
    Folder folder,
    int depth,
    bool isExpanded,
    bool isCurrentFolder,
    bool hasSubfolders,
  ) {
    return Container(
      margin: EdgeInsets.only(left: depth * 16.0),
      child: Material(
        color: isCurrentFolder
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => widget.onFolderSelected(folder),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Expand/collapse button or spacing
                SizedBox(
                  width: 24,
                  child: hasSubfolders
                      ? IconButton(
                          onPressed: () => _toggleExpanded(folder.path),
                          icon: Icon(
                            isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 16,
                            color: isCurrentFolder
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 4),
                // Folder icon
                Icon(
                  hasSubfolders
                      ? (isExpanded ? Icons.folder_open : Icons.folder)
                      : Icons.folder_outlined,
                  size: 16,
                  color: isCurrentFolder
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                // Folder name
                Expanded(
                  child: Text(
                    folder.displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isCurrentFolder
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: isCurrentFolder ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Note count badge
                if (folder.notes.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrentFolder
                          ? Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${folder.notes.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isCurrentFolder
                            ? Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                            : Theme.of(context).colorScheme.primary,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleExpanded(String folderPath) {
    setState(() {
      if (_expandedFolders.contains(folderPath)) {
        _expandedFolders.remove(folderPath);
      } else {
        _expandedFolders.add(folderPath);
      }
    });
  }
}

/// A simplified folder tree item for use in dialogs or smaller spaces
class FolderTreeItem extends StatelessWidget {
  final Folder folder;
  final bool isSelected;
  final VoidCallback? onTap;
  final int depth;

  const FolderTreeItem({
    super.key,
    required this.folder,
    this.isSelected = false,
    this.onTap,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: depth * 16.0),
      child: ListTile(
        selected: isSelected,
        leading: Icon(
          folder.subfolders.isNotEmpty ? Icons.folder : Icons.folder_outlined,
          size: 20,
        ),
        title: Text(
          folder.displayName,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        trailing: folder.notes.isNotEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${folder.notes.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              )
            : null,
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }
}