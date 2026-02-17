package com.sanogueralorenzo.voice.setup

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

internal object PromptBenchmarkDatasetLoader {
    private const val CONNECT_TIMEOUT_MS = 15_000
    private const val READ_TIMEOUT_MS = 20_000

    const val SOURCE_BLOB_URL: String =
        "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/blob/main/voice/scripts/dataset.jsonl"

    private const val SOURCE_RAW_URL: String =
        "https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/voice/scripts/dataset.jsonl"

    suspend fun loadCases(): List<PromptBenchmarkCase> = withContext(Dispatchers.IO) {
        val connection = (URL(SOURCE_RAW_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            instanceFollowRedirects = true
        }
        try {
            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw IllegalStateException("Dataset download failed (HTTP $responseCode)")
            }

            val rows = connection.inputStream.bufferedReader().useLines { lines ->
                lines
                    .map { it.trim() }
                    .filter { it.isNotBlank() }
                    .toList()
            }
            val parsed = rows.mapIndexedNotNull { index, line ->
                parseLineToCase(line = line, fallbackIndex = index + 1)
            }
            if (parsed.isEmpty()) {
                throw IllegalStateException("Dataset is empty")
            }
            parsed
        } finally {
            connection.disconnect()
        }
    }

    private fun parseLineToCase(line: String, fallbackIndex: Int): PromptBenchmarkCase? {
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
