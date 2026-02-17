package com.sanogueralorenzo.voice.setup

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object PromptBenchmarkReportFormatter {
    fun toPlainText(result: PromptBenchmarkSessionResult): String {
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
            .format(Date(result.timestampMs))

        return buildString {
            appendLine("PROMPT BENCHMARK REPORT")
            appendLine("timestamp: $timestamp")
            appendLine("suite_version: ${result.suiteVersion}")
            appendLine("repeats: ${result.repeats}")
            appendLine("model_id: ${result.modelId}")
            appendLine()

            appendLine("[prompt_instructions]")
            appendLine(result.promptInstructionsSnapshot)
            appendLine()

            appendLine("[runtime_config]")
            appendLine(result.runtimeConfigSnapshot)
            appendLine()

            appendLine("[results]")
            for (caseResult in result.cases) {
                val caseDef = caseResult.caseDef
                appendLine("case_id: ${caseDef.id}")
                appendLine("case_title: ${caseDef.title}")
                appendLine("case_category: ${caseDef.category}")
                appendLine("case_type: ${caseDef.type.name}")
                when (caseDef.type) {
                    PromptBenchmarkCaseType.COMPOSE -> {
                        appendLine("input_before: ${caseDef.composeInput.orEmpty()}")
                    }

                    PromptBenchmarkCaseType.EDIT -> {
                        appendLine("input_before_original: ${caseDef.editOriginal.orEmpty()}")
                        appendLine("input_before_instruction: ${caseDef.editInstruction.orEmpty()}")
                    }
                }

                for (run in caseResult.runs) {
                    appendLine("run_${run.runIndex}_success: ${if (run.success) "yes" else "no"}")
                    appendLine("run_${run.runIndex}_latency_ms: ${run.latencyMs}")
                    appendLine("run_${run.runIndex}_backend: ${run.backend ?: "n/a"}")
                    appendLine("run_${run.runIndex}_error_type: ${run.errorType ?: "none"}")
                    appendLine("run_${run.runIndex}_error: ${run.errorMessage ?: "none"}")
                    appendLine("run_${run.runIndex}_after: ${run.output ?: "(failed)"}")
                }

                appendLine("case_avg_latency_ms: ${caseResult.avgLatencyMs}")
                appendLine("case_min_latency_ms: ${caseResult.minLatencyMs}")
                appendLine("case_max_latency_ms: ${caseResult.maxLatencyMs}")
                appendLine("case_unique_outputs: ${caseResult.uniqueOutputsCount}")
                appendLine("case_failure_count: ${caseResult.failureCount}")
                appendLine()
            }

            appendLine("[summary]")
            appendLine("total_cases: ${result.totalCases}")
            appendLine("total_runs: ${result.totalRuns}")
            appendLine("total_failures: ${result.totalFailures}")
            appendLine("stable_cases: ${result.stableCasesCount}")
            appendLine("avg_latency_ms: ${result.avgLatencyMs}")
            appendLine("min_latency_ms: ${result.minLatencyMs}")
            appendLine("max_latency_ms: ${result.maxLatencyMs}")
            appendLine("total_elapsed_ms: ${result.totalElapsedMs}")
        }
    }
}
