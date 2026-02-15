package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtEditHeuristicsTest {
    @Test
    fun analyzeInstruction_detectsDeleteAllPhrases() {
        val deleteAll = LiteRtEditHeuristics.analyzeInstruction("delete all")
        val clearEverything = LiteRtEditHeuristics.analyzeInstruction("clear everything please")
        val removeWhole = LiteRtEditHeuristics.analyzeInstruction("remove the whole message")

        assertEquals(LiteRtEditHeuristics.EditIntent.DELETE_ALL, deleteAll.intent)
        assertEquals(LiteRtEditHeuristics.EditIntent.DELETE_ALL, clearEverything.intent)
        assertEquals(LiteRtEditHeuristics.EditIntent.DELETE_ALL, removeWhole.intent)
    }

    @Test
    fun analyzeInstruction_detectsReplaceIntent() {
        val result = LiteRtEditHeuristics.analyzeInstruction("replace milk with oat milk")
        assertEquals(LiteRtEditHeuristics.EditIntent.REPLACE, result.intent)
        assertEquals("replace milk with oat milk", result.normalizedInstruction)
    }

    @Test
    fun analyzeInstruction_prefersFinalCorrectionForReplace() {
        val result = LiteRtEditHeuristics.analyzeInstruction(
            "replace milk with oat milk no, make it almond milk"
        )
        assertEquals(LiteRtEditHeuristics.EditIntent.REPLACE, result.intent)
        assertEquals("replace milk with almond milk", result.normalizedInstruction)
    }

    @Test
    fun allowBlankOutput_onlyForDeleteAllIntent() {
        assertTrue(LiteRtEditHeuristics.shouldAllowBlankOutput(LiteRtEditHeuristics.EditIntent.DELETE_ALL))
        assertFalse(LiteRtEditHeuristics.shouldAllowBlankOutput(LiteRtEditHeuristics.EditIntent.REPLACE))
        assertFalse(LiteRtEditHeuristics.shouldAllowBlankOutput(LiteRtEditHeuristics.EditIntent.GENERAL))
    }

    @Test
    fun looksLikeList_detectsShoppingAndDelimitedItems() {
        val shoppingText = "buy milk, eggs, bananas, bread"
        assertTrue(LiteRtEditHeuristics.looksLikeList(shoppingText))
    }

    @Test
    fun looksLikeList_ignoresPlainProse() {
        val prose = "I can make it at 5pm and bring the document for review."
        assertFalse(LiteRtEditHeuristics.looksLikeList(prose))
    }

    @Test
    fun deterministic_clearAll_supportsVerbVariants() {
        val source = "Buy milk and eggs"
        val cases = listOf("clear everything", "erase the whole message", "start over")

        for (instruction in cases) {
            val result = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, instruction)
            assertNotNull(result)
            assertEquals("", result?.output)
            assertEquals(LiteRtEditHeuristics.CommandKind.CLEAR_ALL, result?.commandKind)
            assertEquals(LiteRtEditHeuristics.CommandScope.ALL, result?.scope)
            assertEquals(1, result?.matchedCount)
            assertFalse(result?.noMatchDetected == true)
        }
    }

    @Test
    fun deterministic_deleteTerm_supportsVerbVariants() {
        val source = "buy milk next week"
        val cases = listOf(
            "delete milk",
            "remove the word milk",
            "take out \"next week\""
        )

        val first = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, cases[0])
        assertEquals("buy next week", first?.output)

        val second = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, cases[1])
        assertEquals("buy next week", second?.output)

        val third = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, cases[2])
        assertEquals("buy milk", third?.output)
    }

    @Test
    fun deterministic_replaceTerm_supportsVerbVariants() {
        val source = "buy milk and bread"

        val change = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, "change milk to oat milk")
        assertEquals("buy oat milk and bread", change?.output)

        val swap = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, "swap milk for oat milk")
        assertEquals("buy oat milk and bread", swap?.output)

        val useInstead = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, "use oat milk instead of milk")
        assertEquals("buy oat milk and bread", useInstead?.output)
    }

    @Test
    fun deterministic_replaceTerm_supportsPoliteNaturalLanguageForm() {
        val source = "Hey guys. This is Mario speaking."
        val result = LiteRtEditHeuristics.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "can you replace the word guys with the word girls?"
        )

        assertNotNull(result)
        assertEquals("Hey girls. This is Mario speaking.", result?.output)
        assertEquals(LiteRtEditHeuristics.CommandKind.REPLACE_TERM, result?.commandKind)
        assertEquals(LiteRtEditHeuristics.CommandScope.ALL, result?.scope)
        assertEquals(1, result?.matchedCount)
    }

    @Test
    fun deterministic_scope_delete_first_and_last() {
        val source = "milk bread milk eggs milk"

        val first = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, "delete first milk")
        assertNotNull(first)
        assertEquals("bread milk eggs milk", first?.output)
        assertEquals(LiteRtEditHeuristics.CommandScope.FIRST, first?.scope)
        assertEquals(1, first?.matchedCount)

        val last = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, "delete last milk")
        assertNotNull(last)
        assertEquals("milk bread milk eggs", last?.output)
        assertEquals(LiteRtEditHeuristics.CommandScope.LAST, last?.scope)
        assertEquals(1, last?.matchedCount)
    }

    @Test
    fun deterministic_scope_replace_first_and_last() {
        val source = "milk bread milk eggs milk"

        val first = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, "replace first milk with oat")
        assertNotNull(first)
        assertEquals("oat bread milk eggs milk", first?.output)
        assertEquals(LiteRtEditHeuristics.CommandScope.FIRST, first?.scope)

        val last = LiteRtEditHeuristics.tryApplyDeterministicEdit(source, "replace last milk with oat")
        assertNotNull(last)
        assertEquals("milk bread milk eggs oat", last?.output)
        assertEquals(LiteRtEditHeuristics.CommandScope.LAST, last?.scope)
    }

    @Test
    fun deterministic_noMatch_reportsMetadata() {
        val source = "Please buy milk and eggs."
        val result = LiteRtEditHeuristics.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "replace bread with rice"
        )

        assertNotNull(result)
        assertEquals(source, result?.output)
        assertFalse(result?.applied == true)
        assertEquals(0, result?.matchedCount)
        assertTrue(result?.noMatchDetected == true)
        assertEquals(LiteRtEditHeuristics.RuleConfidence.LOW, result?.ruleConfidence)
    }

    @Test
    fun deterministic_rejectsAmbiguousPronounTargets() {
        val source = "Please buy milk and eggs."
        assertNull(
            LiteRtEditHeuristics.tryApplyDeterministicEdit(
                sourceText = source,
                instructionText = "delete it"
            )
        )
        assertNull(
            LiteRtEditHeuristics.tryApplyDeterministicEdit(
                sourceText = source,
                instructionText = "change that to bread"
            )
        )
    }

    @Test
    fun deterministic_rejectsLongInstructionsByCommandGate() {
        val source = "Please buy milk and eggs."
        val longInstruction = "please delete the word milk from the message and then rewrite the rest politely"

        val result = LiteRtEditHeuristics.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = longInstruction
        )

        assertNull(result)
    }

    @Test
    fun deterministic_returnsNullForGeneralInstruction() {
        val result = LiteRtEditHeuristics.tryApplyDeterministicEdit(
            sourceText = "Please buy milk and eggs.",
            instructionText = "make this friendlier"
        )
        assertNull(result)
    }
}
