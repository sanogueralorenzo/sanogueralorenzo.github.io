package com.sanogueralorenzo.overlay.permissions

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.sanogueralorenzo.overlay.settings.SettingsRepository
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged

@Inject
@SingleIn(AppScope::class)
class PermissionsRepository(
    context: Context,
    private val settingsRepository: SettingsRepository
) {
    private val appContext = context.applicationContext
    private val packageName = appContext.packageName
    private val overlayPermissionState = MutableStateFlow(isOverlayPermissionGranted())
    private val notificationPermissionState = MutableStateFlow(isNotificationPermissionGranted())
    private val secureSettingsPermissionState = MutableStateFlow(isWriteSecureSettingsPermissionGranted())

    fun tileAddedFlow(): Flow<Boolean> = settingsRepository.tileAddedFlow()
    fun overlayPermissionFlow(): Flow<Boolean> = overlayPermissionState.asStateFlow()
    fun notificationPermissionFlow(): Flow<Boolean> = notificationPermissionState.asStateFlow()
    fun secureSettingsPermissionFlow(): Flow<Boolean> = secureSettingsPermissionState.asStateFlow()

    fun allRequirementsGrantedFlow(): Flow<Boolean> {
        return combine(
            tileAddedFlow(),
            overlayPermissionFlow(),
            notificationPermissionFlow(),
            secureSettingsPermissionFlow()
        ) { tileAdded, overlayGranted, notificationGranted, secureSettingsGranted ->
            tileAdded && overlayGranted && notificationGranted && secureSettingsGranted
        }.distinctUntilChanged()
    }

    suspend fun setTileAdded(added: Boolean) {
        settingsRepository.setTileAdded(added)
    }

    fun isOverlayPermissionGranted(): Boolean {
        return Settings.canDrawOverlays(appContext)
    }

    fun isNotificationPermissionGranted(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun isWriteSecureSettingsPermissionGranted(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.WRITE_SECURE_SETTINGS
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun refreshPermissionStates() {
        overlayPermissionState.value = isOverlayPermissionGranted()
        notificationPermissionState.value = isNotificationPermissionGranted()
        secureSettingsPermissionState.value = isWriteSecureSettingsPermissionGranted()
    }

    fun secureSettingsCommands(): SecureSettingsCommands {
        return SecureSettingsCommandFactory.create(packageName)
    }
}
