package com.sanogueralorenzo.voice.summary

private val WhitespaceRegex = Regex("\\s+")

data class SummaryBudget(val maxTokens: Int)

/** Small policy helper for rewrite token budgets based on transcript length. */
object SummaryPolicy {
    fun budgetForText(text: String): SummaryBudget {
        return budgetForWordCount(wordCount(text))
    }

    fun budgetForWordCount(wordCount: Int): SummaryBudget {
        return when {
            wordCount <= 20 -> SummaryBudget(maxTokens = 96)
            wordCount <= 50 -> SummaryBudget(maxTokens = 160)
            wordCount <= 100 -> SummaryBudget(maxTokens = 256)
            else -> SummaryBudget(maxTokens = 256)
        }
    }

    private fun wordCount(text: String): Int {
        val cleaned = text.replace(WhitespaceRegex, " ").trim()
        if (cleaned.isBlank()) return 0
        return cleaned.split(WhitespaceRegex).size
    }
}
