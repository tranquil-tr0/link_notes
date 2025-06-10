import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/permission_service.dart';
import '../providers/vault_provider.dart';
import '../utils/path_utils.dart';
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
        // Use SAF with proper cleanup for Android
        final success = await PermissionService.instance.changeVaultDirectoryWithCleanup();
        if (success) {
          final safUri = await PermissionService.instance.getVaultSafUri();
          if (safUri != null) {
            newDirectoryPath = safUri;
            
            // Show user-friendly confirmation of selected location
            final displayPath = PathUtils.safUriToDisplayPath(safUri);
            final description = PathUtils.getStorageLocationDescription(safUri);
            debugPrint('Selected new vault location: $displayPath ($description)');
            
            // Inform user about old permissions
            if (_currentVaultDirectory != null && _currentVaultDirectory != safUri) {
              debugPrint('Note: Previous directory permissions remain active in system settings');
            }
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
          
          // Show user-friendly confirmation of selected location
          final displayPath = PathUtils.safUriToDisplayPath(result);
          debugPrint('Selected new vault location: $displayPath');
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
        // For Android with SAF, update both PermissionService and SettingsService
        await PermissionService.instance.setVaultSafUri(newDirectoryPath);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PathUtils.safUriToDisplayPath(_currentVaultDirectory),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_currentVaultDirectory != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      PathUtils.getStorageLocationDescription(_currentVaultDirectory),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentVaultDirectory!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
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
              'Select a new location for your vault. Your current notes will not be affected or moved.'
              '${Platform.isAndroid ? ' Access to your current directory cannot be revoked'
              ' by the application. You can manually revoke access permissions in App info '
              '> Storage & cache' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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