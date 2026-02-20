package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EditInstructionRulesTest {
    @Test
    fun analyzeInstruction_detectsDeleteAllPhrases() {
        val deleteAll = EditInstructionRules.analyzeInstruction("delete all")
        val clearEverything = EditInstructionRules.analyzeInstruction("clear everything please")
        val removeWhole = EditInstructionRules.analyzeInstruction("remove the whole message")
        val undo = EditInstructionRules.analyzeInstruction("undo")

        assertEquals(EditInstructionRules.EditIntent.DELETE_ALL, deleteAll.intent)
        assertEquals(EditInstructionRules.EditIntent.DELETE_ALL, clearEverything.intent)
        assertEquals(EditInstructionRules.EditIntent.DELETE_ALL, removeWhole.intent)
        assertEquals(EditInstructionRules.EditIntent.DELETE_ALL, undo.intent)
    }

    @Test
    fun analyzeInstruction_detectsReplaceIntent() {
        val result = EditInstructionRules.analyzeInstruction("replace milk with oat milk")
        assertEquals(EditInstructionRules.EditIntent.REPLACE, result.intent)
        assertEquals("replace milk with oat milk", result.normalizedInstruction)
    }

    @Test
    fun strictEditCommand_requiresStartAnchoredCommand() {
        assertTrue(EditInstructionRules.isStrictEditCommand("replace milk with oat milk"))
        assertTrue(EditInstructionRules.isStrictEditCommand("fix milk to oat milk"))
        assertTrue(EditInstructionRules.isStrictEditCommand("please remove milk"))
        assertTrue(EditInstructionRules.isStrictEditCommand("actually never mind"))
        assertTrue(EditInstructionRules.isStrictEditCommand("undo"))
        assertFalse(EditInstructionRules.isStrictEditCommand("actually can we replace milk with oat milk"))
        assertFalse(EditInstructionRules.isStrictEditCommand("hey maybe never mind this part"))
        assertFalse(EditInstructionRules.isStrictEditCommand("scratch that"))
        assertFalse(EditInstructionRules.isStrictEditCommand("make this professional"))
    }

    @Test
    fun analyzeInstruction_prefersFinalCorrectionForReplace() {
        val result = EditInstructionRules.analyzeInstruction(
            "replace milk with oat milk no, make it almond milk"
        )
        assertEquals(EditInstructionRules.EditIntent.REPLACE, result.intent)
        assertEquals("replace milk with almond milk", result.normalizedInstruction)
    }

    @Test
    fun allowBlankOutput_onlyForDeleteAllIntent() {
        assertTrue(EditInstructionRules.shouldAllowBlankOutput(EditInstructionRules.EditIntent.DELETE_ALL))
        assertFalse(EditInstructionRules.shouldAllowBlankOutput(EditInstructionRules.EditIntent.REPLACE))
        assertFalse(EditInstructionRules.shouldAllowBlankOutput(EditInstructionRules.EditIntent.GENERAL))
    }

    @Test
    fun looksLikeList_detectsShoppingAndDelimitedItems() {
        val shoppingText = "buy milk, eggs, bananas, bread"
        assertTrue(EditInstructionRules.looksLikeList(shoppingText))
    }

    @Test
    fun looksLikeList_ignoresPlainProse() {
        val prose = "I can make it at 5pm and bring the document for review."
        assertFalse(EditInstructionRules.looksLikeList(prose))
    }

    @Test
    fun deterministic_clearAll_supportsVerbVariants() {
        val source = "Buy milk and eggs"
        val cases = listOf(
            "clear everything",
            "remove all",
            "delete everything",
            "erase everything",
            "wipe everything",
            "get rid of everything",
            "take out everything",
            "cut all",
            "cut everything",
            "erase the whole message",
            "start over",
            "undo"
        )

        for (instruction in cases) {
            val result = EditInstructionRules.tryApplyDeterministicEdit(source, instruction)
            assertNotNull(result)
            assertEquals("", result?.output)
            assertEquals(EditInstructionRules.CommandKind.CLEAR_ALL, result?.commandKind)
            assertEquals(EditInstructionRules.CommandScope.ALL, result?.scope)
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
            "take out \"next week\"",
            "get rid of milk",
            "cut milk",
            "undo milk"
        )

        val first = EditInstructionRules.tryApplyDeterministicEdit(source, cases[0])
        assertEquals("buy next week", first?.output)

        val second = EditInstructionRules.tryApplyDeterministicEdit(source, cases[1])
        assertEquals("buy next week", second?.output)

        val third = EditInstructionRules.tryApplyDeterministicEdit(source, cases[2])
        assertEquals("buy milk", third?.output)

        val fourth = EditInstructionRules.tryApplyDeterministicEdit(source, cases[3])
        assertEquals("buy next week", fourth?.output)

        val fifth = EditInstructionRules.tryApplyDeterministicEdit(source, cases[4])
        assertEquals("buy next week", fifth?.output)

        val sixth = EditInstructionRules.tryApplyDeterministicEdit(source, cases[5])
        assertEquals("buy next week", sixth?.output)
    }

    @Test
    fun deterministic_deleteTerm_supportsMultipleTargets() {
        val source = "buy apple eggs milk bread"
        val result = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "remove eggs and milk"
        )

        assertNotNull(result)
        assertEquals("buy apple bread", result?.output)
        assertEquals(2, result?.matchedCount)
    }

    @Test
    fun deterministic_deleteAllOnly_commands_doNotAcceptTargets() {
        val source = "buy milk and eggs"
        val resetTargeted = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "reset milk"
        )
        val startOverTargeted = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "start over milk"
        )

        assertNull(resetTargeted)
        assertNull(startOverTargeted)
    }

    @Test
    fun deterministic_replaceTerm_supportsVerbVariants() {
        val source = "buy milk and bread"

        val change = EditInstructionRules.tryApplyDeterministicEdit(source, "change milk to oat milk")
        assertEquals("buy oat milk and bread", change?.output)

        val swap = EditInstructionRules.tryApplyDeterministicEdit(source, "swap milk for oat milk")
        assertEquals("buy oat milk and bread", swap?.output)

        val substitute = EditInstructionRules.tryApplyDeterministicEdit(
            source,
            "substitute milk with oat milk"
        )
        assertEquals("buy oat milk and bread", substitute?.output)

        val correct = EditInstructionRules.tryApplyDeterministicEdit(source, "correct milk to oat milk")
        assertEquals("buy oat milk and bread", correct?.output)

        val fix = EditInstructionRules.tryApplyDeterministicEdit(source, "fix milk to oat milk")
        assertEquals("buy oat milk and bread", fix?.output)

        val update = EditInstructionRules.tryApplyDeterministicEdit(source, "update milk to oat milk")
        assertEquals("buy oat milk and bread", update?.output)

        val useInstead = EditInstructionRules.tryApplyDeterministicEdit(source, "use oat milk instead of milk")
        assertEquals("buy oat milk and bread", useInstead?.output)
    }

    @Test
    fun deterministic_updateNumber_replacesLastNumberToken() {
        val source = "Meeting moved from 5:00 PM to 6:00 PM tomorrow."
        val result = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "update number to 6:30"
        )

        assertNotNull(result)
        assertEquals("Meeting moved from 5:00 PM to 6:30 tomorrow.", result?.output)
        assertEquals(EditInstructionRules.CommandKind.UPDATE_NUMBER, result?.commandKind)
        assertEquals(1, result?.matchedCount)
    }

    @Test
    fun deterministic_replaceTerm_supportsPoliteNaturalLanguageForm() {
        val source = "Hey guys. This is Mario speaking."
        val result = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "can you replace the word guys with the word girls?"
        )

        assertNotNull(result)
        assertEquals("Hey girls. This is Mario speaking.", result?.output)
        assertEquals(EditInstructionRules.CommandKind.REPLACE_TERM, result?.commandKind)
        assertEquals(EditInstructionRules.CommandScope.ALL, result?.scope)
        assertEquals(1, result?.matchedCount)
    }

    @Test
    fun deterministic_replaceTerm_preservesCapitalizedReplacementWhenTargetIsCapitalized() {
        val source = "Hey Mia, can you review this?"
        val result = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "replace Mia with john"
        )

        assertNotNull(result)
        assertEquals("Hey John, can you review this?", result?.output)
    }

    @Test
    fun postReplaceCapitalization_capitalizesEditedOutputForReplaceCommand() {
        val output = EditInstructionRules.applyPostReplaceCapitalization(
            sourceText = "Hey Mia, can you review this?",
            instructionText = "replace Mia with john",
            editedOutput = "Hey john, can you review this?"
        )

        assertEquals("Hey John, can you review this?", output)
    }

    @Test
    fun deterministic_scope_delete_first_and_last() {
        val source = "milk bread milk eggs milk"

        val first = EditInstructionRules.tryApplyDeterministicEdit(source, "delete first milk")
        assertNotNull(first)
        assertEquals("bread milk eggs milk", first?.output)
        assertEquals(EditInstructionRules.CommandScope.FIRST, first?.scope)
        assertEquals(1, first?.matchedCount)

        val last = EditInstructionRules.tryApplyDeterministicEdit(source, "delete last milk")
        assertNotNull(last)
        assertEquals("milk bread milk eggs", last?.output)
        assertEquals(EditInstructionRules.CommandScope.LAST, last?.scope)
        assertEquals(1, last?.matchedCount)
    }

    @Test
    fun deterministic_scope_replace_first_and_last() {
        val source = "milk bread milk eggs milk"

        val first = EditInstructionRules.tryApplyDeterministicEdit(source, "replace first milk with oat")
        assertNotNull(first)
        assertEquals("oat bread milk eggs milk", first?.output)
        assertEquals(EditInstructionRules.CommandScope.FIRST, first?.scope)

        val last = EditInstructionRules.tryApplyDeterministicEdit(source, "replace last milk with oat")
        assertNotNull(last)
        assertEquals("milk bread milk eggs oat", last?.output)
        assertEquals(EditInstructionRules.CommandScope.LAST, last?.scope)
    }

    @Test
    fun deterministic_noMatch_reportsMetadata() {
        val source = "Please buy milk and eggs."
        val result = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = "replace bread with rice"
        )

        assertNotNull(result)
        assertEquals(source, result?.output)
        assertFalse(result?.applied == true)
        assertEquals(0, result?.matchedCount)
        assertTrue(result?.noMatchDetected == true)
        assertEquals(EditInstructionRules.RuleConfidence.LOW, result?.ruleConfidence)
    }

    @Test
    fun deterministic_rejectsAmbiguousPronounTargets() {
        val source = "Please buy milk and eggs."
        assertNull(
            EditInstructionRules.tryApplyDeterministicEdit(
                sourceText = source,
                instructionText = "delete it"
            )
        )
        assertNull(
            EditInstructionRules.tryApplyDeterministicEdit(
                sourceText = source,
                instructionText = "change that to bread"
            )
        )
    }

    @Test
    fun deterministic_rejectsLongInstructionsByCommandGate() {
        val source = "Please buy milk and eggs."
        val longInstruction = "please delete the word milk from the message and then rewrite the rest politely"

        val result = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = source,
            instructionText = longInstruction
        )

        assertNull(result)
    }

    @Test
    fun deterministic_returnsNullForGeneralInstruction() {
        val result = EditInstructionRules.tryApplyDeterministicEdit(
            sourceText = "Please buy milk and eggs.",
            instructionText = "make this friendlier"
        )
        assertNull(result)
    }

    @Test
    fun deterministic_noOpCommands_keepSourceUnchanged() {
        val source = "Please buy milk and eggs."
        val commands = listOf(
            "nevermind",
            "actually never mind",
            "just never mind",
            "cancel",
            "cancel that",
            "forget it",
            "ignore that",
            "disregard that"
        )

        commands.forEach { command ->
            val result = EditInstructionRules.tryApplyDeterministicEdit(
                sourceText = source,
                instructionText = command
            )
            assertNotNull(result)
            assertEquals(source, result?.output)
            assertFalse(result?.applied == true)
            assertEquals(EditInstructionRules.CommandKind.NO_OP, result?.commandKind)
            assertFalse(result?.noMatchDetected == true)
        }
    }
}
