package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtPromptTemplatesTest {
    @Test
    fun rewriteSystemInstruction_isStrictMinimalChange() {
        val instruction = LiteRtPromptTemplates.buildRewriteSystemInstruction(
            bulletMode = false
        )

        assertTrue(instruction.contains("remove only spoken disfluencies", ignoreCase = true))
        assertTrue(instruction.contains("Do not paraphrase", ignoreCase = true))
        assertTrue(instruction.contains("If uncertain, return the text unchanged", ignoreCase = true))
        assertTrue(instruction.contains("Do not convert prose into bullets", ignoreCase = true))
        assertFalse(instruction.contains("slightly warmer", ignoreCase = true))
        assertFalse(instruction.contains("more professional", ignoreCase = true))
    }

    @Test
    fun rewriteSystemInstruction_includesCustomRuleWhenProvided() {
        val instruction = LiteRtPromptTemplates.buildRewriteSystemInstruction(
            bulletMode = true
        )

        assertTrue(instruction.contains("Preserve existing list formatting", ignoreCase = true))
        assertFalse(instruction.contains("Secondary user preference", ignoreCase = true))
    }

    @Test
    fun editSystemInstruction_enforcesExplicitOnlyEdit() {
        val instruction = LiteRtPromptTemplates.buildEditSystemInstruction()

        assertTrue(instruction.contains("Apply only the explicit EDIT_INSTRUCTION"))
        assertTrue(instruction.contains("Allowed operations", ignoreCase = true))
        assertTrue(instruction.contains("If instruction is ambiguous, return ORIGINAL_MESSAGE unchanged"))
        assertTrue(instruction.contains("Return only the final edited message"))
    }

    @Test
    fun benchmarkSnapshot_keepsExpectedSections() {
        val snapshot = LiteRtPromptTemplates.benchmarkInstructionSnapshot("abc")

        assertTrue(snapshot.contains("rewrite_system_instruction:"))
        assertTrue(snapshot.contains("edit_system_instruction:"))
        assertTrue(snapshot.contains("custom_instructions:"))
    }
}
