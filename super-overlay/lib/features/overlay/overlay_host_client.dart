import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_overlay/pigeon/overlay_api.g.dart' as pigeon;

class OverlayNativeState {
  const OverlayNativeState({
    required this.supported,
    required this.bridgeAvailable,
    required this.overlayPermissionGranted,
    required this.notificationPermissionGranted,
    required this.overlayRunning,
    required this.bubbleEnabled,
    required this.bubbleAccessibilityEnabled,
  });

  const OverlayNativeState.unsupported()
    : supported = false,
      bridgeAvailable = false,
      overlayPermissionGranted = false,
      notificationPermissionGranted = false,
      overlayRunning = false,
      bubbleEnabled = false,
      bubbleAccessibilityEnabled = false;

  final bool supported;
  final bool bridgeAvailable;
  final bool overlayPermissionGranted;
  final bool notificationPermissionGranted;
  final bool overlayRunning;
  final bool bubbleEnabled;
  final bool bubbleAccessibilityEnabled;
}

class OverlayHostClient {
  OverlayHostClient({pigeon.OverlayHostApi? api})
    : _api = api ?? pigeon.OverlayHostApi();

  final pigeon.OverlayHostApi _api;

  bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<OverlayNativeState> loadState() async {
    if (!_isSupported) {
      return const OverlayNativeState.unsupported();
    }
    try {
      final state = await _api.getOverlayState();
      return OverlayNativeState(
        supported: true,
        bridgeAvailable: true,
        overlayPermissionGranted: state.overlayPermissionGranted,
        notificationPermissionGranted: state.notificationPermissionGranted,
        overlayRunning: state.overlayRunning,
        bubbleEnabled: state.bubbleEnabled,
        bubbleAccessibilityEnabled: state.bubbleAccessibilityEnabled,
      );
    } on PlatformException {
      return const OverlayNativeState(
        supported: true,
        bridgeAvailable: false,
        overlayPermissionGranted: false,
        notificationPermissionGranted: false,
        overlayRunning: false,
        bubbleEnabled: false,
        bubbleAccessibilityEnabled: false,
      );
    }
  }

  Future<String?> openOverlaySettings() => _run(_api.openOverlaySettings);

  Future<String?> openNotificationSettings() =>
      _run(_api.openNotificationSettings);

  Future<String?> openAccessibilitySettings() =>
      _run(_api.openAccessibilitySettings);

  Future<String?> setBubbleEnabled(bool enabled) =>
      _run(() => _api.setBubbleEnabled(enabled));

  Future<String?> startOverlay() => _run(_api.startOverlay);

  Future<String?> stopOverlay() => _run(_api.stopOverlay);

  Future<String?> _run(Future<void> Function() operation) async {
    if (!_isSupported) {
      return 'Overlay controls are only available on Android.';
    }
    try {
      await operation();
      return null;
    } on PlatformException catch (error) {
      return error.message ?? error.code;
    }
  }
}
