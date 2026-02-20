package com.sanogueralorenzo.voice.benchmark

enum class BenchmarkCaseType {
    COMPOSE,
    EDIT
}

data class BenchmarkCase(
    val id: String,
    val title: String,
    val category: String,
    val type: BenchmarkCaseType,
    val composeInput: String? = null,
    val expectedOutput: String? = null,
    val editOriginal: String? = null,
    val editInstruction: String? = null
) {
    init {
        when (type) {
            BenchmarkCaseType.COMPOSE -> {
                require(!composeInput.isNullOrBlank()) { "composeInput is required for COMPOSE case: $id" }
            }

            BenchmarkCaseType.EDIT -> {
                require(!editOriginal.isNullOrBlank()) { "editOriginal is required for EDIT case: $id" }
                require(!editInstruction.isNullOrBlank()) { "editInstruction is required for EDIT case: $id" }
            }
        }
    }
}

data class BenchmarkRunResult(
    val runIndex: Int,
    val output: String?,
    val latencyMs: Long,
    val backend: String?,
    val errorType: String?,
    val errorMessage: String?,
    val success: Boolean
)

data class BenchmarkCaseResult(
    val caseDef: BenchmarkCase,
    val runs: List<BenchmarkRunResult>,
    val uniqueOutputsCount: Int,
    val avgLatencyMs: Long,
    val minLatencyMs: Long,
    val maxLatencyMs: Long
) {
    val failureCount: Int
        get() = runs.count { !it.success }
}

data class BenchmarkSessionResult(
    val suiteVersion: String,
    val repeats: Int,
    val timestampMs: Long,
    val totalElapsedMs: Long,
    val modelId: String,
    val promptInstructionsSnapshot: String,
    val runtimeConfigSnapshot: String,
    val cases: List<BenchmarkCaseResult>
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

data class BenchmarkProgress(
    val caseIndex: Int,
    val totalCases: Int,
    val runIndex: Int,
    val repeats: Int,
    val caseId: String
)

enum class BenchmarkRunPhase {
    IDLE,
    DOWNLOADING_DATASET,
    RUNNING,
    ERROR,
    COMPLETED
}

data class BenchmarkRunnerState(
    val isRunning: Boolean = false,
    val phase: BenchmarkRunPhase = BenchmarkRunPhase.IDLE,
    val currentCaseIndex: Int = 0,
    val totalCases: Int = 0,
    val currentRunIndex: Int = 0,
    val repeats: Int = 0,
    val errorMessage: String? = null
)
