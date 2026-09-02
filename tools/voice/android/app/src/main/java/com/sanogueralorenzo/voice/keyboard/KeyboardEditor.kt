package com.sanogueralorenzo.voice.keyboard

import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection
import com.sanogueralorenzo.voice.dictation.DictationSession

/** Applies shared dictation output to an IME InputConnection using composing text. */
internal class KeyboardEditor private constructor(
    private val inputConnection: InputConnection,
    private val sourceText: String,
    private val editorAction: Int?,
    private val prefix: String
) {
    var submitAfterFinish: Boolean = false

    fun update(text: String) {
        val composingText = if (text.isBlank()) "" else prefix + text
        runCatching { inputConnection.setComposingText(composingText, 1) }
    }

    fun complete(result: DictationSession.Result) {
        val command = result.command
        when {
            command != null -> {
                clear()
                replaceAll(command.applyTo(sourceText))
            }
            result.hasTranscript -> {
                update(result.text)
                runCatching { inputConnection.finishComposingText() }
            }
            else -> clear()
        }
        if (command == null && result.hasTranscript && submitAfterFinish) {
            editorAction?.let { action ->
                runCatching { inputConnection.performEditorAction(action) }
            }
        }
    }

    fun clear() {
        runCatching {
            inputConnection.setComposingText("", 1)
            inputConnection.finishComposingText()
        }
    }

    private fun replaceAll(text: String) {
        runCatching {
            inputConnection.beginBatchEdit()
            try {
                inputConnection.finishComposingText()
                inputConnection.setSelection(0, sourceText.length)
                inputConnection.commitText(text, 1)
            } finally {
                inputConnection.endBatchEdit()
            }
        }
    }

    companion object {
        fun create(inputConnection: InputConnection, editorInfo: EditorInfo?): KeyboardEditor {
            val beforeCursor = runCatching {
                inputConnection.getTextBeforeCursor(1, 0)?.toString().orEmpty()
            }.getOrDefault("")
            return KeyboardEditor(
                inputConnection = inputConnection,
                sourceText = readEditorText(inputConnection),
                editorAction = KeyboardEditorAction.resolve(editorInfo),
                prefix = if (
                    beforeCursor.isNotEmpty() && !beforeCursor.last().isWhitespace()
                ) " " else ""
            )
        }

        private fun readEditorText(connection: InputConnection): String {
            val extracted = runCatching {
                connection.getExtractedText(ExtractedTextRequest(), 0)?.text?.toString()
            }.getOrNull()
            if (extracted != null) return extracted
            val before = runCatching {
                connection.getTextBeforeCursor(MAX_EDITOR_TEXT_CHARS, 0)?.toString().orEmpty()
            }.getOrDefault("")
            val after = runCatching {
                connection.getTextAfterCursor(MAX_EDITOR_TEXT_CHARS, 0)?.toString().orEmpty()
            }.getOrDefault("")
            return before + after
        }

        private const val MAX_EDITOR_TEXT_CHARS = 100_000
    }
}
