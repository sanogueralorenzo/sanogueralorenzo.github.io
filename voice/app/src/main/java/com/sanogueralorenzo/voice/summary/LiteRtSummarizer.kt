package com.sanogueralorenzo.voice.summary

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.SamplerConfig
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import java.io.File
import java.util.concurrent.atomic.AtomicReference

/**
 * LiteRT-LM based transcript rewriter.
 *
 * Goal: clean disfluencies and repairs while preserving meaning/facts. This component avoids
 * "helpful summarization" by combining deterministic decoding with post-generation safety checks.
 */
class LiteRtSummarizer(context: Context) {
    private data class RewriteRequest(
        val directive: LiteRtPromptTemplates.RewriteDirective,
        val content: String,
        val allowStrongTransform: Boolean
    )

    private data class EditRequest(
        val originalText: String,
        val instructionText: String,
        val intent: LiteRtEditHeuristics.EditIntent,
        val listMode: Boolean
    )

    private sealed interface AttemptResult {
        data class Success(val text: String) : AttemptResult
        data class Failure(
            val reason: RewriteFallbackReason,
            val error: Throwable? = null
        ) : AttemptResult
    }

    private data class RuntimeSnapshot(
        val profile: LiteRtRuntimeProfile,
        val suspectedNativeAbortPreviousRun: Boolean,
        val suspectedNativeAbortCount: Int
    )

    private sealed interface ConversationRunResult {
        data class Success(val output: String) : ConversationRunResult
        data class Timeout(val error: Throwable) : ConversationRunResult
        data class Error(val error: Throwable) : ConversationRunResult
    }

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val operationMutex = Mutex()
    private val initMutex = Mutex()
    private val conversationMutex = Mutex()
    private val activeConversation = AtomicReference<Conversation?>()
    private val backendPolicyStore = LiteRtBackendPolicyStore(appContext)
    private val compatibilityChecker = LiteRtCompatibilityChecker(appContext)
    private val settingsStore = VoiceSettingsStore(appContext)
    private val hardAbortMarkerStore = LiteRtHardAbortMarkerStore(appContext)

    @Volatile
    private var engine: Engine? = null

    @Volatile
    private var initializedModelPath: String? = null

    @Volatile
    private var initializedModelStamp: String? = null

    @Volatile
    private var initializedBackend: Backend? = null

    @Volatile
    private var initializedMaxNumTokens: Int = 0

    @Volatile
    private var rewritesSinceEngineInit: Int = 0

    @Volatile
    private var suspectedNativeAbortPreviousRun: Boolean = false

    @Volatile
    private var suspectedNativeAbortCount: Int = 0

    init {
        val markerStatus = hardAbortMarkerStore.detectAndConsumeStaleMarker()
        suspectedNativeAbortPreviousRun = markerStatus.suspectedPreviousRunAbort
        suspectedNativeAbortCount = markerStatus.suspectedAbortCount
    }

