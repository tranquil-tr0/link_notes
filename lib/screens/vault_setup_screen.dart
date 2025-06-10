import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/permission_service.dart';
import '../utils/path_utils.dart';
import 'dart:io';

class VaultSetupScreen extends StatefulWidget {
  final VoidCallback? onSetupComplete;

  const VaultSetupScreen({super.key, this.onSetupComplete});

  @override
  State<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends State<VaultSetupScreen> {
  final SettingsService _settingsService = SettingsService.instance;
  bool _isLoading = false;
  String? _error;

  /// Select vault location and complete setup immediately
  Future<void> _selectVaultLocation() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      if (Platform.isAndroid) {
        // Use SAF for Android - immediately prompt and save
        final granted = await PermissionService.instance.requestStoragePermission();
        if (granted) {
          final safUri = await PermissionService.instance.getVaultSafUri();
          if (safUri != null) {
            // Show user-friendly confirmation of selected location
            final displayPath = PathUtils.safUriToDisplayPath(safUri);
            final description = PathUtils.getStorageLocationDescription(safUri);
            
            debugPrint('Selected vault location: $displayPath ($description)');
            
            // Immediately save the SAF URI as the vault directory
            // PermissionService.requestStoragePermission() already saves the URI,
            // but we ensure both services are synchronized
            await PermissionService.instance.setVaultSafUri(safUri);
            await _settingsService.setVaultDirectory(safUri);
            await _settingsService.setFirstLaunchCompleted();

            // Complete setup immediately after SAF selection
            if (widget.onSetupComplete != null) {
              widget.onSetupComplete!();
            }
            return;
          } else {
            setState(() {
              _error = 'Failed to get storage access URI. Please try again.';
            });
            return;
          }
        } else {
          setState(() {
            _error = 'Storage access permission is required to select a vault directory';
          });
          return;
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
          // Validate and save the selected directory immediately
          await _saveDirectoryAndComplete(result);
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

  /// Validate and save the selected directory for non-Android platforms
  Future<void> _saveDirectoryAndComplete(String directoryPath) async {
    try {
      // For non-Android platforms, use traditional file system
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Test write permissions by creating a temporary file
      final testFile = File('$directoryPath/.test_write');
      await testFile.writeAsString('test');
      await testFile.delete();

      // Show user-friendly confirmation of selected location
      final displayPath = PathUtils.safUriToDisplayPath(directoryPath);
      debugPrint('Selected vault location: $displayPath');

      // Save the directory to settings
      await _settingsService.setVaultDirectory(directoryPath);
      await _settingsService.setFirstLaunchCompleted();

      // Complete setup immediately
      if (widget.onSetupComplete != null) {
        widget.onSetupComplete!();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to set up vault directory: $e';
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectorySelector() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.folder_special,
            size: 48,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          Text(
            'Select Your Vault Location',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose where you\'d like to store your notes. This will be your vault directory.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _selectVaultLocation,
              icon: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(_isLoading ? 'Setting up...' : 'Select Vault Location'),
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

}