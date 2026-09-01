package com.sanogueralorenzo.voice.keyboard

import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class KeyboardEditorActionTest {
    @Test
    fun returnsExplicitStandardAction() {
        assertEquals(
            EditorInfo.IME_ACTION_SEND,
            KeyboardEditorAction.resolve(EditorInfo.IME_ACTION_SEND)
        )
        assertEquals(
            EditorInfo.IME_ACTION_GO,
            KeyboardEditorAction.resolve(EditorInfo.IME_ACTION_GO)
        )
    }

    @Test
    fun doesNotTurnPlainEnterIntoSend() {
        assertNull(KeyboardEditorAction.resolve(EditorInfo.IME_ACTION_NONE))
        assertNull(KeyboardEditorAction.resolve(EditorInfo.IME_ACTION_UNSPECIFIED))
    }

    @Test
    fun honorsNoEnterActionFlag() {
        assertNull(
            KeyboardEditorAction.resolve(
                EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_ENTER_ACTION
            )
        )
    }

    @Test
    fun returnsCustomEditorAction() {
        assertEquals(
            42,
            KeyboardEditorAction.resolve(
                imeOptions = EditorInfo.IME_ACTION_UNSPECIFIED,
                customActionId = 42,
                hasCustomActionLabel = true
            )
        )
    }
}
