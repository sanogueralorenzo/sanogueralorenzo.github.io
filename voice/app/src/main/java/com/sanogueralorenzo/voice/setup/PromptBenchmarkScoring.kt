package com.sanogueralorenzo.voice.setup

internal object PromptBenchmarkScoring {
    fun isCasePassed(caseResult: PromptBenchmarkCaseResult): Boolean {
        if (caseResult.runs.any { !it.success }) return false
        val expected = caseResult.caseDef.expectedOutput?.trim().orEmpty()
        if (expected.isBlank()) return true
        val output = benchmarkOutputText(caseResult.runs)
        return normalizeForMatch(output) == normalizeForMatch(expected)
    }

    fun benchmarkOutputText(runs: List<PromptBenchmarkRunResult>): String {
        return runs.lastOrNull { !it.output.isNullOrBlank() }?.output
            ?: runs.lastOrNull()?.output
            ?: "(error)"
    }

    fun normalizeForMatch(value: String): String {
        return value.replace("\r\n", "\n").trim()
    }
}
