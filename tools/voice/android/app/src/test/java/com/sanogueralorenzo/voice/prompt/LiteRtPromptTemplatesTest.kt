package com.sanogueralorenzo.voice.prompt

import org.junit.Assert.assertEquals
import org.junit.Test

class LiteRtPromptTemplatesTest {
    @Test
    fun editSystemInstructionUsesCompactCommandContract() {
        assertEquals(
            """
            Transform TEXT according to COMMAND.

            FIX: Correct transcription, spelling, grammar, and punctuation. Preserve meaning and wording.
            SHORT: Make the text shorter. Preserve meaning and essential details.
            MESSAGE: Turn rough notes into a concise, natural message. Do not invent details.

            Return only the final text. Never add labels, explanations, or commentary.
            """.trimIndent(),
            LiteRtPromptTemplates.buildEditSystemInstruction()
        )
    }

    @Test
    fun editUserPromptContainsOnlyCommandAndText() {
        assertEquals(
            """
            COMMAND: MESSAGE

            TEXT:
            tell Sam I will be late
            """.trimIndent(),
            LiteRtPromptTemplates.buildEditUserPrompt(
                originalText = "tell Sam I will be late",
                command = "MESSAGE"
            )
        )
    }
}
