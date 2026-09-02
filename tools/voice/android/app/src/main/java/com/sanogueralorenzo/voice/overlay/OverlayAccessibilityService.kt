package com.sanogueralorenzo.voice.overlay

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.Intent
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.Toast
import androidx.core.content.ContextCompat
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.audio.DictationLanguage
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
import com.sanogueralorenzo.voice.audio.MoonshineMicTranscriber
import com.sanogueralorenzo.voice.dictation.DictationSession
import com.sanogueralorenzo.voice.keyboard.VoiceKeyboardStatusReader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class OverlayAccessibilityService : AccessibilityService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var activeRecording: OverlayRecording? = null

    private var systemDialogReceiverRegistered = false
    private var imeSettingsObserverRegistered = false
    private var keyboardCloseStopScheduled = false
    private val keyboardCloseStopRunnable = Runnable {
        keyboardCloseStopScheduled = false
        if (!isInputMethodWindowVisible()) {
            stopRecordingAndProcess()
            evaluateOverlayVisibility()
        }
    }

    private val systemDialogReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_CLOSE_SYSTEM_DIALOGS,
                Intent.ACTION_SCREEN_OFF -> {
                    cancelRecordingIfActive()
                }
            }
        }
    }
    private val imeSettingsObserver = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean) {
            evaluateOverlayVisibility()
        }
    }

    private val overlayRepository by lazy(LazyThreadSafetyMode.NONE) {
        (application as VoiceApp).appGraph.overlayRepository
    }
    private val languagePreferences by lazy(LazyThreadSafetyMode.NONE) {
        DictationLanguagePreferences(this)
    }
    private val editor by lazy(LazyThreadSafetyMode.NONE) { AccessibilityEditor(this) }
    private val recordingForeground by lazy(LazyThreadSafetyMode.NONE) {
        OverlayRecordingForeground(this)
    }
    private val windowController by lazy(LazyThreadSafetyMode.NONE) {
        OverlayWindowController(
            service = this,
            repository = overlayRepository,
            onTap = ::onBubbleTapped,
            onLongPress = {
                if (!dictationSession.isActive) {
                    startRecording(languagePreferences.secondaryOrPrimary())
                    true
                } else {
                    false
                }
            }
        )
    }
    private val dictationSession by lazy(LazyThreadSafetyMode.NONE) {
        DictationSession(
            transcriber = MoonshineMicTranscriber(this),
            listener = object : DictationSession.Listener {
                override fun onTextChanged(text: String) {
                    editor.replaceText(text)
                }

                override fun onCompleted(result: DictationSession.Result) {
                    activeRecording = null
                    if (result.hasTranscript && !editor.replaceText(result.text)) {
                        showToast(getString(R.string.overlay_commit_failed))
                    }
                    recordingForeground.stop()
                    evaluateOverlayVisibility()
                }

                override fun onCancelled() {
                    restoreOriginalText()
                    recordingForeground.stop()
                    evaluateOverlayVisibility()
                }

                override fun onError(error: Throwable?) {
                    if (error != null) {
                        android.util.Log.w(TAG, "Moonshine overlay recording failed", error)
                    }
                    restoreOriginalText()
                    recordingForeground.stop()
                    evaluateOverlayVisibility()
                    showToast(getString(R.string.overlay_recording_start_failed))
                }
            }
        )
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        runningService = this
        registerSystemDialogReceiverIfNeeded()
        registerImeSettingsObserverIfNeeded()
        windowController.observeSettings(serviceScope)
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOWS_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = flags or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
            notificationTimeout = 0
        }
        warmupMoonshine()
        serviceScope.launch {
            overlayRepository.readConfig()
            evaluateOverlayVisibility()
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        evaluateOverlayVisibility()
    }

    override fun onKeyEvent(event: KeyEvent?): Boolean {
        if (event?.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_BACK) {
            stopRecordingAndProcess()
        }
        return super.onKeyEvent(event)
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (runningService === this) {
            runningService = null
        }
        serviceScope.cancel()
        cancelKeyboardCloseStop()
        unregisterSystemDialogReceiverIfNeeded()
        unregisterImeSettingsObserverIfNeeded()
        recordingForeground.stop()
        activeRecording?.let { editor.replaceText(it.originalText) }
        activeRecording = null
        dictationSession.destroy()
        windowController.hide()
        super.onDestroy()
    }

    private fun evaluateOverlayVisibility() {
        val config = overlayRepository.currentConfig()
        val inputMethodVisible = isInputMethodWindowVisible()
        if (inputMethodVisible || !dictationSession.isActive) {
            cancelKeyboardCloseStop()
        } else {
            scheduleKeyboardCloseStop()
        }
        val shouldShowByContext = config.overlayEnabled &&
            inputMethodVisible &&
            !positioningActive &&
            !VoiceKeyboardStatusReader.read(this).selected
        val shouldKeepVisibleForActiveWork = dictationSession.isActive
        val shouldShow = shouldShowByContext || shouldKeepVisibleForActiveWork

        if (shouldShow) {
            windowController.show(config)
        } else {
            windowController.hide()
        }
    }

    private fun isInputMethodWindowVisible(): Boolean {
        return windows.any { window ->
            window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
        }
    }

    private fun scheduleKeyboardCloseStop() {
        if (keyboardCloseStopScheduled) return
        keyboardCloseStopScheduled = true
        mainHandler.postDelayed(keyboardCloseStopRunnable, KEYBOARD_CLOSE_CONFIRMATION_MS)
    }

    private fun cancelKeyboardCloseStop() {
        if (!keyboardCloseStopScheduled) return
        mainHandler.removeCallbacks(keyboardCloseStopRunnable)
        keyboardCloseStopScheduled = false
    }

    private fun cancelRecordingIfActive() {
        stopRecordingDiscard()
    }

    private fun registerSystemDialogReceiverIfNeeded() {
        if (systemDialogReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        val registered = runCatching {
            ContextCompat.registerReceiver(
                this,
                systemDialogReceiver,
                filter,
                ContextCompat.RECEIVER_EXPORTED
            )
        }.isSuccess
        systemDialogReceiverRegistered = registered
    }

    private fun unregisterSystemDialogReceiverIfNeeded() {
        if (!systemDialogReceiverRegistered) return
        runCatching { unregisterReceiver(systemDialogReceiver) }
        systemDialogReceiverRegistered = false
    }

    private fun registerImeSettingsObserverIfNeeded() {
        if (imeSettingsObserverRegistered) return
        val registered = runCatching {
            contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(Settings.Secure.DEFAULT_INPUT_METHOD),
                false,
                imeSettingsObserver
            )
            contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(Settings.Secure.ENABLED_INPUT_METHODS),
                false,
                imeSettingsObserver
            )
        }.isSuccess
        imeSettingsObserverRegistered = registered
    }

    private fun unregisterImeSettingsObserverIfNeeded() {
        if (!imeSettingsObserverRegistered) return
        runCatching { contentResolver.unregisterContentObserver(imeSettingsObserver) }
        imeSettingsObserverRegistered = false
    }

    private fun onBubbleTapped() {
        if (!dictationSession.isActive) {
            startRecording(languagePreferences.primary())
        } else if (dictationSession.state == DictationSession.State.RECORDING) {
            stopRecordingAndProcess()
        }
    }

    private fun stopRecordingAndProcess(): Boolean {
        cancelKeyboardCloseStop()
        return dictationSession.stop()
    }

    private fun startRecording(language: DictationLanguage) {
        if (dictationSession.isActive || activeRecording != null) return
        if (!overlayRepository.hasRecordAudioPermission()) {
            showToast(getString(R.string.overlay_microphone_required))
            return
        }
        if (!dictationSession.isReady(language)) {
            showToast(getString(R.string.overlay_asr_not_ready))
            return
        }

        val originalText = editor.readText()
        activeRecording = OverlayRecording(originalText)
        recordingForeground.start()
        if (!dictationSession.start(language = language, originalText = originalText)) {
            activeRecording = null
            recordingForeground.stop()
        }
    }

    private fun warmupMoonshine() {
        dictationSession.warmup(languagePreferences.primary())
    }

    private fun stopRecordingDiscard() {
        dictationSession.cancel()
    }

    private fun restoreOriginalText() {
        val recording = activeRecording ?: return
        activeRecording = null
        editor.replaceText(recording.originalText)
    }

    private fun showToast(message: String) {
        mainHandler.post {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
    }

    private data class OverlayRecording(val originalText: String)

    companion object {
        fun setPositioningActive(active: Boolean) {
            if (positioningActive == active) return
            positioningActive = active
            runningService?.mainHandler?.post {
                runningService?.evaluateOverlayVisibility()
            }
        }

        @Volatile
        private var runningService: OverlayAccessibilityService? = null
        @Volatile
        private var positioningActive: Boolean = false

        private const val KEYBOARD_CLOSE_CONFIRMATION_MS = 200L
        private const val TAG = "VoiceOverlay"
    }
}
