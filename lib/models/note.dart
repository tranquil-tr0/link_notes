import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'package:saf_stream/saf_stream.dart';
import '../services/markdown_conversion_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
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
    debugPrint('DEBUG: toFile() called for note: $id at path: $filePath');
    
    // Check if YAML frontmatter is enabled in settings
    final includeYamlFrontmatter = SettingsService.instance.isYamlFrontmatterEnabled();
    
    String fullContent;
    if (includeYamlFrontmatter) {
      // Create frontmatter with metadata
      final frontmatter = '''---
id: $id
title: $title
created_at: ${createdAt.toIso8601String()}
modified_at: ${modifiedAt.toIso8601String()}
---

''';
      fullContent = frontmatter + content;
    } else {
      // Use content without YAML frontmatter
      fullContent = content;
    }
    
    debugPrint('DEBUG: Full content prepared, length: ${fullContent.length}, YAML frontmatter: $includeYamlFrontmatter');
    
    if (Platform.isAndroid && PathUtils.isSafUri(filePath)) {
      debugPrint('DEBUG: Using SAF operations for Android');
      debugPrint('DEBUG: Platform.isAndroid: ${Platform.isAndroid}');
      debugPrint('DEBUG: PathUtils.isSafUri(filePath): ${PathUtils.isSafUri(filePath)}');
      // Use SAF operations for Android
      await _saveUsingSaf(fullContent);
    } else {
      debugPrint('DEBUG: Using traditional file operations');
      // Use traditional file operations for other platforms
      await _saveUsingFile(fullContent);
    }
  }
  
  /// Save using traditional File API
  Future<void> _saveUsingFile(String content) async {
    final file = File(filePath);
    
    // Create directory if it doesn't exist
    await file.parent.create(recursive: true);
    
    await file.writeAsString(content);
  }
  
  /// Save using SAF operations
  Future<void> _saveUsingSaf(String content) async {
    debugPrint('DEBUG: _saveUsingSaf called for file: $filePath');
    debugPrint('DEBUG: Content length: ${content.length} characters');
    
    // Check if this is an existing file (update) or new file (create)
    final fileExists = await _safFileExists();
    debugPrint('DEBUG: File exists check result: $fileExists');
    
    if (fileExists) {
      debugPrint('DEBUG: File exists - calling _updateExistingSafFile');
      await _updateExistingSafFile(content);
    } else {
      debugPrint('DEBUG: File does not exist - calling _createNewSafFile');
      await _createNewSafFile(content);
    }
  }
  
  /// Check if SAF file exists
  Future<bool> _safFileExists() async {
    try {
      debugPrint('DEBUG: _safFileExists called for: $filePath');
      
      // First validate the URI and permissions
      final uriInfo = await PermissionService.instance.getSafUriInfo(filePath);
      debugPrint('DEBUG: SAF URI info: $uriInfo');
      
      final safUtil = SafUtil();
      final docFile = await safUtil.documentFileFromUri(filePath, false);
      final exists = docFile != null;
      debugPrint('DEBUG: File exists check result: $exists');
      if (docFile != null) {
        debugPrint('DEBUG: Found document - URI: ${docFile.uri}, Name: ${docFile.name}, IsDir: ${docFile.isDir}');
      }
      return exists;
    } catch (e) {
      debugPrint('DEBUG: Error checking if SAF file exists: $e');
      debugPrint('DEBUG: Error type: ${e.runtimeType}');
      return false;
    }
  }
  
  /// Update existing SAF file
  Future<void> _updateExistingSafFile(String content) async {
    try {
      final bytes = utf8.encode(content);
      
      // DEBUG: Log file path being updated
      debugPrint('DEBUG: Attempting to update SAF file at path: $filePath');
      
      // For updating existing files, we need to:
      // 1. Delete the existing file first
      // 2. Create a new file with the same name
      // This ensures we overwrite the content properly
      
      final safUtil = SafUtil();
      final docFile = await safUtil.documentFileFromUri(filePath, false);
      
      if (docFile != null) {
        debugPrint('DEBUG: Found existing file: ${docFile.name}');
        
        // Delete the existing file
        debugPrint('DEBUG: Deleting existing file to overwrite it');
        await safUtil.delete(filePath, false);
        
        // Extract the filename and parent directory
        final fileName = _extractFileNameFromUri(filePath);
        final parentUri = await _extractParentUri(filePath);
        
        debugPrint('DEBUG: Extracted filename: $fileName');
        debugPrint('DEBUG: Extracted parent URI: $parentUri');
        
        // Validate parent URI has write permissions
        final hasWritePermission = await safUtil.hasPersistedPermission(
          parentUri,
          checkRead: false,
          checkWrite: true
        );
        debugPrint('DEBUG: Parent URI has write permission: $hasWritePermission');
        
        if (!hasWritePermission) {
          throw Exception('No write permission for parent directory: $parentUri');
        }
        
        // Create the file with the same name
        final safStream = SafStream();
        debugPrint('DEBUG: Creating new file with original name: $fileName');
        
        await safStream.writeFileBytes(
          parentUri,
          fileName,
          'text/markdown',
          bytes,
        );
        
        debugPrint('Successfully updated existing SAF file: $fileName');
      } else {
        debugPrint('DEBUG: Document file not found for URI: $filePath');
        throw Exception('File not found for update: $filePath');
      }
    } catch (e) {
      debugPrint('DEBUG: Detailed error in _updateExistingSafFile: $e');
      debugPrint('DEBUG: Error type: ${e.runtimeType}');
      if (e.toString().contains('PlatformException')) {
        debugPrint('DEBUG: This is a PlatformException - likely a native Android SAF issue');
        
        // Add specific PlatformException analysis
        if (e.toString().contains('File creation failed')) {
          debugPrint('DEBUG: File creation failed - this suggests permission or URI issues');
          debugPrint('DEBUG: Possible causes: 1) Invalid parent URI, 2) No write permission, 3) File locked');
        }
      }
      throw Exception('Failed to update note: $e');
    }
  }
  
  /// Create new SAF file
  Future<void> _createNewSafFile(String content) async {
    try {
      // Extract filename from the URI
      final fileName = _extractFileNameFromUri(filePath);
      
      debugPrint('Creating new SAF file: $fileName');
      
      // Use PermissionService's createSafFile method which handles path creation
      final safFile = await PermissionService.instance.createSafFile(fileName, content);
      
      if (safFile == null) {
        throw Exception('Failed to create SAF file: $fileName');
      }
      
      debugPrint('Successfully created new SAF file: $fileName');
    } catch (e) {
      debugPrint('Error creating new SAF file: $e');
      throw Exception('Failed to create note: $e');
    }
  }
  
  /// Extract parent URI from SAF file URI
  Future<String> _extractParentUri(String fileUri) async {
    debugPrint('DEBUG: _extractParentUri called with: $fileUri');
    
    try {
      // For SAF write operations, we need to use the vault tree URI
      // The file URI format is: content://.../tree/VAULT_PATH/document/VAULT_PATH/filename
      // We need to return the vault tree URI: content://.../tree/VAULT_PATH
      
      final vaultUri = await PermissionService.instance.getVaultSafUri();
      if (vaultUri != null) {
        debugPrint('DEBUG: Using vault URI as parent: $vaultUri');
        return vaultUri;
      }
      
      // Fallback: extract tree portion from the file URI
      final treeMatch = RegExp(r'(content://[^/]+/tree/[^/]+)').firstMatch(fileUri);
      if (treeMatch != null) {
        final treeUri = treeMatch.group(1)!;
        debugPrint('DEBUG: Extracted tree URI from file URI: $treeUri');
        return treeUri;
      }
      
      debugPrint('WARNING: Could not extract parent URI from: $fileUri');
      throw Exception('Unable to determine parent URI for SAF operation');
    } catch (e) {
      debugPrint('DEBUG: Error in _extractParentUri: $e');
      rethrow;
    }
  }
  
  /// Extract filename from SAF URI
  String _extractFileNameFromUri(String fileUri) {
    final decodedUri = Uri.decodeFull(fileUri);
    final parts = decodedUri.split('/');
    return parts.last;
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