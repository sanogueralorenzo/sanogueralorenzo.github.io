import 'package:flutter/material.dart';
import 'package:super_overlay/features/login/login_view_model.dart';
import 'package:super_overlay/mavericks/mavericks_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MavericksInvalidate<LoginViewModel, LoginState>(
      listeners: [
        onEach<LoginState, bool>((state) => state.isLoggedIn, (
          context,
          isLoggedIn,
        ) {
          if (!isLoggedIn) {
            return;
          }
          final text = context.read<LoginViewModel>().state.welcomeMessage;
          if (text == null) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(text)));
        }, uniqueOnly: true),
      ],
      builder: (context, state) {
        final viewModel = context.read<LoginViewModel>();

        return Scaffold(
          appBar: AppBar(title: const Text('Login Example')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Dio + Retrofit + Injector + Freezed',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: viewModel.updateEmail,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: !state.isPasswordVisible,
                    onChanged: viewModel.updatePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: viewModel.togglePasswordVisibility,
                        icon: Icon(
                          state.isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed:
                        state.isLoginButtonVisible &&
                            !state.loginRequest.isLoading
                        ? viewModel.login
                        : null,
                    child: state.loginRequest.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Login'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This uses placeholder API URL and endpoint /auth/login.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
