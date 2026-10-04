package com.sanogueralorenzo.androidsteam.games

internal data class GameLaunchProfile(val tool: String?, val arguments: List<String>, val environment: Map<String, String>) {
    init {
        require(arguments.all { '\u0000' !in it && "%command%" !in it }) { "Enter game arguments without Steam command placeholders." }
        require(environment.keys.all { variable.matches(it) && it !in reserved && !it.startsWith("STEAM_COMPAT_") }) { "Environment names must be valid game variables; Android Steam manages loader, audio and Steam paths." }
        require(environment.values.all { '\u0000' !in it && "%command%" !in it }) { "Environment values cannot contain Steam command placeholders." }
    }

    fun launchOptions(): String = buildList {
        if (environment.isNotEmpty()) {
            add("env")
            environment.forEach { (name, value) -> add(quote("$name=$value")) }
            add("%command%")
        }
        addAll(arguments.map(::quote))
    }.joinToString(" ")

    companion object {
        private val variable = Regex("[A-Za-z_][A-Za-z0-9_]*")
        private val reserved = setOf("LD_PRELOAD", "LD_LIBRARY_PATH", "PULSE_SERVER", "HOME", "PATH", "SteamAppId", "SteamGameId")
        private fun quote(value: String) = "'" + value.replace("'", "'\"'\"'") + "'"
        fun argumentText(arguments: List<String>) = arguments.joinToString(" ") {
            if (Regex("[A-Za-z0-9_./:=+\\-]+").matches(it)) it else quote(it)
        }

        /** Shell-style words only: expansions and commands are never evaluated. */
        fun words(text: String): List<String> {
            val result = mutableListOf<String>()
            val word = StringBuilder()
            var quote: Char? = null
            var escaped = false
            var started = false
            text.forEach { character ->
                if (escaped) {
                    if (quote == '"' && character !in charArrayOf('"', '\\', '$', '`', '\n')) word.append('\\')
                    if (character != '\n') word.append(character)
                    escaped = false
                }
                else if (character == '\\' && quote != '\'') { escaped = true; started = true }
                else if (quote != null) { if (character == quote) quote = null else word.append(character) }
                else if (character == '\'' || character == '"') { quote = character; started = true }
                else if (character.isWhitespace()) {
                    if (started) { result += word.toString(); word.clear(); started = false }
                } else { word.append(character); started = true }
            }
            require(!escaped && quote == null) { "Complete the quoted game argument." }
            if (started) result += word.toString()
            return result
        }

        fun fromSteam(tool: String?, options: String): GameLaunchProfile {
            val tokens = words(options)
            val command = tokens.indexOf("%command%")
            if (command < 0) return GameLaunchProfile(tool, tokens, emptyMap())
            val prefix = tokens.take(command).let { if (it.firstOrNull() == "env") it.drop(1) else it }
            require(prefix.all { '=' in it }) { "Edit complex launch commands in Steam." }
            return GameLaunchProfile(tool, tokens.drop(command + 1), assignments(prefix))
        }

        fun environment(text: String): Map<String, String> = assignments(text.lineSequence().filter { it.isNotBlank() }.asIterable())
        private fun assignments(lines: Iterable<String>): Map<String, String> = buildMap {
            lines.forEach { line ->
                val split = line.indexOf('=')
                require(split > 0) { "Use one NAME=value environment setting per line." }
                val name = line.substring(0, split).trim()
                require(!containsKey(name)) { "Each environment name can appear only once." }
                put(name, line.substring(split + 1))
            }
        }
    }
}
