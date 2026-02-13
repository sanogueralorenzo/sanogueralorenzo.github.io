package com.sanogueralorenzo.overlay.overlay

import android.content.Context
import android.provider.Settings
import com.sanogueralorenzo.overlay.SettingsRepository
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.flow.Flow

@Inject
@SingleIn(AppScope::class)
class OverlayRepository(
    context: Context,
    private val settingsRepository: SettingsRepository
) {
    private val appContext = context.applicationContext

    fun tileAddedFlow(): Flow<Boolean> = settingsRepository.tileAddedFlow()
    fun longPressDismissEnabledFlow(): Flow<Boolean> =
        settingsRepository.longPressDismissEnabledFlow()

    suspend fun setTileAdded(added: Boolean) {
        settingsRepository.setTileAdded(added)
    }

    suspend fun setLongPressDismissEnabled(enabled: Boolean) {
        settingsRepository.setLongPressDismissEnabled(enabled)
    }

    fun isOverlayGranted(): Boolean = Settings.canDrawOverlays(appContext)
}
