package com.sanogueralorenzo.voice.models

import com.sanogueralorenzo.voice.dictation.DictationLanguage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelCatalogTest {
    @Test
    fun spanishStreamingModelContainsTheCompleteSplitFrontendArtifactSet() {
        val specs = ModelCatalog.moonshineStreamingSpecsFor(DictationLanguage.SPANISH)

        assertEquals(
            setOf(
                "adapter.ort",
                "cross_kv.ort",
                "decoder_kv.ort",
                "encoder.ort",
                "frontend.model.ort",
                "frontend.weights.ort",
                "streaming_config.json",
                "tokenizer.bin"
            ),
            specs.map { it.fileName }.toSet()
        )
        assertTrue(specs.all { it.sizeBytes > 0L })
    }
}
