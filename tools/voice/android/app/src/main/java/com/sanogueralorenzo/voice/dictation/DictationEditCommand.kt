package com.sanogueralorenzo.voice.dictation

internal sealed interface DictationEditCommand {
    fun applyTo(source: String): String

    data object Clear : DictationEditCommand {
        override fun applyTo(source: String): String = ""
    }

    data class Delete(private val target: String) : DictationEditCommand {
        override fun applyTo(source: String): String = source
            .replace(targetRegex(target), "")
            .cleanupAfterEdit()
    }

    data class Replace(
        private val target: String,
        private val replacement: String
    ) : DictationEditCommand {
        override fun applyTo(source: String): String = targetRegex(target)
            .replace(source) { replacement }
            .cleanupAfterEdit()
    }
}

internal object DictationEditCommands {
    private val whitespace = Regex("\\s+")
    private val delete = Regex("^delete\\s+(.+)$", RegexOption.IGNORE_CASE)
    private val replace = Regex("^replace\\s+(.+?)\\s+with\\s+(.+)$", RegexOption.IGNORE_CASE)
    private val commandWords = listOf("clear", "delete", "replace")

    fun parse(transcript: String): DictationEditCommand? {
        val normalized = normalize(transcript)
        if (normalized.equals("clear", ignoreCase = true)) {
            return DictationEditCommand.Clear
        }
        delete.matchEntire(normalized)?.let { match ->
            val target = match.groupValues[1].trim()
            if (target.isNotEmpty()) return DictationEditCommand.Delete(target)
        }
        replace.matchEntire(normalized)?.let { match ->
            val target = match.groupValues[1].trim()
            val replacement = match.groupValues[2].trim()
            if (target.isNotEmpty() && replacement.isNotEmpty()) {
                return DictationEditCommand.Replace(target, replacement)
            }
        }
        return null
    }

    fun isPotentialCommand(transcript: String): Boolean {
        val normalized = normalize(transcript).lowercase()
        if (normalized.isEmpty()) return false
        return commandWords.any { command ->
            command.startsWith(normalized) ||
                normalized == command ||
                normalized.startsWith("$command ")
        }
    }

    private fun normalize(transcript: String): String = transcript
        .replace(".", "")
        .replace(",", "")
        .replace(whitespace, " ")
        .trim()
}

private fun targetRegex(target: String): Regex = Regex(
    pattern = "(?<![\\p{L}\\p{N}])${Regex.escape(target)}(?![\\p{L}\\p{N}])",
    option = RegexOption.IGNORE_CASE
)

private fun String.cleanupAfterEdit(): String = this
    .replace(Regex("[ \\t]+([.,!?;:])"), "$1")
    .replace(Regex("[ \\t]{2,}"), " ")
    .trim()
