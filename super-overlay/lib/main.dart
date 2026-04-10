import 'package:flutter/material.dart';
import 'package:super_overlay/features/home/home_screen.dart';
import 'package:super_overlay/features/login/login_injector.dart';
import 'package:super_overlay/features/login/login_screen.dart';
import 'package:super_overlay/features/login/login_view_model.dart';
import 'package:super_overlay/mavericks/mavericks_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  runApp(const SuperOverlayApp());
}

class SuperOverlayApp extends StatelessWidget {
  const SuperOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Super Overlay',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: HomeScreen(
        onOpenLoginExample: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) {
                return MavericksProvider<LoginViewModel>(
                  create: () => injector.get<LoginViewModel>(),
                  child: const LoginScreen(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
