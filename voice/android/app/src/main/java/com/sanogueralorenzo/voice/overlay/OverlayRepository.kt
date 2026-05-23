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
import com.sanogueralorenzo.voice.setup.SetupRepository
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
    val bubbleSizeDp: Int
)

class OverlayRepository(
    context: Context,
    private val setupRepository: SetupRepository
) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.overlayDataStore
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val overlayEnabledState = MutableStateFlow(DEFAULT_OVERLAY_ENABLED)
    private val bubbleXState = sharedBubbleXState
    private val bubbleYState = sharedBubbleYState
    private val bubbleSizeDpState = sharedBubbleSizeDpState

    init {
        val initialSnapshot = runBlocking { dataStore.data.first() }
        overlayEnabledState.value = initialSnapshot[KEY_OVERLAY_ENABLED] ?: DEFAULT_OVERLAY_ENABLED
        bubbleXState.value = initialSnapshot[KEY_BUBBLE_X] ?: DEFAULT_BUBBLE_X_PX
        bubbleYState.value = initialSnapshot[KEY_BUBBLE_Y] ?: DEFAULT_BUBBLE_Y_PX
        bubbleSizeDpState.value = initialSnapshot[KEY_BUBBLE_SIZE_DP] ?: DEFAULT_BUBBLE_SIZE_DP

        scope.launch {
            dataStore.data.collectLatest { prefs ->
                overlayEnabledState.value = prefs[KEY_OVERLAY_ENABLED] ?: DEFAULT_OVERLAY_ENABLED
                bubbleXState.value = prefs[KEY_BUBBLE_X] ?: DEFAULT_BUBBLE_X_PX
                bubbleYState.value = prefs[KEY_BUBBLE_Y] ?: DEFAULT_BUBBLE_Y_PX
                bubbleSizeDpState.value = prefs[KEY_BUBBLE_SIZE_DP] ?: DEFAULT_BUBBLE_SIZE_DP
            }
        }
    }

    fun currentConfig(): OverlayConfig {
        return OverlayConfig(
            overlayEnabled = overlayEnabledState.value,
            bubbleX = bubbleXState.value,
            bubbleY = bubbleYState.value,
            bubbleSizeDp = bubbleSizeDpState.value
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
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_BUBBLE_X] = clampedX
                prefs[KEY_BUBBLE_Y] = clampedY
            }
        }
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

    fun adjustBubbleSizeDp(deltaDp: Int): Int {
        return setBubbleSizeDp(bubbleSizeDpState.value + deltaDp)
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            appContext.resources.displayMetrics
        ).roundToInt()
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
        private val KEY_BUBBLE_X = intPreferencesKey("overlay_bubble_x")
        private val KEY_BUBBLE_Y = intPreferencesKey("overlay_bubble_y")
        private val KEY_BUBBLE_SIZE_DP = intPreferencesKey("overlay_bubble_size_dp")

        private const val DEFAULT_OVERLAY_ENABLED = false
        private const val DEFAULT_BUBBLE_X_PX = 24
        private const val DEFAULT_BUBBLE_Y_PX = 520
        private const val DEFAULT_BUBBLE_SIZE_DP = 32
        private const val MIN_BUBBLE_SIZE_DP = 32
        private const val MAX_BUBBLE_SIZE_DP = 96

        // Shared across repository instances (UI + service) so size changes propagate immediately.
        private val sharedBubbleXState = MutableStateFlow(DEFAULT_BUBBLE_X_PX)
        private val sharedBubbleYState = MutableStateFlow(DEFAULT_BUBBLE_Y_PX)
        private val sharedBubbleSizeDpState = MutableStateFlow(DEFAULT_BUBBLE_SIZE_DP)
    }
}
