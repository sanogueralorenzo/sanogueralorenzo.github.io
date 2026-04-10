package com.example.super_overlay.bridge

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.super_overlay.overlay.BubbleOverlayAccessibilityService
import com.example.super_overlay.overlay.BubbleOverlayPreferences
import com.example.super_overlay.overlay.OverlayService
import com.example.super_overlay.pigeon.FlutterError
import com.example.super_overlay.pigeon.OverlayHostApi
import com.example.super_overlay.pigeon.OverlayState

class OverlayHostApiBridge(
    private val context: Context
) : OverlayHostApi {

    override fun getOverlayState(): OverlayState {
        return OverlayState(
            overlayPermissionGranted = Settings.canDrawOverlays(context),
            notificationPermissionGranted = isNotificationPermissionGranted(),
            overlayRunning = OverlayService.isRunning,
            bubbleEnabled = BubbleOverlayPreferences.isEnabled(context),
            bubbleAccessibilityEnabled = isBubbleAccessibilityEnabled()
        )
    }

    override fun openOverlaySettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}")
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    override fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}")
            )
        }.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    override fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    override fun setBubbleEnabled(enabled: Boolean) {
        BubbleOverlayPreferences.setEnabled(context, enabled)
        BubbleOverlayAccessibilityService.requestRefresh(context)
    }

    override fun startOverlay() {
        if (!Settings.canDrawOverlays(context)) {
            throw FlutterError(
                code = "overlay_permission_denied",
                message = "Display over other apps permission is required.",
                details = null
            )
        }
        val intent = Intent(context, OverlayService::class.java)
        ContextCompat.startForegroundService(context, intent)
    }

    override fun stopOverlay() {
        val intent = Intent(context, OverlayService::class.java)
        context.stopService(intent)
    }

    private fun isNotificationPermissionGranted(): Boolean {
        val notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return notificationsEnabled
        }
        val runtimeGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        return runtimeGranted && notificationsEnabled
    }

    private fun isBubbleAccessibilityEnabled(): Boolean {
        val accessibilityEnabled = Settings.Secure.getInt(
            context.contentResolver,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            0
        ) == 1
        if (!accessibilityEnabled) {
            return false
        }
        val enabledServices = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ).orEmpty()
        if (enabledServices.isBlank()) {
            return false
        }
        val serviceId = ComponentName(
            context,
            BubbleOverlayAccessibilityService::class.java
        ).flattenToString()
        return enabledServices
            .split(':')
            .any { it.equals(serviceId, ignoreCase = true) }
    }
}
