package com.sanogueralorenzo.voice.benchmark

internal object BenchmarkScoring {
    fun isCasePassed(caseResult: BenchmarkCaseResult): Boolean {
        if (caseResult.runs.any { !it.success }) return false
        val expected = caseResult.caseDef.expectedOutput?.trim().orEmpty()
        if (expected.isBlank()) return true
        val output = benchmarkOutputText(caseResult.runs)
        return normalizeForMatch(output) == normalizeForMatch(expected)
    }

    fun benchmarkOutputText(runs: List<BenchmarkRunResult>): String {
        return runs.lastOrNull { !it.output.isNullOrBlank() }?.output
            ?: runs.lastOrNull()?.output
            ?: "(error)"
    }

    fun normalizeForMatch(value: String): String {
        return value.replace("\r\n", "\n").trim()
    }
}
