package com.sanogueralorenzo.voice.setup

import com.google.ai.edge.litertlm.Backend
import com.sanogueralorenzo.voice.summary.LiteRtFailureException
import com.sanogueralorenzo.voice.summary.RewriteResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptBenchmarkingCoreTest {
    @Test
    fun suiteIntegrity_hasTwentyCasesUniqueIdsAndBothTypes() {
        val cases = PromptBenchmarkSuite.defaultCases()
        assertEquals(20, cases.size)
        assertEquals(cases.size, cases.map { it.id }.toSet().size)
        assertTrue(cases.any { it.type == PromptBenchmarkCaseType.COMPOSE })
        assertTrue(cases.any { it.type == PromptBenchmarkCaseType.EDIT })
    }

    @Test
    fun runnerExecutesStrictlySequentialOrder() = runBlocking {
        val cases = listOf(
            PromptBenchmarkCase(
                id = "C1",
                title = "Compose one",
                category = "compose",
                type = PromptBenchmarkCaseType.COMPOSE,
                composeInput = "hello"
            ),
            PromptBenchmarkCase(
                id = "C2",
                title = "Compose two",
                category = "compose",
                type = PromptBenchmarkCaseType.COMPOSE,
                composeInput = "bye"
            )
        )
        val calls = ArrayList<String>()
        val gateway = object : PromptBenchmarkGateway {
            override fun runCompose(input: String): RewriteResult {
                calls += "compose:$input"
                return RewriteResult.Success(text = input.uppercase(), latencyMs = 10L, backend = Backend.CPU)
            }

            override fun runEdit(original: String, instruction: String): RewriteResult {
                calls += "edit:$original|$instruction"
                return RewriteResult.Success(text = original, latencyMs = 10L, backend = Backend.CPU)
            }
        }

        PromptBenchmarkRunner.runAll(
            gateway = gateway,
            cases = cases,
            suiteVersion = "test",
            repeats = 3,
            modelId = "model",
            customInstructions = "",
            promptInstructionsSnapshot = "snapshot"
        )

        assertEquals(
            listOf(
                "compose:hello",
                "compose:hello",
                "compose:hello",
                "compose:bye",
                "compose:bye",
                "compose:bye"
            ),
            calls
        )
    }

    @Test
    fun repeatBehaviorAndAggregation_areComputedPerCase() = runBlocking {
        val case = PromptBenchmarkCase(
            id = "C1",
            title = "Compose",
            category = "compose",
            type = PromptBenchmarkCaseType.COMPOSE,
            composeInput = "x"
        )
        var callCount = 0
        val gateway = object : PromptBenchmarkGateway {
            override fun runCompose(input: String): RewriteResult {
                callCount += 1
                val output = when (callCount) {
                    1, 2 -> "same"
                    else -> "different"
                }
                return RewriteResult.Success(text = output, latencyMs = (callCount * 10).toLong(), backend = Backend.GPU)
            }

            override fun runEdit(original: String, instruction: String): RewriteResult {
                return RewriteResult.Success(text = original, latencyMs = 1L, backend = Backend.CPU)
            }
        }

        val result = PromptBenchmarkRunner.runAll(
            gateway = gateway,
            cases = listOf(case),
            suiteVersion = "test",
            repeats = 3,
            modelId = "model",
            customInstructions = "",
            promptInstructionsSnapshot = "snapshot"
        )

        val caseResult = result.cases.single()
        assertEquals(3, caseResult.runs.size)
        assertEquals(2, caseResult.uniqueOutputsCount)
        assertEquals(20L, caseResult.avgLatencyMs)
        assertEquals(10L, caseResult.minLatencyMs)
        assertEquals(30L, caseResult.maxLatencyMs)
    }

    @Test
    fun failureMapping_isCapturedInRunResults() = runBlocking {
        val case = PromptBenchmarkCase(
            id = "E1",
            title = "Edit",
            category = "edit",
            type = PromptBenchmarkCaseType.EDIT,
            editOriginal = "hello",
            editInstruction = "change"
        )
        val gateway = object : PromptBenchmarkGateway {
            override fun runCompose(input: String): RewriteResult {
                return RewriteResult.Success(text = input, latencyMs = 1L, backend = Backend.CPU)
            }

            override fun runEdit(original: String, instruction: String): RewriteResult {
                return RewriteResult.Failure(
                    latencyMs = 123L,
                    backend = Backend.GPU,
                    error = LiteRtFailureException(
                        type = LiteRtFailureException.TYPE_INVALID_ARGUMENT,
                        litertError = "INVALID_ARGUMENT"
                    )
                )
            }
        }

        val result = PromptBenchmarkRunner.runAll(
            gateway = gateway,
            cases = listOf(case),
            suiteVersion = "test",
            repeats = 3,
            modelId = "model",
            customInstructions = "",
            promptInstructionsSnapshot = "snapshot"
        )

        val run = result.cases.single().runs.first()
        assertEquals(false, run.success)
        assertEquals("invalid_argument", run.errorType)
        assertEquals("INVALID_ARGUMENT", run.errorMessage)
    }

    @Test
    fun formatterIncludesInstructionsAndRunOutputs() {
        val case = PromptBenchmarkCase(
            id = "C1",
            title = "Compose",
            category = "compose",
            type = PromptBenchmarkCaseType.COMPOSE,
            composeInput = "input"
        )
        val session = PromptBenchmarkSessionResult(
            suiteVersion = "v1",
            repeats = 3,
            timestampMs = 1700000000000L,
            totalElapsedMs = 500L,
            modelId = "gemma3-1b-it-litertlm",
            customInstructions = "none",
            promptInstructionsSnapshot = "rewrite_system_instruction:\nR\n\nedit_system_instruction:\nE",
            cases = listOf(
                PromptBenchmarkCaseResult(
                    caseDef = case,
                    runs = listOf(
                        PromptBenchmarkRunResult(1, "out1", 10L, "GPU", null, null, true),
                        PromptBenchmarkRunResult(2, "out2", 20L, "GPU", null, null, true),
                        PromptBenchmarkRunResult(3, "out3", 30L, "CPU", null, null, true)
                    ),
                    uniqueOutputsCount = 3,
                    avgLatencyMs = 20L,
                    minLatencyMs = 10L,
                    maxLatencyMs = 30L
                )
            )
        )

        val text = PromptBenchmarkReportFormatter.toPlainText(session)
        assertTrue(text.contains("[prompt_instructions]"))
        assertTrue(text.contains("rewrite_system_instruction"))
        assertTrue(text.contains("run_1_after: out1"))
        assertTrue(text.contains("run_3_after: out3"))
        assertTrue(text.contains("[summary]"))
    }
}
