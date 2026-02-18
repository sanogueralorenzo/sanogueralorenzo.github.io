package com.sanogueralorenzo.voice.summary

/**
 * Lightweight parsing and deterministic local heuristics for edit instructions and list-like text.
 */
internal object LiteRtEditHeuristics {
    internal enum class EditIntent {
        GENERAL,
        DELETE_ALL,
        REPLACE
    }

    internal enum class CommandScope {
        ALL,
        FIRST,
        LAST
    }

    internal enum class CommandKind {
        CLEAR_ALL,
        DELETE_TERM,
        REPLACE_TERM,
        UPDATE_NUMBER
    }

    internal enum class RuleConfidence {
        HIGH,
        LOW
    }

    internal data class EditInstructionAnalysis(
        val normalizedInstruction: String,
        val intent: EditIntent
    )

    internal data class DeterministicEditResult(
        val output: String,
        val applied: Boolean,
        val intent: EditIntent,
        val scope: CommandScope,
        val commandKind: CommandKind,
        val matchedCount: Int,
        val ruleConfidence: RuleConfidence,
        val noMatchDetected: Boolean
    )

    private data class ParsedCommand(
        val kind: CommandKind,
        val scope: CommandScope,
        val target: String? = null,
        val replacement: String? = null
    )

    private data class ScopedTarget(
        val scope: CommandScope,
        val target: String
    )

    private data class ReplaceApplyResult(
        val output: String,
        val matchedCount: Int
    )

    fun analyzeInstruction(instructionText: String): EditInstructionAnalysis {
        val collapsed = instructionText
            .replace(WhitespaceRegex, " ")
            .trim()
        val normalized = normalizeCorrectionPhrases(collapsed)
        val commandCandidate = stripCommandPreamble(normalized)
        val intent = when {
            DeleteAllRegex.containsMatchIn(commandCandidate) -> EditIntent.DELETE_ALL
            ReplaceRegex.containsMatchIn(commandCandidate) -> EditIntent.REPLACE
            else -> EditIntent.GENERAL
        }
        return EditInstructionAnalysis(
            normalizedInstruction = commandCandidate,
            intent = intent
        )
    }

    fun isStrictEditCommand(instructionText: String): Boolean {
        val collapsed = instructionText
            .replace(WhitespaceRegex, " ")
            .trim()
        if (collapsed.isBlank()) return false
        val commandCandidate = stripCommandPreamble(collapsed)
        if (commandCandidate.isBlank()) return false
        return ClearAllRegex.matches(commandCandidate) ||
            DeleteCommandRegex.matches(commandCandidate) ||
            ReplaceDirectRegex.matches(commandCandidate) ||
            ReplaceUseInsteadRegex.matches(commandCandidate) ||
            UpdateNumberCommandRegex.matches(commandCandidate)
    }

    fun shouldAllowBlankOutput(intent: EditIntent): Boolean {
        return intent == EditIntent.DELETE_ALL
    }

