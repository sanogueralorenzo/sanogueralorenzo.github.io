package com.sanogueralorenzo.overlay.settings
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.flow.Flow

@Inject
@SingleIn(AppScope::class)
class SettingsRepository(
    private val overlayPrefs: OverlayPrefs
) {

    fun tileAddedFlow(): Flow<Boolean> = overlayPrefs.tileAddedFlow()

    suspend fun setTileAdded(added: Boolean) {
        overlayPrefs.setTileAdded(added)
    }
}
