package com.sanogueralorenzo.overlay

import android.content.Context
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.flow.Flow

@Inject
@SingleIn(AppScope::class)
class SettingsRepository(context: Context) {
    private val appContext = context.applicationContext

    fun autoLockMinutesFlow(): Flow<Int> = OverlayPrefs.autoLockMinutesFlow(appContext)

    suspend fun readAutoLockMinutes(): Int = OverlayPrefs.readAutoLockMinutes(appContext)

    fun tileAddedFlow(): Flow<Boolean> = OverlayPrefs.tileAddedFlow(appContext)

    fun autoTimeoutTileAddedFlow(): Flow<Boolean> = OverlayPrefs.autoTimeoutTileAddedFlow(appContext)

    fun longPressDismissEnabledFlow(): Flow<Boolean> =
        OverlayPrefs.longPressDismissEnabledFlow(appContext)

    suspend fun setAutoLockMinutes(minutes: Int) {
        OverlayPrefs.setAutoLockMinutes(appContext, minutes)
    }

    suspend fun setTileAdded(added: Boolean) {
        OverlayPrefs.setTileAdded(appContext, added)
    }

    suspend fun setAutoTimeoutTileAdded(added: Boolean) {
        OverlayPrefs.setAutoTimeoutTileAdded(appContext, added)
    }

    suspend fun setLongPressDismissEnabled(enabled: Boolean) {
        OverlayPrefs.setLongPressDismissEnabled(appContext, enabled)
    }
}