    fun tryApplyDeterministicEdit(
        sourceText: String,
        instructionText: String
    ): DeterministicEditResult? {
        if (sourceText.isBlank() || instructionText.isBlank()) return null
        val analysis = analyzeInstruction(instructionText)
        val commandCandidate = analysis.normalizedInstruction
        if (!passesCommandGate(commandCandidate)) return null

        val parsed = parseDeterministicCommand(commandCandidate) ?: return null
        return when (parsed.kind) {
            CommandKind.CLEAR_ALL -> {
                DeterministicEditResult(
                    output = "",
                    applied = sourceText.isNotEmpty(),
                    intent = EditIntent.DELETE_ALL,
                    scope = CommandScope.ALL,
                    commandKind = CommandKind.CLEAR_ALL,
                    matchedCount = if (sourceText.isNotEmpty()) 1 else 0,
                    ruleConfidence = RuleConfidence.HIGH,
                    noMatchDetected = false
                )
            }

            CommandKind.DELETE_TERM -> {
                val target = parsed.target.orEmpty()
                val targets = splitDeleteTargets(target)
                if (targets.size > 1 && parsed.scope != CommandScope.ALL) return null
                var updated = sourceText
                var totalMatched = 0
                targets.forEach { term ->
                    val replaceResult = applyScopedEdit(
                        sourceText = updated,
                        target = term,
                        replacement = "",
                        scope = if (targets.size > 1) CommandScope.ALL else parsed.scope
                    )
                    updated = replaceResult.output
                    totalMatched += replaceResult.matchedCount
                }
                DeterministicEditResult(
                    output = cleanupEditedText(updated),
                    applied = updated != sourceText,
                    intent = EditIntent.GENERAL,
                    scope = parsed.scope,
                    commandKind = CommandKind.DELETE_TERM,
                    matchedCount = totalMatched,
                    ruleConfidence = if (totalMatched > 0) {
                        RuleConfidence.HIGH
                    } else {
                        RuleConfidence.LOW
                    },
                    noMatchDetected = totalMatched == 0
                )
            }

            CommandKind.REPLACE_TERM -> {
                val target = parsed.target.orEmpty()
                val replacement = parsed.replacement.orEmpty()
                val replaceResult = applyScopedEdit(
                    sourceText = sourceText,
                    target = target,
                    replacement = replacement,
                    scope = parsed.scope
                )
                DeterministicEditResult(
                    output = cleanupEditedText(replaceResult.output),
                    applied = replaceResult.output != sourceText,
                    intent = EditIntent.REPLACE,
                    scope = parsed.scope,
                    commandKind = CommandKind.REPLACE_TERM,
                    matchedCount = replaceResult.matchedCount,
                    ruleConfidence = if (replaceResult.matchedCount > 0) {
                        RuleConfidence.HIGH
                    } else {
                        RuleConfidence.LOW
                    },
                    noMatchDetected = replaceResult.matchedCount == 0
                )
            }

            CommandKind.UPDATE_NUMBER -> {
                val replacement = parsed.replacement.orEmpty()
                val replaceResult = applyLastNumericEdit(
                    sourceText = sourceText,
                    replacement = replacement
                )
                DeterministicEditResult(
                    output = cleanupEditedText(replaceResult.output),
                    applied = replaceResult.output != sourceText,
                    intent = EditIntent.REPLACE,
                    scope = CommandScope.LAST,
                    commandKind = CommandKind.UPDATE_NUMBER,
                    matchedCount = replaceResult.matchedCount,
                    ruleConfidence = if (replaceResult.matchedCount > 0) {
                        RuleConfidence.HIGH
                    } else {
                        RuleConfidence.LOW
                    },
                    noMatchDetected = replaceResult.matchedCount == 0
                )
            }
        }
    }

    fun looksLikeList(text: String): Boolean {
        val input = text.trim()
        if (input.isBlank()) return false

        if (ExplicitBulletRegex.containsMatchIn(input)) return true
        if (ListCueRegex.containsMatchIn(input)) return true
        if (ShoppingTaskCueRegex.containsMatchIn(input) && DelimitedItemsRegex.containsMatchIn(input)) {
            return true
        }

        val newlineSegments = input.lines().map { it.trim() }.filter { it.isNotBlank() }
        if (newlineSegments.size >= 3 && newlineSegments.count { it.length <= 32 } >= 2) {
            return true
        }

        val delimiterCount = input.count { it == ',' || it == ';' || it == '|' }
        if (delimiterCount >= 3) {
            val tokens = input.split(Regex("[,;|]"))
                .map { it.trim() }
                .filter { it.isNotBlank() }
            if (tokens.size >= 4) {
                val avgLen = tokens.sumOf { it.length }.toFloat() / tokens.size.toFloat()
                if (avgLen <= 18f) return true
            }
        }

        return false
    }

