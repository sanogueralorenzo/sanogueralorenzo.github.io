import 'package:app/src/mavericks/mavericks_state.dart';
import 'package:app/src/mavericks/mavericks_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> expectViewModelStates<
  VM extends MavericksViewModel<S>,
  S extends MavericksState<S>
>(
  VM viewModel, {
  required Future<void> Function(VM viewModel) act,
  required List<Object?> expected,
}) async {
  final states = <S>[];
  final subscription = viewModel.stream.listen(states.add);

  await act(viewModel);
  await Future<void>.delayed(Duration.zero);

  expect(states, expected);

  await subscription.cancel();
  await viewModel.close();
}
