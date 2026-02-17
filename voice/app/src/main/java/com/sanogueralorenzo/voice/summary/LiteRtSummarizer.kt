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

class LiteRtSummarizer(context: Context) : LiteRtWarmupClient {
    private data class RewriteRequest(
        val content: String
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
    private val backendPolicyStore = LiteRtBackendPolicyStore()

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

    override fun isModelAvailable(): Boolean {
        return ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm)
    }

    override fun summarizeBlocking(text: String): RewriteResult {
        return summarizeBlocking(text = text, promptTemplateOverride = null)
    }

    fun summarizeBlocking(
        text: String,
        promptTemplateOverride: String? = null
    ): RewriteResult {
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
                summarizeInternal(
                    normalizedInput = normalizedInput,
                    startedAtMs = startedAt,
                    promptTemplateOverride = promptTemplateOverride
                )
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
        startedAtMs: Long,
        promptTemplateOverride: String?
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
                listMode = listMode,
                promptTemplateOverride = promptTemplateOverride
            )
            val guardedOutput = applyComposeOutputGuard(
                originalText = request.content,
                candidateText = output
            )
            RewriteResult.Success(
                text = guardedOutput,
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
        listMode: Boolean,
        promptTemplateOverride: String?
    ): String {
        val userPrompt = LiteRtPromptTemplates.buildRewriteUserPrompt(
            inputText = request.content,
            promptTemplateOverride = promptTemplateOverride
        )
        val config = ConversationConfig(
            systemInstruction = Contents.of(""),
            samplerConfig = SamplerConfig(
                topK = LiteRtRuntimeConfig.TOP_K,
                topP = LiteRtRuntimeConfig.TOP_P,
                temperature = LiteRtRuntimeConfig.TEMPERATURE,
                seed = LiteRtRuntimeConfig.SEED
            )
        )
        val output = runConversation(
            localEngine = localEngine,
            config = config,
            userPrompt = userPrompt,
            timeoutMs = LiteRtRuntimeConfig.REQUEST_TIMEOUT_MS
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
                LiteRtPromptTemplates.buildEditSystemInstruction()
            ),
            samplerConfig = SamplerConfig(
                topK = LiteRtRuntimeConfig.TOP_K,
                topP = LiteRtRuntimeConfig.TOP_P,
                temperature = LiteRtRuntimeConfig.TEMPERATURE,
                seed = LiteRtRuntimeConfig.SEED
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
            timeoutMs = LiteRtRuntimeConfig.REQUEST_TIMEOUT_MS
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
                initializedMaxNumTokens == LiteRtRuntimeConfig.ENGINE_MAX_TOKENS
            ) {
                return@withLock current
            }

            closeEngineLocked()

            val candidateBackends = backendPolicyStore.preferredBackends()
            var lastError: Throwable? = null

            for (backend in candidateBackends) {
                val config = EngineConfig(
                    modelPath = path,
                    backend = backend,
                    maxNumTokens = LiteRtRuntimeConfig.ENGINE_MAX_TOKENS,
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
                    initializedMaxNumTokens = LiteRtRuntimeConfig.ENGINE_MAX_TOKENS
                    Log.i(TAG, "LiteRT engine initialized backend=$backend")
                    return@withLock fresh
                } catch (t: Throwable) {
                    runCatching { fresh?.close() }
                    lastError = t
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
        return "Timed out after ${LiteRtRuntimeConfig.REQUEST_TIMEOUT_MS}ms"
    }

    private fun elapsedSince(startedAtMs: Long): Long {
        return (System.currentTimeMillis() - startedAtMs).coerceAtLeast(0L)
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
        return RewriteRequest(content = text)
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
        val anchorMatches = CLEANED_ANCHOR_REGEX.findAll(cleaned).toList()
        if (anchorMatches.isNotEmpty()) {
            cleaned = cleaned.substring(anchorMatches.last().range.last + 1).trim()
        }
        cleaned = cleaned
            .replace(PREFIX_LABEL_REGEX, "")
            .trim()
            .trim('`')
            .trim()
            .removeSurrounding("\"")
            .removeSurrounding("'")
            .trim()
        if (cleaned.isBlank()) return ""
        if (cleaned.startsWith("user input:", ignoreCase = true)) {
            val nonEmptyLines = cleaned
                .lineSequence()
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .toList()
            if (nonEmptyLines.size >= 2) {
                cleaned = nonEmptyLines.last()
            }
        }
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

    private fun applyComposeOutputGuard(
        originalText: String,
        candidateText: String
    ): String {
        val original = originalText.trim()
        val candidate = candidateText.trim()
        if (original.isBlank()) return candidate
        if (candidate.isBlank()) return original

        val originalChars = original.length
        val candidateChars = candidate.length

        val expandedTooMuch =
            candidateChars > (originalChars * MAX_OUTPUT_EXPANSION_MULTIPLIER).toInt() &&
                (candidateChars - originalChars) > MAX_OUTPUT_EXPANSION_DELTA_CHARS
        if (expandedTooMuch) return original

        val compressedTooMuch =
            candidateChars < (originalChars * MIN_OUTPUT_COMPRESSION_MULTIPLIER).toInt() &&
                (originalChars - candidateChars) > MAX_OUTPUT_COMPRESSION_DELTA_CHARS
        if (compressedTooMuch) return original

        return candidate
    }

    companion object {
        private const val TAG = "LiteRtSummarizer"
        private const val CONVERSATION_TIMEOUT_CANCEL_GRACE_MS = 120L
        private const val MAX_ERROR_MESSAGE_CHARS = 320
        private const val MAX_OUTPUT_EXPANSION_MULTIPLIER = 1.5
        private const val MIN_OUTPUT_COMPRESSION_MULTIPLIER = 0.5
        private const val MAX_OUTPUT_EXPANSION_DELTA_CHARS = 20
        private const val MAX_OUTPUT_COMPRESSION_DELTA_CHARS = 20
        private val SUPPORTED_MODEL_HINTS = listOf(
            "gemma-3n",
            "gemma3-1b",
            "gemma-3-1b",
            "qwen2.5-1.5b",
            "phi-4-mini",
            "tinygarden"
        )
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
        private val CLEANED_ANCHOR_REGEX = Regex(
            "^cleaned\\s*:\\s*",
            setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)
        )
    }
}
