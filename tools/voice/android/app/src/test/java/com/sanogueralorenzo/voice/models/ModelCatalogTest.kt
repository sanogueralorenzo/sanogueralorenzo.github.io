package com.sanogueralorenzo.voice.models

import org.junit.Assert.assertEquals
import org.junit.Test

class ModelCatalogTest {
    @Test
    fun languageModelUsesPinnedQwenArtifact() {
        val model = ModelCatalog.liteRtLm

        assertEquals("qwen3-0.6b-litertlm", model.id)
        assertEquals("Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm", model.fileName)
        assertEquals(
            "https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/" +
                "Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm",
            model.url
        )
        assertEquals(344_437_808L, model.sizeBytes)
        assertEquals(
            "e3e290109da4388d65a17510a0c66af91c8039f52d2c465868dbc43c09a776cf",
            model.sha256
        )
    }
}
