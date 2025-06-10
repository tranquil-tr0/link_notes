import 'dart:io';
import 'note.dart';
import '../utils/path_utils.dart';

class Folder {
  final String name;
  final String path;
  final List<Folder> subfolders;
  final List<Note> notes;
  final Folder? parent;

  Folder({
    required this.name,
    required this.path,
    List<Folder>? subfolders,
    List<Note>? notes,
    this.parent,
  })  : subfolders = subfolders ?? [],
        notes = notes ?? [];

  /// Creates a Folder from a directory path
  static Future<Folder> fromDirectory(
    String directoryPath, {
    Folder? parent,
    bool recursive = true,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw Exception('Directory does not exist: $directoryPath');
    }

    final folderName = directoryPath.split('/').last;
    final folder = Folder(
      name: folderName,
      path: directoryPath,
      parent: parent,
    );

    if (recursive) {
      await folder._loadContents();
    }

    return folder;
  }

  /// Loads the contents of this folder from the file system
  Future<void> _loadContents() async {
    final directory = Directory(path);
    
    try {
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          // Load subfolder
          final subfolder = await Folder.fromDirectory(
            entity.path,
            parent: this,
            recursive: true,
          );
          subfolders.add(subfolder);
        } else if (entity is File && entity.path.endsWith('.md')) {
          // Load note
          try {
            final note = await Note.fromFile(entity);
            notes.add(note);
          } catch (e) {
            // Skip files that can't be parsed as notes
            // Note: In production, consider using a proper logging framework
          }
        }
      }
    } catch (e) {
      // Error loading folder contents - handle gracefully
      // Note: In production, consider using a proper logging framework
    }

    // Sort subfolders and notes alphabetically
    subfolders.sort((a, b) => a.name.compareTo(b.name));
    notes.sort((a, b) => a.title.compareTo(b.title));
  }

  /// Adds a note to this folder
  void addNote(Note note) {
    // Remove note if it already exists (update case)
    notes.removeWhere((n) => n.id == note.id);
    notes.add(note);
    notes.sort((a, b) => a.title.compareTo(b.title));
  }

  /// Adds a subfolder to this folder
  void addSubfolder(Folder folder) {
    // Remove folder if it already exists (update case)
    subfolders.removeWhere((f) => f.name == folder.name);
    subfolders.add(folder);
    subfolders.sort((a, b) => a.name.compareTo(b.name));
  }

  /// Removes a note from this folder by ID
  bool removeNote(String noteId) {
    final initialLength = notes.length;
    notes.removeWhere((note) => note.id == noteId);
    return notes.length < initialLength;
  }

  /// Removes a note from this folder by instance
  bool removeNoteInstance(Note note) {
    return notes.remove(note);
  }

  /// Removes a subfolder from this folder by name
  bool removeSubfolder(String folderName) {
    final initialLength = subfolders.length;
    subfolders.removeWhere((folder) => folder.name == folderName);
    return subfolders.length < initialLength;
  }

  /// Removes a subfolder from this folder by instance
  bool removeSubfolderInstance(Folder folder) {
    return subfolders.remove(folder);
  }

  /// Finds a note by ID in this folder and all subfolders
  Note? findNote(String noteId) {
    // Check notes in this folder
    for (final note in notes) {
      if (note.id == noteId) return note;
    }

    // Check subfolders recursively
    for (final subfolder in subfolders) {
      final found = subfolder.findNote(noteId);
      if (found != null) return found;
    }

    return null;
  }

  /// Finds a subfolder by name in this folder and all subfolders
  Folder? findSubfolder(String folderName) {
    // Check direct subfolders
    for (final subfolder in subfolders) {
      if (subfolder.name == folderName) return subfolder;
    }

    // Check nested subfolders recursively
    for (final subfolder in subfolders) {
      final found = subfolder.findSubfolder(folderName);
      if (found != null) return found;
    }

    return null;
  }

  /// Finds a subfolder by path
  Folder? findSubfolderByPath(String folderPath) {
    if (path == folderPath) return this;

    for (final subfolder in subfolders) {
      final found = subfolder.findSubfolderByPath(folderPath);
      if (found != null) return found;
    }

    return null;
  }

  /// Gets all notes in this folder and all subfolders
  List<Note> getAllNotes() {
    final allNotes = <Note>[...notes];
    
    for (final subfolder in subfolders) {
      allNotes.addAll(subfolder.getAllNotes());
    }
    
    return allNotes;
  }

  /// Gets all subfolders (flattened list) in this folder and all nested folders
  List<Folder> getAllSubfolders() {
    final allFolders = <Folder>[...subfolders];
    
    for (final subfolder in subfolders) {
      allFolders.addAll(subfolder.getAllSubfolders());
    }
    
    return allFolders;
  }

  /// Gets the depth level of this folder (root = 0)
  int get depth {
    if (parent == null) return 0;
    return parent!.depth + 1;
  }

  /// Gets the full path hierarchy as a list
  List<String> get pathHierarchy {
    if (parent == null) return [name];
    return [...parent!.pathHierarchy, name];
  }

  /// Gets the root folder
  Folder get root {
    if (parent == null) return this;
    return parent!.root;
  }

  /// Checks if this folder is empty (no notes or subfolders)
  bool get isEmpty => notes.isEmpty && subfolders.isEmpty;

  /// Checks if this folder has any content
  bool get hasContent => !isEmpty;

  /// Gets the total count of notes in this folder and all subfolders
  int get totalNoteCount {
    int count = notes.length;
    for (final subfolder in subfolders) {
      count += subfolder.totalNoteCount;
    }
    return count;
  }

  /// Creates a directory for this folder if it doesn't exist
  Future<void> createDirectory() async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  /// Deletes the directory and all its contents
  Future<void> deleteDirectory() async {
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Refreshes the folder contents from the file system
  Future<void> refresh() async {
    notes.clear();
    subfolders.clear();
    await _loadContents();
  }

  /// Creates a copy of this folder with updated properties
  Folder copyWith({
    String? name,
    String? path,
    List<Folder>? subfolders,
    List<Note>? notes,
    Folder? parent,
  }) {
    return Folder(
      name: name ?? this.name,
      path: path ?? this.path,
      subfolders: subfolders ?? List<Folder>.from(this.subfolders),
      notes: notes ?? List<Note>.from(this.notes),
      parent: parent ?? this.parent,
    );
  }

  /// Gets a display-friendly path for UI purposes
  String get displayPath => PathUtils.safUriToDisplayPath(path);

  /// Gets a display-friendly name for UI purposes
  String get displayName => PathUtils.extractFolderName(path);

  @override
  String toString() {
    return 'Folder(name: $name, path: $path, notes: ${notes.length}, subfolders: ${subfolders.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Folder && other.path == path;
  }

  @override
  int get hashCode => path.hashCode;
}