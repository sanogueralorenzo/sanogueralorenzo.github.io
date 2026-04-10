import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_overlay/features/login/data/login_models.dart';
import 'package:super_overlay/features/login/data/login_repository.dart';
import 'package:super_overlay/features/login/login_screen.dart';
import 'package:super_overlay/features/login/login_view_model.dart';
import 'package:super_overlay/main.dart';
import 'package:super_overlay/mavericks/mavericks_widgets.dart';

class _FakeLoginRepository implements LoginRepository {
  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    return LoginResponse(
      accessToken: 'fake-token',
      user: LoginUser(id: '1', name: 'Test User', email: email),
    );
  }
}

void main() {
  testWidgets('App opens on home screen by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SuperOverlayApp());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Open Login Example'), findsOneWidget);
  });

  testWidgets('Login screen enables submit once both fields are filled', (
    WidgetTester tester,
  ) async {
    final viewModel = LoginViewModelImpl(
      loginRepository: _FakeLoginRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MavericksProvider<LoginViewModel>.value(
          value: viewModel,
          child: const LoginScreen(),
        ),
      ),
    );

    expect(find.text('Login Example'), findsOneWidget);

    final loginButtonFinder = find.widgetWithText(FilledButton, 'Login');
    expect(tester.widget<FilledButton>(loginButtonFinder).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'person@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.pump();

    expect(tester.widget<FilledButton>(loginButtonFinder).onPressed, isNotNull);

    await viewModel.close();
  });
}
