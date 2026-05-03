import 'package:app/src/features/example/example_view_model.dart';
import 'package:app/src/mavericks/async.dart';
import 'package:app/src/mavericks/mavericks_widgets.dart';
import 'package:flutter/material.dart';

class ExampleScreen extends StatelessWidget {
  const ExampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MavericksInvalidate<ExampleViewModel, ExampleState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Example')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _ExampleContent(state: state),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExampleContent extends StatelessWidget {
  const _ExampleContent({required this.state});

  final ExampleState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.todo) {
      Uninitialized() || Loading(valueOrNull: null) => const Center(
        child: CircularProgressIndicator(),
      ),
      Loading(valueOrNull: final todo?) || Success(value: final todo) =>
        _ExampleTodoCard(title: todo.title, completed: todo.completed),
      Fail(errorOrNull: final error, valueOrNull: final todo?) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExampleTodoCard(title: todo.title, completed: todo.completed),
          const SizedBox(height: 16),
          Text(error.messageOrNull ?? 'Request failed.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.read<ExampleViewModel>().load(),
            child: const Text('Retry'),
          ),
        ],
      ),
      Fail(errorOrNull: final error) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(error.messageOrNull ?? 'Request failed.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.read<ExampleViewModel>().load(),
            child: const Text('Retry'),
          ),
        ],
      ),
    };
  }
}

class _ExampleTodoCard extends StatelessWidget {
  const _ExampleTodoCard({required this.title, required this.completed});

  final String title;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              completed ? Icons.check_circle : Icons.radio_button_unchecked,
              color: completed ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
      ),
    );
  }
}
