package com.sanogueralorenzo.androidsteam.input

/** Coalesce held keys so releasing one input cannot cancel another's hold. */
internal class InputKeys(private val send: (Int, Boolean) -> Unit) {
    private val held = mutableMapOf<String, Set<Int>>()

    fun set(source: String, keys: Set<Int>) {
        if (held[source].orEmpty() == keys) return
        val before = held.values.flatten().toSet()
        if (keys.isEmpty()) held.remove(source) else held[source] = keys
        val after = held.values.flatten().toSet()
        (before - after).forEach { send(it, false) }
        (after - before).forEach { send(it, true) }
    }

    fun clear() {
        held.values.flatten().toSet().forEach { send(it, false) }
        held.clear()
    }
}
