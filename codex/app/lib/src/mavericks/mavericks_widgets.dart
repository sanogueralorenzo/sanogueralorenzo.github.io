import 'dart:async';

import 'package:app/src/mavericks/mavericks_state.dart';
import 'package:app/src/mavericks/mavericks_view_model.dart';
import 'package:flutter/material.dart';

typedef MavericksSelectedValueListener<V> =
    void Function(BuildContext context, V value);

sealed class MavericksListener<S extends MavericksState<S>> {
  const MavericksListener();

  void call(BuildContext context, S previous, S current);
}

final class _OnEachMavericksListener<S extends MavericksState<S>, V>
    extends MavericksListener<S> {
  const _OnEachMavericksListener({
    required this.selector,
    required this.onValue,
    required this.uniqueOnly,
  });

  final V Function(S state) selector;
  final MavericksSelectedValueListener<V> onValue;
  final bool uniqueOnly;

  @override
  void call(BuildContext context, S previous, S current) {
    final currentValue = selector(current);

    if (uniqueOnly) {
      final previousValue = selector(previous);
      if (previousValue == currentValue) return;
    }

    onValue(context, currentValue);
  }
}

MavericksListener<S> onEach<S extends MavericksState<S>, V>(
  V Function(S state) selector,
  MavericksSelectedValueListener<V> onValue, {
  required bool uniqueOnly,
}) {
  return _OnEachMavericksListener(
    selector: selector,
    onValue: onValue,
    uniqueOnly: uniqueOnly,
  );
}

class MavericksProvider<T extends MavericksViewModel<dynamic>>
    extends StatefulWidget {
  const MavericksProvider({
    required this.create,
    required this.child,
    super.key,
  }) : value = null;

  const MavericksProvider.value({
    required T this.value,
    required this.child,
    super.key,
  }) : create = null;

  final T Function()? create;
  final T? value;
  final Widget child;

  static T of<T extends MavericksViewModel<dynamic>>(
    BuildContext context, {
    bool listen = true,
  }) {
    final inherited = listen
        ? context.dependOnInheritedWidgetOfExactType<_MavericksScope<T>>()
        : context
                  .getElementForInheritedWidgetOfExactType<_MavericksScope<T>>()
                  ?.widget
              as _MavericksScope<T>?;

    assert(inherited != null, 'No MavericksProvider<$T> found in context.');
    return inherited!.viewModel;
  }

  @override
  State<MavericksProvider<T>> createState() => _MavericksProviderState<T>();
}

class _ProvidedViewModel<T extends MavericksViewModel<dynamic>> {
  const _ProvidedViewModel({
    required this.viewModel,
    required this.ownsViewModel,
  });

  factory _ProvidedViewModel.fromWidget(MavericksProvider<T> widget) {
    if (widget.create case final create?) {
      return _ProvidedViewModel(viewModel: create(), ownsViewModel: true);
    }

    return _ProvidedViewModel(viewModel: widget.value!, ownsViewModel: false);
  }

  final T viewModel;
  final bool ownsViewModel;

  static bool shouldReplace<T extends MavericksViewModel<dynamic>>(
    MavericksProvider<T> previous,
    MavericksProvider<T> current,
  ) {
    final previousOwnsViewModel = previous.create != null;
    final currentOwnsViewModel = current.create != null;

    if (previousOwnsViewModel && currentOwnsViewModel) return false;

    if (!previousOwnsViewModel && !currentOwnsViewModel) {
      return !identical(previous.value, current.value);
    }

    return true;
  }

  Future<void> dispose() async {
    if (!ownsViewModel) return;

    await viewModel.close();
  }
}

class _MavericksProviderState<T extends MavericksViewModel<dynamic>>
    extends State<MavericksProvider<T>> {
  late _ProvidedViewModel<T> _providedViewModel;

  @override
  void initState() {
    super.initState();
    _providedViewModel = _ProvidedViewModel.fromWidget(widget);
  }

  @override
  void didUpdateWidget(covariant MavericksProvider<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_ProvidedViewModel.shouldReplace(oldWidget, widget)) return;

    final previousProvidedViewModel = _providedViewModel;
    _providedViewModel = _ProvidedViewModel.fromWidget(widget);
    unawaited(previousProvidedViewModel.dispose());
  }

  @override
  void dispose() {
    unawaited(_providedViewModel.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MavericksScope<T>(
      viewModel: _providedViewModel.viewModel,
      child: widget.child,
    );
  }
}

extension MavericksBuildContext on BuildContext {
  T read<T extends MavericksViewModel<dynamic>>() {
    return MavericksProvider.of<T>(this, listen: false);
  }

  T watch<T extends MavericksViewModel<dynamic>>() {
    return MavericksProvider.of<T>(this);
  }
}

class _MavericksScope<T extends MavericksViewModel<dynamic>>
    extends InheritedWidget {
  const _MavericksScope({required this.viewModel, required super.child});

  final T viewModel;

  @override
  bool updateShouldNotify(_MavericksScope<T> oldWidget) {
    return oldWidget.viewModel != viewModel;
  }
}

class MavericksInvalidate<
  T extends MavericksViewModel<S>,
  S extends MavericksState<S>
>
    extends StatefulWidget {
  const MavericksInvalidate({
    required this.builder,
    this.listeners = const [],
    super.key,
  });

  final Widget Function(BuildContext context, S state) builder;
  final List<MavericksListener<S>> listeners;

  @override
  State<MavericksInvalidate<T, S>> createState() =>
      _MavericksInvalidateState<T, S>();
}

class _MavericksInvalidateState<
  T extends MavericksViewModel<S>,
  S extends MavericksState<S>
>
    extends State<MavericksInvalidate<T, S>> {
  StreamSubscription<S>? _subscription;
  late T _viewModel;
  late S _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextViewModel = MavericksProvider.of<T>(context);
    if (_subscription != null && identical(nextViewModel, _viewModel)) return;

    _subscription?.cancel();
    _viewModel = nextViewModel;
    _state = _viewModel.state;
    _subscription = _viewModel.stream.listen(_onStateChanged);
  }

  void _onStateChanged(S nextState) {
    final previousState = _state;
    _state = nextState;
    if (!mounted) return;

    for (final listener in widget.listeners) {
      listener.call(context, previousState, nextState);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _state);
  }
}
