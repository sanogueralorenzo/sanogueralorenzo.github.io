package com.sanogueralorenzo.voice.summary.rules.post

internal class ModelOutputCleanupRule {
    fun clean(
        text: String,
        bulletMode: Boolean
    ): String {
        var cleaned = text.trim()
        if (cleaned.isBlank()) return ""
        val anchorMatches = CLEANED_ANCHOR_REGEX.findAll(cleaned).toList()
        if (anchorMatches.isNotEmpty()) {
            cleaned = cleaned.substring(anchorMatches.last().range.last + 1).trim()
        }
        cleaned = cleaned
            .replace(PREFIX_LABEL_REGEX, "")
            .trim()
            .trim('`')
            .trim()
            .removeSurrounding("\"")
            .removeSurrounding("'")
            .trim()
        if (cleaned.isBlank()) return ""
        if (cleaned.startsWith("user input:", ignoreCase = true)) {
            val nonEmptyLines = cleaned
                .lineSequence()
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .toList()
            if (nonEmptyLines.size >= 2) {
                cleaned = nonEmptyLines.last()
            }
        }
        if (!bulletMode && cleaned.startsWith("- ")) {
            cleaned = cleaned
                .lineSequence()
                .map { it.removePrefix("- ").trim() }
                .filter { it.isNotBlank() }
                .joinToString(" ")
        }
        return cleaned
    }

    private companion object {
        private val PREFIX_LABEL_REGEX = Regex(
            "^(rewritten|rewrite|cleaned|output|result)\\s*:\\s*",
            RegexOption.IGNORE_CASE
        )
        private val CLEANED_ANCHOR_REGEX = Regex(
            "^cleaned\\s*:\\s*",
            setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)
        )
    }
}
