package com.sanogueralorenzo.voice.summary

interface LiteRtWarmupClient {
    fun isModelAvailable(): Boolean
    fun summarizeBlocking(text: String): RewriteResult
}
