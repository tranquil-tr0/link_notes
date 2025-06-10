import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/permission_service.dart';
import 'dart:io';

class VaultSetupScreen extends StatefulWidget {
  final VoidCallback? onSetupComplete;

  const VaultSetupScreen({super.key, this.onSetupComplete});

  @override
  State<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends State<VaultSetupScreen> {
  final SettingsService _settingsService = SettingsService.instance;
  String? _selectedDirectory;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setDefaultDirectory();
  }

  /// Set the default directory using path_provider for cross-platform support
  Future<void> _setDefaultDirectory() async {
    try {
      String defaultPath;

      final directory = await getApplicationDocumentsDirectory();
      defaultPath = '${directory.path}/Link Notes';
      
      setState(() {
        _selectedDirectory = defaultPath;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to get default directory: $e';
      });
    }
  }

  /// Open directory picker to select custom vault location
  Future<void> _pickDirectory() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      if (Platform.isAndroid) {
        // Use SAF for Android
        final granted = await PermissionService.instance.requestStoragePermission();
        if (granted) {
          final safUri = await PermissionService.instance.getVaultSafUri();
          if (safUri != null) {
            setState(() {
              _selectedDirectory = 'SAF Directory: $safUri';
            });
          }
        } else {
          setState(() {
            _error = 'Storage access permission is required to select a vault directory';
          });
        }
      } else {
        // Use traditional file picker for other platforms
        String? initialDirectory;
        if (Platform.isIOS) {
          final docDir = await getApplicationDocumentsDirectory();
          initialDirectory = docDir.path;
        }

        final result = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Select Vault Directory',
          lockParentWindow: true,
          initialDirectory: initialDirectory,
        );

        if (result != null) {
          setState(() {
            _selectedDirectory = result;
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to select directory: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Validate and save the selected directory
  Future<void> _saveVaultDirectory() async {
    if (_selectedDirectory == null || _selectedDirectory!.isEmpty) {
      setState(() {
        _error = 'Please select a vault directory';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (Platform.isAndroid) {
        // For Android with SAF, ensure we have permissions
        final hasPermission = await PermissionService.instance.hasStoragePermission();
        if (!hasPermission) {
          setState(() {
            _error = 'Storage access permission is required. Please select a directory first.';
          });
          return;
        }

        // Get the SAF URI and save it
        final safUri = await PermissionService.instance.getVaultSafUri();
        if (safUri != null) {
          await _settingsService.setVaultDirectory(safUri);
        } else {
          setState(() {
            _error = 'Failed to get storage access URI. Please try selecting the directory again.';
          });
          return;
        }
      } else {
        // For other platforms, use traditional file system
        final directory = Directory(_selectedDirectory!);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        // Test write permissions by creating a temporary file
        final testFile = File('${_selectedDirectory!}/.test_write');
        await testFile.writeAsString('test');
        await testFile.delete();

        // Save the directory to settings
        await _settingsService.setVaultDirectory(_selectedDirectory!);
      }

      await _settingsService.setFirstLaunchCompleted();

      // Notify completion
      if (widget.onSetupComplete != null) {
        widget.onSetupComplete!();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to set up vault directory: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.folder_special,
                      size: 80,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Welcome to Link Notes',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Choose where you\'d like to store your notes vault',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    _buildDirectorySelector(),
                    const SizedBox(height: 32),
                    if (_error != null) _buildErrorMessage(),
                  ],
                ),
              ),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectorySelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder, size: 20),
              const SizedBox(width: 8),
              Text(
                'Vault Directory',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Text(
              _selectedDirectory ?? 'No directory selected',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickDirectory,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Browse...'),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _setDefaultDirectory,
                icon: const Icon(Icons.restore),
                label: const Text('Default'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your notes will be read from and stored here. '
            'We suggest choosing somewhere inside your Obsidian vault or your Obsidian vault.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveVaultDirectory,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirm Vault Directory'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'You can change this location later in settings',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}