package com.sanogueralorenzo.voice.overlay

internal fun textRepresentsHint(
    text: String,
    showingHintText: Boolean,
    hintText: String?,
    hasEditableContent: () -> Boolean
): Boolean {
    if (showingHintText) return true
    if (!hintText.isNullOrBlank() && text.equals(hintText.trim(), ignoreCase = true)) return true
    return !hasEditableContent()
}