    private fun normalizeCorrectionPhrases(text: String): String {
        if (text.isBlank()) return text

        val replaceCorrection = ReplaceCorrectionRegex.find(text)
        if (replaceCorrection != null) {
            val from = replaceCorrection.groupValues[1].trim()
            val correctedTo = replaceCorrection.groupValues[3].trim().trimEnd('.', '!')
            if (from.isNotBlank() && correctedTo.isNotBlank()) {
                return "replace $from with $correctedTo"
            }
        }

        if (InsteadOfPhraseRegex.containsMatchIn(text)) {
            return text
        }

        val generalCorrection = GeneralCorrectionRegex.find(text)
        if (generalCorrection != null) {
            val correctedTail = generalCorrection.groupValues[1].trim()
            if (correctedTail.isNotBlank()) {
                return correctedTail
            }
        }

        return text
    }

    private fun parseDeterministicCommand(instruction: String): ParsedCommand? {
        val clear = parseClearAllCommand(instruction)
        val delete = parseDeleteCommand(instruction)
        val replace = parseReplaceCommand(instruction)
        val updateNumber = parseUpdateNumberCommand(instruction)
        val parsed = listOfNotNull(clear, delete, replace, updateNumber)
        if (parsed.size != 1) return null
        return parsed.first()
    }

    private fun parseClearAllCommand(instruction: String): ParsedCommand? {
        if (!ClearAllRegex.matches(instruction)) return null
        return ParsedCommand(
            kind = CommandKind.CLEAR_ALL,
            scope = CommandScope.ALL
        )
    }

    private fun parseDeleteCommand(instruction: String): ParsedCommand? {
        val match = DeleteCommandRegex.find(instruction) ?: return null
        val rawTarget = listOfNotNull(
            match.groups[1]?.value,
            match.groups[2]?.value,
            match.groups[3]?.value
        ).firstOrNull().orEmpty()
        val scoped = scopedTarget(rawTarget) ?: return null
        val target = normalizeCommandTerm(scoped.target, stripArticleWordPrefix = true)
        if (target.isBlank()) return null
        if (DeleteAllTargetRegex.matches(target)) return null
        if (isAmbiguousPronounTarget(target)) return null
        return ParsedCommand(
            kind = CommandKind.DELETE_TERM,
            scope = scoped.scope,
            target = target
        )
    }

    private fun parseReplaceCommand(instruction: String): ParsedCommand? {
        val directMatch = ReplaceDirectRegex.find(instruction)
        if (directMatch != null) {
            val fromScoped = scopedTarget(directMatch.groupValues[1]) ?: return null
            val from = normalizeCommandTerm(fromScoped.target, stripArticleWordPrefix = true)
            val to = normalizeReplacementTerm(directMatch.groupValues[2])
            if (from.isBlank() || to.isBlank()) return null
            if (isAmbiguousPronounTarget(from)) return null
            return ParsedCommand(
                kind = CommandKind.REPLACE_TERM,
                scope = fromScoped.scope,
                target = from,
                replacement = to
            )
        }

        val useInsteadMatch = ReplaceUseInsteadRegex.find(instruction) ?: return null
        val fromScoped = scopedTarget(useInsteadMatch.groupValues[2]) ?: return null
        val from = normalizeCommandTerm(fromScoped.target, stripArticleWordPrefix = true)
        val to = normalizeReplacementTerm(useInsteadMatch.groupValues[1])
        if (from.isBlank() || to.isBlank()) return null
        if (isAmbiguousPronounTarget(from)) return null
        return ParsedCommand(
            kind = CommandKind.REPLACE_TERM,
            scope = fromScoped.scope,
            target = from,
            replacement = to
        )
    }

    private fun parseUpdateNumberCommand(instruction: String): ParsedCommand? {
        val match = UpdateNumberCommandRegex.find(instruction) ?: return null
        val replacement = normalizeReplacementTerm(match.groupValues[1])
        if (replacement.isBlank()) return null
        return ParsedCommand(
            kind = CommandKind.UPDATE_NUMBER,
            scope = CommandScope.LAST,
            replacement = replacement
        )
    }

