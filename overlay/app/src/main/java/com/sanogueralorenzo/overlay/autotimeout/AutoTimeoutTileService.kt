package com.sanogueralorenzo.overlay.autotimeout

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import com.sanogueralorenzo.overlay.R
import com.sanogueralorenzo.overlay.SettingsRepository
import com.sanogueralorenzo.overlay.overlay.OverlayDeviceAdminReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class AutoTimeoutTileService : TileService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val settingsRepository by lazy { SettingsRepository(applicationContext) }

    override fun onClick() {
        super.onClick()
        if (!isDeviceAdminActive()) {
            Toast.makeText(this, R.string.auto_timeout_requirements_message, Toast.LENGTH_SHORT).show()
            updateTileState()
            return
        }
        val intent = Intent(this, AutoTimeoutService::class.java)
        val isRunning = isServiceRunning()
        if (isRunning) {
            stopService(intent)
        } else {
            startForegroundService(intent)
        }
        AutoTimeoutService.requestTileUpdate(this)
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        serviceScope.launch {
            settingsRepository.setAutoTimeoutTileAdded(true)
        }
    }

    override fun onTileRemoved() {
        super.onTileRemoved()
        serviceScope.launch {
            settingsRepository.setAutoTimeoutTileAdded(false)
        }
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun updateTileState() {
        val active = isDeviceAdminActive()
        qsTile?.apply {
            state = when {
                !active -> Tile.STATE_UNAVAILABLE
                isServiceRunning() -> Tile.STATE_ACTIVE
                else -> Tile.STATE_INACTIVE
            }
            updateTile()
        }
    }

    private fun isDeviceAdminActive(): Boolean {
        val dpm = getSystemService(DevicePolicyManager::class.java) ?: return false
        val component = ComponentName(this, OverlayDeviceAdminReceiver::class.java)
        return dpm.isAdminActive(component)
    }

    private fun isServiceRunning(): Boolean {
        val manager = getSystemService(ActivityManager::class.java) ?: return false
        @Suppress("DEPRECATION")
        return manager.getRunningServices(Integer.MAX_VALUE).any { info ->
            info.service.className == AutoTimeoutService::class.java.name
        }
    }
}
