import 'package:flutter/material.dart';
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
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.blue)),
      home: MavericksProvider<LoginViewModel>(
        create: () => injector.get<LoginViewModel>(),
        child: const LoginScreen(),
      ),
    );
  }
}