    private fun scopedTarget(raw: String): ScopedTarget? {
        var target = raw.trim()
        target = target.replace(DeleteContextSuffixRegex, "")
        target = target.replace(ArticleWordPrefixRegex, "")
        target = target.trim()
        if (target.isBlank()) return null

        val hasFirst = ScopeFirstRegex.containsMatchIn(target)
        val hasLast = ScopeLastRegex.containsMatchIn(target)
        if (hasFirst && hasLast) return null

        val scope = when {
            hasFirst -> CommandScope.FIRST
            hasLast -> CommandScope.LAST
            else -> CommandScope.ALL
        }
        target = target
            .replace(ScopedPrefixRegex, "")
            .replace(ScopedSuffixRegex, "")
            .trim()
        if (target.isBlank()) return null
        return ScopedTarget(scope = scope, target = target)
    }

    private fun applyScopedEdit(
        sourceText: String,
        target: String,
        replacement: String,
        scope: CommandScope
    ): ReplaceApplyResult {
        val regex = targetRegex(target)
        val matches = regex.findAll(sourceText).toList()
        if (matches.isEmpty()) {
            return ReplaceApplyResult(output = sourceText, matchedCount = 0)
        }

        return when (scope) {
            CommandScope.ALL -> {
                ReplaceApplyResult(
                    output = regex.replace(sourceText, replacement),
                    matchedCount = matches.size
                )
            }

            CommandScope.FIRST -> {
                val first = matches.first()
                ReplaceApplyResult(
                    output = sourceText.replaceRange(first.range, replacement),
                    matchedCount = 1
                )
            }

            CommandScope.LAST -> {
                val last = matches.last()
                ReplaceApplyResult(
                    output = sourceText.replaceRange(last.range, replacement),
                    matchedCount = 1
                )
            }
        }
    }

    private fun splitDeleteTargets(target: String): List<String> {
        val normalized = target.trim()
        if (!DeleteTargetSeparatorRegex.containsMatchIn(normalized)) {
            return listOf(normalized)
        }
        val tokens = DeleteTargetSeparatorRegex.split(normalized)
            .map { normalizeCommandTerm(it, stripArticleWordPrefix = true) }
            .filter { it.isNotBlank() }
        if (tokens.size < 2) return listOf(normalized)
        if (tokens.any { WordRegex.findAll(it).count() > MAX_MULTI_TARGET_TERM_WORDS }) {
            return listOf(normalized)
        }
        return tokens.distinctBy { it.lowercase() }
    }

    private fun targetRegex(term: String): Regex {
        val escaped = Regex.escape(term)
        return if (SingleTokenRegex.matches(term)) {
            Regex("\\b$escaped\\b", setOf(RegexOption.IGNORE_CASE))
        } else {
            Regex(escaped, setOf(RegexOption.IGNORE_CASE))
        }
    }

    private fun applyLastNumericEdit(sourceText: String, replacement: String): ReplaceApplyResult {
        val matches = NumericLikeRegex.findAll(sourceText).toList()
        if (matches.isEmpty()) {
            return ReplaceApplyResult(output = sourceText, matchedCount = 0)
        }
        val last = matches.last()
        return ReplaceApplyResult(
            output = sourceText.replaceRange(last.range, replacement),
            matchedCount = 1
        )
    }

    private fun passesCommandGate(normalizedInstruction: String): Boolean {
        if (normalizedInstruction.length > MAX_COMMAND_CHARS) return false
        if (WordRegex.findAll(normalizedInstruction).count() > MAX_COMMAND_WORDS) return false
        return true
    }

    private fun normalizeCommandTerm(
        raw: String,
        stripArticleWordPrefix: Boolean
    ): String {
        var term = raw.trim()
        term = term.replace(TrimPoliteSuffixRegex, "")
        term = stripWrappingQuotes(term)
        if (stripArticleWordPrefix) {
            term = term.replace(ArticleWordPrefixRegex, "")
        }
        term = term.trim().trimEnd('.', ',', ';', '!', '?', ':')
        return term.trim()
    }

    private fun normalizeReplacementTerm(raw: String): String {
        var term = raw.trim()
        term = term.replace(TrimPoliteSuffixRegex, "")
        term = stripWrappingQuotes(term)
        term = term.replace(ArticleWordPrefixRegex, "")
        term = term.trim().trimEnd('.', ',', ';', '!', '?', ':')
        return term.trim()
    }

