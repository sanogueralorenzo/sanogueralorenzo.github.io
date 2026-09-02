package com.sanogueralorenzo.voice.keyboard

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.view.View
import android.view.inputmethod.ExtractedTextRequest
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
import com.sanogueralorenzo.voice.audio.DictationLanguage
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
import com.sanogueralorenzo.voice.audio.MoonshineMicTranscriber
import com.sanogueralorenzo.voice.dictation.DictationSession
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme
import kotlin.math.max

/** Compact voice keyboard using the same Moonshine microphone transcriber as the overlay. */
class VoiceInputMethodService : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)
    private val languagePreferences by lazy(LazyThreadSafetyMode.NONE) {
        DictationLanguagePreferences(this)
    }
    private val dictationSession by lazy(LazyThreadSafetyMode.NONE) {
        DictationSession(
            transcriber = MoonshineMicTranscriber(this),
            listener = object : DictationSession.Listener {
                override fun onStateChanged(state: DictationSession.State) {
                    when (state) {
                        DictationSession.State.RECORDING -> keyboardState = keyboardState.copy(
                            mode = CompactKeyboardMode.RECORDING,
                            speechActive = false
                        )

                        DictationSession.State.STOPPING -> keyboardState = keyboardState.copy(
                            mode = CompactKeyboardMode.PROCESSING,
                            speechActive = false
                        )

                        DictationSession.State.IDLE,
                        DictationSession.State.CLOSED -> Unit
                    }
                }

                override fun onTextChanged(text: String) {
                    activeEditorSession?.let { updateComposition(it, text) }
                }

                override fun onAudioLevel(level: Float) {
                    onDictationAudioLevel(level)
                }

                override fun onCompleted(result: DictationSession.Result) {
                    completeEditorSession(result)
                }

                override fun onCancelled() {
                    clearActiveEditorSession()
                }

                override fun onError(error: Throwable?) {
                    clearActiveEditorSession()
                    Toast.makeText(
                        this@VoiceInputMethodService,
                        R.string.keyboard_recording_start_failed,
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
        )
    }

    private var activeEditorSession: EditorSession? = null
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
                        onIdleTap = { startRecording(languagePreferences.primary()) },
                        onIdleLongPress = { startRecording(languagePreferences.secondaryOrPrimary()) },
                        onDiscardTap = ::discardRecording,
                        onSendTap = { stopRecording(submitAfterFinish = true) }
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
        if (dictationSession.state == DictationSession.State.RECORDING) {
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
        activeEditorSession = null
        dictationSession.destroy()
        super.onDestroy()
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
    }

    private fun startRecording(language: DictationLanguage) {
        if (activeEditorSession != null || keyboardState.mode != CompactKeyboardMode.IDLE) return
        if (!hasMicrophonePermission() || !dictationSession.isReady(language)) {
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
        val session = EditorSession(
            inputConnection = connection,
            sourceText = readEditorText(connection),
            editorAction = KeyboardEditorAction.resolve(currentInputEditorInfo),
            prefix = if (beforeCursor.isNotEmpty() && !beforeCursor.last().isWhitespace()) " " else ""
        )
        activeEditorSession = session
        if (!dictationSession.start(language = language, originalText = "")) {
            activeEditorSession = null
        }
    }

    private fun stopRecording(submitAfterFinish: Boolean = false) {
        val session = activeEditorSession ?: return
        session.submitAfterFinish = submitAfterFinish
        dictationSession.stop()
    }

    private fun discardRecording() {
        if (activeEditorSession == null) return
        dictationSession.cancel()
    }

    private fun onDictationAudioLevel(level: Float) {
        if (activeEditorSession == null || keyboardState.mode != CompactKeyboardMode.RECORDING) {
            return
        }
        val active = KeyboardSpeechGate.isActive(
            currentlyActive = keyboardState.speechActive,
            audioLevel = level
        )
        if (keyboardState.speechActive != active) {
            keyboardState = keyboardState.copy(speechActive = active)
        }
    }

    private fun completeEditorSession(result: DictationSession.Result) {
        val session = activeEditorSession ?: return
        val command = result.command
        if (command != null) {
            clearComposition(session)
            replaceEditorText(session, command.applyTo(session.sourceText))
        } else if (result.hasTranscript) {
            updateComposition(session, result.text)
            runCatching { session.inputConnection.finishComposingText() }
        } else {
            clearComposition(session)
        }
        activeEditorSession = null
        showIdle()
        if (command == null && result.hasTranscript && session.submitAfterFinish) {
            session.editorAction?.let { action ->
                runCatching { session.inputConnection.performEditorAction(action) }
            }
        }
    }

    private fun clearActiveEditorSession() {
        activeEditorSession?.let(::clearComposition)
        activeEditorSession = null
        showIdle()
    }

    private fun updateComposition(session: EditorSession, text: String) {
        val composingText = if (text.isBlank()) "" else session.prefix + text
        runCatching { session.inputConnection.setComposingText(composingText, 1) }
    }

    private fun clearComposition(session: EditorSession) {
        runCatching {
            session.inputConnection.setComposingText("", 1)
            session.inputConnection.finishComposingText()
        }
    }

    private fun readEditorText(connection: InputConnection): String {
        val extracted = runCatching {
            connection.getExtractedText(ExtractedTextRequest(), 0)?.text?.toString()
        }.getOrNull()
        if (extracted != null) return extracted

        val before = runCatching {
            connection.getTextBeforeCursor(MAX_EDITOR_TEXT_CHARS, 0)?.toString().orEmpty()
        }.getOrDefault("")
        val after = runCatching {
            connection.getTextAfterCursor(MAX_EDITOR_TEXT_CHARS, 0)?.toString().orEmpty()
        }.getOrDefault("")
        return before + after
    }

    private fun replaceEditorText(session: EditorSession, text: String) {
        runCatching {
            session.inputConnection.beginBatchEdit()
            try {
                session.inputConnection.finishComposingText()
                session.inputConnection.setSelection(0, session.sourceText.length)
                session.inputConnection.commitText(text, 1)
            } finally {
                session.inputConnection.endBatchEdit()
            }
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
        dictationSession.warmup(languagePreferences.primary())
    }

    private fun hasMicrophonePermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
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

    private data class EditorSession(
        val inputConnection: InputConnection,
        val sourceText: String,
        val editorAction: Int?,
        val prefix: String,
        var submitAfterFinish: Boolean = false
    )

    private companion object {
        const val MAX_EDITOR_TEXT_CHARS = 100_000
        const val KEYBOARD_BACKGROUND_LIGHT = 0xFFE8EAED.toInt()
        const val KEYBOARD_BACKGROUND_DARK = 0xFF131519.toInt()
    }
}
