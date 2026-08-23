package com.sanogueralorenzo.voice.prompt

import org.junit.Assert.assertEquals
import org.junit.Test

class PromptTemplateStoreTest {
    @Test
    fun sourceUrls_pointToAndroidPromptLocation() {
        assertEquals(
            "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/blob/main/tools/voice/evals/prompt_a.json",
            PromptTemplateStore.SOURCE_BLOB_URL
        )
        assertEquals(
            "https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/voice/evals/prompt_a.json",
            PromptTemplateStore.SOURCE_RAW_URL
        )
    }
}
