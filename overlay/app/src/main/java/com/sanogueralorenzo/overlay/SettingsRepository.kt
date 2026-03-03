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

    fun tileAddedFlow(): Flow<Boolean> = OverlayPrefs.tileAddedFlow(appContext)

    suspend fun setTileAdded(added: Boolean) {
        OverlayPrefs.setTileAdded(appContext, added)
    }
}
