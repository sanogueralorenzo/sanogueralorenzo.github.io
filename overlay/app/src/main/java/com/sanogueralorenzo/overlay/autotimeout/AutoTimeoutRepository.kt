package com.sanogueralorenzo.overlay.autotimeout

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import com.sanogueralorenzo.overlay.SettingsRepository
import com.sanogueralorenzo.overlay.overlay.OverlayDeviceAdminReceiver
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.flow.Flow

@Inject
@SingleIn(AppScope::class)
class AutoTimeoutRepository(
    context: Context,
    private val settingsRepository: SettingsRepository
) {
    private val appContext = context.applicationContext

    fun autoLockMinutesFlow(): Flow<Int> = settingsRepository.autoLockMinutesFlow()

    suspend fun readAutoLockMinutes(): Int = settingsRepository.readAutoLockMinutes()

    fun tileAddedFlow(): Flow<Boolean> = settingsRepository.autoTimeoutTileAddedFlow()

    suspend fun setAutoLockMinutes(minutes: Int) {
        settingsRepository.setAutoLockMinutes(minutes)
    }

    suspend fun setTileAdded(added: Boolean) {
        settingsRepository.setAutoTimeoutTileAdded(added)
    }

    fun isDeviceAdminActive(): Boolean {
        val dpm = appContext.getSystemService(DevicePolicyManager::class.java) ?: return false
        val component = ComponentName(appContext, OverlayDeviceAdminReceiver::class.java)
        return dpm.isAdminActive(component)
    }
}