    fun isModelAvailable(): Boolean {
        return ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm)
    }

    fun currentBackendPolicy(): LiteRtBackendPolicy {
        return backendPolicyStore.currentPolicy(currentModelSha())
    }

    fun latestCompatibilityStatus(): LiteRtCompatibilityStatus? {
        return compatibilityChecker.latestStatus(
            modelSha = currentModelSha(),
            appVersionCode = compatibilityChecker.currentAppVersionCode()
        )
    }

    fun resetCompatibilityForCurrentModel() {
        val modelSha = currentModelSha()
        backendPolicyStore.clearPolicy(modelSha)
        compatibilityChecker.clearForModel(modelSha)
    }

    fun latestHardAbortStatus(): LiteRtHardAbortStatus {
        val status = hardAbortMarkerStore.currentStatus()
        return status.copy(
            suspectedPreviousRunAbort = suspectedNativeAbortPreviousRun,
            suspectedAbortCount = suspectedNativeAbortCount
        )
    }

    fun warmupAsync() {
        scope.launch {
            operationMutex.withLock {
                if (!isConfiguredModelSupported()) return@withLock
                val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm) ?: return@withLock
                val runtimeProfile = LiteRtRuntimeProfiler.snapshot(appContext)
                if (runtimeProfile.shouldBypassForMemoryPressure()) return@withLock
                val localEngine = ensureEngine(modelFile, runtimeProfile = runtimeProfile) ?: return@withLock
                val backend = initializedBackend ?: Backend.GPU
                runCompatibilityProbe(
                    localEngine = localEngine,
                    modelSha = currentModelSha(),
                    appVersionCode = compatibilityChecker.currentAppVersionCode(),
                    backend = backend,
                    force = false
                )
            }
        }
    }

    fun runCompatibilityProbeBlocking(force: Boolean = true): LiteRtCompatibilityStatus {
        val modelSha = currentModelSha()
        val appVersionCode = compatibilityChecker.currentAppVersionCode()
        val preferredBackendName = backendPolicyStore.preferredBackends(modelSha)
            .firstOrNull()
            ?.name
            ?: Backend.GPU.name

        return runBlocking(Dispatchers.Default) {
            operationMutex.withLock {
                if (!isConfiguredModelSupported()) {
                    return@withLock compatibilityChecker.recordFailure(
                        modelSha = modelSha,
                        appVersionCode = appVersionCode,
                        backendName = preferredBackendName,
                        reason = "unsupported_model"
                    )
                }
                val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm)
                if (modelFile == null) {
                    return@withLock compatibilityChecker.recordFailure(
                        modelSha = modelSha,
                        appVersionCode = appVersionCode,
                        backendName = preferredBackendName,
                        reason = "model_missing"
                    )
                }
                val runtimeProfile = LiteRtRuntimeProfiler.snapshot(appContext)
                if (runtimeProfile.shouldBypassForMemoryPressure()) {
                    return@withLock compatibilityChecker.recordFailure(
                        modelSha = modelSha,
                        appVersionCode = appVersionCode,
                        backendName = preferredBackendName,
                        reason = "memory_guard"
                    )
                }
                val localEngine = ensureEngine(modelFile, runtimeProfile = runtimeProfile)
                if (localEngine == null) {
                    return@withLock compatibilityChecker.recordFailure(
                        modelSha = modelSha,
                        appVersionCode = appVersionCode,
                        backendName = preferredBackendName,
                        reason = "engine_init_failed"
                    )
                }
                runCompatibilityProbe(
                    localEngine = localEngine,
                    modelSha = modelSha,
                    appVersionCode = appVersionCode,
                    backend = initializedBackend ?: Backend.GPU,
                    force = force
                )
            }
        }
    }

    fun summarizeBlocking(text: String): RewriteResult {
        val startedAt = System.currentTimeMillis()
        if (text.isBlank()) {
            return RewriteResult.RewriteFallback(
                reason = RewriteFallbackReason.EMPTY_INPUT,
                latencyMs = 0L
            )
        }
        if (!isConfiguredModelSupported()) {
            return RewriteResult.RewriteFallback(
                reason = RewriteFallbackReason.UNSUPPORTED_MODEL,
                latencyMs = 0L
            )
        }
        if (!isModelAvailable()) {
            return RewriteResult.RewriteFallback(
                reason = RewriteFallbackReason.MODEL_UNAVAILABLE,
                latencyMs = 0L
            )
        }

        return runBlocking(Dispatchers.Default) {
            operationMutex.withLock {
                summarizeInternal(text, startedAt)
            }
        }
    }

    fun applyEditInstructionBlocking(
        originalText: String,
        instructionText: String
    ): RewriteResult {
        val startedAt = System.currentTimeMillis()
        if (originalText.isBlank() || instructionText.isBlank()) {
            return RewriteResult.RewriteFallback(
                reason = RewriteFallbackReason.EMPTY_INPUT,
                latencyMs = 0L
            )
        }
        if (!isConfiguredModelSupported()) {
            return RewriteResult.RewriteFallback(
                reason = RewriteFallbackReason.UNSUPPORTED_MODEL,
                latencyMs = 0L
            )
        }
        if (!isModelAvailable()) {
            return RewriteResult.RewriteFallback(
                reason = RewriteFallbackReason.MODEL_UNAVAILABLE,
                latencyMs = 0L
            )
        }

        return runBlocking(Dispatchers.Default) {
            operationMutex.withLock {
                applyEditInstructionInternal(
                    originalText = originalText,
                    instructionText = instructionText,
                    startedAtMs = startedAt
                )
            }
        }
    }

    fun cancelActive() {
        scope.launch {
            cancelActiveConversation()
        }
    }

    fun release() {
        runBlocking(Dispatchers.Default) {
            operationMutex.withLock {
                cancelActiveConversation()
                activeConversation.set(null)
                initMutex.withLock {
                    closeEngineLocked()
                }
            }
        }
        scope.cancel()
    }

    private suspend fun cancelActiveConversation() {
        conversationMutex.withLock {
            runCatching { activeConversation.get()?.cancelProcess() }
        }
    }

    private suspend fun summarizeInternal(
        text: String,
        startedAtMs: Long
    ): RewriteResult {
        val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm)
            ?: return fallbackResult(RewriteFallbackReason.MODEL_UNAVAILABLE, startedAtMs)

        val normalizedInput = normalizeInput(text)
        if (normalizedInput.isBlank()) {
            return fallbackResult(RewriteFallbackReason.EMPTY_INPUT, startedAtMs)
        }
        val request = parseRewriteRequest(normalizedInput)
        if (request.content.isBlank()) {
            return fallbackResult(RewriteFallbackReason.EMPTY_INPUT, startedAtMs)
        }
        val listMode = looksLikeList(request.content)
        val modelSha = currentModelSha()
        val appVersionCode = compatibilityChecker.currentAppVersionCode()

        var lastReason = RewriteFallbackReason.ERROR
        var lastError: Throwable? = null
        var retriedAfterInvalidArgument = false
        var retriedAfterRuntimeError = false
        var forcedCompatibilityReprobe = false
        var lastRuntimeSnapshot: RuntimeSnapshot? = null

        for (attempt in 0 until MAX_REWRITE_ATTEMPTS) {
            val runtimeSnapshot = captureRuntimeSnapshot()
            lastRuntimeSnapshot = runtimeSnapshot
            val runtimeProfile = runtimeSnapshot.profile
            if (runtimeProfile.shouldBypassForMemoryPressure()) {
                Log.i(
                    TAG,
                    "LiteRT rewrite skipped: reason=MEMORY_GUARD availMemMb=${runtimeProfile.availMemMb} lowMemory=${runtimeProfile.lowMemory}"
                )
                return fallbackResult(
                    reason = RewriteFallbackReason.MEMORY_GUARD,
                    startedAtMs = startedAtMs,
                    listFormattingHintUsed = listMode,
                    runtimeSnapshot = runtimeSnapshot,
                    memoryGuardTriggered = true
                )
            }
            if (exceedsRewriteInputLimit(request.content, runtimeProfile.limits)) {
                Log.i(
                    TAG,
                    "LiteRT rewrite switching to chunked mode: tier=${runtimeProfile.tier} chars=${request.content.length} words=${wordCount(request.content)} limits=${runtimeProfile.limits.compactLabel()}"
                )
            }
            val rewriteChunks = splitRewriteContent(
                text = request.content,
                limits = runtimeProfile.limits,
                listMode = listMode
            )
            if (rewriteChunks.isEmpty()) {
                return fallbackResult(
                    reason = RewriteFallbackReason.RUNTIME_TIER_LIMIT,
                    startedAtMs = startedAtMs,
                    listFormattingHintUsed = listMode,
                    runtimeSnapshot = runtimeSnapshot
                )
            }
            val shouldForceReset = (attempt > 0 && lastReason == RewriteFallbackReason.INVALID_ARGUMENT)
            val localEngine = ensureEngine(
                modelFile = modelFile,
                forceReset = shouldForceReset,
                runtimeProfile = runtimeProfile
            ) ?: return fallbackResult(
                RewriteFallbackReason.ENGINE_INIT_FAILED,
                startedAtMs,
                listFormattingHintUsed = listMode,
                runtimeSnapshot = runtimeSnapshot
            )

            val backend = initializedBackend ?: Backend.GPU
            var compatibilityStatus = runCompatibilityProbe(
                localEngine = localEngine,
                modelSha = modelSha,
                appVersionCode = appVersionCode,
                backend = backend,
                force = false
            )
            if (compatibilityStatus.disabled) {
                if (!forcedCompatibilityReprobe) {
                    compatibilityStatus = runCompatibilityProbe(
                        localEngine = localEngine,
                        modelSha = modelSha,
                        appVersionCode = appVersionCode,
                        backend = backend,
                        force = true
                    )
                    forcedCompatibilityReprobe = true
                }
                if (compatibilityStatus.disabled) {
                    Log.w(TAG, "LiteRT compatibility probe is disabled for backend=$backend; continuing with runtime attempt")
                }
            }

            val attemptResult = if (rewriteChunks.size == 1) {
                val timeoutMs = LiteRtRewritePolicy.adaptiveTimeoutMs(
                    inputText = request.content,
                    rewritesSinceEngineInit = rewritesSinceEngineInit
                )
                rewriteOnce(
                    localEngine = localEngine,
                    request = request,
                    listMode = listMode,
                    timeoutMs = timeoutMs
                )
            } else {
                rewriteChunksOnce(
                    localEngine = localEngine,
                    request = request,
                    chunks = rewriteChunks,
                    listMode = listMode
                )
            }

            when (attemptResult) {
                is AttemptResult.Success -> {
                    rewritesSinceEngineInit += 1
                    compatibilityChecker.recordSuccess(
                        modelSha = modelSha,
                        appVersionCode = appVersionCode,
                        backendName = backend.name
                    )
                    return RewriteResult.RewriteSuccess(
                        text = attemptResult.text,
                        latencyMs = elapsedSince(startedAtMs),
                        backend = backend,
                        listFormattingHintUsed = listMode,
                        runtimeTier = runtimeProfile.tier.name,
                        runtimeLimits = runtimeProfile.limits.compactLabel(),
                        availMemMb = runtimeProfile.availMemMb,
                        lowMemory = runtimeProfile.lowMemory,
                        suspectedNativeAbortPreviousRun = runtimeSnapshot.suspectedNativeAbortPreviousRun,
                        suspectedNativeAbortCount = runtimeSnapshot.suspectedNativeAbortCount
                    )
                }

                is AttemptResult.Failure -> {
                    lastReason = attemptResult.reason
                    lastError = attemptResult.error

                    if (
                        attemptResult.reason == RewriteFallbackReason.INVALID_ARGUMENT &&
                        !retriedAfterInvalidArgument
                    ) {
                        retriedAfterInvalidArgument = true
                        resetEngineNow()
                        continue
                    }

                    if (
                        attemptResult.reason == RewriteFallbackReason.ERROR &&
                        !retriedAfterRuntimeError
                    ) {
                        retriedAfterRuntimeError = true
                        resetEngineNow()
                        continue
                    }

                    if (
                        attemptResult.reason == RewriteFallbackReason.TIMEOUT &&
                        attempt == 0
                    ) {
                        continue
                    }

                    return fallbackResult(
                        reason = attemptResult.reason,
                        startedAtMs = startedAtMs,
                        listFormattingHintUsed = listMode,
                        runtimeSnapshot = runtimeSnapshot,
                        runtimeError = attemptResult.error
                    )
                }
            }
        }

        return fallbackResult(
            reason = lastReason,
            startedAtMs = startedAtMs,
            listFormattingHintUsed = listMode,
            runtimeSnapshot = lastRuntimeSnapshot,
            runtimeError = lastError
        )
    }

    private suspend fun rewriteOnce(
        localEngine: Engine,
        request: RewriteRequest,
        listMode: Boolean,
        timeoutMs: Long
    ): AttemptResult {
        val config = ConversationConfig(
            systemInstruction = Contents.of(
                LiteRtPromptTemplates.buildRewriteSystemInstruction(
                    directive = request.directive,
                    bulletMode = listMode,
                    allowStrongTransform = request.allowStrongTransform,
                    customInstructions = currentRuntimeCustomInstructions()
                )
            ),
            samplerConfig = SamplerConfig(
                topK = 1,
                topP = 1.0,
                temperature = 0.0,
                seed = 42
            )
        )
        return when (val conversationResult = runConversation(localEngine, config, request.content, timeoutMs)) {
            is ConversationRunResult.Success -> {
                val cleaned = cleanModelOutput(conversationResult.output, bulletMode = listMode)
                if (cleaned.isBlank()) {
                    AttemptResult.Failure(RewriteFallbackReason.EMPTY_OUTPUT)
                } else if (!isSafeRewrite(request.content, cleaned, request.directive)) {
                    AttemptResult.Failure(RewriteFallbackReason.SAFETY_REJECTED)
                } else {
                    AttemptResult.Success(cleaned)
                }
            }

            is ConversationRunResult.Timeout -> {
                AttemptResult.Failure(RewriteFallbackReason.TIMEOUT, conversationResult.error)
            }

            is ConversationRunResult.Error -> {
                val error = conversationResult.error
                if (LiteRtRewritePolicy.isInputTooLongError(error)) {
                    AttemptResult.Failure(RewriteFallbackReason.INPUT_TOO_LONG, error)
                } else if (LiteRtRewritePolicy.isInvalidArgumentError(error)) {
                    AttemptResult.Failure(RewriteFallbackReason.INVALID_ARGUMENT, error)
                } else {
                    Log.w(TAG, "LiteRT rewrite failed", error)
                    AttemptResult.Failure(RewriteFallbackReason.ERROR, error)
                }
            }
        }
    }

    private suspend fun rewriteChunksOnce(
        localEngine: Engine,
        request: RewriteRequest,
        chunks: List<String>,
        listMode: Boolean
    ): AttemptResult {
        val rewrittenChunks = ArrayList<String>(chunks.size)
        for (chunk in chunks) {
            val chunkRequest = request.copy(content = chunk)
            val timeoutMs = LiteRtRewritePolicy.adaptiveTimeoutMs(
                inputText = chunk,
                rewritesSinceEngineInit = rewritesSinceEngineInit
            )
            when (
                val chunkResult = rewriteOnce(
                    localEngine = localEngine,
                    request = chunkRequest,
                    listMode = listMode,
                    timeoutMs = timeoutMs
                )
            ) {
                is AttemptResult.Success -> rewrittenChunks += chunkResult.text
                is AttemptResult.Failure -> return chunkResult
            }
        }
        val merged = mergeRewrittenChunks(rewrittenChunks, listMode)
        if (merged.isBlank()) {
            return AttemptResult.Failure(RewriteFallbackReason.EMPTY_OUTPUT)
        }
        return if (isSafeRewrite(request.content, merged, request.directive)) {
            AttemptResult.Success(merged)
        } else {
            AttemptResult.Failure(RewriteFallbackReason.SAFETY_REJECTED)
        }
    }

    private suspend fun applyEditInstructionInternal(
        originalText: String,
        instructionText: String,
        startedAtMs: Long
    ): RewriteResult {
        val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm)
            ?: return fallbackResult(RewriteFallbackReason.MODEL_UNAVAILABLE, startedAtMs)

        val original = originalText.trim()
        val normalizedInstruction = normalizeInput(instructionText)
        if (original.isBlank() || normalizedInstruction.isBlank()) {
            return fallbackResult(RewriteFallbackReason.EMPTY_INPUT, startedAtMs)
        }
        val instructionAnalysis = LiteRtEditHeuristics.analyzeInstruction(normalizedInstruction)
        val editRequest = EditRequest(
            originalText = original,
            instructionText = instructionAnalysis.normalizedInstruction,
            intent = instructionAnalysis.intent,
            listMode = looksLikeList(original) || looksLikeList(instructionAnalysis.normalizedInstruction)
        )
        val modelSha = currentModelSha()
        val appVersionCode = compatibilityChecker.currentAppVersionCode()

        var lastReason = RewriteFallbackReason.ERROR
        var lastError: Throwable? = null
        var retriedAfterInvalidArgument = false
        var retriedAfterRuntimeError = false
        var forcedCompatibilityReprobe = false
        var lastRuntimeSnapshot: RuntimeSnapshot? = null

        for (attempt in 0 until MAX_REWRITE_ATTEMPTS) {
            val runtimeSnapshot = captureRuntimeSnapshot()
            lastRuntimeSnapshot = runtimeSnapshot
            val runtimeProfile = runtimeSnapshot.profile
            if (runtimeProfile.shouldBypassForMemoryPressure()) {
                Log.i(
                    TAG,
                    "LiteRT edit skipped: reason=MEMORY_GUARD availMemMb=${runtimeProfile.availMemMb} lowMemory=${runtimeProfile.lowMemory}"
                )
                return fallbackResult(
                    reason = RewriteFallbackReason.MEMORY_GUARD,
                    startedAtMs = startedAtMs,
                    listFormattingHintUsed = editRequest.listMode,
                    editIntent = editRequest.intent.name,
                    runtimeSnapshot = runtimeSnapshot,
                    memoryGuardTriggered = true
                )
            }
            if (exceedsEditInputLimit(editRequest, runtimeProfile.limits)) {
                Log.i(
                    TAG,
                    "LiteRT edit skipped: reason=RUNTIME_TIER_LIMIT tier=${runtimeProfile.tier} sourceChars=${editRequest.originalText.length} instructionChars=${editRequest.instructionText.length} limits=${runtimeProfile.limits.compactLabel()}"
                )
                return fallbackResult(
                    reason = RewriteFallbackReason.RUNTIME_TIER_LIMIT,
                    startedAtMs = startedAtMs,
                    listFormattingHintUsed = editRequest.listMode,
                    editIntent = editRequest.intent.name,
                    runtimeSnapshot = runtimeSnapshot
                )
            }
            val shouldForceReset = (attempt > 0 && lastReason == RewriteFallbackReason.INVALID_ARGUMENT)
            val localEngine = ensureEngine(
                modelFile = modelFile,
                forceReset = shouldForceReset,
                runtimeProfile = runtimeProfile
            ) ?: return fallbackResult(
                RewriteFallbackReason.ENGINE_INIT_FAILED,
                startedAtMs,
                listFormattingHintUsed = editRequest.listMode,
                editIntent = editRequest.intent.name,
                runtimeSnapshot = runtimeSnapshot
            )

            val backend = initializedBackend ?: Backend.GPU
            var compatibilityStatus = runCompatibilityProbe(
                localEngine = localEngine,
                modelSha = modelSha,
                appVersionCode = appVersionCode,
                backend = backend,
                force = false
            )
            if (compatibilityStatus.disabled) {
                if (!forcedCompatibilityReprobe) {
                    compatibilityStatus = runCompatibilityProbe(
                        localEngine = localEngine,
                        modelSha = modelSha,
                        appVersionCode = appVersionCode,
                        backend = backend,
                        force = true
                    )
                    forcedCompatibilityReprobe = true
                }
                if (compatibilityStatus.disabled) {
                    Log.w(TAG, "LiteRT compatibility probe is disabled for backend=$backend; continuing with runtime attempt")
                }
            }

            val timeoutMs = LiteRtRewritePolicy.adaptiveTimeoutMs(
                inputText = "${editRequest.originalText}\n${editRequest.instructionText}",
                rewritesSinceEngineInit = rewritesSinceEngineInit
            )
            val attemptResult = editOnce(
                localEngine = localEngine,
                request = editRequest,
                timeoutMs = timeoutMs
            )

            when (attemptResult) {
                is AttemptResult.Success -> {
                    rewritesSinceEngineInit += 1
                    compatibilityChecker.recordSuccess(
                        modelSha = modelSha,
                        appVersionCode = appVersionCode,
                        backendName = backend.name
                    )
                    return RewriteResult.RewriteSuccess(
                        text = attemptResult.text,
                        latencyMs = elapsedSince(startedAtMs),
                        backend = backend,
                        listFormattingHintUsed = editRequest.listMode,
                        editIntent = editRequest.intent.name,
                        runtimeTier = runtimeProfile.tier.name,
                        runtimeLimits = runtimeProfile.limits.compactLabel(),
                        availMemMb = runtimeProfile.availMemMb,
                        lowMemory = runtimeProfile.lowMemory,
                        suspectedNativeAbortPreviousRun = runtimeSnapshot.suspectedNativeAbortPreviousRun,
                        suspectedNativeAbortCount = runtimeSnapshot.suspectedNativeAbortCount
                    )
                }

                is AttemptResult.Failure -> {
                    lastReason = attemptResult.reason
                    lastError = attemptResult.error
                    if (
                        attemptResult.reason == RewriteFallbackReason.INVALID_ARGUMENT &&
                        !retriedAfterInvalidArgument
                    ) {
                        retriedAfterInvalidArgument = true
                        resetEngineNow()
                        continue
                    }
                    if (
                        attemptResult.reason == RewriteFallbackReason.ERROR &&
                        !retriedAfterRuntimeError
                    ) {
                        retriedAfterRuntimeError = true
                        resetEngineNow()
                        continue
                    }
                    if (attemptResult.reason == RewriteFallbackReason.TIMEOUT && attempt == 0) {
                        continue
                    }
                    return fallbackResult(
                        reason = attemptResult.reason,
                        startedAtMs = startedAtMs,
                        listFormattingHintUsed = editRequest.listMode,
                        editIntent = editRequest.intent.name,
                        runtimeSnapshot = runtimeSnapshot,
                        runtimeError = attemptResult.error
                    )
                }
            }
        }

        return fallbackResult(
            reason = lastReason,
            startedAtMs = startedAtMs,
            listFormattingHintUsed = editRequest.listMode,
            editIntent = editRequest.intent.name,
            runtimeSnapshot = lastRuntimeSnapshot,
            runtimeError = lastError
        )
    }

    private suspend fun editOnce(
        localEngine: Engine,
        request: EditRequest,
        timeoutMs: Long
    ): AttemptResult {
        val config = ConversationConfig(
            systemInstruction = Contents.of(
                LiteRtPromptTemplates.buildEditSystemInstruction(
                    customInstructions = currentRuntimeCustomInstructions()
                )
            ),
            samplerConfig = SamplerConfig(
                topK = 1,
                topP = 1.0,
                temperature = 0.0,
                seed = 42
            )
        )
        val userPrompt = LiteRtPromptTemplates.buildEditUserPrompt(
            originalText = request.originalText,
            instructionText = request.instructionText,
            editIntent = request.intent.name,
            listMode = request.listMode
        )
        return when (val conversationResult = runConversation(localEngine, config, userPrompt, timeoutMs)) {
            is ConversationRunResult.Success -> {
                val cleaned = cleanModelOutput(
                    text = conversationResult.output,
                    bulletMode = request.listMode
                )
                if (cleaned.isBlank() && !LiteRtEditHeuristics.shouldAllowBlankOutput(request.intent)) {
                    AttemptResult.Failure(RewriteFallbackReason.EMPTY_OUTPUT)
                } else {
                    AttemptResult.Success(cleaned)
                }
            }

            is ConversationRunResult.Timeout -> {
                AttemptResult.Failure(RewriteFallbackReason.TIMEOUT, conversationResult.error)
            }

            is ConversationRunResult.Error -> {
                val error = conversationResult.error
                if (LiteRtRewritePolicy.isInputTooLongError(error)) {
                    AttemptResult.Failure(RewriteFallbackReason.INPUT_TOO_LONG, error)
                } else if (LiteRtRewritePolicy.isInvalidArgumentError(error)) {
                    AttemptResult.Failure(RewriteFallbackReason.INVALID_ARGUMENT, error)
                } else {
                    Log.w(TAG, "LiteRT edit failed", error)
                    AttemptResult.Failure(RewriteFallbackReason.ERROR, error)
                }
            }
        }
    }

    private suspend fun runCompatibilityProbe(
        localEngine: Engine,
        modelSha: String,
        appVersionCode: Long,
        backend: Backend,
        force: Boolean
    ): LiteRtCompatibilityStatus {
        if (!force && compatibilityChecker.hasStatus(modelSha, appVersionCode, backend.name)) {
            val existing = compatibilityChecker.statusFor(modelSha, appVersionCode, backend.name)
            val recentlyChecked = (System.currentTimeMillis() - existing.lastCheckedAtMs) < PROBE_RECHECK_INTERVAL_MS
            if (existing.healthy || existing.disabled || recentlyChecked) {
                return existing
            }
        }

        return try {
            val probeOutput = runProbeOnce(localEngine)
            if (probeOutput.isBlank()) {
                Log.w(TAG, "LiteRT compatibility probe returned empty output; treating as soft success")
                compatibilityChecker.recordSuccess(
                    modelSha = modelSha,
                    appVersionCode = appVersionCode,
                    backendName = backend.name
                )
            } else {
                compatibilityChecker.recordSuccess(
                    modelSha = modelSha,
                    appVersionCode = appVersionCode,
                    backendName = backend.name
                )
            }
        } catch (t: Throwable) {
            val reason = if (LiteRtRewritePolicy.isInvalidArgumentError(t)) {
                "probe_invalid_argument"
            } else {
                "probe_error:${t::class.java.simpleName}"
            }
            if (backend == Backend.GPU) {
                backendPolicyStore.markGpuFailed(modelSha)
            }
            compatibilityChecker.recordFailure(
                modelSha = modelSha,
                appVersionCode = appVersionCode,
                backendName = backend.name,
                reason = reason
            )
        }
    }

    private suspend fun runProbeOnce(localEngine: Engine): String {
        val config = ConversationConfig(
            systemInstruction = Contents.of(LiteRtPromptTemplates.PROBE_SYSTEM_INSTRUCTION),
            samplerConfig = SamplerConfig(
                topK = 1,
                topP = 1.0,
                temperature = 0.0,
                seed = 7
            )
        )
        return when (val result = runConversation(localEngine, config, LiteRtPromptTemplates.PROBE_USER_MESSAGE, PROBE_TIMEOUT_MS)) {
            is ConversationRunResult.Success -> {
                cleanModelOutput(result.output, bulletMode = false)
            }

            is ConversationRunResult.Timeout -> {
                throw result.error
            }

            is ConversationRunResult.Error -> {
                throw result.error
            }
        }
    }

    private suspend fun runConversation(
        localEngine: Engine,
        config: ConversationConfig,
        userPrompt: String,
        timeoutMs: Long
    ): ConversationRunResult {
        val conversation = localEngine.createConversation(config)
        conversationMutex.withLock {
            activeConversation.set(conversation)
        }
        hardAbortMarkerStore.markOperationStart()
        try {
            val output = withTimeout(timeoutMs) {
                val streamed = StringBuilder()
                var lastChunk = ""
                conversation.sendMessageAsync(userPrompt).collect { message ->
                    val chunk = message.toTextPayload()
                    if (chunk.isBlank()) return@collect
                    if (chunk.startsWith(lastChunk)) {
                        streamed.append(chunk.removePrefix(lastChunk))
                    } else if (!lastChunk.startsWith(chunk)) {
                        streamed.append(chunk)
                    }
                    lastChunk = chunk
                }
                if (streamed.isNotBlank()) streamed.toString() else lastChunk
            }
            return ConversationRunResult.Success(output)
        } catch (t: Throwable) {
            if (t is TimeoutCancellationException) {
                conversationMutex.withLock {
                    if (activeConversation.get() === conversation) {
                        runCatching { conversation.cancelProcess() }
                    }
                }
                delay(CONVERSATION_TIMEOUT_CANCEL_GRACE_MS)
                return ConversationRunResult.Timeout(t)
            }
            return ConversationRunResult.Error(t)
        } finally {
            hardAbortMarkerStore.clearOperationMarker()
            conversationMutex.withLock {
                if (activeConversation.get() === conversation) {
                    activeConversation.set(null)
                }
                runCatching { conversation.close() }
            }
        }
    }

    private suspend fun ensureEngine(
        modelFile: File?,
        forceReset: Boolean = false,
        runtimeProfile: LiteRtRuntimeProfile? = null
    ): Engine? {
        if (modelFile == null || !modelFile.exists()) return null
        return initMutex.withLock {
            val current = engine
            val path = modelFile.absolutePath
            val modelStamp = "${modelFile.length()}:${modelFile.lastModified()}"
            val desiredMaxTokens = runtimeProfile?.limits?.engineMaxTokens ?: DEFAULT_ENGINE_MAX_TOKENS
            if (
                !forceReset &&
                current != null &&
                current.isInitialized() &&
                initializedModelPath == path &&
                initializedModelStamp == modelStamp &&
                initializedMaxNumTokens == desiredMaxTokens
            ) {
                return@withLock current
            }

            closeEngineLocked()

            val modelSha = currentModelSha()
            val candidateBackends = backendPolicyStore.preferredBackends(modelSha)
            var lastError: Throwable? = null

            for (backend in candidateBackends) {
                val config = EngineConfig(
                    modelPath = path,
                    backend = backend,
                    maxNumTokens = desiredMaxTokens,
                    cacheDir = appContext.cacheDir.absolutePath
                )
                var fresh: Engine? = null
                try {
                    fresh = Engine(config)
                    fresh.initialize()
                    engine = fresh
                    initializedModelPath = path
                    initializedModelStamp = modelStamp
                    initializedBackend = backend
                    initializedMaxNumTokens = desiredMaxTokens
                    rewritesSinceEngineInit = 0
                    Log.i(TAG, "LiteRT engine initialized backend=$backend maxTokens=$desiredMaxTokens tier=${runtimeProfile?.tier}")
                    return@withLock fresh
                } catch (t: Throwable) {
                    runCatching { fresh?.close() }
                    lastError = t
                    if (backend == Backend.GPU) {
                        backendPolicyStore.markGpuFailed(modelSha)
                    }
                    Log.w(TAG, "LiteRT init failed for backend=$backend", t)
                }
            }

            Log.e(TAG, "LiteRT engine init failed on all backends", lastError)
            null
        }
    }

    private suspend fun resetEngineNow() {
        initMutex.withLock {
            closeEngineLocked()
        }
    }

    private fun closeEngineLocked() {
        runCatching { engine?.close() }
        engine = null
        initializedModelPath = null
        initializedModelStamp = null
        initializedBackend = null
        initializedMaxNumTokens = 0
        rewritesSinceEngineInit = 0
        activeConversation.set(null)
    }

    private fun fallbackResult(
        reason: RewriteFallbackReason,
        startedAtMs: Long,
        listFormattingHintUsed: Boolean = false,
        editIntent: String? = null,
        runtimeSnapshot: RuntimeSnapshot? = null,
        memoryGuardTriggered: Boolean = false,
        runtimeError: Throwable? = null
    ): RewriteResult {
        if (reason != RewriteFallbackReason.EMPTY_INPUT) {
            val errorSummary = summarizeThrowable(runtimeError)
            Log.i(
                TAG,
                "LiteRT fallback reason=${reason.name} error=${errorSummary ?: "none"} tier=${runtimeSnapshot?.profile?.tier ?: "n/a"} limits=${runtimeSnapshot?.profile?.limits?.compactLabel() ?: "n/a"}"
            )
        }
        return RewriteResult.RewriteFallback(
            reason = reason,
            latencyMs = elapsedSince(startedAtMs),
            listFormattingHintUsed = listFormattingHintUsed,
            editIntent = editIntent,
            runtimeError = summarizeThrowable(runtimeError),
            runtimeTier = runtimeSnapshot?.profile?.tier?.name,
            runtimeLimits = runtimeSnapshot?.profile?.limits?.compactLabel(),
            availMemMb = runtimeSnapshot?.profile?.availMemMb,
            lowMemory = runtimeSnapshot?.profile?.lowMemory ?: false,
            memoryGuardTriggered = memoryGuardTriggered,
            suspectedNativeAbortPreviousRun = runtimeSnapshot?.suspectedNativeAbortPreviousRun ?: suspectedNativeAbortPreviousRun,
            suspectedNativeAbortCount = runtimeSnapshot?.suspectedNativeAbortCount ?: suspectedNativeAbortCount
        )
    }

    private fun summarizeThrowable(error: Throwable?): String? {
        if (error == null) return null
        val type = error::class.java.simpleName.ifBlank { "Throwable" }
        val message = error.message
            ?.replace(WHITESPACE_REGEX, " ")
            ?.trim()
            ?.take(180)
            .orEmpty()
        return if (message.isBlank()) type else "$type: $message"
    }

    private fun elapsedSince(startedAtMs: Long): Long {
        return (System.currentTimeMillis() - startedAtMs).coerceAtLeast(0L)
    }

    private fun currentModelSha(): String {
        val sha = ModelCatalog.liteRtLm.sha256.trim().lowercase()
        return if (sha.isBlank()) ModelCatalog.liteRtLm.id else sha
    }

    private fun isConfiguredModelSupported(): Boolean {
        val id = ModelCatalog.liteRtLm.id.lowercase()
        val fileName = ModelCatalog.liteRtLm.fileName.lowercase()
        // LiteRT-LM preview support is limited to specific model families.
        return SUPPORTED_MODEL_HINTS.any { hint ->
            id.contains(hint) || fileName.contains(hint)
        }
    }

    private fun Message.toTextPayload(): String {
        val parts = contents.contents
        if (parts.isEmpty()) return ""
        return buildString(parts.size * 8) {
            for (part in parts) {
                if (part is Content.Text) {
                    append(part.text)
                }
            }
        }
    }

    private fun parseRewriteRequest(text: String): RewriteRequest {
        val allowStrongTransform = hasHighIntensityIntro(text)
        val tagged = parseTaggedDirectivePrefix(text, allowStrongTransform)
        if (tagged != null) {
            return tagged
        }

        val introDirective = parseNaturalLanguageIntroDirective(text, allowStrongTransform)
        if (introDirective != null) {
            return introDirective
        }

        return RewriteRequest(
            directive = LiteRtPromptTemplates.RewriteDirective.DEFAULT,
            content = text,
            allowStrongTransform = allowStrongTransform
        )
    }

    private fun parseTaggedDirectivePrefix(
        text: String,
        allowStrongTransform: Boolean
    ): RewriteRequest? {
        val match = DIRECTIVE_PREFIX_REGEX.find(text) ?: return null

        val rawTag = listOfNotNull(
            match.groups[1]?.value,
            match.groups[2]?.value,
            match.groups[3]?.value,
            match.groups[4]?.value
        ).firstOrNull()?.lowercase()

        val directive = directiveFromToken(rawTag)

        if (directive == LiteRtPromptTemplates.RewriteDirective.DEFAULT) {
            return null
        }

        val content = text.substring(match.range.last + 1).trimStart()
        if (content.isBlank()) {
            return null
        }
        return RewriteRequest(
            directive = directive,
            content = content,
            allowStrongTransform = allowStrongTransform
        )
    }

    private fun parseNaturalLanguageIntroDirective(
        text: String,
        allowStrongTransform: Boolean
    ): RewriteRequest? {
        val match = NATURAL_INTRO_DIRECTIVE_REGEX.find(text) ?: return null
        val rawDirective = match.groups[1]?.value
        val content = match.groups[2]?.value?.trim().orEmpty()
        if (content.isBlank()) return null
        val directive = directiveFromToken(rawDirective)
        if (directive == LiteRtPromptTemplates.RewriteDirective.DEFAULT) return null
        return RewriteRequest(
            directive = directive,
            content = content,
            allowStrongTransform = allowStrongTransform
        )
    }

    private fun directiveFromToken(token: String?): LiteRtPromptTemplates.RewriteDirective {
        return when (token?.trim()?.lowercase()) {
            "short", "concise", "brief" -> LiteRtPromptTemplates.RewriteDirective.SHORT
            "warm", "friendly", "kind" -> LiteRtPromptTemplates.RewriteDirective.WARM
            "work", "professional", "formal", "business", "for work" ->
                LiteRtPromptTemplates.RewriteDirective.WORK
            else -> LiteRtPromptTemplates.RewriteDirective.DEFAULT
        }
    }

    private fun normalizeInput(text: String): String {
        val collapsed = text.replace(WHITESPACE_REGEX, " ").trim()
        if (collapsed.isBlank()) return ""
        return collapsed
            .replace(REPEATED_FILLER_REGEX, "$1")
            .replace(SPACE_BEFORE_PUNCTUATION_REGEX, "$1")
            .replace(REPEATED_PUNCTUATION_REGEX, "$1")
            .trim()
    }

    private fun cleanModelOutput(
        text: String,
        bulletMode: Boolean
    ): String {
        var cleaned = text.trim()
        if (cleaned.isBlank()) return ""
        cleaned = cleaned
            .replace(PREFIX_LABEL_REGEX, "")
            .trim()
            .trim('`')
            .trim()
            .removeSurrounding("\"")
            .removeSurrounding("'")
            .trim()
        if (cleaned.isBlank()) return ""
        if (!bulletMode && cleaned.startsWith("- ")) {
            cleaned = cleaned
                .lineSequence()
                .map { it.removePrefix("- ").trim() }
                .filter { it.isNotBlank() }
                .joinToString(" ")
        }
        return cleaned
    }

    private fun looksLikeList(text: String): Boolean {
        return LiteRtEditHeuristics.looksLikeList(text)
    }

    private fun isSafeRewrite(
        source: String,
        rewritten: String,
        directive: LiteRtPromptTemplates.RewriteDirective
    ): Boolean {
        val allowStyleNovelty = directive == LiteRtPromptTemplates.RewriteDirective.WARM ||
            directive == LiteRtPromptTemplates.RewriteDirective.WORK
        return LiteRtSafetyGate.isSafeRewrite(
            source = source,
            rewritten = rewritten,
            allowStyleNovelty = allowStyleNovelty
        )
    }

    private fun hasHighIntensityIntro(text: String): Boolean {
        val intro = text.trim().take(INTRO_SCAN_MAX_CHARS)
        if (intro.isBlank()) return false
        return HIGH_INTENSITY_REGEX.containsMatchIn(intro)
    }

    private fun exceedsRewriteInputLimit(
        text: String,
        limits: LiteRtRuntimeLimits
    ): Boolean {
        return text.length > limits.rewriteInputMaxChars ||
            wordCount(text) > limits.rewriteInputMaxWords
    }

    private fun exceedsEditInputLimit(
        request: EditRequest,
        limits: LiteRtRuntimeLimits
    ): Boolean {
        val chars = request.originalText.length + request.instructionText.length
        val words = wordCount(request.originalText) + wordCount(request.instructionText)
        return chars > limits.editInputMaxChars || words > limits.editInputMaxWords
    }

    private fun splitRewriteContent(
        text: String,
        limits: LiteRtRuntimeLimits,
        listMode: Boolean
    ): List<String> {
        if (!exceedsRewriteInputLimit(text, limits)) {
            return listOf(text)
        }
        val maxChunkChars = limits.rewriteInputMaxChars
        val maxChunkWords = limits.rewriteInputMaxWords
        val targetChunkChars = (maxChunkChars * CHUNK_TARGET_RATIO).toInt().coerceAtLeast(240)
        val targetChunkWords = (maxChunkWords * CHUNK_TARGET_RATIO).toInt().coerceAtLeast(40)
        val rawSegments = if (listMode) {
            text.split(LIST_SEGMENT_SPLIT_REGEX)
        } else {
            text.split(SENTENCE_SPLIT_REGEX)
        }
            .map { it.trim() }
            .filter { it.isNotBlank() }
        if (rawSegments.isEmpty()) return emptyList()

        val chunks = ArrayList<String>()
        var current = StringBuilder()

        fun flushCurrent() {
            if (current.isNotEmpty()) {
                chunks += current.toString().trim()
                current = StringBuilder()
            }
        }

        for (segment in rawSegments) {
            val normalizedSegment = segment.replace(WHITESPACE_REGEX, " ").trim()
            if (normalizedSegment.isBlank()) continue

            if (exceedsBounds(normalizedSegment, maxChunkChars, maxChunkWords)) {
                flushCurrent()
                val forcedChunks = forceSplitSegment(normalizedSegment, maxChunkChars, maxChunkWords)
                chunks += forcedChunks
                continue
            }

            val candidate = if (current.isEmpty()) {
                normalizedSegment
            } else {
                "${current.toString().trimEnd()} $normalizedSegment"
            }
            if (!exceedsBounds(candidate, targetChunkChars, targetChunkWords)) {
                current.clear()
                current.append(candidate)
            } else {
                flushCurrent()
                current.append(normalizedSegment)
            }
        }
        flushCurrent()
        return chunks.filterNot { exceedsBounds(it, maxChunkChars, maxChunkWords) }
    }

    private fun forceSplitSegment(
        segment: String,
        maxChars: Int,
        maxWords: Int
    ): List<String> {
        val words = segment.split(WHITESPACE_REGEX).filter { it.isNotBlank() }
        if (words.isEmpty()) return emptyList()
        val chunks = ArrayList<String>()
        var current = StringBuilder()
        var currentWords = 0

        for (word in words) {
            val candidate = if (current.isEmpty()) word else "${current.toString()} $word"
            val candidateWords = currentWords + 1
            if (candidate.length <= maxChars && candidateWords <= maxWords) {
                current.clear()
                current.append(candidate)
                currentWords = candidateWords
            } else {
                if (current.isNotEmpty()) {
                    chunks += current.toString()
                }
                current.clear()
                current.append(word.take(maxChars))
                currentWords = 1
            }
        }
        if (current.isNotEmpty()) {
            chunks += current.toString()
        }
        return chunks
    }

    private fun mergeRewrittenChunks(
        chunks: List<String>,
        listMode: Boolean
    ): String {
        if (chunks.isEmpty()) return ""
        val nonBlank = chunks.map { it.trim() }.filter { it.isNotBlank() }
        if (nonBlank.isEmpty()) return ""
        return if (listMode) {
            nonBlank.joinToString("\n")
        } else {
            nonBlank.joinToString(" ")
                .replace(WHITESPACE_REGEX, " ")
                .replace(SPACE_BEFORE_PUNCTUATION_REGEX, "$1")
                .trim()
        }
    }

    private fun exceedsBounds(
        text: String,
        maxChars: Int,
        maxWords: Int
    ): Boolean {
        return text.length > maxChars || wordCount(text) > maxWords
    }

    private fun captureRuntimeSnapshot(): RuntimeSnapshot {
        val profile = LiteRtRuntimeProfiler.snapshot(appContext)
        val status = hardAbortMarkerStore.currentStatus()
        val count = maxOf(status.suspectedAbortCount, suspectedNativeAbortCount)
        suspectedNativeAbortCount = count
        return RuntimeSnapshot(
            profile = profile,
            suspectedNativeAbortPreviousRun = suspectedNativeAbortPreviousRun,
            suspectedNativeAbortCount = count
        )
    }

    private fun currentRuntimeCustomInstructions(): String {
        return LiteRtRewritePolicy.clipCustomInstructions(settingsStore.customInstructions())
    }

    private fun wordCount(text: String): Int {
        return WORD_REGEX.findAll(text).count()
    }

    companion object {
        private const val TAG = "LiteRtSummarizer"
        private const val PROBE_TIMEOUT_MS = 4_000L
        private const val CONVERSATION_TIMEOUT_CANCEL_GRACE_MS = 120L
        private const val PROBE_RECHECK_INTERVAL_MS = 10 * 60 * 1000L
        private const val MAX_REWRITE_ATTEMPTS = 3
        private const val DEFAULT_ENGINE_MAX_TOKENS = 224
        private const val CHUNK_TARGET_RATIO = 0.82
        private val SUPPORTED_MODEL_HINTS = listOf(
            "gemma-3n",
            "gemma3-1b",
            "gemma-3-1b",
            "qwen2.5-1.5b",
            "phi-4-mini",
            "tinygarden"
        )
        private const val INTRO_SCAN_MAX_CHARS = 140
        private val WHITESPACE_REGEX = Regex("\\s+")
        private val SENTENCE_SPLIT_REGEX = Regex("(?<=[.!?])\\s+")
        private val LIST_SEGMENT_SPLIT_REGEX = Regex("\\n+|(?<=[,;])\\s+")
        private val REPEATED_FILLER_REGEX = Regex(
            "\\b(um+|uh+|erm+|emm+|hmm+)(?:\\s+\\1\\b)+",
            RegexOption.IGNORE_CASE
        )
        private val SPACE_BEFORE_PUNCTUATION_REGEX = Regex("\\s+([,.;!?])")
        private val REPEATED_PUNCTUATION_REGEX = Regex("([,.;!?])\\1+")
        private val PREFIX_LABEL_REGEX = Regex(
            "^(rewritten|rewrite|cleaned|output|result)\\s*:\\s*",
            RegexOption.IGNORE_CASE
        )
        private val WORD_REGEX = Regex("\\p{L}[\\p{L}\\p{N}'’-]*")
        private val HIGH_INTENSITY_REGEX = Regex(
            "\\b(very|extremely|heavily|drastically|significantly|major\\s+rewrite|substantially)\\b",
            RegexOption.IGNORE_CASE
        )
        private val DIRECTIVE_PREFIX_REGEX = Regex(
            "^\\s*(?:\\[([\\p{L}]+)]|/([\\p{L}]+)|(?:tone|style)\\s+([\\p{L}]+)\\s*[:\\-]?|([\\p{L}]+)\\s*[:\\-])\\s*",
            RegexOption.IGNORE_CASE
        )
        private val NATURAL_INTRO_DIRECTIVE_REGEX = Regex(
            "^\\s*(?:(?:please|pls)\\s+)?(?:(?:can|could|would)\\s+you\\s+)?" +
                "(?:(?:make|keep|rewrite|write|clean(?:\\s+up)?|format|turn)\\s+(?:this|it|message)?\\s+)?" +
                "(?:in\\s+(?:a\\s+)?)?(short|concise|brief|warm|friendly|kind|professional|formal|business|work|for\\s+work)" +
                "(?:\\s+(?:tone|style|version))?(?:\\s*[:,-]\\s*|\\s+)(.+)$",
            RegexOption.IGNORE_CASE
        )
    }
}
