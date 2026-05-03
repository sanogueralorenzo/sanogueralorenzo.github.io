import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/features/example/example_screen.dart';
import 'package:app/src/features/example/example_todo.dart';
import 'package:app/src/features/example/example_view_model.dart';
import 'package:app/src/mavericks/async.dart';
import 'package:app/src/mavericks/mavericks_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeExampleViewModel extends ExampleViewModel {
  _FakeExampleViewModel(super.initialState);

  @override
  Future<void> load() async {}
}

void main() {
  testWidgets('renders example data from Mavericks state', (
    WidgetTester tester,
  ) async {
    final viewModel = _FakeExampleViewModel(
      const ExampleState(
        todo: Success(
          ExampleTodo(
            id: 1,
            userId: 1,
            title: 'Wire the example feature',
            completed: true,
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MavericksProvider<ExampleViewModel>.value(
        value: viewModel,
        child: const _TestApp(child: ExampleScreen()),
      ),
    );

    expect(find.text('Example'), findsOneWidget);
    expect(find.text('Wire the example feature'), findsOneWidget);

    await viewModel.close();
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }
}
