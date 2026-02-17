package com.sanogueralorenzo.voice.setup.benchmark

import com.sanogueralorenzo.voice.setup.PromptBenchmarkProgress
import org.json.JSONObject

data class PromptBenchmarkRunRequest(
    val runId: String,
    val promptRelPath: String,
    val datasetRelPath: String,
    val outputRelPath: String
)

data class PromptBenchmarkRunStatus(
    val runId: String,
    val state: String,
    val updatedAtMs: Long,
    val startedAtMs: Long? = null,
    val message: String? = null,
    val error: String? = null,
    val progress: PromptBenchmarkProgress? = null,
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
