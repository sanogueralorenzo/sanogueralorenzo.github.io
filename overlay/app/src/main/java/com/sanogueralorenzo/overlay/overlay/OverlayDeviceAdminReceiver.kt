package com.sanogueralorenzo.overlay.overlay

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import com.sanogueralorenzo.overlay.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class OverlayDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)

    }
    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        CoroutineScope(Dispatchers.IO).launch {
            SettingsRepository(context).setAutoLockMinutes(0)
        }
    }
}
