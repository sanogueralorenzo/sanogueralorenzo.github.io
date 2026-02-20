package com.sanogueralorenzo.voice.benchmark

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

internal object BenchmarkDatasetLoader {
    private const val CONNECT_TIMEOUT_MS = 15_000
    private const val READ_TIMEOUT_MS = 20_000

    const val SOURCE_BLOB_URL: String =
        "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/blob/main/voice/scripts/dataset.jsonl"

    private const val SOURCE_RAW_URL: String =
        "https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/voice/scripts/dataset.jsonl"

    suspend fun loadCases(): List<BenchmarkCase> = withContext(Dispatchers.IO) {
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
                BenchmarkDatasetParser.parseLineToCase(line = line, fallbackIndex = index + 1)
            }
            if (parsed.isEmpty()) {
                throw IllegalStateException("Dataset is empty")
            }
            parsed
        } finally {
            connection.disconnect()
        }
    }

}
