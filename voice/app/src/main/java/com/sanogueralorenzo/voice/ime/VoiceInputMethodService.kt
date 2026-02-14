package com.sanogueralorenzo.voice.ime

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.asr.AsrEngine
import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.audio.MoonshineTranscriber
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.setup.MainActivity
import com.sanogueralorenzo.voice.summary.LiteRtSummarizer
import com.sanogueralorenzo.voice.summary.RewriteResult
import com.sanogueralorenzo.voice.summary.SummaryPolicy
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

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
    private var pendingCommit: PendingCommit? = null

    @Volatile
    private var pendingSendMode: SendMode = SendMode.COMPOSE_NEW

    @Volatile
    private var pendingEditSourceText: String = ""

    private val pendingCommitRunnable = Runnable { flushPendingCommit() }
    private val activeChunkFutures = ArrayList<Future<*>>()

    private val moonshineTranscriberLazy = lazy(LazyThreadSafetyMode.NONE) { MoonshineTranscriber(this) }
    private val liteRtSummarizerLazy = lazy(LazyThreadSafetyMode.NONE) { LiteRtSummarizer(this) }
    private val asrRuntimeStatusStoreLazy = lazy(LazyThreadSafetyMode.NONE) { AsrRuntimeStatusStore(this) }
    private val moonshineTranscriber: MoonshineTranscriber get() = moonshineTranscriberLazy.value
    private val liteRtSummarizer: LiteRtSummarizer get() = liteRtSummarizerLazy.value
    private val asrRuntimeStatusStore: AsrRuntimeStatusStore get() = asrRuntimeStatusStoreLazy.value
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
        liteRtSummarizer.warmupAsync()
        warmupMoonshineAsync()
        return ComposeView(this).apply {
            attachOwnersToWindowTree(this)
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
            setContent {
                VoiceTheme {
                    val state by keyboardViewModel.collectAsStateWithLifecycle(
                        lifecycleOwner = this@VoiceInputMethodService
                    )
                    VoiceKeyboardImeContent(
                        state = state,
                        onIdleTap = { onIdlePillTap() },
                        onEditTap = { onEditPillTap() },
                        onDeleteTap = { onDeleteTap() },
                        onSendTap = { onSendTap() },
                        onDebugTap = { keyboardViewModel.showDebugDialog() },
                        onDebugDismiss = { keyboardViewModel.hideDebugDialog() }
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        cancelInFlight()
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
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
        schedulePendingCommitFlush(delayMs = 0L)
        refreshEditableInputState()
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        schedulePendingCommitFlush(delayMs = 0L)
        refreshEditableInputState()
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
        startRecording(mode = SendMode.COMPOSE_NEW)
    }

    private fun onEditPillTap() {
        if (audioRecorder != null || inFlight != null || keyboardViewModel.isProcessing()) return
        val sourceText = currentInputTextSnapshot()
        if (sourceText.isBlank()) {
            keyboardViewModel.setCanEditCurrentInput(false)
            return
        }
        if (!hasMicPermission()) {
            openAppForPermission()
            return
        }
        if (!isMoonshineModelReady() || !liteRtSummarizer.isModelAvailable()) {
            openAppForPermission()
            return
        }
        startRecording(
            mode = SendMode.EDIT_EXISTING,
            editSourceText = sourceText
        )
    }

    private fun startRecording(mode: SendMode, editSourceText: String = "") {
        if (audioRecorder != null) return
        pendingSendMode = mode
        pendingEditSourceText = if (mode == SendMode.EDIT_EXISTING) editSourceText else ""
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
            pendingSendMode = SendMode.COMPOSE_NEW
            pendingEditSourceText = ""
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
        pendingSendMode = SendMode.COMPOSE_NEW
        pendingEditSourceText = ""
        keyboardViewModel.showIdle()
        refreshEditableInputState()
    }

    private fun onSendTap() {
        if (inFlight != null) return
        val recorder = audioRecorder ?: return
        audioRecorder = null
        keyboardViewModel.showTranscribing()
        val mode = pendingSendMode
        val editSourceText = pendingEditSourceText
        pendingSendMode = SendMode.COMPOSE_NEW
        pendingEditSourceText = ""

        submitSendRequest(
            SendRequest(
                recorder = recorder,
                sessionId = sessionCounter.incrementAndGet(),
                packageName = currentInputEditorInfo?.packageName,
                chunkSessionId = activeChunkSessionId,
                mode = mode,
                editSourceText = editSourceText
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
            val transcribe = transcribeRequest(request)
            if (Thread.currentThread().isInterrupted) {
                postIdleAfterBackgroundWork()
                return
            }
            val rewrite = if (request.mode == SendMode.EDIT_EXISTING) {
                editCurrentTextWithInstruction(
                    sourceText = request.editSourceText,
                    instructionTranscript = transcribe.transcript
                )
            } else {
                rewriteTranscriptIfNeeded(transcribe.transcript)
            }
            if (Thread.currentThread().isInterrupted) {
                postIdleAfterBackgroundWork()
                return
            }
            val totalElapsed = SystemClock.uptimeMillis() - pipelineStartedAt
            val metrics = VoiceDebugMetrics(
                sessionId = request.sessionId,
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
                rewriteAttempted = rewrite.attempted,
                rewriteApplied = rewrite.applied,
                rewriteFallbackReason = rewrite.fallbackReason,
                committed = false
            )
            postSendResult(request, rewrite.output, metrics)
        } catch (t: Throwable) {
            Log.e(TAG, "onSend pipeline failed", t)
            postIdleAfterBackgroundWork()
        } finally {
            endChunkSession(request.chunkSessionId, cancelPending = false)
        }
    }

    private fun transcribeRequest(request: SendRequest): TranscribeStageResult {
        val startedAt = SystemClock.uptimeMillis()
        val fullPcm = request.recorder.stopAndGetPcm()
        val chunkWaitStartedAt = SystemClock.uptimeMillis()
        awaitChunkSessionQuiescence(request.chunkSessionId)
        val chunkWaitElapsedMs = SystemClock.uptimeMillis() - chunkWaitStartedAt

        val moonshineStartedAt = SystemClock.uptimeMillis()
        val streamingText = finalizeMoonshineTranscript(request.chunkSessionId)
        val moonshineElapsedMs = SystemClock.uptimeMillis() - moonshineStartedAt
        if (streamingText.isNotBlank()) {
            asrRuntimeStatusStore.recordRun(engineUsed = AsrEngine.MOONSHINE)
            val totalElapsedMs = SystemClock.uptimeMillis() - startedAt
            if (totalElapsedMs >= SLOW_TRANSCRIBE_PIPELINE_MS) {
                Log.i(
                    TAG,
                    "Moonshine transcribe pipeline slow: total=${totalElapsedMs}ms moonshine=${moonshineElapsedMs}ms chunkWait=${chunkWaitElapsedMs}ms samples=${fullPcm.size} finalChars=${streamingText.length}"
                )
            }
            return TranscribeStageResult(
                transcript = streamingText,
                path = TranscriptionPath.STREAMING,
                inputSamples = fullPcm.size,
                chunkWaitMs = chunkWaitElapsedMs,
                streamingFinalizeMs = moonshineElapsedMs,
                oneShotMs = 0L,
                elapsedMs = totalElapsedMs
            )
        }

        if (fullPcm.isEmpty()) {
            asrRuntimeStatusStore.recordRun(
                engineUsed = AsrEngine.MOONSHINE,
                reason = "no_audio"
            )
            return TranscribeStageResult(
                transcript = "",
                path = TranscriptionPath.EMPTY_AUDIO,
                inputSamples = 0,
                chunkWaitMs = chunkWaitElapsedMs,
                streamingFinalizeMs = moonshineElapsedMs,
                oneShotMs = 0L,
                elapsedMs = SystemClock.uptimeMillis() - startedAt
            )
        }

        val oneShotStartedAt = SystemClock.uptimeMillis()
        val oneShot = moonshineTranscriber.transcribeWithoutStreaming(
            pcm = fullPcm,
            sampleRateHz = VoiceAudioRecorder.SAMPLE_RATE_HZ
        )
        val oneShotElapsedMs = SystemClock.uptimeMillis() - oneShotStartedAt
        val totalElapsedMs = SystemClock.uptimeMillis() - startedAt
        if (oneShot.isNotBlank()) {
            asrRuntimeStatusStore.recordRun(
                engineUsed = AsrEngine.MOONSHINE,
                reason = "streaming_empty_non_streaming_used"
            )
            return TranscribeStageResult(
                transcript = oneShot,
                path = TranscriptionPath.ONE_SHOT_FALLBACK,
                inputSamples = fullPcm.size,
                chunkWaitMs = chunkWaitElapsedMs,
                streamingFinalizeMs = moonshineElapsedMs,
                oneShotMs = oneShotElapsedMs,
                elapsedMs = totalElapsedMs
            )
        }

        asrRuntimeStatusStore.recordRun(
            engineUsed = AsrEngine.MOONSHINE,
            reason = "empty_after_all_paths"
        )
        return TranscribeStageResult(
            transcript = "",
            path = TranscriptionPath.EMPTY_AFTER_ALL_PATHS,
            inputSamples = fullPcm.size,
            chunkWaitMs = chunkWaitElapsedMs,
            streamingFinalizeMs = moonshineElapsedMs,
            oneShotMs = oneShotElapsedMs,
            elapsedMs = totalElapsedMs
        )
    }

    private fun rewriteTranscriptIfNeeded(transcript: String): RewriteStageResult {
        val startedAt = SystemClock.uptimeMillis()
        val shouldRewrite = transcript.isNotBlank() && liteRtSummarizer.isModelAvailable()
        if (shouldRewrite) {
            mainHandler.post { keyboardViewModel.showSummarizing() }
        }
        if (!shouldRewrite) {
            return RewriteStageResult(
                output = transcript,
                attempted = false,
                applied = false,
                fallbackReason = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt
            )
        }

        val budget = SummaryPolicy.budgetForText(transcript)
        val result = liteRtSummarizer.summarizeBlocking(
            text = transcript,
            maxTokens = budget.maxTokens
        )
        return when (result) {
            is RewriteResult.RewriteSuccess -> RewriteStageResult(
                output = result.text,
                attempted = true,
                applied = true,
                fallbackReason = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt
            )
            is RewriteResult.RewriteFallback -> {
                Log.i(
                    TAG,
                    "Rewrite fallback reason=${result.reason} latencyMs=${result.latencyMs}"
                )
                RewriteStageResult(
                    output = transcript,
                    attempted = true,
                    applied = false,
                    fallbackReason = result.reason.name,
                    elapsedMs = SystemClock.uptimeMillis() - startedAt
                )
            }
        }
    }

    private fun editCurrentTextWithInstruction(
        sourceText: String,
        instructionTranscript: String
    ): RewriteStageResult {
        val startedAt = SystemClock.uptimeMillis()
        val normalizedSource = sourceText.trim()
        val normalizedInstruction = instructionTranscript.trim()
        if (normalizedSource.isBlank() || normalizedInstruction.isBlank()) {
            return RewriteStageResult(
                output = sourceText,
                attempted = false,
                applied = false,
                fallbackReason = if (normalizedInstruction.isBlank()) "empty_instruction" else "empty_source",
                elapsedMs = SystemClock.uptimeMillis() - startedAt
            )
        }
        if (!liteRtSummarizer.isModelAvailable()) {
            return RewriteStageResult(
                output = sourceText,
                attempted = false,
                applied = false,
                fallbackReason = "model_unavailable",
                elapsedMs = SystemClock.uptimeMillis() - startedAt
            )
        }

        mainHandler.post { keyboardViewModel.showSummarizing() }
        val editBudget = SummaryPolicy.budgetForText(sourceText).maxTokens.coerceAtLeast(128)
        val result = liteRtSummarizer.applyEditInstructionBlocking(
            originalText = sourceText,
            instructionText = normalizedInstruction,
            maxTokens = editBudget
        )
        return when (result) {
            is RewriteResult.RewriteSuccess -> RewriteStageResult(
                output = result.text,
                attempted = true,
                applied = result.text != sourceText,
                fallbackReason = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt
            )

            is RewriteResult.RewriteFallback -> RewriteStageResult(
                output = sourceText,
                attempted = true,
                applied = false,
                fallbackReason = result.reason.name,
                elapsedMs = SystemClock.uptimeMillis() - startedAt
            )
        }
    }

    private fun postSendResult(request: SendRequest, output: String, metrics: VoiceDebugMetrics) {
        mainHandler.post {
            inFlight = null
            if (!isSessionCurrent(request.sessionId, request.packageName)) {
                keyboardViewModel.setDebugMetrics(metrics.copy(committed = false))
                keyboardViewModel.showIdle()
                refreshEditableInputState()
                return@post
            }
            val committed = if (output.isBlank()) {
                false
            } else if (request.mode == SendMode.EDIT_EXISTING) {
                replaceCurrentInputText(output)
            } else {
                enqueuePendingCommit(output, request.sessionId, request.packageName)
                true
            }
            if (output.isNotBlank()) {
                if (!committed) {
                    Log.w(TAG, "Output generated but commit failed for session=${request.sessionId}")
                }
            } else {
                Log.i(TAG, "No transcript text to commit for session=${request.sessionId}")
            }
            keyboardViewModel.setDebugMetrics(metrics.copy(committed = committed))
            keyboardViewModel.showIdle()
            refreshEditableInputState()
        }
    }

    private fun postIdleAfterBackgroundWork() {
        mainHandler.post {
            inFlight = null
            keyboardViewModel.showIdle()
            refreshEditableInputState()
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

    private fun commitSummary(summary: String): Boolean {
        val connection = currentInputConnection ?: return false
        return runCatching {
            connection.commitText(summary, 1)
        }.getOrElse {
            Log.w(TAG, "commitText failed", it)
            false
        }
    }

    private fun enqueuePendingCommit(summary: String, sessionId: Int, packageName: String?) {
        pendingCommit = PendingCommit(
            summary = summary,
            sessionId = sessionId,
            packageName = packageName
        )
        schedulePendingCommitFlush(delayMs = 0L)
    }

    private fun flushPendingCommit() {
        val pending = pendingCommit ?: return
        if ((SystemClock.uptimeMillis() - pending.createdAtMs) > MAX_COMMIT_WINDOW_MS) {
            Log.w(TAG, "pending commit expired for session=${pending.sessionId}")
            pendingCommit = null
            refreshEditableInputState()
            return
        }
        if (!isSessionCurrent(pending.sessionId, pending.packageName)) {
            pendingCommit = null
            refreshEditableInputState()
            return
        }
        if (commitSummary(pending.summary)) {
            pendingCommit = null
            refreshEditableInputState()
            return
        }
        val nextAttempt = pending.attempt + 1
        if (nextAttempt >= MAX_COMMIT_ATTEMPTS) {
            Log.w(TAG, "commitText retries exhausted for session=${pending.sessionId}")
            pendingCommit = null
            refreshEditableInputState()
            return
        }
        pendingCommit = pending.copy(attempt = nextAttempt)
        schedulePendingCommitFlush(delayMs = COMMIT_RETRY_DELAY_MS)
    }

    private fun schedulePendingCommitFlush(delayMs: Long) {
        mainHandler.removeCallbacks(pendingCommitRunnable)
        if (delayMs <= 0L) {
            mainHandler.post(pendingCommitRunnable)
        } else {
            mainHandler.postDelayed(pendingCommitRunnable, delayMs)
        }
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
        return ModelCatalog.moonshineTinyStreamingSpecs.all {
            ModelStore.isModelPresent(this, it)
        }
    }

    private fun cancelInFlight() {
        sessionCounter.incrementAndGet()
        pendingCommit = null
        pendingSendMode = SendMode.COMPOSE_NEW
        pendingEditSourceText = ""
        mainHandler.removeCallbacks(pendingCommitRunnable)
        moonshineTranscriberIfInitialized()?.cancelActive()
        inFlight?.cancel(true)
        inFlight = null
        liteRtSummarizerIfInitialized()?.cancelActive()
        endChunkSession(activeChunkSessionId, cancelPending = true)
        refreshEditableInputState()
    }

    private fun cancelSessionWork(cancelProcessing: Boolean) {
        stopRecordingDiscardAsync()
        if (cancelProcessing) {
            cancelInFlight()
        }
        keyboardViewModel.showIdle()
        refreshEditableInputState()
    }

    private fun stopRecordingDiscardAsync() {
        val recorder = audioRecorder ?: return
        audioRecorder = null
        pendingSendMode = SendMode.COMPOSE_NEW
        pendingEditSourceText = ""
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
        refreshEditableInputState()
    }

    private fun refreshEditableInputState() {
        keyboardViewModel.setCanEditCurrentInput(currentInputTextSnapshot().isNotBlank())
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

    private data class SendRequest(
        val recorder: VoiceAudioRecorder,
        val sessionId: Int,
        val packageName: String?,
        val chunkSessionId: Int,
        val mode: SendMode,
        val editSourceText: String
    )

    private data class PendingCommit(
        val summary: String,
        val sessionId: Int,
        val packageName: String?,
        val attempt: Int = 0,
        val createdAtMs: Long = SystemClock.uptimeMillis()
    )

    private data class TranscribeStageResult(
        val transcript: String,
        val path: TranscriptionPath,
        val inputSamples: Int,
        val chunkWaitMs: Long,
        val streamingFinalizeMs: Long,
        val oneShotMs: Long,
        val elapsedMs: Long
    )

    private data class RewriteStageResult(
        val output: String,
        val attempted: Boolean,
        val applied: Boolean,
        val fallbackReason: String?,
        val elapsedMs: Long
    )

    private enum class SendMode {
        COMPOSE_NEW,
        EDIT_EXISTING
    }

    companion object {
        private const val TAG = "VoiceIme"
        private const val INPUT_SNAPSHOT_MAX_CHARS = 4_000
        private const val COMMIT_RETRY_DELAY_MS = 120L
        private const val MAX_COMMIT_ATTEMPTS = 20
        private const val MAX_COMMIT_WINDOW_MS = 4_000L
        private const val CHUNK_WAIT_TOTAL_MS = 4_500L
        private const val CHUNK_WAIT_SLICE_MS = 180L
        private const val MOONSHINE_FINALIZE_WAIT_MS = 2_500L
        private const val SLOW_TRANSCRIBE_PIPELINE_MS = 900L
    }
}
