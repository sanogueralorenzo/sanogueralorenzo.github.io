package com.sanogueralorenzo.overlay.overlay

import android.app.ActivityManager
import android.content.Intent
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import com.sanogueralorenzo.overlay.R
import com.sanogueralorenzo.overlay.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class OverlayTileService : TileService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val settingsRepository by lazy { SettingsRepository(applicationContext) }

    override fun onClick() {
        super.onClick()
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, R.string.overlay_permission_needed, Toast.LENGTH_SHORT).show()
            updateTileState()
            return
        }
        val intent = Intent(this, OverlayService::class.java)
        val isRunning = isServiceRunning()
        if (isRunning) {
            stopService(intent)
        } else {
            startForegroundService(intent)
        }
        OverlayService.requestTileUpdate(this)
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        serviceScope.launch {
            settingsRepository.setTileAdded(true)
        }
    }

    override fun onTileRemoved() {
        super.onTileRemoved()
        serviceScope.launch {
            settingsRepository.setTileAdded(false)
        }
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun updateTileState() {
        val hasPermission = Settings.canDrawOverlays(this)
        qsTile?.apply {
            state = when {
                !hasPermission -> Tile.STATE_UNAVAILABLE
                isServiceRunning() -> Tile.STATE_ACTIVE
                else -> Tile.STATE_INACTIVE
            }
            updateTile()
        }
    }

    private fun isServiceRunning(): Boolean {
        val manager = getSystemService(ActivityManager::class.java) ?: return false
        @Suppress("DEPRECATION")
        return manager.getRunningServices(Integer.MAX_VALUE).any { info ->
            info.service.className == OverlayService::class.java.name
        }
    }
}
