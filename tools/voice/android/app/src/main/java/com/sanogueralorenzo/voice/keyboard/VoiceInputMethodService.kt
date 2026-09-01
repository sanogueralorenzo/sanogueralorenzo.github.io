package com.sanogueralorenzo.voice.keyboard

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
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
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max

/** Compact, audio-reactive voice keyboard backed only by the local Moonshine model. */
class VoiceInputMethodService : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val processingExecutor = Executors.newSingleThreadExecutor()
    private val moonshineExecutor = Executors.newSingleThreadExecutor()
    private val sessionCounter = AtomicInteger(0)
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)
    private val moonshineTranscriber by lazy(LazyThreadSafetyMode.NONE) {
        KeyboardMoonshineTranscriber(this)
    }

    @Volatile
    private var activeSession: RecordingSession? = null
    private var processingFuture: Future<*>? = null
    private var inputRootView: View? = null
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
                        onSendTap = ::stopAndTranscribe
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
        inputRootView = container
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
        if (activeSession?.processing == false) {
            stopAndTranscribe()
        }
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        super.onFinishInputView(finishingInput)
    }

    override fun onFinishInput() {
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        super.onFinishInput()
    }

    override fun onDestroy() {
        activeSession?.recorder?.stopAndGetPcm()
        activeSession = null
        processingFuture?.cancel(true)
        processingFuture = null
        inputRootView = null
        processingExecutor.shutdownNow()
        moonshineExecutor.shutdownNow()
        runCatching { moonshineTranscriber.close() }
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        super.onDestroy()
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
        val sessionId = sessionCounter.incrementAndGet()
        val recorder = KeyboardAudioRecorder(
            onLevelChanged = { level ->
                mainHandler.post {
                    if (activeSession?.id == sessionId && keyboardState.mode != CompactKeyboardMode.PROCESSING) {
                        keyboardState = keyboardState.copy(audioLevel = level.coerceIn(0f, 1f))
                    }
                }
            },
            onAudioFrame = { frame -> enqueueAudioFrame(sessionId, frame) }
        )
        val session = RecordingSession(
            id = sessionId,
            recorder = recorder,
            inputConnection = currentInputConnection
        )
        activeSession = session
        keyboardState = keyboardState.copy(
            mode = CompactKeyboardMode.RECORDING,
            audioLevel = 0f
        )
        try {
            moonshineExecutor.submit {
                val started = moonshineTranscriber.startSession()
                if (!started) {
                    mainHandler.post { failRecordingStart(sessionId) }
                }
            }
        } catch (_: RejectedExecutionException) {
            failRecordingStart(sessionId)
            return
        }
        if (!recorder.start()) {
            failRecordingStart(sessionId)
        }
    }

    private fun enqueueAudioFrame(sessionId: Int, frame: ShortArray) {
        if (activeSession?.id != sessionId) return
        try {
            moonshineExecutor.execute {
                if (activeSession?.id == sessionId) {
                    moonshineTranscriber.addAudio(frame)
                }
            }
        } catch (_: RejectedExecutionException) {
            // Ignore late audio during service shutdown.
        }
    }

    private fun stopAndTranscribe() {
        val session = activeSession ?: return
        if (session.processing) return
        session.processing = true
        keyboardState = keyboardState.copy(
            mode = CompactKeyboardMode.PROCESSING,
            audioLevel = 0f
        )
        try {
            processingFuture = processingExecutor.submit {
                val pcm = session.recorder.stopAndGetPcm()
                val streamingTranscript = runCatching {
                    moonshineExecutor.submit<String> {
                        moonshineTranscriber.finishSession()
                    }.get(FINALIZE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                }.getOrDefault("")
                val transcript = streamingTranscript.ifBlank {
                    moonshineTranscriber.transcribeOneShot(pcm)
                }.trim()
                mainHandler.post {
                    if (activeSession?.id != session.id) return@post
                    if (transcript.isNotBlank()) {
                        commitTranscript(session.inputConnection, transcript)
                    }
                    activeSession = null
                    processingFuture = null
                    showIdle()
                }
            }
        } catch (_: RejectedExecutionException) {
            activeSession = null
            showIdle()
        }
    }

    private fun discardRecording() {
        val session = activeSession ?: return
        activeSession = null
        sessionCounter.incrementAndGet()
        showIdle()
        try {
            processingExecutor.execute { session.recorder.stopAndGetPcm() }
            moonshineExecutor.execute { moonshineTranscriber.cancelActive() }
        } catch (_: RejectedExecutionException) {
            session.recorder.stopAndGetPcm()
        }
    }

    private fun failRecordingStart(sessionId: Int) {
        val session = activeSession?.takeIf { it.id == sessionId } ?: return
        activeSession = null
        try {
            processingExecutor.execute { session.recorder.stopAndGetPcm() }
            moonshineExecutor.execute { moonshineTranscriber.cancelActive() }
        } catch (_: RejectedExecutionException) {
            session.recorder.stopAndGetPcm()
        }
        showIdle()
        Toast.makeText(this, R.string.keyboard_recording_start_failed, Toast.LENGTH_SHORT).show()
    }

    private fun commitTranscript(inputConnection: InputConnection?, transcript: String) {
        val connection = inputConnection ?: currentInputConnection ?: return
        val beforeCursor = runCatching {
            connection.getTextBeforeCursor(1, 0)?.toString().orEmpty()
        }.getOrDefault("")
        val prefix = if (beforeCursor.isNotEmpty() && !beforeCursor.last().isWhitespace()) " " else ""
        runCatching { connection.commitText(prefix + transcript, 1) }
    }

    private fun showIdle() {
        keyboardState = keyboardState.copy(
            mode = CompactKeyboardMode.IDLE,
            audioLevel = 0f
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
        try {
            processingExecutor.execute { moonshineTranscriber.warmup() }
        } catch (_: RejectedExecutionException) {
            // Service is already shutting down.
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
        val recorder: KeyboardAudioRecorder,
        val inputConnection: InputConnection?,
        var processing: Boolean = false
    )

    private companion object {
        const val FINALIZE_TIMEOUT_MS = 4_500L
        const val KEYBOARD_BACKGROUND_LIGHT = 0xFFE8EAED.toInt()
        const val KEYBOARD_BACKGROUND_DARK = 0xFF131519.toInt()
    }
}
