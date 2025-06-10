import 'package:flutter/material.dart';
import '../models/note.dart';

/// Basic file editor with minimal features - just title display and content editing
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
  late TextEditingController _contentController;
  late FocusNode _contentFocusNode;
  late String _title;

  @override
  void initState() {
    super.initState();

    // Initialize title
    _title = widget.note?.title ?? widget.initialTitle ?? 'Untitled';

    // Initialize content controller
    final initialContent = widget.note?.content ?? widget.initialContent ?? '';
    _contentController = TextEditingController(text: initialContent);
    _contentFocusNode = FocusNode();

    // Focus on content
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: TextField(
        controller: _contentController,
        focusNode: _contentFocusNode,
        decoration: const InputDecoration(
          hintText: 'Start writing...',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(height: 1.5, fontFamily: 'monospace'),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
      ),
    );
  }
}
