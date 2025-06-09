import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';

/// NoteEditorScreen provides a full-featured markdown editor for creating and editing notes
/// 
/// Features:
/// - Plain text editor with markdown support
/// - Real-time preview toggle between edit and preview modes
/// - Auto-save functionality with proper debouncing
/// - AppBar with save, delete, and navigation actions
/// - Markdown toolbar for common formatting operations
/// - Word count and character count display
/// - Integration with NotesProvider for note CRUD operations
class NoteEditorScreen extends StatefulWidget {
  final Note? note; // null for new notes, existing note for editing
  final String? initialTitle;
  final String? initialContent;

  const NoteEditorScreen({
    super.key,
    this.note,
    this.initialTitle,
    this.initialContent,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late FocusNode _contentFocusNode;
  
  bool _isPreviewMode = false;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  Timer? _autoSaveTimer;
  
  String? _originalTitle;
  String? _originalContent;

  @override
  void initState() {
    super.initState();
    
    // Initialize controllers with existing note data or provided initial values
    _originalTitle = widget.note?.title ?? widget.initialTitle ?? '';
    _originalContent = widget.note?.content ?? widget.initialContent ?? '';
    
    _titleController = TextEditingController(text: _originalTitle);
    _contentController = TextEditingController(text: _originalContent);
    _contentFocusNode = FocusNode();
    
    // Listen for changes to track unsaved changes
    _titleController.addListener(_onTextChanged);
    _contentController.addListener(_onTextChanged);
    
    // Focus on content if this is a new note
    if (widget.note == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _contentFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Check if there are unsaved changes
    final hasChanges = _titleController.text != _originalTitle ||
                      _contentController.text != _originalContent;
    
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
    
    // Restart auto-save timer
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), () {
      if (_hasUnsavedChanges && !_isSaving) {
        _saveNote(autoSave: true);
      }
    });
  }

  Future<void> _saveNote({bool autoSave = false}) async {
    if (_isSaving) return;
    
    final title = _titleController.text.trim();
    final content = _contentController.text;
    
    // Don't save if title is empty
    if (title.isEmpty) {
      if (!autoSave) {
        _showSnackBar('Please enter a title for the note', isError: true);
      }
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      final notesProvider = context.read<NotesProvider>();
      Note? savedNote;
      
      if (widget.note == null) {
        // Creating new note
        savedNote = await notesProvider.createNote(
          title: title,
          content: content,
        );
      } else {
        // Updating existing note
        savedNote = await notesProvider.updateNote(
          widget.note!,
          newTitle: title,
          newContent: content,
        );
      }
      
      if (savedNote != null) {
        _originalTitle = title;
        _originalContent = content;
        _hasUnsavedChanges = false;
        
        if (!autoSave) {
          _showSnackBar('Note saved successfully');
        }
      } else {
        if (!autoSave) {
          _showSnackBar('Failed to save note', isError: true);
        }
      }
    } catch (e) {
      if (!autoSave) {
        _showSnackBar('Error saving note: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteNote() async {
    if (widget.note == null) return;
    
    final confirmed = await _showDeleteConfirmDialog();
    if (!confirmed) return;
    
    try {
      final notesProvider = context.read<NotesProvider>();
      final success = await notesProvider.deleteNote(widget.note!);
      
      if (success && mounted) {
        Navigator.of(context).pop();
        _showSnackBar('Note deleted successfully');
      } else {
        _showSnackBar('Failed to delete note', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error deleting note: $e', isError: true);
    }
  }

  Future<bool> _showDeleteConfirmDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${_titleController.text}"?'),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('Pressed Delete Confirm Dialog: Cancel Button');
              Navigator.of(context).pop(false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              debugPrint('Pressed Delete Confirm Dialog: Delete Button');
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Do you want to save before leaving?'),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('Pressed Unsaved Changes Dialog: Discard Button');
              Navigator.of(context).pop(true);
            },
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () {
              debugPrint('Pressed Unsaved Changes Dialog: Cancel Button');
              Navigator.of(context).pop(false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              debugPrint('Pressed Unsaved Changes Dialog: Save Button');
              await _saveNote();
              if (mounted) Navigator.of(context).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  void _togglePreviewMode() {
    setState(() {
      _isPreviewMode = !_isPreviewMode;
    });
  }

  void _insertMarkdown(String prefix, {String? suffix, bool wrapSelection = false}) {
    final selection = _contentController.selection;
    final text = _contentController.text;
    
    if (selection.isValid) {
      String newText;
      String selectedText = selection.textInside(text);
      
      if (wrapSelection && selectedText.isNotEmpty) {
        newText = text.replaceRange(
          selection.start,
          selection.end,
          '$prefix$selectedText${suffix ?? prefix}',
        );
      } else {
        newText = text.replaceRange(
          selection.start,
          selection.end,
          '$prefix${suffix ?? ''}',
        );
      }
      
      _contentController.text = newText;
      
      // Position cursor after inserted text
      final newCursorPosition = selection.start + prefix.length + 
          (wrapSelection && selectedText.isNotEmpty ? selectedText.length + (suffix?.length ?? prefix.length) : 0);
      _contentController.selection = TextSelection.collapsed(
        offset: newCursorPosition,
      );
    }
    
    _contentFocusNode.requestFocus();
  }

  Widget _buildMarkdownToolbar() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _buildToolbarButton(
              icon: Icons.format_bold,
              tooltip: 'Bold',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Bold');
                _insertMarkdown('**', wrapSelection: true);
              },
            ),
            _buildToolbarButton(
              icon: Icons.format_italic,
              tooltip: 'Italic',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Italic');
                _insertMarkdown('*', wrapSelection: true);
              },
            ),
            const VerticalDivider(),
            _buildToolbarButton(
              icon: Icons.title,
              tooltip: 'Header 1',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Header 1');
                _insertMarkdown('# ');
              },
            ),
            _buildToolbarButton(
              icon: Icons.format_size,
              tooltip: 'Header 2',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Header 2');
                _insertMarkdown('## ');
              },
            ),
            const VerticalDivider(),
            _buildToolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Bullet List',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Bullet List');
                _insertMarkdown('- ');
              },
            ),
            _buildToolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: 'Numbered List',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Numbered List');
                _insertMarkdown('1. ');
              },
            ),
            const VerticalDivider(),
            _buildToolbarButton(
              icon: Icons.link,
              tooltip: 'Link',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Link');
                _insertMarkdown('[', suffix: '](url)');
              },
            ),
            _buildToolbarButton(
              icon: Icons.code,
              tooltip: 'Code',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Code');
                _insertMarkdown('`', wrapSelection: true);
              },
            ),
            _buildToolbarButton(
              icon: Icons.format_quote,
              tooltip: 'Quote',
              onPressed: () {
                debugPrint('Pressed Markdown Toolbar: Quote');
                _insertMarkdown('> ');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  Widget _buildStatusBar() {
    final content = _contentController.text;
    final wordCount = content.isEmpty ? 0 : content.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    final charCount = content.length;
    
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_hasUnsavedChanges) ...[
            Icon(
              Icons.circle,
              size: 8,
              color: Colors.orange,
            ),
            const SizedBox(width: 4),
            Text(
              'Unsaved changes',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
          ],
          if (_isSaving) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Saving...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 16),
          ],
          const Spacer(),
          Text(
            '$wordCount words • $charCount characters',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
          actions: [
            if (_isPreviewMode)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit Mode',
                onPressed: () {
                  debugPrint('Pressed Edit Mode Button');
                  _togglePreviewMode();
                },
              )
            else
              IconButton(
                icon: const Icon(Icons.preview),
                tooltip: 'Preview Mode',
                onPressed: () {
                  debugPrint('Pressed Preview Mode Button');
                  _togglePreviewMode();
                },
              ),
            const SizedBox(width: 8),
            if (widget.note != null)
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Delete Note',
                onPressed: () {
                  debugPrint('Pressed Delete Note Button');
                  _deleteNote();
                },
              ),
            IconButton(
              icon: Icon(_isSaving ? Icons.hourglass_empty : Icons.save),
              tooltip: 'Save Note',
              onPressed: _isSaving ? null : () {
                debugPrint('Pressed Save Note Button');
                _saveNote();
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Title field
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                ),
                child: TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    hintText: 'Note title...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _contentFocusNode.requestFocus(),
                ),
              ),
              
              // Markdown toolbar (only in edit mode)
              if (!_isPreviewMode) _buildMarkdownToolbar(),
              
              // Content area
              Expanded(
                child: _isPreviewMode ? _buildPreviewMode() : _buildEditMode(),
              ),
              
              // Status bar
              _buildStatusBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditMode() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _contentController,
        focusNode: _contentFocusNode,
        decoration: const InputDecoration(
          hintText: 'Start writing your note...',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          height: 1.5,
          fontFamily: 'monospace',
        ),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
      ),
    );
  }

  Widget _buildPreviewMode() {
    final content = _contentController.text;
    
    if (content.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.preview, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Nothing to preview yet'),
            SizedBox(height: 8),
            Text('Switch to edit mode to start writing'),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          content,
          style: const TextStyle(
            fontSize: 16,
            height: 1.5,
            fontFamily: 'serif',
          ),
        ),
      ),
    );
  }
}