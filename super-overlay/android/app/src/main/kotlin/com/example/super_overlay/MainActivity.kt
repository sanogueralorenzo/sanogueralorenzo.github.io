package com.example.super_overlay

import com.example.super_overlay.bridge.OverlayHostApiBridge
import com.example.super_overlay.pigeon.OverlayHostApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OverlayHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            OverlayHostApiBridge(applicationContext)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        OverlayHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
