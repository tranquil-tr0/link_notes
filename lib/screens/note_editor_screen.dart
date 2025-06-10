import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../providers/vault_provider.dart';
import '../widgets/markdown_editor_widget.dart';
import '../services/markdown_conversion_service.dart';

/// Enhanced markdown editor with WYSIWYG editing and auto-save functionality
class NoteEditorScreen extends StatefulWidget {
  final Note? note;
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
  late String _title;
  late Note _currentNote;
  Delta? _currentDelta;
  Delta? _lastSavedDelta;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    
    // Initialize title
    _title = widget.note?.title ?? widget.initialTitle ?? 'Untitled';
    
    // Initialize or create note
    if (widget.note != null) {
      _currentNote = widget.note!;
      _lastSavedDelta = _currentNote.deltaContent;
    } else {
      // Create new note
      final content = widget.initialContent ?? '';
      _currentNote = Note(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _title,
        content: content,
        filePath: '', // Will be set when saving
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      _lastSavedDelta = MarkdownConversionService.markdownToDelta(content);
    }
  }

  void _onContentChanged(Delta delta) {
    setState(() {
      _currentDelta = delta;
      _hasUnsavedChanges = _lastSavedDelta == null || !_deltasEqual(_lastSavedDelta!, delta);
      _saveError = null; // Clear any previous save errors
    });
  }

  bool _deltasEqual(Delta a, Delta b) {
    return a.toJson().toString() == b.toJson().toString();
  }

  Future<void> _saveNote() async {
    if (_currentDelta == null || _isSaving) return;
    
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      // Update note with current Delta content
      final updatedNote = _currentNote.copyWith(
        modifiedAt: DateTime.now(),
      );
      
      // Save using Delta conversion
      await updatedNote.toFileFromDelta(_currentDelta!);
      
      // Update state
      _lastSavedDelta = _currentDelta;
      _currentNote = updatedNote;
      
      setState(() {
        _hasUnsavedChanges = false;
      });
      
      // Notify VaultProvider about the change
      if (mounted) {
        final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
        vaultProvider.refresh();
      }
      
      if (kDebugMode) {
        debugPrint('Note saved successfully: ${_currentNote.title}');
      }
    } catch (e) {
      setState(() {
        _saveError = 'Failed to save: $e';
      });
      
      if (kDebugMode) {
        debugPrint('Save error: $e');
      }
      
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<bool> _onWillPop() async {
    // Auto-save when navigating away if there are unsaved changes
    if (_hasUnsavedChanges && _currentDelta != null) {
      await _saveNote();
    }
    return true;
  }

  void _showPreviewDialog() {
    if (_currentDelta == null) return;
    
    final markdown = MarkdownConversionService.deltaToMarkdown(_currentDelta!);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Markdown Preview',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    markdown,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _onWillPop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Expanded(child: Text(_title)),
              if (_hasUnsavedChanges)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Unsaved',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_hasUnsavedChanges)
              IconButton(
                onPressed: _saveNote,
                icon: const Icon(Icons.save),
                tooltip: 'Save note',
              ),
            
            // Debug preview button (only in debug mode)
            if (kDebugMode)
              IconButton(
                onPressed: _showPreviewDialog,
                icon: const Icon(Icons.preview),
                tooltip: 'Preview markdown',
              ),
          ],
        ),
        body: Column(
          children: [
            // Error banner
            if (_saveError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                child: Text(
                  _saveError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            
            // Editor
            Expanded(
              child: MarkdownEditorWidget(
                note: _currentNote,
                onContentChanged: _onContentChanged,
                readOnly: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
