import 'package:app/src/di/injector.dart';
import 'package:app/src/features/example/example_screen.dart';
import 'package:app/src/features/example/example_view_model.dart';
import 'package:app/src/mavericks/mavericks_widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

part 'app_router.g.dart';

abstract final class AppRouter {
  static GoRouter createRouter() {
    return GoRouter(routes: $appRoutes);
  }
}

@TypedGoRoute<ExampleRoute>(path: '/')
class ExampleRoute extends GoRouteData with $ExampleRoute {
  const ExampleRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return MavericksProvider<ExampleViewModel>(
      create: () => Injector.get<ExampleViewModel>()..load(),
      child: const ExampleScreen(),
    );
  }
}
