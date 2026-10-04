package com.sanogueralorenzo.androidsteam.games

/** Edit selected KeyValues fields while preserving every unrelated source byte. */
internal class SteamSettingsText(private val source: String) {
    private data class Entry(val key: String, val start: Int, val end: Int,
        val text: String?, val valueStart: Int, val valueEnd: Int,
        val children: List<Entry>?, val closing: Int)
    private var position = 0
    private val entries = read(0, false).first

    fun get(path: List<String>): String? = find(path)?.text
    fun keys(path: List<String>): List<String> = (if (path.isEmpty()) entries else find(path)?.children).orEmpty().map { it.key }

    fun put(path: List<String>, value: String?): String {
        require(path.isNotEmpty())
        val existing = find(path)
        if (value == null) return if (existing == null) source else source.removeRange(existing.start, existing.end)
        if (existing != null) {
            require(existing.children == null) { "Steam setting is not a text field." }
            return source.replaceRange(existing.valueStart, existing.valueEnd, quote(value))
        }
        var parent: Entry? = null
        var depth = 0
        while (depth < path.lastIndex) {
            val next = entry(parent?.children ?: entries, path[depth]) ?: break
            require(next.children != null) { "Steam settings section is not an object." }
            parent = next; depth++
        }
        fun field(index: Int, indent: String): String = if (index == path.lastIndex)
            "$indent${quote(path[index])}\t${quote(value)}\n"
        else "$indent${quote(path[index])}\n$indent{\n${field(index + 1, "$indent\t")}$indent}\n"
        val insertion = parent?.closing ?: source.length
        val text = "\n" + field(depth, "\t".repeat(depth)) + "\t".repeat((depth - 1).coerceAtLeast(0))
        return source.substring(0, insertion) + text + source.substring(insertion)
    }

    private fun find(path: List<String>): Entry? {
        var children = entries
        var result: Entry? = null
        path.forEachIndexed { index, name ->
            result = entry(children, name) ?: return null
            if (index < path.lastIndex) children = result!!.children ?: return null
        }
        return result
    }

    private fun entry(children: List<Entry>, name: String): Entry? {
        val matches = children.filter { it.key.equals(name, true) }
        require(matches.size <= 1) { "Steam settings contain an ambiguous field. Edit it in Steam." }
        return matches.singleOrNull()
    }

    private fun read(depth: Int, nested: Boolean): Pair<List<Entry>, Int> {
        require(depth <= 64) { "Steam settings are too deeply nested." }
        val result = mutableListOf<Entry>()
        while (true) {
            whitespace()
            if (position == source.length) {
                require(!nested) { "Steam settings object is incomplete." }
                return result to position
            }
            if (source[position] == '}') {
                require(nested) { "Steam settings have an unmatched closing brace." }
                return result to position++
            }
            val start = position
            val key = string()
            whitespace()
            val valueStart = position
            if (position < source.length && source[position] == '{') {
                position++
                val (children, closing) = read(depth + 1, true)
                result += Entry(key, start, position, null, valueStart, position, children, closing)
            } else {
                val value = string()
                result += Entry(key, start, position, value, valueStart, position, null, -1)
            }
        }
    }

    private fun whitespace() {
        while (position < source.length) {
            if (source[position].isWhitespace()) position++
            else if (source.startsWith("//", position)) {
                position = source.indexOf('\n', position).takeIf { it >= 0 } ?: source.length
            } else break
        }
    }

    private fun string(): String {
        require(position < source.length && source[position++] == '"') { "Steam settings contain an invalid field." }
        val result = StringBuilder()
        while (position < source.length) {
            val character = source[position++]
            if (character == '"') return result.toString()
            if (character != '\\') { result.append(character); continue }
            require(position < source.length) { "Steam settings string is incomplete." }
            when (val escaped = source[position++]) {
                '"', '\\' -> result.append(escaped)
                'n' -> result.append('\n')
                'r' -> result.append('\r')
                't' -> result.append('\t')
                else -> result.append('\\').append(escaped)
            }
        }
        error("Steam settings string is incomplete.")
    }

    companion object {
        private fun quote(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"")
            .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + "\""
    }
}
