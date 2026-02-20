package com.sanogueralorenzo.voice.benchmark

import org.json.JSONObject

internal object BenchmarkDatasetParser {
    fun parseLineToCase(line: String, fallbackIndex: Int): BenchmarkCase? {
        return runCatching {
            val json = JSONObject(line)
            val input = json.optString("input").trim()
            if (input.isBlank()) return null
            val id = json.optInt("id", fallbackIndex)
            val expected = json.optString("expected").trim().ifBlank { null }
            BenchmarkCase(
                id = id.toString(),
                title = "Case $id",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = input,
                expectedOutput = expected
            )
        }.getOrNull()
    }
}
