package com.sanogueralorenzo.voice.keyboard

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.inputmethod.InputConnection
import android.widget.FrameLayout
import android.widget.Toast
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.sanogueralorenzo.voice.MainActivity
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.audio.DictationTextBuffer
import com.sanogueralorenzo.voice.audio.MoonshineMicTranscriber
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.math.max

/** Compact voice keyboard using the same Moonshine microphone transcriber as the overlay. */
class VoiceInputMethodService : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val transcriberExecutor = Executors.newSingleThreadExecutor()
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)
    private val moonshineTranscriber by lazy(LazyThreadSafetyMode.NONE) {
        MoonshineMicTranscriber(this)
    }

    private var nextSessionId = 0
    private var activeSession: RecordingSession? = null
    private var finishRecordingRunnable: Runnable? = null
    private var keyboardState by mutableStateOf(CompactKeyboardState())

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateRegistryController.savedStateRegistry

    override fun onCreate() {
        super.onCreate()
        savedStateRegistryController.performAttach()
        savedStateRegistryController.performRestore(null)
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        attachOwnersToWindowTree(null)
        warmupMoonshine()
    }

    override fun onCreateInputView(): View {
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        showIdle()
        val initialDarkTheme = isSystemDarkTheme()
        val backgroundColor = keyboardBackground(initialDarkTheme)
        applyNavigationBarTheme(initialDarkTheme, backgroundColor)
        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            setBackgroundColor(backgroundColor)
        }
        val composeView = ComposeView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            setBackgroundColor(backgroundColor)
            attachOwnersToWindowTree(this)
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
            setContent {
                val darkTheme = isSystemInDarkTheme()
                LaunchedEffect(darkTheme) {
                    applyNavigationBarTheme(darkTheme, keyboardBackground(darkTheme))
                }
                VoiceTheme(darkTheme = darkTheme, dynamicColor = false) {
                    CompactKeyboardContent(
                        state = keyboardState,
                        isDarkTheme = darkTheme,
                        onIdleTap = ::startRecording,
                        onDiscardTap = ::discardRecording,
                        onSendTap = ::stopRecording
                    )
                }
            }
        }
        container.addView(composeView)
        attachOwnersToWindowTree(container)
        ViewCompat.setOnApplyWindowInsetsListener(container) { _, insets ->
            updateBottomInset(insets)
            insets
        }
        container.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                updateBottomInset(ViewCompat.getRootWindowInsets(view))
                ViewCompat.requestApplyInsets(view)
            }

            override fun onViewDetachedFromWindow(view: View) = Unit
        })
        ViewCompat.requestApplyInsets(container)
        return container
    }

    override fun onEvaluateFullscreenMode(): Boolean = false

    override fun onStartInputView(info: android.view.inputmethod.EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        attachOwnersToWindowTree(null)
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        if (activeSession?.stopping == false) {
            stopRecording()
        }
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        super.onFinishInputView(finishingInput)
    }

    override fun onFinishInput() {
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        super.onFinishInput()
    }

    override fun onDestroy() {
        finishRecordingRunnable?.let(mainHandler::removeCallbacks)
        finishRecordingRunnable = null
        moonshineTranscriber.detachCallbacks()
        activeSession = null
        transcriberExecutor.shutdownNow()
        runCatching { moonshineTranscriber.close() }
        super.onDestroy()
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
    }

    private fun startRecording() {
        if (activeSession != null || keyboardState.mode != CompactKeyboardMode.IDLE) return
        if (!hasMicrophonePermission() || !modelsReady()) {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return
        }
        val connection = currentInputConnection ?: return
        val beforeCursor = runCatching {
            connection.getTextBeforeCursor(1, 0)?.toString().orEmpty()
        }.getOrDefault("")
        val session = RecordingSession(
            id = ++nextSessionId,
            inputConnection = connection,
            prefix = if (beforeCursor.isNotEmpty() && !beforeCursor.last().isWhitespace()) " " else "",
            textBuffer = DictationTextBuffer("")
        )
        activeSession = session
        keyboardState = keyboardState.copy(
            mode = CompactKeyboardMode.RECORDING,
            speechActive = false
        )
        runOnTranscriberThread {
            val started = moonshineTranscriber.start(
                MoonshineMicTranscriber.Callbacks(
                    onText = { text -> onMoonshineText(session.id, text) },
                    onLine = { line -> onMoonshineLine(session.id, line.id, line.text.orEmpty()) },
                    onError = { onMoonshineError(session.id) },
                    onSpeechStateChanged = { active ->
                        mainHandler.post { onMoonshineSpeechStateChanged(session.id, active) }
                    }
                )
            )
            mainHandler.post {
                if (!started && activeSession?.id == session.id) {
                    failRecording(session.id)
                }
            }
        }
    }

    private fun stopRecording() {
        val session = activeSession ?: return
        if (session.stopping) return
        session.stopping = true
        keyboardState = keyboardState.copy(
            mode = CompactKeyboardMode.PROCESSING,
            speechActive = false
        )
        runOnTranscriberThread {
            moonshineTranscriber.stop()
            mainHandler.post {
                scheduleRecordingFinish(session.id, FINAL_TRANSCRIPT_TIMEOUT_MS)
            }
        }
    }

    private fun discardRecording() {
        val session = activeSession ?: return
        finishRecordingRunnable?.let(mainHandler::removeCallbacks)
        finishRecordingRunnable = null
        moonshineTranscriber.detachCallbacks()
        activeSession = null
        clearComposition(session)
        showIdle()
        runOnTranscriberThread { moonshineTranscriber.cancel() }
    }

    private fun onMoonshineText(sessionId: Int, text: String) {
        val session = activeSession?.takeIf { it.id == sessionId } ?: return
        updateComposition(session, session.textBuffer.updatePartial(text))
        if (session.stopping) {
            scheduleRecordingFinish(sessionId, FINAL_TRANSCRIPT_TIMEOUT_MS)
        }
    }

    private fun onMoonshineLine(sessionId: Int, lineId: Long, text: String) {
        val session = activeSession?.takeIf { it.id == sessionId } ?: return
        updateComposition(session, session.textBuffer.completeLine(lineId, text))
        if (session.stopping) {
            scheduleRecordingFinish(sessionId, FINAL_LINE_SETTLE_MS)
        }
    }

    private fun onMoonshineError(sessionId: Int) {
        if (activeSession?.id != sessionId) return
        failRecording(sessionId)
    }

    private fun onMoonshineSpeechStateChanged(sessionId: Int, active: Boolean) {
        if (activeSession?.id != sessionId || keyboardState.mode != CompactKeyboardMode.RECORDING) {
            return
        }
        if (keyboardState.speechActive != active) {
            keyboardState = keyboardState.copy(speechActive = active)
        }
    }

    private fun scheduleRecordingFinish(sessionId: Int, delayMs: Long) {
        if (activeSession?.id != sessionId) return
        finishRecordingRunnable?.let(mainHandler::removeCallbacks)
        finishRecordingRunnable = Runnable {
            finishRecordingRunnable = null
            finishRecording(sessionId)
        }.also { runnable ->
            mainHandler.postDelayed(runnable, delayMs)
        }
    }

    private fun finishRecording(sessionId: Int) {
        val session = activeSession?.takeIf { it.id == sessionId } ?: return
        finishRecordingRunnable?.let(mainHandler::removeCallbacks)
        finishRecordingRunnable = null
        moonshineTranscriber.detachCallbacks()
        if (session.textBuffer.hasTranscript) {
            updateComposition(session, session.textBuffer.currentText())
            runCatching { session.inputConnection.finishComposingText() }
        } else {
            clearComposition(session)
        }
        activeSession = null
        showIdle()
    }

    private fun failRecording(sessionId: Int) {
        val session = activeSession?.takeIf { it.id == sessionId } ?: return
        finishRecordingRunnable?.let(mainHandler::removeCallbacks)
        finishRecordingRunnable = null
        moonshineTranscriber.detachCallbacks()
        activeSession = null
        clearComposition(session)
        showIdle()
        runOnTranscriberThread { moonshineTranscriber.cancel() }
        Toast.makeText(this, R.string.keyboard_recording_start_failed, Toast.LENGTH_SHORT).show()
    }

    private fun updateComposition(session: RecordingSession, text: String) {
        val composingText = if (text.isBlank()) "" else session.prefix + text
        runCatching { session.inputConnection.setComposingText(composingText, 1) }
    }

    private fun clearComposition(session: RecordingSession) {
        runCatching {
            session.inputConnection.setComposingText("", 1)
            session.inputConnection.finishComposingText()
        }
    }

    private fun showIdle() {
        keyboardState = keyboardState.copy(
            mode = CompactKeyboardMode.IDLE,
            speechActive = false
        )
    }

    private fun updateBottomInset(insets: WindowInsetsCompat?) {
        if (insets == null) {
            keyboardState = keyboardState.copy(bottomInsetPx = 0)
            return
        }
        var bottom = 0
        listOf(
            WindowInsetsCompat.Type.navigationBars(),
            WindowInsetsCompat.Type.tappableElement()
        ).forEach { type ->
            bottom = max(bottom, insets.getInsetsIgnoringVisibility(type).bottom)
            bottom = max(bottom, insets.getInsets(type).bottom)
        }
        if (keyboardState.bottomInsetPx != bottom) {
            keyboardState = keyboardState.copy(bottomInsetPx = bottom)
        }
    }

    private fun warmupMoonshine() {
        runOnTranscriberThread { moonshineTranscriber.warmup() }
    }

    private fun runOnTranscriberThread(block: () -> Unit) {
        try {
            transcriberExecutor.execute(block)
        } catch (_: RejectedExecutionException) {
            // Ignore late work while the input method is shutting down.
        }
    }

    private fun hasMicrophonePermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun modelsReady(): Boolean {
        return ModelCatalog.moonshineMediumStreamingSpecs.all { spec ->
            ModelStore.isModelReadyStrict(this, spec)
        }
    }

    private fun isSystemDarkTheme(): Boolean {
        val nightMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return nightMode == Configuration.UI_MODE_NIGHT_YES
    }

    private fun keyboardBackground(darkTheme: Boolean): Int {
        return if (darkTheme) KEYBOARD_BACKGROUND_DARK else KEYBOARD_BACKGROUND_LIGHT
    }

    private fun applyNavigationBarTheme(darkTheme: Boolean, backgroundColor: Int) {
        val imeWindow = window?.window ?: return
        imeWindow.navigationBarColor = backgroundColor
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            imeWindow.isNavigationBarContrastEnforced = false
        }
        WindowCompat.getInsetsController(imeWindow, imeWindow.decorView)
            .isAppearanceLightNavigationBars = !darkTheme
    }

    private fun attachOwnersToWindowTree(contentView: View?) {
        contentView?.setViewTreeLifecycleOwner(this)
        contentView?.setViewTreeSavedStateRegistryOwner(this)
        window?.window?.decorView?.setViewTreeLifecycleOwner(this)
        window?.window?.decorView?.setViewTreeSavedStateRegistryOwner(this)
    }

    private data class RecordingSession(
        val id: Int,
        val inputConnection: InputConnection,
        val prefix: String,
        val textBuffer: DictationTextBuffer,
        var stopping: Boolean = false
    )

    private companion object {
        const val FINAL_TRANSCRIPT_TIMEOUT_MS = 800L
        const val FINAL_LINE_SETTLE_MS = 50L
        const val KEYBOARD_BACKGROUND_LIGHT = 0xFFE8EAED.toInt()
        const val KEYBOARD_BACKGROUND_DARK = 0xFF131519.toInt()
    }
}
