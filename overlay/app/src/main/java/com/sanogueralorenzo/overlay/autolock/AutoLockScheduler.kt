package com.sanogueralorenzo.overlay.autolock

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import com.sanogueralorenzo.overlay.SettingsRepository
import com.sanogueralorenzo.overlay.overlay.OverlayDeviceAdminReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class AutoLockScheduler(
    context: Context,
    private val handler: Handler,
    private val settingsRepository: SettingsRepository,
    private val serviceScope: CoroutineScope,
    private val stopSelf: () -> Unit,
    private val stopOnInvalidConfig: Boolean
) {
    private val appContext = context.applicationContext
    private var lockRunnable: Runnable? = null

    fun start() {
        serviceScope.launch {
            settingsRepository.autoLockMinutesFlow().collect { minutes ->
                handler.post {
                    lockRunnable?.let { handler.removeCallbacks(it) }
                    lockRunnable = null
                    if (minutes <= 0) {
                        if (stopOnInvalidConfig) {
                            stopSelf()
                        }
                        return@post
                    }
                    val dpm = appContext.getSystemService(DevicePolicyManager::class.java)
                    if (dpm == null) {
                        if (stopOnInvalidConfig) {
                            stopSelf()
                        }
                        return@post
                    }
                    val admin = ComponentName(appContext, OverlayDeviceAdminReceiver::class.java)
                    if (!dpm.isAdminActive(admin)) {
                        if (stopOnInvalidConfig) {
                            stopSelf()
                        }
                        return@post
                    }
                    lockRunnable = Runnable {
                        val currentDpm = appContext.getSystemService(DevicePolicyManager::class.java)
                        val currentAdmin = ComponentName(
                            appContext,
                            OverlayDeviceAdminReceiver::class.java
                        )
                        if (currentDpm?.isAdminActive(currentAdmin) != true) {
                            stopSelf()
                            return@Runnable
                        }
                        try {
                            currentDpm.lockNow()
                        } catch (_: SecurityException) {
                            stopSelf()
                            return@Runnable
                        }
                        stopSelf()
                    }
                    handler.postDelayed(lockRunnable!!, minutes.toLong() * 60_000L)
                }
            }
        }
    }

    fun clear() {
        lockRunnable?.let { handler.removeCallbacks(it) }
        lockRunnable = null
    }
}
