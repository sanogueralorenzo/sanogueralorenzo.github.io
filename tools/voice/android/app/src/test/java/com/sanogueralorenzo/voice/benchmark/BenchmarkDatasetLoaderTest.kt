package com.sanogueralorenzo.voice.benchmark

import org.junit.Assert.assertEquals
import org.junit.Test

class BenchmarkDatasetLoaderTest {
    @Test
    fun sourceUrls_pointToSharedEvalDataset() {
        assertEquals(
            "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/blob/main/tools/voice/evals/dataset.jsonl",
            BenchmarkDatasetLoader.SOURCE_BLOB_URL
        )
        assertEquals(
            "https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/voice/evals/dataset.jsonl",
            BenchmarkDatasetLoader.SOURCE_RAW_URL
        )
    }
}
