import 'package:flutter/material.dart';
import '../services/permission_service.dart';

/// Widget that handles storage permission requests with user-friendly UI
class PermissionRequestWidget extends StatefulWidget {
  final VoidCallback? onPermissionGranted;
  final VoidCallback? onPermissionDenied;
  final Widget? child;

  const PermissionRequestWidget({
    super.key,
    this.onPermissionGranted,
    this.onPermissionDenied,
    this.child,
  });

  @override
  State<PermissionRequestWidget> createState() => _PermissionRequestWidgetState();
}

class _PermissionRequestWidgetState extends State<PermissionRequestWidget> {
  final PermissionService _permissionService = PermissionService.instance;
  bool _isLoading = false;
  bool _hasPermission = false;
  bool _isPermanentlyDenied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final hasPermission = await _permissionService.hasStoragePermission();
      final isPermanentlyDenied = await _permissionService.isPermissionPermanentlyDenied();

      setState(() {
        _hasPermission = hasPermission;
        _isPermanentlyDenied = isPermanentlyDenied;
      });

      if (hasPermission && widget.onPermissionGranted != null) {
        widget.onPermissionGranted!();
      } else if (!hasPermission && widget.onPermissionDenied != null) {
        widget.onPermissionDenied!();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to check permissions: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final granted = await _permissionService.requestStoragePermission();
      final isPermanentlyDenied = !granted ? await _permissionService.isPermissionPermanentlyDenied() : false;

      setState(() {
        _hasPermission = granted;
        _isPermanentlyDenied = isPermanentlyDenied;
      });

      if (granted && widget.onPermissionGranted != null) {
        widget.onPermissionGranted!();
      } else if (!granted && widget.onPermissionDenied != null) {
        widget.onPermissionDenied!();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to request permissions: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    await _permissionService.openAppSettings();
    // Re-check permissions after returning from settings
    await Future.delayed(const Duration(milliseconds: 500));
    await _checkPermission();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (_hasPermission) {
      return widget.child ?? const SizedBox.shrink();
    }

    return _buildPermissionRequestWidget();
  }

  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Checking permissions...'),
        ],
      ),
    );
  }

  Widget _buildPermissionRequestWidget() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.folder_special,
            size: 64,
            color: Colors.orange,
          ),
          const SizedBox(height: 24),
          Text(
            'Storage Permission Required',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            _permissionService.getPermissionRequirementsMessage(),
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_error != null) ...[
            Container(
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
            ),
            const SizedBox(height: 16),
          ],
          if (_isPermanentlyDenied) ...[
            ElevatedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 8),
            Text(
              'Please enable storage permissions in your device settings',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ] else ...[
            ElevatedButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.check),
              label: const Text('Grant Permission'),
            ),
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed: _checkPermission,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}