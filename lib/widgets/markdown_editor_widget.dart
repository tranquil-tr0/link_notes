import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import '../services/markdown_conversion_service.dart';
import '../models/note.dart';

class MarkdownEditorWidget extends StatefulWidget {
  final Note? note;
  final String? initialContent;
  final Function(Delta delta)? onContentChanged;
  final bool readOnly;
  
  const MarkdownEditorWidget({
    super.key,
    this.note,
    this.initialContent,
    this.onContentChanged,
    this.readOnly = false,
  });

  @override
  State<MarkdownEditorWidget> createState() => _MarkdownEditorWidgetState();
}

class _MarkdownEditorWidgetState extends State<MarkdownEditorWidget> {
  late QuillController _controller;
  late FocusNode _focusNode;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    
    // Initialize from Note or markdown content
    final initialMarkdown = widget.note?.content ?? widget.initialContent ?? '';
    final initialDelta = widget.note?.deltaContent ?? 
                        MarkdownConversionService.markdownToDelta(initialMarkdown);
    
    _controller = QuillController(
      document: Document.fromDelta(initialDelta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    
    // Listen for changes
    _controller.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    if (widget.onContentChanged != null) {
      widget.onContentChanged!(_controller.document.toDelta());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Simple toolbar for essential formatting
        if (!widget.readOnly) _buildToolbar(),
        
        // Main editor
        Expanded(
          child: QuillEditor.basic(
            controller: _controller,
            focusNode: _focusNode,
            scrollController: _scrollController,
            config: QuillEditorConfig(
              placeholder: 'Start writing in markdown...',
              expands: false,
              autoFocus: false,
              padding: const EdgeInsets.all(16),
              characterShortcutEvents: _buildMarkdownShortcuts(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: QuillSimpleToolbar(
        controller: _controller,
        config: QuillSimpleToolbarConfig(
          multiRowsDisplay: false,
          showDividers: true,
          showFontFamily: false,
          showFontSize: false,
          showBoldButton: true,
          showItalicButton: true,
          showSmallButton: false,
          showUnderLineButton: false,
          showStrikeThrough: true,
          showInlineCode: true,
          showColorButton: false,
          showBackgroundColorButton: false,
          showClearFormat: false,
          showAlignmentButtons: false,
          showLeftAlignment: false,
          showCenterAlignment: false,
          showRightAlignment: false,
          showJustifyAlignment: false,
          showHeaderStyle: true,
          showListNumbers: true,
          showListBullets: true,
          showListCheck: false,
          showCodeBlock: true,
          showQuote: true,
          showIndent: false,
          showLink: false,
          showUndo: true,
          showRedo: true,
          showDirection: false,
        ),
      ),
    );
  }


  List<CharacterShortcutEvent> _buildMarkdownShortcuts() {
    return [
      // Headers: # text → styled header (live conversion)
      CharacterShortcutEvent(
        key: 'Header markdown',
        character: ' ',
        handler: (controller) => _handleHeaderMarkdown(controller),
      ),
      
      // Lists: - text → bullet list (live conversion)
      CharacterShortcutEvent(
        key: 'List markdown',
        character: ' ',
        handler: (controller) => _handleListMarkdown(controller),
      ),
      
      // Blockquotes: > text → blockquote (live conversion)
      CharacterShortcutEvent(
        key: 'Blockquote markdown',
        character: ' ',
        handler: (controller) => _handleBlockquoteMarkdown(controller),
      ),
    ];
  }

  bool _handleHeaderMarkdown(QuillController controller) {
    final selection = controller.selection;
    final text = controller.document.toPlainText();
    final line = _getCurrentLine(text, selection.start);
    
    final headerMatch = RegExp(r'^(#{1,6})\s').firstMatch(line);
    if (headerMatch != null) {
      final level = headerMatch.group(1)!.length;
      final headerText = line.substring(headerMatch.end);
      
      // Apply header formatting
      _replaceLineWithAttribute(
        controller,
        headerText,
        HeaderAttribute(level: level),
      );
      return true;
    }
    return false;
  }

  bool _handleListMarkdown(QuillController controller) {
    final selection = controller.selection;
    final text = controller.document.toPlainText();
    final line = _getCurrentLine(text, selection.start);
    
    if (RegExp(r'^[-*]\s').hasMatch(line)) {
      // Bullet list
      final listText = line.substring(2);
      _replaceLineWithAttribute(controller, listText, Attribute.ul);
      return true;
    } else if (RegExp(r'^\d+\.\s').hasMatch(line)) {
      // Ordered list
      final listText = line.replaceFirst(RegExp(r'^\d+\.\s'), '');
      _replaceLineWithAttribute(controller, listText, Attribute.ol);
      return true;
    }
    return false;
  }

  bool _handleBlockquoteMarkdown(QuillController controller) {
    final selection = controller.selection;
    final text = controller.document.toPlainText();
    final line = _getCurrentLine(text, selection.start);
    
    if (line.startsWith('> ')) {
      final quoteText = line.substring(2);
      _replaceLineWithAttribute(controller, quoteText, Attribute.blockQuote);
      return true;
    }
    return false;
  }

  String _getCurrentLine(String text, int position) {
    final lines = text.split('\n');
    int currentPos = 0;
    for (final line in lines) {
      if (currentPos + line.length >= position) {
        return line;
      }
      currentPos += line.length + 1; // +1 for newline
    }
    return '';
  }

  void _replaceLineWithAttribute(
    QuillController controller,
    String newText,
    Attribute attribute,
  ) {
    // Get current line position
    final selection = controller.selection;
    final text = controller.document.toPlainText();
    final lineStart = text.lastIndexOf('\n', selection.start - 1) + 1;
    final lineEnd = text.indexOf('\n', selection.start);
    final actualLineEnd = lineEnd == -1 ? text.length : lineEnd;
    
    // Create delta to replace the line
    final delta = Delta()
      ..retain(lineStart)
      ..delete(actualLineEnd - lineStart)
      ..insert(newText, {attribute.key: attribute.value});
    
    // Apply the changes
    controller.compose(
      delta,
      TextSelection.collapsed(offset: lineStart + newText.length),
      ChangeSource.local,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onContentChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}