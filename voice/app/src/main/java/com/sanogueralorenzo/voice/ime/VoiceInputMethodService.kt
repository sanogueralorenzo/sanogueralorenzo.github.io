package com.sanogueralorenzo.voice.ime

import android.Manifest
import android.content.Intent
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.di.appGraph
import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.audio.MoonshineTranscriber
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.settings.KeyboardThemeMode
import com.sanogueralorenzo.voice.settings.ThemeRepository
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import com.sanogueralorenzo.voice.setup.MainActivity
import com.sanogueralorenzo.voice.summary.LiteRtSummarizer
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme
import androidx.lifecycle.compose.collectAsStateWithLifecycle as collectFlowAsStateWithLifecycle
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max

/**
 * Custom voice IME that records speech, transcribes with Moonshine, rewrites with LiteRT,
 * and commits the final text into the active editor.
 */
class VoiceInputMethodService : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val chunkExecutor = Executors.newSingleThreadExecutor()
    private val sessionCounter = AtomicInteger(0)
    private val moonshineWarmupStarted = AtomicBoolean(false)
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)
    private val chunkSessionCounter = AtomicInteger(0)
    private val chunkLock = Any()

    @Volatile
    private var inFlight: Future<*>? = null

    @Volatile
    private var audioRecorder: VoiceAudioRecorder? = null

    @Volatile
    private var activeChunkSessionId: Int = 0

    @Volatile
    private var imeInputRootView: View? = null

    private val activeChunkFutures = ArrayList<Future<*>>()

    private val moonshineTranscriberLazy = lazy(LazyThreadSafetyMode.NONE) { MoonshineTranscriber(this) }
    private val appGraphLazy = lazy(LazyThreadSafetyMode.NONE) { applicationContext.appGraph() }
    private val liteRtSummarizerLazy = lazy(LazyThreadSafetyMode.NONE) {
        LiteRtSummarizer(
            context = this,
            composePolicy = appGraphLazy.value.liteRtComposePolicy,
            deterministicComposeRewriter = appGraphLazy.value.deterministicComposeRewriter,
            composeLlmGate = appGraphLazy.value.liteRtComposeLlmGate
        )
    }
    private val asrRuntimeStatusStoreLazy = lazy(LazyThreadSafetyMode.NONE) { appGraphLazy.value.asrRuntimeStatusStore }
    private val settingsStoreLazy = lazy(LazyThreadSafetyMode.NONE) { appGraphLazy.value.settingsStore }
    private val themeRepositoryLazy = lazy(LazyThreadSafetyMode.NONE) { appGraphLazy.value.themeRepository }
    private val moonshineTranscriber: MoonshineTranscriber get() = moonshineTranscriberLazy.value
    private val liteRtSummarizer: LiteRtSummarizer get() = liteRtSummarizerLazy.value
    private val asrRuntimeStatusStore: AsrRuntimeStatusStore get() = asrRuntimeStatusStoreLazy.value
    private val settingsStore: VoiceSettingsStore get() = settingsStoreLazy.value
    private val themeRepository: ThemeRepository get() = themeRepositoryLazy.value
    private val imePipeline by lazy {
        VoiceImePipeline(
            transcriptionCoordinator = ImeTranscriptionCoordinator(
                moonshineTranscriber = moonshineTranscriber,
                asrRuntimeStatusStore = asrRuntimeStatusStore,
                logTag = TAG
            ),
            rewriteCoordinator = ImeRewriteCoordinator(
                settingsStore = settingsStore,
                liteRtSummarizer = liteRtSummarizer
            ),
            commitCoordinator = ImeCommitCoordinator()
        )
    }
    private val keyboardViewModel by lazy { VoiceKeyboardViewModel(VoiceKeyboardState()) }

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
    }

    override fun onCreateInputView(): View {
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        warmupMoonshineAsync()
        val preComposeBackground = if (isImeDarkThemeEnabled(themeRepository.keyboardThemeMode())) {
            IME_BACKGROUND_DARK
        } else {
            IME_BACKGROUND_LIGHT
        }
        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(preComposeBackground)
        }
        val composeView = ComposeView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(preComposeBackground)
            attachOwnersToWindowTree(this)
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
            setContent {
                val keyboardThemeMode by themeRepository.keyboardThemeModeFlow.collectFlowAsStateWithLifecycle(
                    initialValue = themeRepository.keyboardThemeMode(),
                    lifecycleOwner = this@VoiceInputMethodService
                )
                val effectiveDarkTheme = keyboardThemeMode.resolveIsDark(isSystemInDarkTheme())
                VoiceTheme {
                    val state by keyboardViewModel.collectAsStateWithLifecycle(
                        lifecycleOwner = this@VoiceInputMethodService
                    )
                    VoiceKeyboardImeContent(
                        state = state,
                        onIdleTap = { onIdlePillTap() },
                        onDeleteTap = { onDeleteTap() },
                        onSendTap = { onSendTap() },
                        onDebugToggle = { keyboardViewModel.toggleInlineDebug() },
                        onDebugLongPress = { onDebugLongPress() },
                        isDarkThemeOverride = effectiveDarkTheme
                    )
                }
            }
        }
        container.addView(composeView)
        attachOwnersToWindowTree(container)
        ViewCompat.setOnApplyWindowInsetsListener(container) { _, insets ->
            updateBottomInsetFromInsets(insets)
            insets
        }
        container.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {
                updateBottomInsetFromInsets(ViewCompat.getRootWindowInsets(v))
                ViewCompat.requestApplyInsets(v)
            }

            override fun onViewDetachedFromWindow(v: View) = Unit
        })
        imeInputRootView = container
        ViewCompat.requestApplyInsets(container)
        return container
    }

    override fun onDestroy() {
        cancelInFlight()
        imeInputRootView = null
        val recorderToRelease = audioRecorder
        audioRecorder = null
        val moonshineToRelease = moonshineTranscriberIfInitialized()
        val liteRtSummarizerToRelease = liteRtSummarizerIfInitialized()
        executor.shutdownNow()
        chunkExecutor.shutdownNow()
        Thread({
            recorderToRelease?.release()
            moonshineToRelease?.release()
            liteRtSummarizerToRelease?.release()
        }, "voice-ime-release").start()
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        super.onDestroy()
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        attachOwnersToWindowTree(null)
        imeInputRootView?.let { view ->
            updateBottomInsetFromInsets(ViewCompat.getRootWindowInsets(view))
            ViewCompat.requestApplyInsets(view)
        }
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
    }

    override fun onEvaluateFullscreenMode(): Boolean = false

    override fun onFinishInputView(finishingInput: Boolean) {
        cancelSessionWork(cancelProcessing = false)
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        super.onFinishInputView(finishingInput)
    }

    override fun onFinishInput() {
        cancelSessionWork(cancelProcessing = true)
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        super.onFinishInput()
    }

    private fun onIdlePillTap() {
        if (audioRecorder != null || inFlight != null || keyboardViewModel.isProcessing()) return
        if (!hasMicPermission()) {
            openAppForPermission()
            return
        }
        if (!isMoonshineModelReady()) {
            openAppForPermission()
            return
        }
        startRecording()
    }

    private fun onDebugLongPress() {
        val cleared = replaceCurrentInputText("")
        if (cleared) {
            Log.i(TAG, "Debug long press cleared current input text")
        } else {
            Log.w(TAG, "Debug long press failed to clear current input text")
        }
    }

    private fun startRecording() {
        if (audioRecorder != null) return
        val chunkSessionId = beginChunkSession()
        val recorder = VoiceAudioRecorder(
            onLevelChanged = { level ->
                mainHandler.post { keyboardViewModel.updateAudioLevel(level) }
            },
            onAudioFrame = { frame ->
                enqueueMoonshineAudioFrame(chunkSessionId, frame)
            }
        )
        if (!recorder.start()) {
            endChunkSession(chunkSessionId, cancelPending = true)
            keyboardViewModel.showIdle()
            return
        }
        enqueueMoonshineSessionStart(chunkSessionId)
        audioRecorder = recorder
        keyboardViewModel.showRecording()
    }

    private fun onDeleteTap() {
        if (inFlight != null) return
        stopRecordingDiscardAsync()
        keyboardViewModel.showIdle()
    }

    private fun onSendTap() {
        if (inFlight != null) return
        val recorder = audioRecorder ?: return
        audioRecorder = null
        keyboardViewModel.showTranscribing()
        val sourceTextSnapshot = currentInputTextSnapshot()

        submitSendRequest(
            SendRequest(
                recorder = recorder,
                sessionId = sessionCounter.incrementAndGet(),
                packageName = currentInputEditorInfo?.packageName,
                chunkSessionId = activeChunkSessionId,
                sourceTextSnapshot = sourceTextSnapshot
            )
        )
    }

    private fun submitSendRequest(request: SendRequest) {
        try {
            inFlight = executor.submit {
                processSendRequest(request)
            }
        } catch (_: RejectedExecutionException) {
            Thread {
                request.recorder.stopAndGetPcm()
                endChunkSession(request.chunkSessionId, cancelPending = true)
            }.start()
            keyboardViewModel.showIdle()
        }
    }

    private fun processSendRequest(request: SendRequest) {
        val pipelineStartedAt = SystemClock.uptimeMillis()
        try {
            val pipelineRequest = ImePipelineRequest(
                recorder = request.recorder,
                sourceTextSnapshot = request.sourceTextSnapshot,
                chunkSessionId = request.chunkSessionId
            )
            val transcribe = imePipeline.transcribe(
                request = pipelineRequest,
                awaitChunkSessionQuiescence = { awaitChunkSessionQuiescence(it) },
                finalizeMoonshineTranscript = { finalizeMoonshineTranscript(it) }
            )
            if (Thread.currentThread().isInterrupted) {
                postIdleAfterBackgroundWork()
                return
            }
            val rewrite = imePipeline.rewrite(
                request = pipelineRequest,
                transcript = transcribe.transcript,
                onShowRewriting = { mainHandler.post { keyboardViewModel.showRewriting() } }
            )
            if (Thread.currentThread().isInterrupted) {
                postIdleAfterBackgroundWork()
                return
            }
            val totalElapsed = SystemClock.uptimeMillis() - pipelineStartedAt
            val metrics = VoiceDebugMetrics(
                sessionId = request.sessionId,
                operationMode = rewrite.operation,
                timestampMs = System.currentTimeMillis(),
                totalMs = totalElapsed,
                transcribeMs = transcribe.elapsedMs,
                rewriteMs = rewrite.elapsedMs,
                chunkWaitMs = transcribe.chunkWaitMs,
                streamingFinalizeMs = transcribe.streamingFinalizeMs,
                oneShotMs = transcribe.oneShotMs,
                transcriptionPath = transcribe.path,
                inputSamples = transcribe.inputSamples,
                transcriptChars = transcribe.transcript.length,
                outputChars = rewrite.output.length,
                moonshineTranscriptText = debugTextSample(transcribe.transcript),
                postLiteRtText = debugTextSample(rewrite.output),
                rewriteAttempted = rewrite.attempted,
                rewriteApplied = rewrite.applied,
                rewriteBackend = rewrite.backend,
                rewriteErrorType = rewrite.errorType,
                rewriteError = rewrite.errorMessage,
                committed = false,
                editIntent = rewrite.editIntent
            )
            postSendResult(request, rewrite, metrics)
        } catch (t: Throwable) {
            Log.e(TAG, "onSend pipeline failed", t)
            postIdleAfterBackgroundWork()
        } finally {
            endChunkSession(request.chunkSessionId, cancelPending = false)
        }
    }

    private fun postSendResult(request: SendRequest, rewrite: ImeRewriteResult, metrics: VoiceDebugMetrics) {
        mainHandler.post {
            inFlight = null
            val outputForCommit = appendInlineDebugIfEnabled(
                output = rewrite.output,
                metrics = metrics,
                modeName = rewrite.operation.name
            )
            val commitResult = imePipeline.commit(
                operation = rewrite.operation,
                outputForCommit = outputForCommit,
                editIntent = metrics.editIntent,
                sessionId = request.sessionId,
                packageName = request.packageName,
                isSessionCurrent = ::isSessionCurrent,
                replaceCurrentInputText = ::replaceCurrentInputText
            )
            if (commitResult.sessionMismatch) {
                keyboardViewModel.setDebugMetrics(metrics.copy(committed = false))
                keyboardViewModel.showIdle()
                return@post
            }
            val committed = commitResult.committed
            if (outputForCommit.isNotBlank()) {
                if (!committed) {
                    Log.w(TAG, "Output generated but commit failed for session=${request.sessionId}")
                }
            } else {
                if (committed && rewrite.operation == ImeOperation.EDIT) {
                    Log.i(TAG, "Edit cleared input for session=${request.sessionId}")
                } else {
                    Log.i(TAG, "No transcript text to commit for session=${request.sessionId}")
                }
            }
            keyboardViewModel.setDebugMetrics(
                metrics.copy(
                    committed = committed,
                    outputChars = outputForCommit.length
                )
            )
            keyboardViewModel.showIdle()
        }
    }

    private fun appendInlineDebugIfEnabled(
        output: String,
        metrics: VoiceDebugMetrics,
        modeName: String
    ): String {
        if (!keyboardViewModel.isInlineDebugEnabled()) return output
        if (output.isBlank()) return output
        return output.trimEnd() + "\n\n" + VoiceDebugFooterFormatter.format(metrics, modeName)
    }

    private fun debugTextSample(text: String): String {
        val normalized = text.replace("\r\n", "\n").trim()
        if (normalized.isBlank()) return "(empty)"
        if (normalized.length <= DEBUG_TEXT_SAMPLE_MAX_CHARS) return normalized
        return normalized.take(DEBUG_TEXT_SAMPLE_MAX_CHARS) + "… [truncated]"
    }

    private fun postIdleAfterBackgroundWork() {
        mainHandler.post {
            inFlight = null
            keyboardViewModel.showIdle()
        }
    }

    private fun enqueueMoonshineSessionStart(sessionId: Int) {
        if (sessionId == 0) return
        val isActive = synchronized(chunkLock) { activeChunkSessionId == sessionId }
        if (!isActive) return
        try {
            val future = chunkExecutor.submit {
                synchronized(chunkLock) {
                    if (activeChunkSessionId != sessionId) return@submit
                }
                val started = moonshineTranscriber.startSession()
                if (!started) {
                    Log.w(TAG, "Moonshine session start failed.")
                }
            }
            synchronized(chunkLock) {
                if (activeChunkSessionId == sessionId) {
                    activeChunkFutures.add(future)
                } else {
                    future.cancel(true)
                }
            }
        } catch (_: RejectedExecutionException) {
            // Ignore late work during shutdown.
        }
    }

    private fun enqueueMoonshineAudioFrame(sessionId: Int, pcm: ShortArray) {
        if (sessionId == 0 || pcm.isEmpty()) return
        val isActive = synchronized(chunkLock) { activeChunkSessionId == sessionId }
        if (!isActive) return
        try {
            val future = chunkExecutor.submit {
                synchronized(chunkLock) {
                    if (activeChunkSessionId != sessionId) return@submit
                }
                moonshineTranscriber.addAudio(
                    pcm = pcm,
                    sampleRateHz = VoiceAudioRecorder.SAMPLE_RATE_HZ
                )
            }
            synchronized(chunkLock) {
                if (activeChunkSessionId == sessionId) {
                    activeChunkFutures.add(future)
                } else {
                    future.cancel(true)
                }
            }
        } catch (_: RejectedExecutionException) {
            // Ignore late work during shutdown.
        }
    }

    private fun awaitChunkSessionQuiescence(sessionId: Int) {
        if (sessionId == 0) return
        val waitDeadlineMs = SystemClock.uptimeMillis() + CHUNK_WAIT_TOTAL_MS
        while (true) {
            val pending = synchronized(chunkLock) {
                if (activeChunkSessionId != sessionId) return
                activeChunkFutures.removeAll { it.isDone || it.isCancelled }
                activeChunkFutures.toList()
            }
            if (pending.isEmpty()) break
            val remainingMs = waitDeadlineMs - SystemClock.uptimeMillis()
            if (remainingMs <= 0L) {
                cancelPendingChunkWork(sessionId)
                break
            }
            var deadlineReached = false
            for (future in pending) {
                val remainingForFutureMs = waitDeadlineMs - SystemClock.uptimeMillis()
                if (remainingForFutureMs <= 0L) {
                    cancelPendingChunkWork(sessionId)
                    deadlineReached = true
                    break
                }
                val timeoutMs = minOf(remainingForFutureMs, CHUNK_WAIT_SLICE_MS)
                runCatching {
                    future.get(timeoutMs, TimeUnit.MILLISECONDS)
                }.onFailure { error ->
                    if (error is TimeoutException) return@onFailure
                    future.cancel(true)
                    moonshineTranscriberIfInitialized()?.cancelActive()
                }
            }
            if (deadlineReached) break
        }
    }

    private fun finalizeMoonshineTranscript(sessionId: Int): String {
        return try {
            val future = chunkExecutor.submit<String> {
                synchronized(chunkLock) {
                    if (activeChunkSessionId != sessionId) return@submit ""
                }
                moonshineTranscriber.stopSessionAndGetTranscript()
            }
            future.get(MOONSHINE_FINALIZE_WAIT_MS, TimeUnit.MILLISECONDS)
        } catch (t: Throwable) {
            moonshineTranscriberIfInitialized()?.cancelActive()
            Log.w(TAG, "Moonshine finalize failed", t)
            ""
        }
    }

    private fun beginChunkSession(): Int {
        val id = chunkSessionCounter.incrementAndGet()
        synchronized(chunkLock) {
            activeChunkSessionId = id
            activeChunkFutures.clear()
        }
        return id
    }

    private fun endChunkSession(sessionId: Int, cancelPending: Boolean) {
        synchronized(chunkLock) {
            if (sessionId == 0 || activeChunkSessionId != sessionId) return
            if (cancelPending) {
                activeChunkFutures.forEach { it.cancel(true) }
            }
            activeChunkFutures.clear()
            activeChunkSessionId = 0
        }
    }

    private fun isSessionCurrent(sessionId: Int, packageName: String?): Boolean {
        if (sessionCounter.get() != sessionId) return false
        if (packageName != null && currentInputEditorInfo?.packageName != packageName) return false
        return true
    }

    private fun hasMicPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun openAppForPermission() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun isMoonshineModelReady(): Boolean {
        return ModelCatalog.moonshineMediumStreamingSpecs.all {
            ModelStore.isModelPresent(this, it)
        }
    }

    private fun cancelInFlight() {
        sessionCounter.incrementAndGet()
        moonshineTranscriberIfInitialized()?.cancelActive()
        inFlight?.cancel(true)
        inFlight = null
        liteRtSummarizerIfInitialized()?.cancelActive()
        endChunkSession(activeChunkSessionId, cancelPending = true)
    }

    private fun cancelSessionWork(cancelProcessing: Boolean) {
        stopRecordingDiscardAsync()
        if (cancelProcessing) {
            cancelInFlight()
        }
        keyboardViewModel.showIdle()
    }

    private fun stopRecordingDiscardAsync() {
        val recorder = audioRecorder ?: return
        audioRecorder = null
        moonshineTranscriberIfInitialized()?.cancelActive()
        val chunkSessionId = activeChunkSessionId
        endChunkSession(chunkSessionId, cancelPending = true)
        try {
            executor.submit {
                recorder.stopAndGetPcm()
            }
        } catch (_: RejectedExecutionException) {
            Thread {
                recorder.stopAndGetPcm()
            }.start()
        }
    }

    private fun currentInputTextSnapshot(): String {
        val connection = currentInputConnection ?: return ""
        val extracted = runCatching {
            connection.getExtractedText(ExtractedTextRequest(), 0)?.text?.toString()
        }.getOrNull().orEmpty()
        if (extracted.isNotBlank()) return extracted

        val before = runCatching {
            connection.getTextBeforeCursor(INPUT_SNAPSHOT_MAX_CHARS, 0)?.toString()
        }.getOrNull().orEmpty()
        val selected = runCatching {
            connection.getSelectedText(0)?.toString()
        }.getOrNull().orEmpty()
        val after = runCatching {
            connection.getTextAfterCursor(INPUT_SNAPSHOT_MAX_CHARS, 0)?.toString()
        }.getOrNull().orEmpty()

        return "$before$selected$after"
    }

    private fun replaceCurrentInputText(newText: String): Boolean {
        val connection = currentInputConnection ?: return false
        return runCatching {
            val extracted = connection.getExtractedText(ExtractedTextRequest(), 0)
            connection.beginBatchEdit()
            try {
                val fullText = extracted?.text
                if (fullText != null) {
                    connection.setSelection(0, fullText.length)
                } else {
                    val beforeLen = connection.getTextBeforeCursor(INPUT_SNAPSHOT_MAX_CHARS, 0)?.length ?: 0
                    val afterLen = connection.getTextAfterCursor(INPUT_SNAPSHOT_MAX_CHARS, 0)?.length ?: 0
                    connection.deleteSurroundingText(beforeLen, afterLen)
                }
                connection.commitText(newText, 1)
            } finally {
                connection.endBatchEdit()
            }
            true
        }.getOrElse {
            Log.w(TAG, "replaceCurrentInputText failed", it)
            false
        }
    }

    private fun warmupMoonshineAsync() {
        if (!isMoonshineModelReady()) return
        if (!moonshineWarmupStarted.compareAndSet(false, true)) return
        try {
            executor.submit {
                moonshineTranscriber.warmup()
            }
        } catch (_: RejectedExecutionException) {
            Thread {
                moonshineTranscriber.warmup()
            }.start()
        }
    }

    private fun moonshineTranscriberIfInitialized(): MoonshineTranscriber? {
        return if (moonshineTranscriberLazy.isInitialized()) moonshineTranscriberLazy.value else null
    }

    private fun liteRtSummarizerIfInitialized(): LiteRtSummarizer? {
        return if (liteRtSummarizerLazy.isInitialized()) liteRtSummarizerLazy.value else null
    }

    private fun cancelPendingChunkWork(sessionId: Int) {
        synchronized(chunkLock) {
            if (activeChunkSessionId != sessionId) return
            activeChunkFutures.forEach { it.cancel(true) }
            activeChunkFutures.clear()
        }
        moonshineTranscriberIfInitialized()?.cancelActive()
    }

    private fun attachOwnersToWindowTree(contentView: View?) {
        contentView?.setViewTreeLifecycleOwner(this)
        contentView?.setViewTreeSavedStateRegistryOwner(this)
        window?.window?.decorView?.setViewTreeLifecycleOwner(this)
        window?.window?.decorView?.setViewTreeSavedStateRegistryOwner(this)
    }

    private fun updateBottomInsetFromInsets(insets: WindowInsetsCompat?) {
        if (insets == null) {
            keyboardViewModel.setBottomInsetPx(0)
            return
        }
        val types = intArrayOf(
            WindowInsetsCompat.Type.navigationBars(),
            WindowInsetsCompat.Type.tappableElement()
        )
        var bottom = 0
        for (type in types) {
            bottom = max(bottom, insets.getInsetsIgnoringVisibility(type).bottom)
            bottom = max(bottom, insets.getInsets(type).bottom)
        }
        keyboardViewModel.setBottomInsetPx(bottom)
    }

    private fun isImeDarkThemeEnabled(themeMode: KeyboardThemeMode): Boolean {
        return themeMode.resolveIsDark(isSystemDarkTheme())
    }

    private fun isSystemDarkTheme(): Boolean {
        val uiMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return uiMode == Configuration.UI_MODE_NIGHT_YES
    }

    private data class SendRequest(
        val recorder: VoiceAudioRecorder,
        val sessionId: Int,
        val packageName: String?,
        val chunkSessionId: Int,
        val sourceTextSnapshot: String
    )

    companion object {
        private const val TAG = "VoiceIme"
        private const val INPUT_SNAPSHOT_MAX_CHARS = 4_000
        private const val CHUNK_WAIT_TOTAL_MS = 7_000L
        private const val CHUNK_WAIT_SLICE_MS = 180L
        private const val MOONSHINE_FINALIZE_WAIT_MS = 4_500L
        private const val DEBUG_TEXT_SAMPLE_MAX_CHARS = 360
        private const val IME_BACKGROUND_LIGHT = 0xFFE8EAED.toInt()
        private const val IME_BACKGROUND_DARK = 0xFF131519.toInt()
    }
}
