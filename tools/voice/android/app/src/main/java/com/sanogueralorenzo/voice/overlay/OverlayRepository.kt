package com.sanogueralorenzo.voice.overlay

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import android.util.TypedValue
import androidx.core.content.ContextCompat
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlin.math.roundToInt

private val Context.overlayDataStore: DataStore<Preferences> by preferencesDataStore(
    name = OverlayRepository.DATASTORE_NAME
)

data class OverlayConfig(
    val overlayEnabled: Boolean,
    val bubbleX: Int,
    val bubbleY: Int,
    val bubbleSizeDp: Int,
    val hasCustomBubblePosition: Boolean
)

class OverlayRepository(context: Context) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.overlayDataStore
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val overlayEnabledState = MutableStateFlow(DEFAULT_OVERLAY_ENABLED)
    private val bubbleXState = sharedBubbleXState
    private val bubbleYState = sharedBubbleYState
    private val bubbleSizeDpState = sharedBubbleSizeDpState
    private val hasCustomBubblePositionState = sharedHasCustomBubblePositionState

    init {
        val initialSnapshot = runBlocking { dataStore.data.first() }
        overlayEnabledState.value = initialSnapshot[KEY_OVERLAY_ENABLED] ?: DEFAULT_OVERLAY_ENABLED
        applyStoredBubblePosition(initialSnapshot)
        bubbleSizeDpState.value = initialSnapshot[KEY_BUBBLE_SIZE_DP] ?: DEFAULT_BUBBLE_SIZE_DP

        scope.launch {
            dataStore.data.collectLatest { prefs ->
                overlayEnabledState.value = prefs[KEY_OVERLAY_ENABLED] ?: DEFAULT_OVERLAY_ENABLED
                applyStoredBubblePosition(prefs)
                bubbleSizeDpState.value = prefs[KEY_BUBBLE_SIZE_DP] ?: DEFAULT_BUBBLE_SIZE_DP
            }
        }
    }

    fun currentConfig(): OverlayConfig {
        return OverlayConfig(
            overlayEnabled = overlayEnabledState.value,
            bubbleX = bubbleXState.value,
            bubbleY = bubbleYState.value,
            bubbleSizeDp = bubbleSizeDpState.value,
            hasCustomBubblePosition = hasCustomBubblePositionState.value
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

    fun setBubblePosition(x: Int, y: Int) {
        val clampedX = x.coerceAtLeast(0)
        val clampedY = y.coerceAtLeast(0)
        bubbleXState.value = clampedX
        bubbleYState.value = clampedY
        hasCustomBubblePositionState.value = true
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_BUBBLE_X] = clampedX
                prefs[KEY_BUBBLE_Y] = clampedY
            }
        }
    }

    fun setDefaultBubblePosition(x: Int, y: Int) {
        if (hasCustomBubblePositionState.value) return
        bubbleXState.value = x.coerceAtLeast(0)
        bubbleYState.value = y.coerceAtLeast(0)
    }

    fun nudgeBubblePositionByDp(deltaXDp: Int, deltaYDp: Int) {
        val deltaXPx = dpToPx(deltaXDp)
        val deltaYPx = dpToPx(deltaYDp)
        setBubblePosition(
            x = bubbleXState.value + deltaXPx,
            y = bubbleYState.value + deltaYPx
        )
    }

    fun setBubbleSizeDp(sizeDp: Int): Int {
        val clamped = clampBubbleSizeDp(sizeDp)
        bubbleSizeDpState.value = clamped
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_BUBBLE_SIZE_DP] = clamped
            }
        }
        return clamped
    }

    fun bubbleSizeDpFlow(): StateFlow<Int> = bubbleSizeDpState.asStateFlow()
    fun bubbleXFlow(): StateFlow<Int> = bubbleXState.asStateFlow()
    fun bubbleYFlow(): StateFlow<Int> = bubbleYState.asStateFlow()

    fun clampBubbleSizeDp(sizeDp: Int): Int {
        return sizeDp.coerceIn(MIN_BUBBLE_SIZE_DP, MAX_BUBBLE_SIZE_DP)
    }

    fun adjustBubbleSizeDp(deltaDp: Int): OverlayConfig {
        val config = currentConfig()
        val newSizeDp = clampBubbleSizeDp(config.bubbleSizeDp + deltaDp)
        if (newSizeDp == config.bubbleSizeDp) return config
        if (config.hasCustomBubblePosition) {
            val oldSizePx = dpToPx(config.bubbleSizeDp)
            val newSizePx = dpToPx(newSizeDp)
            val positionShiftPx = (oldSizePx - newSizePx) / 2
            setBubblePosition(
                x = config.bubbleX + positionShiftPx,
                y = config.bubbleY + positionShiftPx
            )
        }
        setBubbleSizeDp(newSizeDp)
        return currentConfig()
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            appContext.resources.displayMetrics
        ).roundToInt()
    }

    private fun applyStoredBubblePosition(preferences: Preferences) {
        val storedX = preferences[KEY_BUBBLE_X]
        val storedY = preferences[KEY_BUBBLE_Y]
        if (storedX == null || storedY == null) {
            hasCustomBubblePositionState.value = false
            return
        }
        hasCustomBubblePositionState.value = true
        bubbleXState.value = storedX
        bubbleYState.value = storedY
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

    companion object {
        internal const val DATASTORE_NAME = "overlay_store"

        private val KEY_OVERLAY_ENABLED = booleanPreferencesKey("overlay_enabled")
        private val KEY_BUBBLE_X = intPreferencesKey("overlay_bubble_x")
        private val KEY_BUBBLE_Y = intPreferencesKey("overlay_bubble_y")
        private val KEY_BUBBLE_SIZE_DP = intPreferencesKey("overlay_bubble_size_dp")

        private const val DEFAULT_OVERLAY_ENABLED = false
        private const val DEFAULT_BUBBLE_SIZE_DP = 36
        private const val MIN_BUBBLE_SIZE_DP = 32
        private const val MAX_BUBBLE_SIZE_DP = 96

        // Shared across repository instances (UI + service) so size changes propagate immediately.
        private val sharedBubbleXState = MutableStateFlow(0)
        private val sharedBubbleYState = MutableStateFlow(0)
        private val sharedBubbleSizeDpState = MutableStateFlow(DEFAULT_BUBBLE_SIZE_DP)
        private val sharedHasCustomBubblePositionState = MutableStateFlow(false)
    }
}
