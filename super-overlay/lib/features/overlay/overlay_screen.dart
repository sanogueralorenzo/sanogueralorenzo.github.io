import 'package:flutter/material.dart';
import 'package:super_overlay/features/overlay/overlay_host_client.dart';

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  final OverlayHostClient _overlayHostClient = OverlayHostClient();

  OverlayNativeState _state = const OverlayNativeState.unsupported();
  bool _isLoadingState = true;
  bool _isExecutingAction = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    setState(() {
      _isLoadingState = true;
      _errorMessage = null;
    });

    final state = await _overlayHostClient.loadState();
    if (!mounted) {
      return;
    }

    setState(() {
      _state = state;
      _isLoadingState = false;
    });
  }

  Future<void> _runAction(Future<String?> Function() action) async {
    setState(() {
      _isExecutingAction = true;
      _errorMessage = null;
    });

    final error = await action();
    await _refreshState();
    if (!mounted) {
      return;
    }

    setState(() {
      _isExecutingAction = false;
      _errorMessage = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissionIcon = _state.overlayPermissionGranted
        ? Icons.check_circle
        : Icons.error_outline;
    final permissionColor = _state.overlayPermissionGranted
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overlay'),
        actions: [
          IconButton(
            onPressed: _isLoadingState || _isExecutingAction
                ? null
                : _refreshState,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  Icon(
                    Icons.dark_mode,
                    size: 72,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Overlay',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Play media with the screen off',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Get started', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const _StepRow(
                    icon: Icons.play_arrow_outlined,
                    chip: 'Step 1',
                    title: 'Play Media',
                    body:
                        'Play from the app that does not support background play.',
                  ),
                  const _StepRow(
                    icon: Icons.keyboard_arrow_down,
                    chip: 'Step 2',
                    title: 'Swipe down',
                    body: 'Pull down the status bar to see Quick Settings.',
                  ),
                  const _StepRow(
                    icon: Icons.grid_view,
                    chip: 'Step 3',
                    title: 'Tap Overlay',
                    body: 'Tap the tile to cover the screen with black.',
                  ),
                  const _StepRow(
                    icon: Icons.power_settings_new,
                    chip: 'Step 4',
                    title: 'Press power to stop',
                    body:
                        'Your phone locks, playback stops and the overlay goes away.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Permissions',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(permissionIcon, color: permissionColor),
              title: const Text('Display over other apps'),
              subtitle: Text(
                _state.overlayPermissionGranted
                    ? 'Granted'
                    : 'Required to use Overlay',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: FilledButton.tonal(
                onPressed: _isExecutingAction
                    ? null
                    : () => _runAction(_overlayHostClient.openOverlaySettings),
                child: const Text('Open settings'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                _state.notificationPermissionGranted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: _state.notificationPermissionGranted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              title: const Text('Notifications'),
              subtitle: Text(
                _state.notificationPermissionGranted
                    ? 'Enabled'
                    : 'Required for foreground status',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: FilledButton.tonal(
                onPressed: _isExecutingAction
                    ? null
                    : () => _runAction(
                        _overlayHostClient.openNotificationSettings,
                      ),
                child: const Text('Open settings'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Bubble Tap-To-Talk',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable bubble overlay'),
                    subtitle: const Text(
                      'Shows a draggable bubble while a keyboard is visible. Tap once to dictate.',
                    ),
                    value: _state.bubbleEnabled,
                    onChanged: (_isExecutingAction || !_state.bridgeAvailable)
                        ? null
                        : (value) => _runAction(
                            () => _overlayHostClient.setBubbleEnabled(value),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _state.bubbleAccessibilityEnabled
                            ? Icons.check_circle
                            : Icons.error_outline,
                        size: 20,
                        color: _state.bubbleAccessibilityEnabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _state.bubbleAccessibilityEnabled
                              ? 'Accessibility service enabled'
                              : 'Accessibility service required',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _isExecutingAction
                            ? null
                            : () => _runAction(
                                _overlayHostClient.openAccessibilitySettings,
                              ),
                        child: const Text('Open settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Overlay controls', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    _state.overlayRunning
                        ? 'Overlay is active'
                        : 'Overlay is inactive',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              (_isExecutingAction ||
                                  !_state.overlayPermissionGranted)
                              ? null
                              : () =>
                                    _runAction(_overlayHostClient.startOverlay),
                          child: const Text('Start overlay'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              (_isExecutingAction || !_state.overlayRunning)
                              ? null
                              : () =>
                                    _runAction(_overlayHostClient.stopOverlay),
                          child: const Text('Stop overlay'),
                        ),
                      ),
                    ],
                  ),
                  if (_isLoadingState || _isExecutingAction) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
          if (!_state.supported || !_state.bridgeAvailable) ...[
            const SizedBox(height: 12),
            Text(
              'Native overlay bridge is only available on Android runtime.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.icon,
    required this.chip,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String chip;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(label: Text(chip)),
                const SizedBox(height: 2),
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
