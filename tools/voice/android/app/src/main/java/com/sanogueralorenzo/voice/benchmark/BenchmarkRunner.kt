package com.sanogueralorenzo.voice.benchmark

import com.sanogueralorenzo.voice.summary.RewriteResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

object BenchmarkRunner {
    const val DEFAULT_REPEATS = 1

    suspend fun runAll(
        gateway: BenchmarkGateway,
        cases: List<BenchmarkCase>,
        suiteVersion: String,
        repeats: Int = DEFAULT_REPEATS,
        modelId: String,
        promptInstructionsSnapshot: String,
        runtimeConfigSnapshot: String,
        composePromptTemplateOverride: String? = null,
        onProgress: ((BenchmarkProgress) -> Unit)? = null
    ): BenchmarkSessionResult {
        require(repeats > 0) { "repeats must be > 0" }
        val startedAt = System.currentTimeMillis()
        val caseResults = ArrayList<BenchmarkCaseResult>(cases.size)

        for ((caseIndexZeroBased, caseDef) in cases.withIndex()) {
            val runs = ArrayList<BenchmarkRunResult>(repeats)
            val caseIndex = caseIndexZeroBased + 1

            for (runIndex in 1..repeats) {
                currentCoroutineContext().ensureActive()
                onProgress?.invoke(
                    BenchmarkProgress(
                        caseIndex = caseIndex,
                        totalCases = cases.size,
                        runIndex = runIndex,
                        repeats = repeats,
                        caseId = caseDef.id
                    )
                )

                val rewriteResult = withContext(Dispatchers.IO) {
                    when (caseDef.type) {
                        BenchmarkCaseType.COMPOSE -> gateway.runCompose(
                            input = caseDef.composeInput.orEmpty(),
                            promptTemplateOverride = composePromptTemplateOverride
                        )
                        BenchmarkCaseType.EDIT -> gateway.runEdit(
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
        return BenchmarkSessionResult(
            suiteVersion = suiteVersion,
            repeats = repeats,
            timestampMs = System.currentTimeMillis(),
            totalElapsedMs = totalElapsedMs,
            modelId = modelId,
            promptInstructionsSnapshot = promptInstructionsSnapshot,
            runtimeConfigSnapshot = runtimeConfigSnapshot,
            cases = caseResults
        )
    }

    private fun RewriteResult.toRunResult(runIndex: Int): BenchmarkRunResult {
        return when (this) {
            is RewriteResult.Success -> BenchmarkRunResult(
                runIndex = runIndex,
                output = text,
                latencyMs = latencyMs,
                backend = backend.name,
                errorType = null,
                errorMessage = null,
                success = true
            )

            is RewriteResult.Failure -> BenchmarkRunResult(
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
        caseDef: BenchmarkCase,
        runs: List<BenchmarkRunResult>
    ): BenchmarkCaseResult {
        val latencies = runs.map { it.latencyMs }
        val successfulOutputs = runs
            .filter { it.success }
            .mapNotNull { it.output }
            .map { it.trim() }
            .filter { it.isNotBlank() }

        val uniqueOutputsCount = if (successfulOutputs.isEmpty()) 0 else successfulOutputs.toSet().size
        val avgLatency = if (latencies.isEmpty()) 0L else latencies.average().toLong()

        return BenchmarkCaseResult(
            caseDef = caseDef,
            runs = runs,
            uniqueOutputsCount = uniqueOutputsCount,
            avgLatencyMs = avgLatency,
            minLatencyMs = latencies.minOrNull() ?: 0L,
            maxLatencyMs = latencies.maxOrNull() ?: 0L
        )
    }
}
