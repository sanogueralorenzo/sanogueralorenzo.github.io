package com.sanogueralorenzo.voice.summary

import com.sanogueralorenzo.voice.engine.VoiceEngine
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File

class VoiceEngineConformanceTest {
    @Test
    fun preprocess_matchesSharedFixtures() {
        val fixture = readFixture("preprocess.json")
        assertEquals(1, fixture.getInt("version"))
        assertEquals("preprocess", fixture.getString("operation"))

        fixture.getJSONArray("cases").forEachObject { case ->
            val result = VoiceEngine.preprocess(case.getString("input"))

            assertEquals(case.name, case.getString("expectedText"), result.text)
            assertEquals(case.name, case.getBoolean("expectedChanged"), result.changed)
            assertEquals(
                case.name,
                case.getJSONArray("expectedAppliedRuleIds").toStringList(),
                result.appliedRuleIds.toList()
            )
        }
    }

    @Test
    fun normalization_matchesSharedFixtures() {
        val fixture = readFixture("normalization.json")
        assertEquals(1, fixture.getInt("version"))
        assertEquals("normalization", fixture.getString("operation"))

        fixture.getJSONArray("composeInputCases").forEachObject { case ->
            assertEquals(
                case.name,
                case.getString("expected"),
                VoiceEngine.normalizeComposeInput(case.getString("input"))
            )
        }
        fixture.getJSONArray("instructionInputCases").forEachObject { case ->
            assertEquals(
                case.name,
                case.getString("expected"),
                VoiceEngine.normalizeInstructionInput(case.getString("input"))
            )
        }
        fixture.getJSONArray("composeOutputCases").forEachObject { case ->
            assertEquals(
                case.name,
                case.getString("expected"),
                VoiceEngine.normalizeComposeOutputText(case.getString("input"))
            )
        }
        fixture.getJSONArray("cleanModelOutputCases").forEachObject { case ->
            assertEquals(
                case.name,
                case.getString("expected"),
                VoiceEngine.cleanModelOutput(
                    text = case.getString("input"),
                    bulletMode = case.getBoolean("bulletMode")
                )
            )
        }
    }

    @Test
    fun postprocess_matchesSharedFixtures() {
        val fixture = readFixture("postprocess.json")
        assertEquals(1, fixture.getInt("version"))
        assertEquals("postprocess", fixture.getString("operation"))

        fixture.getJSONArray("cases").forEachObject { case ->
            assertEquals(
                case.name,
                case.getString("expected"),
                VoiceEngine.postprocess(
                    originalText = case.getString("originalText"),
                    modelOutput = case.getString("modelOutput"),
                    listMode = case.getBoolean("listMode")
                )
            )
        }
    }

    @Test
    fun editAnalysis_matchesSharedFixtures() {
        val fixture = readFixture("edit_analysis.json")
        assertEquals(1, fixture.getInt("version"))
        assertEquals("edit_analysis", fixture.getString("operation"))

        fixture.getJSONArray("cases").forEachObject { case ->
            val analysis = VoiceEngine.analyzeInstruction(case.getString("instruction"))

            assertEquals(
                case.name,
                case.getString("expectedNormalizedInstruction"),
                analysis.normalizedInstruction
            )
            assertEquals(case.name, case.getString("expectedIntent"), analysis.intent.name)
            assertEquals(
                case.name,
                case.getBoolean("expectedStrictEditCommand"),
                VoiceEngine.isStrictEditCommand(case.getString("instruction"))
            )
        }

        fixture.getJSONArray("allowBlankOutputCases").forEachObject { case ->
            assertEquals(
                case.name,
                case.getBoolean("expected"),
                VoiceEngine.shouldAllowBlankOutput(
                    VoiceEngine.EditIntent.valueOf(case.getString("intent"))
                )
            )
        }
    }

    @Test
    fun deterministicEdits_matchSharedFixtures() {
        val fixture = readFixture("deterministic_edits.json")
        assertEquals(1, fixture.getInt("version"))
        assertEquals("deterministic_edits", fixture.getString("operation"))

        fixture.getJSONArray("cases").forEachObject { case ->
            val result = VoiceEngine.tryApplyDeterministicEdit(
                sourceText = case.getString("sourceText"),
                instructionText = case.getString("instruction")
            )
            assertNotNull(case.name, result)
            assertDeterministicEdit(case.name, case.getJSONObject("expected"), result!!)
        }

        fixture.getJSONArray("nullCases").forEachObject { case ->
            assertNull(
                case.name,
                VoiceEngine.tryApplyDeterministicEdit(
                    sourceText = case.getString("sourceText"),
                    instructionText = case.getString("instruction")
                )
            )
        }
    }

    @Test
    fun listDetection_matchesSharedFixtures() {
        val fixture = readFixture("list_detection.json")
        assertEquals(1, fixture.getInt("version"))
        assertEquals("list_detection", fixture.getString("operation"))

        fixture.getJSONArray("cases").forEachObject { case ->
            assertEquals(
                case.name,
                case.getBoolean("expected"),
                VoiceEngine.looksLikeList(case.getString("input"))
            )
        }
    }

    @Test
    fun replacementCasing_matchesSharedFixtures() {
        val fixture = readFixture("replacement_casing.json")
        assertEquals(1, fixture.getInt("version"))
        assertEquals("replacement_casing", fixture.getString("operation"))

        fixture.getJSONArray("cases").forEachObject { case ->
            assertEquals(
                case.name,
                case.getString("expected"),
                VoiceEngine.postReplaceCapitalization(
                    sourceText = case.getString("sourceText"),
                    instructionText = case.getString("instruction"),
                    editedOutput = case.getString("editedOutput")
                )
            )
        }
    }

    private fun assertDeterministicEdit(
        caseName: String,
        expected: JSONObject,
        result: VoiceEngine.DeterministicEditResult
    ) {
        assertEquals(caseName, expected.getString("output"), result.output)
        assertEquals(caseName, expected.getBoolean("applied"), result.applied)
        assertEquals(caseName, expected.getString("intent"), result.intent.name)
        assertEquals(caseName, expected.getString("scope"), result.scope.name)
        assertEquals(caseName, expected.getString("commandKind"), result.commandKind.name)
        assertEquals(caseName, expected.getInt("matchedCount"), result.matchedCount)
        assertEquals(caseName, expected.getString("ruleConfidence"), result.ruleConfidence.name)
        assertEquals(caseName, expected.getBoolean("noMatchDetected"), result.noMatchDetected)
    }

    private fun readFixture(fileName: String): JSONObject {
        val fixturesDir = System.getProperty("voice.engine.fixtures.dir")
            ?: error("Missing voice.engine.fixtures.dir system property")
        return JSONObject(File(fixturesDir, fileName).readText())
    }

    private val JSONObject.name: String
        get() = optString("name").ifBlank { toString() }

    private fun JSONArray.forEachObject(block: (JSONObject) -> Unit) {
        for (index in 0 until length()) {
            block(getJSONObject(index))
        }
    }

    private fun JSONArray.toStringList(): List<String> {
        return List(length()) { index -> getString(index) }
    }
}
