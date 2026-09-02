package com.sanogueralorenzo.voice.dictation

import com.sanogueralorenzo.voice.dictation.DictationLanguage

/** Minimal speech-to-text boundary used by the shared dictation lifecycle. */
internal interface DictationTranscriber {
    data class Callbacks(
        val onText: (String) -> Unit,
        val onLine: (id: Long, text: String) -> Unit,
        val onError: (Throwable) -> Unit,
        val onAudioLevel: ((Float) -> Unit)? = null
    )

    fun warmup(language: DictationLanguage): Boolean
    fun isReady(language: DictationLanguage): Boolean
    fun start(language: DictationLanguage, callbacks: Callbacks): Boolean
    fun stop()
    fun detachCallbacks()
    fun close()
}
