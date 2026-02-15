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
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import java.io.File
import java.util.concurrent.atomic.AtomicReference

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

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val operationMutex = Mutex()
    private val initMutex = Mutex()
    private val conversationMutex = Mutex()
    private val activeConversation = AtomicReference<Conversation?>()
    private val backendPolicyStore = LiteRtBackendPolicyStore(appContext)
    private val settingsStore = VoiceSettingsStore(appContext)

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

    fun isModelAvailable(): Boolean {
        return ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm)
    }

    fun currentBackendPolicy(): LiteRtBackendPolicy {
        return backendPolicyStore.currentPolicy(currentModelSha())
    }

    fun warmupAsync() {
        scope.launch {
            operationMutex.withLock {
                if (!isConfiguredModelSupported()) return@withLock
                val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm) ?: return@withLock
                runCatching {
                    ensureEngine(modelFile)
                }.onFailure { error ->
                    Log.w(TAG, "LiteRT warmup failed", error)
                }
            }
        }
    }

    fun summarizeBlocking(text: String): RewriteResult {
        val startedAt = System.currentTimeMillis()
        val normalizedInput = normalizeInput(text)
        if (normalizedInput.isBlank()) {
            return RewriteResult.Success(
                text = "",
                latencyMs = 0L,
                backend = initializedBackend ?: Backend.GPU
            )
        }
        if (!isConfiguredModelSupported() || !isModelAvailable()) {
            return RewriteResult.Success(
                text = normalizedInput,
                latencyMs = 0L,
                backend = initializedBackend ?: Backend.GPU
            )
        }

        return runBlocking(Dispatchers.Default) {
            operationMutex.withLock {
                summarizeInternal(normalizedInput, startedAt)
            }
        }
    }

    fun applyEditInstructionBlocking(
        originalText: String,
        instructionText: String
    ): RewriteResult {
        val startedAt = System.currentTimeMillis()
        val normalizedSource = originalText.trim()
        val normalizedInstruction = normalizeInput(instructionText)
        if (normalizedSource.isBlank() || normalizedInstruction.isBlank()) {
            return RewriteResult.Success(
                text = originalText,
                latencyMs = 0L,
                backend = initializedBackend ?: Backend.GPU
            )
        }
        if (!isConfiguredModelSupported() || !isModelAvailable()) {
            return RewriteResult.Success(
                text = originalText,
                latencyMs = 0L,
                backend = initializedBackend ?: Backend.GPU
            )
        }

        return runBlocking(Dispatchers.Default) {
            operationMutex.withLock {
                applyEditInstructionInternal(
                    originalText = normalizedSource,
                    instructionText = normalizedInstruction,
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
        normalizedInput: String,
        startedAtMs: Long
    ): RewriteResult {
        val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm)
            ?: return RewriteResult.Success(
                text = normalizedInput,
                latencyMs = elapsedSince(startedAtMs),
                backend = initializedBackend ?: Backend.GPU
            )

        val request = parseRewriteRequest(normalizedInput)
        if (request.content.isBlank()) {
            return RewriteResult.Success(
                text = normalizedInput,
                latencyMs = elapsedSince(startedAtMs),
                backend = initializedBackend ?: Backend.GPU
            )
        }

        val localEngine = try {
            ensureEngine(modelFile)
        } catch (t: Throwable) {
            return RewriteResult.Failure(
                latencyMs = elapsedSince(startedAtMs),
                backend = initializedBackend,
                error = toLiteRtFailure(t, "LiteRT engine initialization failed")
            )
        }

        val backend = initializedBackend ?: Backend.GPU
        return try {
            val listMode = looksLikeList(request.content)
            val output = rewriteOnce(
                localEngine = localEngine,
                request = request,
                listMode = listMode
            )
            RewriteResult.Success(
                text = output,
                latencyMs = elapsedSince(startedAtMs),
                backend = backend
            )
        } catch (t: Throwable) {
            if (LiteRtRewritePolicy.isInvalidArgumentError(t)) {
                resetEngineNow()
            }
            RewriteResult.Failure(
                latencyMs = elapsedSince(startedAtMs),
                backend = backend,
                error = toLiteRtFailure(t, timeoutFallbackMessage(t) ?: "LiteRT rewrite failed")
            )
        }
    }

    private suspend fun rewriteOnce(
        localEngine: Engine,
        request: RewriteRequest,
        listMode: Boolean
    ): String {
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
        val output = runConversation(
            localEngine = localEngine,
            config = config,
            userPrompt = request.content,
            timeoutMs = REQUEST_TIMEOUT_MS
        )
        return cleanModelOutput(output, bulletMode = listMode)
    }

    private suspend fun applyEditInstructionInternal(
        originalText: String,
        instructionText: String,
        startedAtMs: Long
    ): RewriteResult {
        val modelFile = ModelStore.ensureModelFile(appContext, ModelCatalog.liteRtLm)
            ?: return RewriteResult.Success(
                text = originalText,
                latencyMs = elapsedSince(startedAtMs),
                backend = initializedBackend ?: Backend.GPU
            )

        val instructionAnalysis = LiteRtEditHeuristics.analyzeInstruction(instructionText)
        val editRequest = EditRequest(
            originalText = originalText,
            instructionText = instructionAnalysis.normalizedInstruction,
            intent = instructionAnalysis.intent,
            listMode = looksLikeList(originalText) || looksLikeList(instructionAnalysis.normalizedInstruction)
        )

        val localEngine = try {
            ensureEngine(modelFile)
        } catch (t: Throwable) {
            return RewriteResult.Failure(
                latencyMs = elapsedSince(startedAtMs),
                backend = initializedBackend,
                error = toLiteRtFailure(t, "LiteRT engine initialization failed")
            )
        }

        val backend = initializedBackend ?: Backend.GPU
        return try {
            val output = editOnce(
                localEngine = localEngine,
                request = editRequest
            )
            RewriteResult.Success(
                text = output,
                latencyMs = elapsedSince(startedAtMs),
                backend = backend
            )
        } catch (t: Throwable) {
            if (LiteRtRewritePolicy.isInvalidArgumentError(t)) {
                resetEngineNow()
            }
            RewriteResult.Failure(
                latencyMs = elapsedSince(startedAtMs),
                backend = backend,
                error = toLiteRtFailure(t, timeoutFallbackMessage(t) ?: "LiteRT edit failed")
            )
        }
    }

    private suspend fun editOnce(
        localEngine: Engine,
        request: EditRequest
    ): String {
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
        val output = runConversation(
            localEngine = localEngine,
            config = config,
            userPrompt = userPrompt,
            timeoutMs = REQUEST_TIMEOUT_MS
        )
        return cleanModelOutput(text = output, bulletMode = request.listMode)
    }

    private suspend fun runConversation(
        localEngine: Engine,
        config: ConversationConfig,
        userPrompt: String,
        timeoutMs: Long
    ): String {
        val conversation = localEngine.createConversation(config)
        conversationMutex.withLock {
            activeConversation.set(conversation)
        }
        try {
            return withTimeout(timeoutMs) {
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
        } catch (t: Throwable) {
            if (t is TimeoutCancellationException) {
                conversationMutex.withLock {
                    if (activeConversation.get() === conversation) {
                        runCatching { conversation.cancelProcess() }
                    }
                }
                delay(CONVERSATION_TIMEOUT_CANCEL_GRACE_MS)
            }
            throw t
        } finally {
            conversationMutex.withLock {
                if (activeConversation.get() === conversation) {
                    activeConversation.set(null)
                }
                runCatching { conversation.close() }
            }
        }
    }

    private suspend fun ensureEngine(
        modelFile: File,
        forceReset: Boolean = false
    ): Engine {
        if (!modelFile.exists()) {
            throw IllegalStateException("LiteRT model file unavailable")
        }
        return initMutex.withLock {
            val current = engine
            val path = modelFile.absolutePath
            val modelStamp = "${modelFile.length()}:${modelFile.lastModified()}"
            if (
                !forceReset &&
                current != null &&
                current.isInitialized() &&
                initializedModelPath == path &&
                initializedModelStamp == modelStamp &&
                initializedMaxNumTokens == DEFAULT_ENGINE_MAX_TOKENS
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
                    maxNumTokens = DEFAULT_ENGINE_MAX_TOKENS,
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
                    initializedMaxNumTokens = DEFAULT_ENGINE_MAX_TOKENS
                    Log.i(TAG, "LiteRT engine initialized backend=$backend")
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

            throw (lastError ?: IllegalStateException("LiteRT engine init failed on all backends"))
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
        activeConversation.set(null)
    }

    private fun toLiteRtFailure(
        t: Throwable?,
        fallbackMessage: String? = null
    ): LiteRtFailureException {
        val type = when {
            t != null && LiteRtRewritePolicy.isInvalidArgumentError(t) -> LiteRtFailureException.TYPE_INVALID_ARGUMENT
            t != null && LiteRtRewritePolicy.isInputTooLongError(t) -> LiteRtFailureException.TYPE_INPUT_TOO_LONG
            else -> LiteRtFailureException.TYPE_UNKNOWN
        }
        val litertError = extractLiteRtError(t)
            ?: sanitizeErrorMessage(fallbackMessage)
            ?: "LiteRT runtime failure"
        return LiteRtFailureException(
            type = type,
            litertError = litertError,
            cause = t
        )
    }

    private fun extractLiteRtError(t: Throwable?): String? {
        var current = t
        while (current != null) {
            val message = sanitizeErrorMessage(current.message)
            if (!message.isNullOrBlank()) {
                return message
            }
            current = current.cause
        }
        return null
    }

    private fun sanitizeErrorMessage(message: String?): String? {
        val sanitized = message
            ?.replace(WHITESPACE_REGEX, " ")
            ?.trim()
            ?.take(MAX_ERROR_MESSAGE_CHARS)
            .orEmpty()
        return sanitized.ifBlank { null }
    }

    private fun timeoutFallbackMessage(t: Throwable): String? {
        if (t !is TimeoutCancellationException) return null
        return "Timed out after ${REQUEST_TIMEOUT_MS}ms"
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

    private fun hasHighIntensityIntro(text: String): Boolean {
        val intro = text.trim().take(INTRO_SCAN_MAX_CHARS)
        if (intro.isBlank()) return false
        return HIGH_INTENSITY_REGEX.containsMatchIn(intro)
    }

    private fun currentRuntimeCustomInstructions(): String {
        return LiteRtRewritePolicy.clipCustomInstructions(settingsStore.customInstructions())
    }

    companion object {
        private const val TAG = "LiteRtSummarizer"
        private const val REQUEST_TIMEOUT_MS = 30_000L
        private const val CONVERSATION_TIMEOUT_CANCEL_GRACE_MS = 120L
        private const val DEFAULT_ENGINE_MAX_TOKENS = 224
        private const val MAX_ERROR_MESSAGE_CHARS = 320
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
