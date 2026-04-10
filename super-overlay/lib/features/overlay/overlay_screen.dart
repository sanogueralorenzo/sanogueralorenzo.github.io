import 'package:flutter/material.dart';

class OverlayScreen extends StatelessWidget {
  const OverlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Overlay')),
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
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              title: const Text('Permissions'),
              subtitle: Text(
                'Required to use Overlay',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
            ),
          ),
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
