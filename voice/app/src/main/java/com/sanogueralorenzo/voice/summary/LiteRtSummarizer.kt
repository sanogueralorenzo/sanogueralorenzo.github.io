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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
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
    private enum class RewriteDirective {
        DEFAULT,
        SHORT,
        WARM,
        WORK
    }

    private data class RewriteRequest(
        val directive: RewriteDirective,
        val content: String
    )

    private sealed interface AttemptResult {
        data class Success(val text: String) : AttemptResult
        data class Failure(
            val reason: RewriteFallbackReason,
            val error: Throwable? = null
        ) : AttemptResult
    }

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val initMutex = Mutex()
    private val activeConversation = AtomicReference<Conversation?>()
    private val backendPolicyStore = LiteRtBackendPolicyStore(appContext)
    private val compatibilityChecker = LiteRtCompatibilityChecker(appContext)

    @Volatile
    private var engine: Engine? = null

    @Volatile
    private var initializedModelPath: String? = null

    @Volatile
    private var initializedBackend: Backend? = null

    @Volatile
    private var rewritesSinceEngineInit: Int = 0

    fun isModelAvailable(): Boolean {
        return ModelStore.isModelPresent(appContext, ModelCatalog.liteRtLm)
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

    fun warmupAsync() {
        scope.launch {
            val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm) ?: return@launch
            val localEngine = ensureEngine(modelFile) ?: return@launch
            val backend = initializedBackend ?: Backend.CPU
            runCompatibilityProbe(
                localEngine = localEngine,
                modelSha = currentModelSha(),
                appVersionCode = compatibilityChecker.currentAppVersionCode(),
                backend = backend,
                force = false
            )
        }
    }

    fun runCompatibilityProbeBlocking(force: Boolean = true): LiteRtCompatibilityStatus {
        val modelSha = currentModelSha()
        val appVersionCode = compatibilityChecker.currentAppVersionCode()
        val preferredBackendName = backendPolicyStore.preferredBackends(modelSha)
            .firstOrNull()
            ?.name
            ?: Backend.CPU.name

        return runBlocking(Dispatchers.Default) {
            val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm)
            if (modelFile == null) {
                return@runBlocking compatibilityChecker.recordFailure(
                    modelSha = modelSha,
                    appVersionCode = appVersionCode,
                    backendName = preferredBackendName,
                    reason = "model_missing"
                )
            }
            val localEngine = ensureEngine(modelFile)
            if (localEngine == null) {
                return@runBlocking compatibilityChecker.recordFailure(
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
                backend = initializedBackend ?: Backend.CPU,
                force = force
            )
        }
    }

    fun summarizeBlocking(
        text: String,
        maxTokens: Int
    ): RewriteResult {
        val startedAt = System.currentTimeMillis()
        if (text.isBlank()) {
            return RewriteResult.RewriteFallback(
                reason = RewriteFallbackReason.EMPTY_INPUT,
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
            summarizeInternal(text, maxTokens, startedAt)
        }
    }

    fun applyEditInstructionBlocking(
        originalText: String,
        instructionText: String,
        maxTokens: Int
    ): RewriteResult {
        val startedAt = System.currentTimeMillis()
        if (originalText.isBlank() || instructionText.isBlank()) {
            return RewriteResult.RewriteFallback(
                reason = RewriteFallbackReason.EMPTY_INPUT,
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
            applyEditInstructionInternal(
                originalText = originalText,
                instructionText = instructionText,
                maxTokens = maxTokens,
                startedAtMs = startedAt
            )
        }
    }

    fun cancelActive() {
        activeConversation.get()?.cancelProcess()
    }

    fun release() {
        cancelActive()
        activeConversation.set(null)
        runBlocking(Dispatchers.Default) {
            initMutex.withLock {
                closeEngineLocked()
            }
        }
        scope.cancel()
    }

    private suspend fun summarizeInternal(
        text: String,
        maxTokens: Int,
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

        var lastReason = RewriteFallbackReason.ERROR
        var retriedAfterInvalidArgument = false

        for (attempt in 0 until MAX_REWRITE_ATTEMPTS) {
            val localEngine = ensureEngine(
                modelFile = modelFile,
                forceReset = attempt > 0 && lastReason == RewriteFallbackReason.INVALID_ARGUMENT
            ) ?: return fallbackResult(RewriteFallbackReason.ENGINE_INIT_FAILED, startedAtMs)

            val backend = initializedBackend ?: Backend.CPU
            val compatibilityStatus = runCompatibilityProbe(
                localEngine = localEngine,
                modelSha = currentModelSha(),
                appVersionCode = compatibilityChecker.currentAppVersionCode(),
                backend = backend,
                force = false
            )
            if (compatibilityStatus.disabled) {
                return fallbackResult(RewriteFallbackReason.COMPATIBILITY_DISABLED, startedAtMs)
            }

            val timeoutMs = LiteRtRewritePolicy.adaptiveTimeoutMs(
                inputText = request.content,
                rewritesSinceEngineInit = rewritesSinceEngineInit
            )
            val attemptResult = rewriteOnce(
                localEngine = localEngine,
                request = request,
                maxTokens = maxTokens,
                timeoutMs = timeoutMs
            )

            when (attemptResult) {
                is AttemptResult.Success -> {
                    rewritesSinceEngineInit += 1
                    return RewriteResult.RewriteSuccess(
                        text = attemptResult.text,
                        latencyMs = elapsedSince(startedAtMs),
                        backend = backend
                    )
                }

                is AttemptResult.Failure -> {
                    lastReason = attemptResult.reason

                    if (backend == Backend.GPU && shouldDemoteGpu(attemptResult.reason)) {
                        backendPolicyStore.markGpuFailed(currentModelSha())
                        resetEngineNow()
                        continue
                    }

                    if (
                        attemptResult.reason == RewriteFallbackReason.INVALID_ARGUMENT &&
                        !retriedAfterInvalidArgument
                    ) {
                        retriedAfterInvalidArgument = true
                        resetEngineNow()
                        continue
                    }

                    if (
                        attemptResult.reason == RewriteFallbackReason.TIMEOUT &&
                        attempt == 0
                    ) {
                        continue
                    }

                    return fallbackResult(attemptResult.reason, startedAtMs)
                }
            }
        }

        return fallbackResult(lastReason, startedAtMs)
    }

    private suspend fun rewriteOnce(
        localEngine: Engine,
        request: RewriteRequest,
        maxTokens: Int,
        timeoutMs: Long
    ): AttemptResult {
        val config = ConversationConfig(
            systemInstruction = Contents.of(
                buildRewriteInstruction(request.content, request.directive)
            ),
            samplerConfig = SamplerConfig(
                topK = 1,
                topP = 1.0,
                temperature = 0.0,
                seed = 42
            )
        )
        val conversation = localEngine.createConversation(config)
        activeConversation.set(conversation)

        return try {
            val output = withTimeout(timeoutMs) {
                val streamed = StringBuilder()
                var lastChunk = ""
                conversation.sendMessageAsync(request.content).collect { message ->
                    val chunk = message.toTextPayload()
                    if (chunk.isBlank()) return@collect
                    if (chunk.startsWith(lastChunk)) {
                        streamed.append(chunk.removePrefix(lastChunk))
                    } else if (!lastChunk.startsWith(chunk)) {
                        streamed.append(chunk)
                    }
                    lastChunk = chunk
                    if (streamed.length > maxTokens * 6) {
                        conversation.cancelProcess()
                    }
                }
                if (streamed.isNotBlank()) streamed.toString() else lastChunk
            }

            val cleaned = cleanModelOutput(output, looksLikeList(request.content))
            if (cleaned.isBlank()) {
                AttemptResult.Failure(RewriteFallbackReason.EMPTY_OUTPUT)
            } else if (!isSafeRewrite(request.content, cleaned)) {
                AttemptResult.Failure(RewriteFallbackReason.SAFETY_REJECTED)
            } else {
                AttemptResult.Success(cleaned)
            }
        } catch (t: Throwable) {
            if (LiteRtRewritePolicy.isInvalidArgumentError(t)) {
                AttemptResult.Failure(RewriteFallbackReason.INVALID_ARGUMENT, t)
            } else {
                val timeout = t is kotlinx.coroutines.TimeoutCancellationException
                if (timeout) {
                    AttemptResult.Failure(RewriteFallbackReason.TIMEOUT, t)
                } else {
                    Log.w(TAG, "LiteRT rewrite failed", t)
                    AttemptResult.Failure(RewriteFallbackReason.ERROR, t)
                }
            }
        } finally {
            runCatching { conversation.cancelProcess() }
            if (activeConversation.get() === conversation) {
                activeConversation.set(null)
            }
            conversation.close()
        }
    }

    private suspend fun applyEditInstructionInternal(
        originalText: String,
        instructionText: String,
        maxTokens: Int,
        startedAtMs: Long
    ): RewriteResult {
        val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm)
            ?: return fallbackResult(RewriteFallbackReason.MODEL_UNAVAILABLE, startedAtMs)

        val original = originalText.trim()
        val instructions = normalizeInput(instructionText)
        if (original.isBlank() || instructions.isBlank()) {
            return fallbackResult(RewriteFallbackReason.EMPTY_INPUT, startedAtMs)
        }

        var lastReason = RewriteFallbackReason.ERROR
        var retriedAfterInvalidArgument = false

        for (attempt in 0 until MAX_REWRITE_ATTEMPTS) {
            val localEngine = ensureEngine(
                modelFile = modelFile,
                forceReset = attempt > 0 && lastReason == RewriteFallbackReason.INVALID_ARGUMENT
            ) ?: return fallbackResult(RewriteFallbackReason.ENGINE_INIT_FAILED, startedAtMs)

            val backend = initializedBackend ?: Backend.CPU
            val compatibilityStatus = runCompatibilityProbe(
                localEngine = localEngine,
                modelSha = currentModelSha(),
                appVersionCode = compatibilityChecker.currentAppVersionCode(),
                backend = backend,
                force = false
            )
            if (compatibilityStatus.disabled) {
                return fallbackResult(RewriteFallbackReason.COMPATIBILITY_DISABLED, startedAtMs)
            }

            val timeoutMs = LiteRtRewritePolicy.adaptiveTimeoutMs(
                inputText = "$original\n$instructions",
                rewritesSinceEngineInit = rewritesSinceEngineInit
            )
            val attemptResult = editOnce(
                localEngine = localEngine,
                originalText = original,
                instructionText = instructions,
                maxTokens = maxTokens,
                timeoutMs = timeoutMs
            )

            when (attemptResult) {
                is AttemptResult.Success -> {
                    rewritesSinceEngineInit += 1
                    return RewriteResult.RewriteSuccess(
                        text = attemptResult.text,
                        latencyMs = elapsedSince(startedAtMs),
                        backend = backend
                    )
                }

                is AttemptResult.Failure -> {
                    lastReason = attemptResult.reason
                    if (backend == Backend.GPU && shouldDemoteGpu(attemptResult.reason)) {
                        backendPolicyStore.markGpuFailed(currentModelSha())
                        resetEngineNow()
                        continue
                    }
                    if (
                        attemptResult.reason == RewriteFallbackReason.INVALID_ARGUMENT &&
                        !retriedAfterInvalidArgument
                    ) {
                        retriedAfterInvalidArgument = true
                        resetEngineNow()
                        continue
                    }
                    if (attemptResult.reason == RewriteFallbackReason.TIMEOUT && attempt == 0) {
                        continue
                    }
                    return fallbackResult(attemptResult.reason, startedAtMs)
                }
            }
        }

        return fallbackResult(lastReason, startedAtMs)
    }

    private suspend fun editOnce(
        localEngine: Engine,
        originalText: String,
        instructionText: String,
        maxTokens: Int,
        timeoutMs: Long
    ): AttemptResult {
        val config = ConversationConfig(
            systemInstruction = Contents.of(EDIT_SYSTEM_INSTRUCTION),
            samplerConfig = SamplerConfig(
                topK = 1,
                topP = 1.0,
                temperature = 0.0,
                seed = 42
            )
        )
        val conversation = localEngine.createConversation(config)
        activeConversation.set(conversation)
        val userPrompt = buildEditPrompt(
            originalText = originalText,
            instructionText = instructionText
        )

        return try {
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
                    if (streamed.length > maxTokens * 6) {
                        conversation.cancelProcess()
                    }
                }
                if (streamed.isNotBlank()) streamed.toString() else lastChunk
            }

            val cleaned = cleanModelOutput(output, bulletMode = looksLikeList(originalText))
            if (cleaned.isBlank()) {
                AttemptResult.Failure(RewriteFallbackReason.EMPTY_OUTPUT)
            } else {
                AttemptResult.Success(cleaned)
            }
        } catch (t: Throwable) {
            if (LiteRtRewritePolicy.isInvalidArgumentError(t)) {
                AttemptResult.Failure(RewriteFallbackReason.INVALID_ARGUMENT, t)
            } else {
                val timeout = t is kotlinx.coroutines.TimeoutCancellationException
                if (timeout) {
                    AttemptResult.Failure(RewriteFallbackReason.TIMEOUT, t)
                } else {
                    Log.w(TAG, "LiteRT edit failed", t)
                    AttemptResult.Failure(RewriteFallbackReason.ERROR, t)
                }
            }
        } finally {
            runCatching { conversation.cancelProcess() }
            if (activeConversation.get() === conversation) {
                activeConversation.set(null)
            }
            conversation.close()
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
            if (existing.healthy || existing.disabled) {
                return existing
            }
        }

        return try {
            val probeOutput = runProbeOnce(localEngine)
            if (probeOutput.isBlank()) {
                compatibilityChecker.recordFailure(
                    modelSha = modelSha,
                    appVersionCode = appVersionCode,
                    backendName = backend.name,
                    reason = "probe_empty_output"
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
            systemInstruction = Contents.of(PROBE_SYSTEM_INSTRUCTION),
            samplerConfig = SamplerConfig(
                topK = 1,
                topP = 1.0,
                temperature = 0.0,
                seed = 7
            )
        )
        val conversation = localEngine.createConversation(config)
        return try {
            withTimeout(PROBE_TIMEOUT_MS) {
                val streamed = StringBuilder()
                var lastChunk = ""
                conversation.sendMessageAsync(PROBE_USER_MESSAGE).collect { message ->
                    val chunk = message.toTextPayload()
                    if (chunk.isBlank()) return@collect
                    if (chunk.startsWith(lastChunk)) {
                        streamed.append(chunk.removePrefix(lastChunk))
                    } else if (!lastChunk.startsWith(chunk)) {
                        streamed.append(chunk)
                    }
                    lastChunk = chunk
                }
                val output = if (streamed.isNotBlank()) streamed.toString() else lastChunk
                cleanModelOutput(output, bulletMode = false)
            }
        } finally {
            runCatching { conversation.cancelProcess() }
            conversation.close()
        }
    }

    private suspend fun ensureEngine(modelFile: File?, forceReset: Boolean = false): Engine? {
        if (modelFile == null || !modelFile.exists()) return null
        return initMutex.withLock {
            val current = engine
            val path = modelFile.absolutePath
            if (!forceReset && current != null && current.isInitialized() && initializedModelPath == path) {
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
                    maxNumTokens = 320,
                    cacheDir = appContext.cacheDir.absolutePath
                )
                var fresh: Engine? = null
                try {
                    fresh = Engine(config)
                    fresh.initialize()
                    engine = fresh
                    initializedModelPath = path
                    initializedBackend = backend
                    rewritesSinceEngineInit = 0
                    Log.i(TAG, "LiteRT engine initialized with backend=$backend")
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
        initializedBackend = null
        rewritesSinceEngineInit = 0
    }

    private fun shouldDemoteGpu(reason: RewriteFallbackReason): Boolean {
        return reason == RewriteFallbackReason.TIMEOUT ||
            reason == RewriteFallbackReason.INVALID_ARGUMENT ||
            reason == RewriteFallbackReason.ERROR
    }

    private fun fallbackResult(reason: RewriteFallbackReason, startedAtMs: Long): RewriteResult {
        return RewriteResult.RewriteFallback(
            reason = reason,
            latencyMs = elapsedSince(startedAtMs)
        )
    }

    private fun elapsedSince(startedAtMs: Long): Long {
        return (System.currentTimeMillis() - startedAtMs).coerceAtLeast(0L)
    }

    private fun currentModelSha(): String {
        val sha = ModelCatalog.liteRtLm.sha256.trim().lowercase()
        return if (sha.isBlank()) ModelCatalog.liteRtLm.id else sha
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

    private fun buildRewriteInstruction(input: String, directive: RewriteDirective): String {
        val directiveRule = when (directive) {
            RewriteDirective.DEFAULT ->
                "Keep neutral tone and preserve the speaker's intent exactly."

            RewriteDirective.SHORT ->
                "Keep it concise and direct; remove minor verbosity but keep all actionable details."

            RewriteDirective.WARM ->
                "Keep a warm, friendly tone while preserving exact meaning and facts."

            RewriteDirective.WORK ->
                "Use a professional workplace tone: clear, direct, and precise."
        }
        val formatRule = if (looksLikeList(input)) {
            "Output a bullet list using '- '. Keep all requested items."
        } else {
            "Output plain prose with punctuation and capitalization. Keep the same meaning and details."
        }
        return "$BASE_INSTRUCTIONS $directiveRule $formatRule $SAFETY_INSTRUCTIONS"
    }

    private fun buildEditPrompt(originalText: String, instructionText: String): String {
        return buildString(originalText.length + instructionText.length + 80) {
            append("ORIGINAL_MESSAGE:\n")
            append(originalText)
            append("\n\nEDIT_INSTRUCTION:\n")
            append(instructionText)
        }
    }

    private fun parseRewriteRequest(text: String): RewriteRequest {
        val match = DIRECTIVE_PREFIX_REGEX.find(text)
            ?: return RewriteRequest(directive = RewriteDirective.DEFAULT, content = text)

        val rawTag = listOfNotNull(
            match.groups[1]?.value,
            match.groups[2]?.value,
            match.groups[3]?.value,
            match.groups[4]?.value
        ).firstOrNull()?.lowercase()

        val directive = when (rawTag) {
            "short", "concise", "brief" -> RewriteDirective.SHORT
            "warm", "friendly", "kind" -> RewriteDirective.WARM
            "work", "professional", "formal", "business" -> RewriteDirective.WORK
            else -> RewriteDirective.DEFAULT
        }

        if (directive == RewriteDirective.DEFAULT) {
            return RewriteRequest(directive = RewriteDirective.DEFAULT, content = text)
        }

        val content = text.substring(match.range.last + 1).trimStart()
        if (content.isBlank()) {
            return RewriteRequest(directive = RewriteDirective.DEFAULT, content = text)
        }
        return RewriteRequest(directive = directive, content = content)
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

    private fun cleanModelOutput(text: String, bulletMode: Boolean): String {
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
        return LIST_CUE_REGEX.containsMatchIn(text)
    }

    private fun isSafeRewrite(source: String, rewritten: String): Boolean {
        val candidate = rewritten.trim()
        if (candidate.isBlank()) return false

        val sourceHasDigits = source.any(Char::isDigit)
        val rewrittenHasDigits = candidate.any(Char::isDigit)
        if (sourceHasDigits && !rewrittenHasDigits) return false

        val sourceNumbers = NUMBER_REGEX.findAll(source).map { it.value }.toSet()
        val rewrittenNumbers = NUMBER_REGEX.findAll(candidate).map { it.value }.toSet()
        if (!rewrittenNumbers.containsAll(sourceNumbers)) return false

        val sourceLinks = LINKISH_REGEX.findAll(source).map { it.value.lowercase() }.toSet()
        val rewrittenLinks = LINKISH_REGEX.findAll(candidate).map { it.value.lowercase() }.toSet()
        if (!rewrittenLinks.containsAll(sourceLinks)) return false

        if (hasNegation(source) && !hasNegation(candidate)) return false

        val sourceWords = WORD_REGEX.findAll(source).count()
        val rewrittenWords = WORD_REGEX.findAll(candidate).count()
        if (sourceWords >= 8) {
            val ratio = rewrittenWords.toFloat() / sourceWords.toFloat()
            val hasIntentCue = FINAL_INTENT_CUE_REGEX.containsMatchIn(source)
            if (ratio < MIN_WORD_RATIO && !hasIntentCue) {
                return false
            }
            if (ratio > MAX_WORD_RATIO && !hasIntentCue) {
                return false
            }
        }

        return true
    }

    private fun hasNegation(text: String): Boolean {
        return NEGATION_REGEX.containsMatchIn(text)
    }

    companion object {
        private const val TAG = "LiteRtSummarizer"
        private const val PROBE_TIMEOUT_MS = 4_000L
        private const val MAX_REWRITE_ATTEMPTS = 2
        private const val MIN_WORD_RATIO = 0.3f
        private const val MAX_WORD_RATIO = 1.35f
        private val WHITESPACE_REGEX = Regex("\\s+")
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
        private val NUMBER_REGEX = Regex("\\b\\d+(?:[.,:/-]\\d+)*\\b")
        private val LINKISH_REGEX = Regex(
            "\\b(?:https?://\\S+|www\\.\\S+|\\S+@\\S+\\.\\S+)\\b",
            RegexOption.IGNORE_CASE
        )
        private val NEGATION_REGEX = Regex(
            "\\b(no|not|never|none|don't|doesn't|didn't|can't|cannot|won't|shouldn't|isn't|aren't|wasn't|weren't|without)\\b",
            RegexOption.IGNORE_CASE
        )
        private val LIST_CUE_REGEX = Regex(
            "\\b(first|second|third|fourth|fifth|next|then|finally|list|bullet|bullets|items?|steps?|points?)\\b|\\d+[.)]",
            RegexOption.IGNORE_CASE
        )
        private val FINAL_INTENT_CUE_REGEX = Regex(
            "\\b(never\\s?mind|nevermind|scratch\\s+that|actually|instead|rather)\\b",
            RegexOption.IGNORE_CASE
        )
        private val DIRECTIVE_PREFIX_REGEX = Regex(
            "^\\s*(?:\\[([\\p{L}]+)]|/([\\p{L}]+)|(?:tone|style)\\s+([\\p{L}]+)\\s*[:\\-]?|([\\p{L}]+)\\s*[:\\-])\\s*",
            RegexOption.IGNORE_CASE
        )
        private const val BASE_INSTRUCTIONS =
            "You rewrite noisy ASR transcripts into send-ready text. " +
                "Remove disfluencies (um, uh, emm), false starts, and repeated fragments. " +
                "Resolve self-corrections to the final intended wording. " +
                "When the speaker changes direction (for example 'never mind'), keep the final intent. " +
                "Preserve all concrete facts and constraints."
        private const val SAFETY_INSTRUCTIONS =
            "Do not summarize, do not drop important meaning, and do not add new facts. " +
                "Preserve names, numbers, dates, links, and negation exactly when present. " +
                "Output only the rewritten text."
        private const val EDIT_SYSTEM_INSTRUCTION =
            "You are an expert text editor. Apply EDIT_INSTRUCTION to ORIGINAL_MESSAGE exactly. " +
                "Keep all untouched content faithful. Do not invent facts. " +
                "Return only the fully edited final message, with no explanations."

        private const val PROBE_SYSTEM_INSTRUCTION =
            "Return a very short plain-text response. No markdown."
        private const val PROBE_USER_MESSAGE = "ping"
    }
}
