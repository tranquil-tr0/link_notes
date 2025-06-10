import 'dart:io';
import 'package:flutter_quill/quill_delta.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import '../services/markdown_conversion_service.dart';
import '../utils/path_utils.dart';

class Note {
  final String id;
  final String title;
  final String content;
  final String filePath;
  final DateTime createdAt;
  final DateTime modifiedAt;
  
  /// Optional Delta cache for performance
  Delta? _cachedDelta;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.filePath,
    required this.createdAt,
    required this.modifiedAt,
  });

  /// Creates a Note instance from a file
  static Future<Note> fromFile(File file) async {
    if (!await file.exists()) {
      throw Exception('File does not exist: ${file.path}');
    }

    final content = await file.readAsString();
    final filePath = file.path;
    final fileName = file.path.split('/').last.replaceAll('.md', '');
    final stat = await file.stat();

    // Extract metadata from the beginning of the file if it exists
    String noteContent = content;
    String title = fileName;
    String id = fileName;
    DateTime? createdAt;
    DateTime? modifiedAt;

    // Check for YAML frontmatter
    if (content.startsWith('---\n')) {
      final endIndex = content.indexOf('\n---\n', 4);
      if (endIndex != -1) {
        final frontmatter = content.substring(4, endIndex);
        noteContent = content.substring(endIndex + 5);
        
        // Parse YAML-like metadata
        final lines = frontmatter.split('\n');
        for (final line in lines) {
          if (line.contains(':')) {
            final parts = line.split(':');
            final key = parts[0].trim();
            final value = parts.sublist(1).join(':').trim();
            
            switch (key) {
              case 'id':
                id = value;
                break;
              case 'title':
                title = value;
                break;
              case 'created_at':
                createdAt = DateTime.tryParse(value);
                break;
              case 'modified_at':
                modifiedAt = DateTime.tryParse(value);
                break;
            }
          }
        }
      }
    }

    final note = Note(
      id: id,
      title: title,
      content: noteContent.trim(),
      filePath: filePath,
      createdAt: createdAt ?? stat.changed,
      modifiedAt: modifiedAt ?? stat.modified,
    );
    
    // Pre-cache Delta for performance
    note._cachedDelta = MarkdownConversionService.markdownToDelta(note.content);
    
    return note;
  }

  /// Creates a Note instance from a SafDocumentFile
  static Note fromSafFile(SafDocumentFile safFile, String content) {
    final fileName = safFile.name.replaceAll('.md', '');
    
    // Extract metadata from the beginning of the file if it exists
    String noteContent = content;
    String title = fileName;
    String id = fileName;
    DateTime? createdAt;
    DateTime? modifiedAt;

    // Check for YAML frontmatter
    if (content.startsWith('---\n')) {
      final endIndex = content.indexOf('\n---\n', 4);
      if (endIndex != -1) {
        final frontmatter = content.substring(4, endIndex);
        noteContent = content.substring(endIndex + 5);
        
        // Parse YAML-like metadata
        final lines = frontmatter.split('\n');
        for (final line in lines) {
          if (line.contains(':')) {
            final parts = line.split(':');
            final key = parts[0].trim();
            final value = parts.sublist(1).join(':').trim();
            
            switch (key) {
              case 'id':
                id = value;
                break;
              case 'title':
                title = value;
                break;
              case 'created_at':
                createdAt = DateTime.tryParse(value);
                break;
              case 'modified_at':
                modifiedAt = DateTime.tryParse(value);
                break;
            }
          }
        }
      }
    }

    // Use current time if metadata is not available
    final now = DateTime.now();
    
    final note = Note(
      id: id,
      title: title,
      content: noteContent.trim(),
      filePath: safFile.uri, // Use URI as file path for SAF files
      createdAt: createdAt ?? now,
      modifiedAt: modifiedAt ?? now,
    );
    
    // Pre-cache Delta for performance
    note._cachedDelta = MarkdownConversionService.markdownToDelta(note.content);
    
    return note;
  }

  /// Saves the Note to a file
  Future<void> toFile() async {
    final file = File(filePath);
    
    // Create directory if it doesn't exist
    await file.parent.create(recursive: true);
    
    // Create frontmatter with metadata
    final frontmatter = '''---
id: $id
title: $title
created_at: ${createdAt.toIso8601String()}
modified_at: ${modifiedAt.toIso8601String()}
---

''';
    
    final fullContent = frontmatter + content;
    await file.writeAsString(fullContent);
  }

  /// Get Delta representation for editor (with caching)
  Delta get deltaContent {
    _cachedDelta ??= MarkdownConversionService.markdownToDelta(content);
    return _cachedDelta!;
  }

  /// Save Note with Delta → Markdown conversion
  Future<void> toFileFromDelta(Delta delta) async {
    // Convert Delta back to markdown
    final markdownContent = MarkdownConversionService.deltaToMarkdown(delta);
    
    // Update content and clear cache
    final updatedNote = copyWith(
      content: markdownContent,
      modifiedAt: DateTime.now(),
    );
    updatedNote._cachedDelta = null;
    
    // Save using existing file infrastructure
    await updatedNote.toFile();
  }

  /// Creates a copy of this Note with updated fields
  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? filePath,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    final note = Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
    
    // Clear cache if content changed
    if (content != null && content != this.content) {
      note._cachedDelta = null;
    } else {
      // Preserve cache if content unchanged
      note._cachedDelta = _cachedDelta;
    }
    
    return note;
  }

  /// Converts Note metadata to JSON (excludes content for efficiency)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }

  /// Creates a Note instance from JSON metadata
  factory Note.fromJson(Map<String, dynamic> json, String content) {
    return Note(
      id: json['id'],
      title: json['title'],
      content: content,
      filePath: json['filePath'],
      createdAt: DateTime.parse(json['createdAt']),
      modifiedAt: DateTime.parse(json['modifiedAt']),
    );
  }

  /// Gets the file name without extension
  String get fileName {
    if (PathUtils.isSafUri(filePath)) {
      // For SAF URIs, extract the name from the URI structure
      return PathUtils.extractFolderName(filePath).replaceAll('.md', '');
    } else {
      return filePath.split('/').last.replaceAll('.md', '');
    }
  }

  /// Gets the directory path
  String get directoryPath {
    if (PathUtils.isSafUri(filePath)) {
      // For SAF URIs, return a meaningful parent path representation
      return PathUtils.safUriToInternalPath(filePath.substring(0, filePath.lastIndexOf('/')));
    } else {
      return filePath.substring(0, filePath.lastIndexOf('/'));
    }
  }

  /// Gets a display-friendly file path for UI purposes
  String get displayPath => PathUtils.safUriToDisplayPath(filePath);

  /// Gets a display-friendly directory path for UI purposes
  String get displayDirectoryPath => PathUtils.safUriToDisplayPath(directoryPath);

  @override
  String toString() {
    return 'Note(id: $id, title: $title, filePath: $filePath)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Note && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}