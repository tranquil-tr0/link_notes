import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/permission_service.dart';
import '../providers/vault_provider.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService.instance;
  String? _currentVaultDirectory;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    setState(() {
      _currentVaultDirectory = _settingsService.getVaultDirectory();
    });
  }

  Future<void> _changeVaultLocation() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      String? newDirectoryPath;

      if (Platform.isAndroid) {
        // Use SAF for Android - immediately apply the new directory
        final granted = await PermissionService.instance.requestStoragePermission();
        if (granted) {
          final safUri = await PermissionService.instance.getVaultSafUri();
          if (safUri != null) {
            newDirectoryPath = safUri;
          } else {
            setState(() {
              _error = 'Failed to get storage access URI. Please try again.';
            });
            return;
          }
        } else {
          setState(() {
            _error = 'Storage access permission is required to change vault directory';
          });
          return;
        }
      } else {
        // Use traditional file picker for other platforms
        final result = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Select New Vault Directory',
          lockParentWindow: true,
        );

        if (result != null) {
          newDirectoryPath = result;
        } else {
          return; // User cancelled
        }
      }

      // Apply the directory change immediately
      await _applyDirectoryChange(newDirectoryPath);
    } catch (e) {
      setState(() {
        _error = 'Failed to change vault directory: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _applyDirectoryChange(String newDirectoryPath) async {
    try {
      final vaultProvider = context.read<VaultProvider>();
      
      if (Platform.isAndroid) {
        // For Android with SAF, just save the URI
        await _settingsService.setVaultDirectory(newDirectoryPath);
      } else {
        // For other platforms, test directory access
        final newDirectory = Directory(newDirectoryPath);
        if (!await newDirectory.exists()) {
          await newDirectory.create(recursive: true);
        }

        // Test write permissions
        final testFile = File('$newDirectoryPath/.test_write');
        await testFile.writeAsString('test');
        await testFile.delete();

        // Update settings
        await _settingsService.setVaultDirectory(newDirectoryPath);
      }

      // Reinitialize the vault with new location
      await vaultProvider.changeVaultDirectory(newDirectoryPath);

      setState(() {
        _currentVaultDirectory = newDirectoryPath;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vault directory changed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to change vault directory: $e';
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vault Settings',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            _buildVaultDirectorySection(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _buildErrorMessage(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVaultDirectorySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_special),
                const SizedBox(width: 8),
                Text(
                  'Vault Directory',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Current Location:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _currentVaultDirectory ?? 'Not set',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _changeVaultLocation,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open),
                label: Text(_isLoading ? 'Changing location...' : 'Change Vault Location'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a new location for your vault. Your current notes will not be affected or moved.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
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