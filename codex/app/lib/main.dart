import 'package:flutter/material.dart';

void main() {
  runApp(const PilotApp());
}

class PilotApp extends StatelessWidget {
  const PilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PiLOT',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF0F766E),
        ),
      ),
      home: const PilotHomeScreen(),
    );
  }
}

class PilotHomeScreen extends StatelessWidget {
  const PilotHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('PiLOT')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusPanel(colorScheme: colorScheme),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.add),
                      label: const Text('New Run'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.settings),
                      label: const Text('Server Settings'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const Expanded(child: Center(child: Text('No runs yet'))),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.hub_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Codex Hub'),
                  SizedBox(height: 4),
                  Text('Disconnected'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
