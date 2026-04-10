import 'package:pigeon/pigeon.dart';

class OverlayState {
  OverlayState({
    required this.overlayPermissionGranted,
    required this.notificationPermissionGranted,
    required this.overlayRunning,
    required this.bubbleEnabled,
    required this.bubbleAccessibilityEnabled,
  });

  bool overlayPermissionGranted;
  bool notificationPermissionGranted;
  bool overlayRunning;
  bool bubbleEnabled;
  bool bubbleAccessibilityEnabled;
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

  void openAccessibilitySettings();

  void setBubbleEnabled(bool enabled);

  void startOverlay();

  void stopOverlay();
}
