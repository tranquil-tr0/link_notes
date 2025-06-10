import 'dart:io';
import 'package:saf_util/saf_util_platform_interface.dart';

class Note {
  final String id;
  final String title;
  final String content;
  final String filePath;
  final DateTime createdAt;
  final DateTime modifiedAt;

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

    return Note(
      id: id,
      title: title,
      content: noteContent.trim(),
      filePath: filePath,
      createdAt: createdAt ?? stat.changed,
      modifiedAt: modifiedAt ?? stat.modified,
    );
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
    
    return Note(
      id: id,
      title: title,
      content: noteContent.trim(),
      filePath: safFile.uri, // Use URI as file path for SAF files
      createdAt: createdAt ?? now,
      modifiedAt: modifiedAt ?? now,
    );
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

  /// Creates a copy of this Note with updated fields
  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? filePath,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
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
  String get fileName => filePath.split('/').last.replaceAll('.md', '');

  /// Gets the directory path
  String get directoryPath => filePath.substring(0, filePath.lastIndexOf('/'));

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