    private fun stripCommandPreamble(text: String): String {
        val withoutPreamble = text
            .replace(CommandPreambleRegex, "")
            .trim()
            .trimEnd('?')
            .trim()
        return withoutPreamble.ifBlank { text.trim() }
    }

    private fun isAmbiguousPronounTarget(target: String): Boolean {
        return AmbiguousPronounTargetRegex.matches(target.trim())
    }

    private fun stripWrappingQuotes(text: String): String {
        var value = text.trim()
        if (value.length < 2) return value
        val pairs = listOf(
            '"' to '"',
            '\'' to '\'',
            '“' to '”',
            '‘' to '’',
            '`' to '`'
        )
        for ((start, end) in pairs) {
            if (value.first() == start && value.last() == end && value.length >= 2) {
                value = value.substring(1, value.length - 1).trim()
                break
            }
        }
        return value
    }

    private fun cleanupEditedText(text: String): String {
        if (text.isBlank()) return ""
        return text
            .replace(SpaceBeforePunctuationRegex, "$1")
            .replace(MultiSpaceRegex, " ")
            .replace(SpacedNewlineRegex, "\n")
            .replace(MultiNewlineRegex, "\n\n")
            .trim()
    }

    private const val MAX_COMMAND_WORDS = 10
    private const val MAX_COMMAND_CHARS = 96
    private const val MAX_MULTI_TARGET_TERM_WORDS = 3

    private val WhitespaceRegex = Regex("\\s+")
    private val WordRegex = Regex("\\p{L}[\\p{L}\\p{N}'’-]*")
    private val CommandPreambleRegex = Regex(
        "^\\s*(?:(?:okay|ok|hey)\\s+)?(?:(?:can|could|would|will)\\s+you\\s+)?(?:please\\s+)?",
        RegexOption.IGNORE_CASE
    )

    private val ClearAllRegex = Regex(
        "^\\s*(?:please\\s+)?(?:(?:delete|clear|erase|wipe|remove|reset)\\s+(?:all|everything|(?:the\\s+)?(?:whole|entire)\\s+(?:message|text)|(?:the\\s+)?message|(?:the\\s+)?text)|start\\s+over|scratch(?:\\s+that)?)\\s*$",
        RegexOption.IGNORE_CASE
    )
    private val DeleteAllRegex = Regex(
        "\\b(?:delete|clear|remove|erase|wipe|reset|start\\s+over|scratch)\\b.*\\b(?:all|everything|whole|entire|start\\s+over)\\b",
        RegexOption.IGNORE_CASE
    )
    private val DeleteCommandRegex = Regex(
        "^\\s*(?:please\\s+)?(?:(?:delete|remove|erase|drop|cut)\\s+(.+?)|take\\s+out\\s+(.+?)|get\\s+rid\\s+of\\s+(.+?))\\s*$",
        RegexOption.IGNORE_CASE
    )

    private val ReplaceRegex = Regex(
        "^\\s*(?:please\\s+)?(?:(?:replace|change|swap|substitute|update|correct)\\s+.+\\s+(?:with|to|for)\\s+.+|use\\s+.+\\s+instead\\s+of\\s+.+)$",
        RegexOption.IGNORE_CASE
    )
    private val ReplaceDirectRegex = Regex(
        "^\\s*(?:please\\s+)?(?:replace|change|swap|substitute|update|correct)\\s+(.+?)\\s+(?:with|to|for)\\s+(.+?)\\s*$",
        RegexOption.IGNORE_CASE
    )
    private val ReplaceUseInsteadRegex = Regex(
        "^\\s*(?:please\\s+)?use\\s+(.+?)\\s+instead\\s+of\\s+(.+?)\\s*$",
        RegexOption.IGNORE_CASE
    )
    private val UpdateNumberCommandRegex = Regex(
        "^\\s*(?:please\\s+)?update\\s+number\\s+(?:to|with)\\s+(.+?)\\s*$",
        RegexOption.IGNORE_CASE
    )
    private val DeleteTargetSeparatorRegex = Regex(
        "\\s*(?:,|\\band\\b)\\s*",
        RegexOption.IGNORE_CASE
    )
    private val NumericLikeRegex = Regex(
        "\\b\\d{1,4}(?::\\d{2})?(?:\\s?(?:am|pm))?\\b",
        RegexOption.IGNORE_CASE
    )

