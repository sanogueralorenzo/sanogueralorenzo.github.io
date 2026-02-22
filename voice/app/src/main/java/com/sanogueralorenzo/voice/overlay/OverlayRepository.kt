package com.sanogueralorenzo.voice.overlay

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sanogueralorenzo.voice.setup.SetupRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

private val Context.overlayDataStore: DataStore<Preferences> by preferencesDataStore(
    name = OverlayRepository.DATASTORE_NAME
)

data class OverlayConfig(
    val overlayEnabled: Boolean,
    val positioningMode: Boolean,
    val bubbleX: Int,
    val bubbleY: Int
)

class OverlayRepository(
    context: Context,
    private val setupRepository: SetupRepository
) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.overlayDataStore
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val overlayEnabledState = MutableStateFlow(DEFAULT_OVERLAY_ENABLED)
    private val positioningModeState = MutableStateFlow(DEFAULT_POSITIONING_MODE)
    private val bubbleXState = MutableStateFlow(DEFAULT_BUBBLE_X_PX)
    private val bubbleYState = MutableStateFlow(DEFAULT_BUBBLE_Y_PX)

    init {
        val initialSnapshot = runBlocking { dataStore.data.first() }
        overlayEnabledState.value = initialSnapshot[KEY_OVERLAY_ENABLED] ?: DEFAULT_OVERLAY_ENABLED
        positioningModeState.value = initialSnapshot[KEY_POSITIONING_MODE] ?: DEFAULT_POSITIONING_MODE
        bubbleXState.value = initialSnapshot[KEY_BUBBLE_X] ?: DEFAULT_BUBBLE_X_PX
        bubbleYState.value = initialSnapshot[KEY_BUBBLE_Y] ?: DEFAULT_BUBBLE_Y_PX

        scope.launch {
            dataStore.data.collectLatest { prefs ->
                overlayEnabledState.value = prefs[KEY_OVERLAY_ENABLED] ?: DEFAULT_OVERLAY_ENABLED
                positioningModeState.value = prefs[KEY_POSITIONING_MODE] ?: DEFAULT_POSITIONING_MODE
                bubbleXState.value = prefs[KEY_BUBBLE_X] ?: DEFAULT_BUBBLE_X_PX
                bubbleYState.value = prefs[KEY_BUBBLE_Y] ?: DEFAULT_BUBBLE_Y_PX
            }
        }
    }

    fun currentConfig(): OverlayConfig {
        return OverlayConfig(
            overlayEnabled = overlayEnabledState.value,
            positioningMode = positioningModeState.value,
            bubbleX = bubbleXState.value,
            bubbleY = bubbleYState.value
        )
    }

    fun setOverlayEnabled(enabled: Boolean) {
        overlayEnabledState.value = enabled
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_OVERLAY_ENABLED] = enabled
            }
        }
    }

    fun setPositioningMode(enabled: Boolean) {
        positioningModeState.value = enabled
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_POSITIONING_MODE] = enabled
            }
        }
    }

    fun setBubblePosition(x: Int, y: Int) {
        bubbleXState.value = x
        bubbleYState.value = y
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_BUBBLE_X] = x
                prefs[KEY_BUBBLE_Y] = y
            }
        }
    }

    fun resetBubblePosition() {
        setBubblePosition(DEFAULT_BUBBLE_X_PX, DEFAULT_BUBBLE_Y_PX)
    }

    fun hasRecordAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun isAccessibilityServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getInt(
            appContext.contentResolver,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            0
        ) == 1
        if (!enabled) return false

        val enabledServices = Settings.Secure.getString(
            appContext.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ).orEmpty()
        if (enabledServices.isBlank()) return false

        val serviceId = ComponentName(appContext, OverlayAccessibilityService::class.java).flattenToString()
        return enabledServices
            .split(':')
            .any { it.equals(serviceId, ignoreCase = true) }
    }

    fun isVoiceImeSelected(): Boolean {
        return setupRepository.keyboardStatus().selected
    }

    companion object {
        internal const val DATASTORE_NAME = "overlay_store"

        private val KEY_OVERLAY_ENABLED = booleanPreferencesKey("overlay_enabled")
        private val KEY_POSITIONING_MODE = booleanPreferencesKey("overlay_positioning_mode")
        private val KEY_BUBBLE_X = intPreferencesKey("overlay_bubble_x")
        private val KEY_BUBBLE_Y = intPreferencesKey("overlay_bubble_y")

        private const val DEFAULT_OVERLAY_ENABLED = false
        private const val DEFAULT_POSITIONING_MODE = false
        private const val DEFAULT_BUBBLE_X_PX = 24
        private const val DEFAULT_BUBBLE_Y_PX = 520
    }
}
