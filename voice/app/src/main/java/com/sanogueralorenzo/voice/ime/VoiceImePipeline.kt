package com.sanogueralorenzo.voice.ime

internal class VoiceImePipeline(
    private val speechProcessor: SpeechProcessor,
    private val commitCoordinator: ImeCommitCoordinator
) {
    fun processSpeech(
        request: ImePipelineRequest,
        awaitChunkSessionQuiescence: (Int) -> Unit,
        finalizeMoonshineTranscript: (Int) -> String,
        onShowRewriting: () -> Unit
    ): ImePipelineResult {
        return speechProcessor.process(
            request = request,
            awaitChunkSessionQuiescence = awaitChunkSessionQuiescence,
            finalizeMoonshineTranscript = finalizeMoonshineTranscript,
            onShowRewriting = onShowRewriting
        )
    }

    fun commit(
        operation: ImeOperation,
        outputForCommit: String,
        editIntent: String?,
        sessionId: Int,
        packageName: String?,
        isSessionCurrent: (Int, String?) -> Boolean,
        replaceCurrentInputText: (String) -> Boolean
    ): ImeCommitResult {
        return commitCoordinator.commit(
            operation = operation,
            outputForCommit = outputForCommit,
            editIntent = editIntent,
            sessionId = sessionId,
            packageName = packageName,
            isSessionCurrent = isSessionCurrent,
            replaceCurrentInputText = replaceCurrentInputText
        )
    }
}