    private val DeleteAllTargetRegex = Regex(
        "^(?:all|everything|(?:the\\s+)?(?:whole|entire)\\s+(?:message|text)|(?:the\\s+)?message|(?:the\\s+)?text)$",
        RegexOption.IGNORE_CASE
    )
    private val ReplaceCorrectionRegex = Regex(
        "^\\s*(?:please\\s+)?replace\\s+(.+?)\\s+with\\s+(.+?)\\s*(?:,?\\s*(?:no|actually|instead|wait)\\s*,?\\s*(?:let'?s\\s+do|make\\s+it|use)?\\s+(.+))\\s*$",
        RegexOption.IGNORE_CASE
    )
    private val GeneralCorrectionRegex = Regex(
        "^\\s*.+?\\s+(?:no|actually|instead|rather|wait)\\s*,?\\s*(?:let'?s\\s+do|make\\s+it|use)?\\s+(.+)\\s*$",
        RegexOption.IGNORE_CASE
    )
    private val InsteadOfPhraseRegex = Regex(
        "\\binstead\\s+of\\b",
        RegexOption.IGNORE_CASE
    )

    private val DeleteContextSuffixRegex = Regex(
        "\\s+(?:from\\s+(?:the\\s+)?(?:message|text)|in\\s+(?:the\\s+)?(?:message|text)|from\\s+it)$",
        RegexOption.IGNORE_CASE
    )
    private val ScopedPrefixRegex = Regex(
        "^(?:only\\s+)?(?:first|last|final)\\s+",
        RegexOption.IGNORE_CASE
    )
    private val ScopedSuffixRegex = Regex(
        "\\s+(?:only\\s+first|first|last|final)$",
        RegexOption.IGNORE_CASE
    )
    private val ScopeFirstRegex = Regex(
        "\\b(?:only\\s+first|first)\\b",
        RegexOption.IGNORE_CASE
    )
    private val ScopeLastRegex = Regex(
        "\\b(?:last|final)\\b",
        RegexOption.IGNORE_CASE
    )
    private val AmbiguousPronounTargetRegex = Regex(
        "^(?:it|that|this|thing|part)$",
        RegexOption.IGNORE_CASE
    )

    private val ExplicitBulletRegex = Regex(
        "(?m)^\\s*(?:[-*•]|\\d+[.)])\\s+\\S+"
    )
    private val ListCueRegex = Regex(
        "\\b(first|second|third|fourth|fifth|next|then|finally|list|bullet|bullets|items?|steps?|points?)\\b|\\d+[.)]",
        RegexOption.IGNORE_CASE
    )
    private val ShoppingTaskCueRegex = Regex(
        "\\b(buy|shopping|groceries|todo|to-do|tasks?|pick\\s+up|get\\s+me|remember\\s+to|need\\s+to)\\b",
        RegexOption.IGNORE_CASE
    )
    private val DelimitedItemsRegex = Regex(
        "\\b\\w+\\b\\s*[,;|]\\s*\\b\\w+\\b\\s*[,;|]"
    )

    private val SingleTokenRegex = Regex("^[\\p{L}\\p{N}_'’-]+$")
    private val ArticleWordPrefixRegex = Regex(
        "^(?:(?:the|a|an)\\s+)?(?:word|phrase|term|text|token)\\s+",
        RegexOption.IGNORE_CASE
    )
    private val TrimPoliteSuffixRegex = Regex(
        "\\s*(?:please|pls|thanks|thank\\s+you)$",
        RegexOption.IGNORE_CASE
    )
    private val SpaceBeforePunctuationRegex = Regex("\\s+([,.;!?])")
    private val MultiSpaceRegex = Regex("[ \\t]{2,}")
    private val SpacedNewlineRegex = Regex("[ \\t]*\\n[ \\t]*")
    private val MultiNewlineRegex = Regex("\\n{3,}")
}
