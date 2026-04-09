package com.sanogueralorenzo.voice.benchmark.adb

import com.sanogueralorenzo.voice.benchmark.BenchmarkProgress
import org.json.JSONObject

object BenchmarkAdbContracts {
    const val ACTION_RUN = "com.sanogueralorenzo.voice.DEBUG_BENCHMARK_RUN"

    const val EXTRA_RUN_ID = "run_id"
    const val EXTRA_PROMPT_REL_PATH = "prompt_rel_path"
    const val EXTRA_DATASET_REL_PATH = "dataset_rel_path"
    const val EXTRA_OUTPUT_REL_PATH = "output_rel_path"

    const val DEFAULT_RESULTS_DIR = "benchmark_runs"
    const val APP_DEFAULT_PROMPT_SENTINEL = "__APP_DEFAULT__"
}

data class BenchmarkRunRequest(
    val runId: String,
    val promptRelPath: String,
    val datasetRelPath: String,
    val outputRelPath: String
)

data class BenchmarkRunStatus(
    val runId: String,
    val state: String,
    val updatedAtMs: Long,
    val startedAtMs: Long? = null,
    val message: String? = null,
    val error: String? = null,
    val progress: BenchmarkProgress? = null,
    val resultRelPath: String? = null,
    val reportRelPath: String? = null
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("run_id", runId)
            put("state", state)
            put("updated_at_ms", updatedAtMs)
            if (startedAtMs != null) put("started_at_ms", startedAtMs)
            if (!message.isNullOrBlank()) put("message", message)
            if (!error.isNullOrBlank()) put("error", error)
            if (!resultRelPath.isNullOrBlank()) put("result_rel_path", resultRelPath)
            if (!reportRelPath.isNullOrBlank()) put("report_rel_path", reportRelPath)
            if (progress != null) {
                put(
                    "progress",
                    JSONObject().apply {
                        put("case_index", progress.caseIndex)
                        put("total_cases", progress.totalCases)
                        put("run_index", progress.runIndex)
                        put("repeats", progress.repeats)
                        put("case_id", progress.caseId)
                    }
                )
            }
        }
    }
}
