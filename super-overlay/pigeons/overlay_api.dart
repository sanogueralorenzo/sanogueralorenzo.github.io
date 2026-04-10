import 'package:pigeon/pigeon.dart';

class OverlayState {
  OverlayState({
    required this.overlayPermissionGranted,
    required this.notificationPermissionGranted,
    required this.overlayRunning,
  });

  bool overlayPermissionGranted;
  bool notificationPermissionGranted;
  bool overlayRunning;
}

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'super_overlay',
    dartOut: 'lib/pigeon/overlay_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/example/super_overlay/pigeon/OverlayApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.example.super_overlay.pigeon'),
    dartOptions: DartOptions(),
  ),
)
@HostApi()
abstract class OverlayHostApi {
  OverlayState getOverlayState();

  void openOverlaySettings();

  void openNotificationSettings();

  void startOverlay();

  void stopOverlay();
}
