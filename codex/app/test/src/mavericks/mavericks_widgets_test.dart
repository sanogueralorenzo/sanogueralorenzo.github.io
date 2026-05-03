import 'package:app/src/mavericks/mavericks_state.dart';
import 'package:app/src/mavericks/mavericks_view_model.dart';
import 'package:app/src/mavericks/mavericks_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'MavericksInvalidate resubscribes when the provided view model changes',
    (tester) async {
      final firstViewModel = _CounterViewModel(1);
      final secondViewModel = _CounterViewModel(2);
      final hostKey = GlobalKey<_SwapHostState>();

      await tester.pumpWidget(
        MaterialApp(
          home: _SwapHost(
            key: hostKey,
            firstViewModel: firstViewModel,
            secondViewModel: secondViewModel,
            child: MavericksInvalidate<_CounterViewModel, _CounterState>(
              builder: (context, state) {
                return Text('${state.count}', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);

      hostKey.currentState!.swap();
      await tester.pump();
      await tester.pump();

      expect(find.text('2'), findsOneWidget);

      firstViewModel.setCount(3);
      await tester.pump();
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      secondViewModel.setCount(4);
      await tester.pump();
      await tester.pump();
      expect(find.text('4'), findsOneWidget);

      await firstViewModel.close();
      await secondViewModel.close();
    },
  );

  testWidgets('MavericksInvalidate listener receives state transitions', (
    tester,
  ) async {
    final viewModel = _CounterViewModel(1);
    final values = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MavericksProvider<_CounterViewModel>.value(
          value: viewModel,
          child: MavericksInvalidate<_CounterViewModel, _CounterState>(
            listeners: [
              onEach<_CounterState, int>(
                (state) => state.count,
                (context, count) => values.add(count),
                uniqueOnly: false,
              ),
            ],
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    viewModel.setCount(3);
    await tester.pump();
    await tester.pump();
    expect(values, [3]);

    viewModel.setCount(5);
    await tester.pump();
    await tester.pump();
    expect(values, [3, 5]);

    await viewModel.close();
  });

  testWidgets('onEach only fires when the selected value changes', (
    tester,
  ) async {
    final viewModel = _CounterViewModel(1);
    final values = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MavericksProvider<_CounterViewModel>.value(
          value: viewModel,
          child: MavericksInvalidate<_CounterViewModel, _CounterState>(
            listeners: [
              onEach<_CounterState, int>(
                (state) => state.count,
                (context, count) => values.add(count),
                uniqueOnly: true,
              ),
            ],
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    viewModel.setLabel('updated');
    await tester.pump();
    await tester.pump();
    expect(values, isEmpty);

    viewModel.setCount(3);
    await tester.pump();
    await tester.pump();
    expect(values, [3]);

    await viewModel.close();
  });

  testWidgets('onEach can observe every state update or only unique values', (
    tester,
  ) async {
    final viewModel = _CounterViewModel(1);
    final allValues = <int>[];
    final uniqueValues = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MavericksProvider<_CounterViewModel>.value(
          value: viewModel,
          child: MavericksInvalidate<_CounterViewModel, _CounterState>(
            listeners: [
              onEach<_CounterState, int>(
                (state) => state.count,
                (context, count) => allValues.add(count),
                uniqueOnly: false,
              ),
              onEach<_CounterState, int>(
                (state) => state.count,
                (context, count) => uniqueValues.add(count),
                uniqueOnly: true,
              ),
            ],
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    viewModel.setLabel('updated');
    await tester.pump();
    await tester.pump();
    expect(allValues, [1]);
    expect(uniqueValues, isEmpty);

    viewModel.setCount(3);
    await tester.pump();
    await tester.pump();
    expect(allValues, [1, 3]);
    expect(uniqueValues, [3]);

    await viewModel.close();
  });

  testWidgets(
    'MavericksProvider keeps the owned view model across parent rebuilds',
    (tester) async {
      final hostKey = GlobalKey<_OwnedHostState>();

      await tester.pumpWidget(
        MaterialApp(
          home: _OwnedHost(key: hostKey, child: const _OwnedCounterBody()),
        ),
      );

      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      hostKey.currentState!.rebuildWithoutChangingProviderMode();
      await tester.pump();
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets('context.watch reads the provided view model', (tester) async {
    final viewModel = _CounterViewModel(7);

    await tester.pumpWidget(
      MaterialApp(
        home: MavericksProvider<_CounterViewModel>.value(
          value: viewModel,
          child: const _WatchingCounterBody(),
        ),
      ),
    );

    expect(find.text('7'), findsOneWidget);

    await viewModel.close();
  });
}

class _SwapHost extends StatefulWidget {
  const _SwapHost({
    required this.firstViewModel,
    required this.secondViewModel,
    required this.child,
    super.key,
  });

  final _CounterViewModel firstViewModel;
  final _CounterViewModel secondViewModel;
  final Widget child;

  @override
  State<_SwapHost> createState() => _SwapHostState();
}

class _SwapHostState extends State<_SwapHost> {
  var _useSecond = false;

  void swap() {
    setState(() {
      _useSecond = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MavericksProvider<_CounterViewModel>.value(
      value: _useSecond ? widget.secondViewModel : widget.firstViewModel,
      child: widget.child,
    );
  }
}

class _OwnedHost extends StatefulWidget {
  const _OwnedHost({required this.child, super.key});

  final Widget child;

  @override
  State<_OwnedHost> createState() => _OwnedHostState();
}

class _OwnedHostState extends State<_OwnedHost> {
  var _parentTick = 0;

  void rebuildWithoutChangingProviderMode() {
    setState(() {
      _parentTick += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MavericksProvider<_CounterViewModel>(
      create: () => _CounterViewModel(_parentTick + 1),
      child: widget.child,
    );
  }
}

class _OwnedCounterBody extends StatelessWidget {
  const _OwnedCounterBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          onPressed: () {
            final viewModel = context.read<_CounterViewModel>();
            viewModel.setCount(viewModel.state.count + 1);
          },
          icon: const Icon(Icons.add),
        ),
        MavericksInvalidate<_CounterViewModel, _CounterState>(
          builder: (context, state) {
            return Text('${state.count}', textDirection: TextDirection.ltr);
          },
        ),
      ],
    );
  }
}

class _WatchingCounterBody extends StatelessWidget {
  const _WatchingCounterBody();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<_CounterViewModel>();
    return Text('${viewModel.state.count}', textDirection: TextDirection.ltr);
  }
}

class _CounterViewModel extends MavericksViewModel<_CounterState> {
  _CounterViewModel(int count)
    : super(_CounterState(count: count, label: 'label-$count'));

  void setCount(int count) {
    setState((state) => state.copyWith(count: count));
  }

  void setLabel(String label) {
    setState((state) => state.copyWith(label: label));
  }
}

class _CounterState extends MavericksState<_CounterState> {
  const _CounterState({required this.count, required this.label});

  final int count;
  final String label;

  _CounterState copyWith({int? count, String? label}) {
    return _CounterState(
      count: count ?? this.count,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _CounterState &&
        other.count == count &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(count, label);
}
