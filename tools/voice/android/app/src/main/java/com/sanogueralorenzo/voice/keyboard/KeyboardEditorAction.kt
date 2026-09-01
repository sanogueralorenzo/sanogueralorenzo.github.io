package com.sanogueralorenzo.voice.keyboard

import android.view.inputmethod.EditorInfo

/** Resolves only actions explicitly requested by the focused field. */
internal object KeyboardEditorAction {
    fun resolve(editorInfo: EditorInfo?): Int? {
        if (editorInfo == null) return null
        return resolve(
            imeOptions = editorInfo.imeOptions,
            customActionId = editorInfo.actionId,
            hasCustomActionLabel = editorInfo.actionLabel != null
        )
    }

    internal fun resolve(
        imeOptions: Int,
        customActionId: Int = 0,
        hasCustomActionLabel: Boolean = false
    ): Int? {
        if (imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0) return null
        if (hasCustomActionLabel && customActionId != 0) return customActionId

        return when (val action = imeOptions and EditorInfo.IME_MASK_ACTION) {
            EditorInfo.IME_ACTION_GO,
            EditorInfo.IME_ACTION_SEARCH,
            EditorInfo.IME_ACTION_SEND,
            EditorInfo.IME_ACTION_NEXT,
            EditorInfo.IME_ACTION_DONE,
            EditorInfo.IME_ACTION_PREVIOUS -> action
            else -> null
        }
    }
}
