import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

class MarkdownConversionService {
  static late final md.Document _markdownDocument;
  static late final MarkdownToDelta _mdToDelta;
  static late final DeltaToMarkdown _deltaToMd;
  
  static void initialize() {
    // Configure with GitHub Flavored Markdown + custom extensions
    _markdownDocument = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: [
        // Add custom syntaxes like tables if needed
        const EmbeddableTableSyntax(),
      ],
    );
    
    _mdToDelta = MarkdownToDelta(
      markdownDocument: _markdownDocument,
      customElementToBlockAttribute: {
        'h4': (element) => [HeaderAttribute(level: 4)],
        'h5': (element) => [HeaderAttribute(level: 5)],
        'h6': (element) => [HeaderAttribute(level: 6)],
      },
    );
    
    _deltaToMd = DeltaToMarkdown();
  }
  
  /// Convert markdown string to Quill Delta for editor
  static Delta markdownToDelta(String markdown) {
    return _mdToDelta.convert(markdown);
  }
  
  /// Convert Quill Delta back to markdown for file storage
  static String deltaToMarkdown(Delta delta) {
    return _deltaToMd.convert(delta);
  }
  
  /// Validate conversion round-trip accuracy
  static bool validateConversion(String originalMarkdown) {
    final delta = markdownToDelta(originalMarkdown);
    final convertedBack = deltaToMarkdown(delta);
    return originalMarkdown.trim() == convertedBack.trim();
  }
}