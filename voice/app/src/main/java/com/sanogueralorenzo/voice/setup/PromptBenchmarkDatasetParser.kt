package com.sanogueralorenzo.voice.setup

import org.json.JSONObject

internal object PromptBenchmarkDatasetParser {
    fun parseLineToCase(line: String, fallbackIndex: Int): PromptBenchmarkCase? {
        return runCatching {
            val json = JSONObject(line)
            val input = json.optString("input").trim()
            if (input.isBlank()) return null
            val id = json.optInt("id", fallbackIndex)
            val expected = json.optString("expected").trim().ifBlank { null }
            PromptBenchmarkCase(
                id = id.toString(),
                title = "Case $id",
                category = "compose",
                type = PromptBenchmarkCaseType.COMPOSE,
                composeInput = input,
                expectedOutput = expected
            )
        }.getOrNull()
    }
}
