package com.sanogueralorenzo.voice.setup

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
import com.sanogueralorenzo.voice.keyboard.VoiceKeyboardStatusReader
import com.sanogueralorenzo.voice.models.LocalModelsRepository
import com.sanogueralorenzo.voice.overlay.OverlayRepository
import com.sanogueralorenzo.voice.product.VoiceInputType
import com.sanogueralorenzo.voice.product.VoiceInputTypePreferences
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

data class VoiceSetupStatus(
    val loading: Boolean = true,
    val modelsReady: Boolean = false,
    val microphoneAllowed: Boolean = false,
    val overlayServiceEnabled: Boolean = false,
    val keyboardEnabled: Boolean = false,
    val keyboardSelected: Boolean = false,
    val inputType: VoiceInputType? = null
) {
    val ready: Boolean
        get() = modelsReady && microphoneAllowed && when (inputType) {
            VoiceInputType.KEYBOARD -> keyboardSelected
            VoiceInputType.OVERLAY -> overlayServiceEnabled
            null -> false
        }
}

/** Single source of truth for setup requirements shared by Home and Android settings callbacks. */
@Inject
@SingleIn(AppScope::class)
class VoiceSetupRepository(
    context: Context,
    private val overlayRepository: OverlayRepository,
    private val localModelsRepository: LocalModelsRepository,
    private val languagePreferences: DictationLanguagePreferences,
    private val inputTypePreferences: VoiceInputTypePreferences
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val refreshMutex = Mutex()
    private val mutableStatus = MutableStateFlow(VoiceSetupStatus())

    val status: StateFlow<VoiceSetupStatus> = mutableStatus.asStateFlow()

    private val settingsObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            refresh()
        }
    }

    init {
        listOf(
            Settings.Secure.DEFAULT_INPUT_METHOD,
            Settings.Secure.ENABLED_INPUT_METHODS,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ).forEach { setting ->
            appContext.contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(setting),
                false,
                settingsObserver
            )
        }
        scope.launch {
            localModelsRepository.status
                .map { it.downloadedLanguages }
                .distinctUntilChanged()
                .drop(1)
                .collect { refresh() }
        }
        refresh()
    }

    fun refresh() {
        scope.launch {
            refreshMutex.withLock {
                val nextStatus = withContext(Dispatchers.IO) {
                    val downloadedLanguages = localModelsRepository.readDownloadedLanguages()
                    val modelsReady = languagePreferences
                        .syncDownloaded(downloadedLanguages)
                        .isNotEmpty()
                    val keyboardStatus = VoiceKeyboardStatusReader.read(appContext)
                    VoiceSetupStatus(
                        loading = false,
                        modelsReady = modelsReady,
                        microphoneAllowed = overlayRepository.hasRecordAudioPermission(),
                        overlayServiceEnabled = overlayRepository.isAccessibilityServiceEnabled(),
                        keyboardEnabled = keyboardStatus.enabled,
                        keyboardSelected = keyboardStatus.selected,
                        inputType = inputTypePreferences.read()
                    )
                }
                syncOverlayEnabled(nextStatus.inputType)
                mutableStatus.value = nextStatus
            }
        }
    }

    fun selectInputType(inputType: VoiceInputType) {
        inputTypePreferences.write(inputType)
        syncOverlayEnabled(inputType)
        mutableStatus.value = mutableStatus.value.copy(inputType = inputType)
        refresh()
    }

    private fun syncOverlayEnabled(inputType: VoiceInputType?) {
        val enabled = inputType == VoiceInputType.OVERLAY
        if (overlayRepository.currentConfig().overlayEnabled != enabled) {
            overlayRepository.setOverlayEnabled(enabled)
        }
    }
}
