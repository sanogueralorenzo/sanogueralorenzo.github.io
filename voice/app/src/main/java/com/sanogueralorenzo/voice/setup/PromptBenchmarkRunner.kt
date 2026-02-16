package com.sanogueralorenzo.voice.setup

import com.sanogueralorenzo.voice.summary.RewriteResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

object PromptBenchmarkRunner {
    const val DEFAULT_REPEATS = 1

    suspend fun runAll(
        gateway: PromptBenchmarkGateway,
        cases: List<PromptBenchmarkCase>,
        suiteVersion: String,
        repeats: Int = DEFAULT_REPEATS,
        modelId: String,
        promptInstructionsSnapshot: String,
        onProgress: ((PromptBenchmarkProgress) -> Unit)? = null
    ): PromptBenchmarkSessionResult {
        require(repeats > 0) { "repeats must be > 0" }
        val startedAt = System.currentTimeMillis()
        val caseResults = ArrayList<PromptBenchmarkCaseResult>(cases.size)

        for ((caseIndexZeroBased, caseDef) in cases.withIndex()) {
            val runs = ArrayList<PromptBenchmarkRunResult>(repeats)
            val caseIndex = caseIndexZeroBased + 1

            for (runIndex in 1..repeats) {
                currentCoroutineContext().ensureActive()
                onProgress?.invoke(
                    PromptBenchmarkProgress(
                        caseIndex = caseIndex,
                        totalCases = cases.size,
                        runIndex = runIndex,
                        repeats = repeats,
                        caseId = caseDef.id
                    )
                )

                val rewriteResult = withContext(Dispatchers.IO) {
                    when (caseDef.type) {
                        PromptBenchmarkCaseType.COMPOSE -> gateway.runCompose(caseDef.composeInput.orEmpty())
                        PromptBenchmarkCaseType.EDIT -> gateway.runEdit(
                            original = caseDef.editOriginal.orEmpty(),
                            instruction = caseDef.editInstruction.orEmpty()
                        )
                    }
                }

                runs += rewriteResult.toRunResult(runIndex = runIndex)
            }

            caseResults += aggregateCase(caseDef, runs)
        }

        val totalElapsedMs = (System.currentTimeMillis() - startedAt).coerceAtLeast(0L)
        return PromptBenchmarkSessionResult(
            suiteVersion = suiteVersion,
            repeats = repeats,
            timestampMs = System.currentTimeMillis(),
            totalElapsedMs = totalElapsedMs,
            modelId = modelId,
            promptInstructionsSnapshot = promptInstructionsSnapshot,
            cases = caseResults
        )
    }

    private fun RewriteResult.toRunResult(runIndex: Int): PromptBenchmarkRunResult {
        return when (this) {
            is RewriteResult.Success -> PromptBenchmarkRunResult(
                runIndex = runIndex,
                output = text,
                latencyMs = latencyMs,
                backend = backend.name,
                errorType = null,
                errorMessage = null,
                success = true
            )

            is RewriteResult.Failure -> PromptBenchmarkRunResult(
                runIndex = runIndex,
                output = null,
                latencyMs = latencyMs,
                backend = backend?.name,
                errorType = error.type,
                errorMessage = error.litertError,
                success = false
            )
        }
    }

    private fun aggregateCase(
        caseDef: PromptBenchmarkCase,
        runs: List<PromptBenchmarkRunResult>
    ): PromptBenchmarkCaseResult {
        val latencies = runs.map { it.latencyMs }
        val successfulOutputs = runs
            .filter { it.success }
            .mapNotNull { it.output }
            .map { it.trim() }
            .filter { it.isNotBlank() }

        val uniqueOutputsCount = if (successfulOutputs.isEmpty()) 0 else successfulOutputs.toSet().size
        val avgLatency = if (latencies.isEmpty()) 0L else latencies.average().toLong()

        return PromptBenchmarkCaseResult(
            caseDef = caseDef,
            runs = runs,
            uniqueOutputsCount = uniqueOutputsCount,
            avgLatencyMs = avgLatency,
            minLatencyMs = latencies.minOrNull() ?: 0L,
            maxLatencyMs = latencies.maxOrNull() ?: 0L
        )
    }
}
