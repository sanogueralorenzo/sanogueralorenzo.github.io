package com.sanogueralorenzo.voice.summary.rules.post

import com.sanogueralorenzo.voice.summary.rules.pre.EditInstructionRules

internal class PostReplaceCapitalizationRule {
    fun apply(
        sourceText: String,
        instructionText: String,
        editedOutput: String
    ): String {
        if (sourceText.isBlank() || instructionText.isBlank() || editedOutput.isBlank()) return editedOutput
        val terms = EditInstructionRules.replacementTermsForPostCapitalization(instructionText) ?: return editedOutput

        val sourceMatches = targetRegex(terms.target).findAll(sourceText).toList()
        val capitalizedSourceMatch = sourceMatches.firstOrNull { isCapitalizedWordMatch(it.value) }
            ?: return editedOutput

        val replacementRegex = targetRegex(terms.replacement)
        return replacementRegex.replace(editedOutput) { match ->
            applyReplacementCasing(capitalizedSourceMatch.value, match.value)
        }
    }

    private fun targetRegex(term: String): Regex {
        val escaped = Regex.escape(term)
        return if (SingleTokenRegex.matches(term)) {
            Regex("\\b$escaped\\b", setOf(RegexOption.IGNORE_CASE))
        } else {
            Regex(escaped, setOf(RegexOption.IGNORE_CASE))
        }
    }

    private fun applyReplacementCasing(sourceMatch: String, replacement: String): String {
        if (replacement.isBlank()) return replacement
        if (!isCapitalizedWordMatch(sourceMatch)) return replacement
        val firstLetterIndex = replacement.indexOfFirst { it.isLetter() }
        if (firstLetterIndex < 0) return replacement
        if (replacement[firstLetterIndex].isUpperCase()) return replacement
        return buildString(replacement.length) {
            append(replacement.substring(0, firstLetterIndex))
            append(replacement[firstLetterIndex].titlecaseChar())
            append(replacement.substring(firstLetterIndex + 1))
        }
    }

    private fun isCapitalizedWordMatch(value: String): Boolean {
        val firstLetterIndex = value.indexOfFirst { it.isLetter() }
        if (firstLetterIndex < 0) return false
        return value[firstLetterIndex].isUpperCase()
    }

    private companion object {
        private val SingleTokenRegex = Regex("^[\\p{L}\\p{N}_'’-]+$")
    }
}
