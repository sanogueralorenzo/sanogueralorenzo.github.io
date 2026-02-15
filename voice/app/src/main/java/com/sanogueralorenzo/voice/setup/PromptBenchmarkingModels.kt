package com.sanogueralorenzo.voice.setup

enum class PromptBenchmarkCaseType {
    COMPOSE,
    EDIT
}

data class PromptBenchmarkCase(
    val id: String,
    val title: String,
    val category: String,
    val type: PromptBenchmarkCaseType,
    val composeInput: String? = null,
    val editOriginal: String? = null,
    val editInstruction: String? = null
) {
    init {
        when (type) {
            PromptBenchmarkCaseType.COMPOSE -> {
                require(!composeInput.isNullOrBlank()) { "composeInput is required for COMPOSE case: $id" }
            }

            PromptBenchmarkCaseType.EDIT -> {
                require(!editOriginal.isNullOrBlank()) { "editOriginal is required for EDIT case: $id" }
                require(!editInstruction.isNullOrBlank()) { "editInstruction is required for EDIT case: $id" }
            }
        }
    }
}

data class PromptBenchmarkRunResult(
    val runIndex: Int,
    val output: String?,
    val latencyMs: Long,
    val backend: String?,
    val errorType: String?,
    val errorMessage: String?,
    val success: Boolean
)

data class PromptBenchmarkCaseResult(
    val caseDef: PromptBenchmarkCase,
    val runs: List<PromptBenchmarkRunResult>,
    val uniqueOutputsCount: Int,
    val avgLatencyMs: Long,
    val minLatencyMs: Long,
    val maxLatencyMs: Long
) {
    val failureCount: Int
        get() = runs.count { !it.success }
}

data class PromptBenchmarkSessionResult(
    val suiteVersion: String,
    val repeats: Int,
    val timestampMs: Long,
    val totalElapsedMs: Long,
    val modelId: String,
    val customInstructions: String,
    val promptInstructionsSnapshot: String,
    val cases: List<PromptBenchmarkCaseResult>
) {
    val totalCases: Int
        get() = cases.size

    val totalRuns: Int
        get() = cases.sumOf { it.runs.size }

    val totalFailures: Int
        get() = cases.sumOf { it.failureCount }

    val stableCasesCount: Int
        get() = cases.count { it.uniqueOutputsCount <= 1 }

    val avgLatencyMs: Long
        get() {
            val latencies = cases.flatMap { caseResult ->
                caseResult.runs.map { run -> run.latencyMs }
            }
            if (latencies.isEmpty()) return 0L
            return latencies.average().toLong()
        }

    val minLatencyMs: Long
        get() {
            val latencies = cases.flatMap { caseResult ->
                caseResult.runs.map { run -> run.latencyMs }
            }
            if (latencies.isEmpty()) return 0L
            return latencies.minOrNull() ?: 0L
        }

    val maxLatencyMs: Long
        get() {
            val latencies = cases.flatMap { caseResult ->
                caseResult.runs.map { run -> run.latencyMs }
            }
            if (latencies.isEmpty()) return 0L
            return latencies.maxOrNull() ?: 0L
        }
}

data class PromptBenchmarkProgress(
    val caseIndex: Int,
    val totalCases: Int,
    val runIndex: Int,
    val repeats: Int,
    val caseId: String
)

data class PromptBenchmarkRunnerState(
    val isRunning: Boolean = false,
    val currentCaseIndex: Int = 0,
    val totalCases: Int = 0,
    val currentRunIndex: Int = 0,
    val repeats: Int = 0,
    val errorMessage: String? = null
)
