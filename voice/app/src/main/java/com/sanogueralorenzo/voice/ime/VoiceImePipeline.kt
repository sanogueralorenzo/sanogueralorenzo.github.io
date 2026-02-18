package com.sanogueralorenzo.voice.ime

internal class VoiceImePipeline(
    private val transcriptionCoordinator: ImeTranscriptionCoordinator,
    private val rewriteCoordinator: ImeRewriteCoordinator,
    private val commitCoordinator: ImeCommitCoordinator
) {
    fun transcribe(
        request: ImePipelineRequest,
        awaitChunkSessionQuiescence: (Int) -> Unit,
        finalizeMoonshineTranscript: (Int) -> String
    ): ImeTranscriptionResult {
        return transcriptionCoordinator.transcribe(
            request = request,
            awaitChunkSessionQuiescence = awaitChunkSessionQuiescence,
            finalizeMoonshineTranscript = finalizeMoonshineTranscript
        )
    }

    fun rewrite(
        request: ImePipelineRequest,
        transcript: String,
        onShowRewriting: () -> Unit
    ): ImeRewriteResult {
        return rewriteCoordinator.rewrite(
            sourceText = request.sourceTextSnapshot,
            transcript = transcript,
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
