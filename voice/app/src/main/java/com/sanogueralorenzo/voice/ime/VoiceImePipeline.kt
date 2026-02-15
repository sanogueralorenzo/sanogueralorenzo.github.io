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
            mode = request.mode,
            transcript = transcript,
            editSourceText = request.editSourceText,
            onShowRewriting = onShowRewriting
        )
    }

    fun commit(
        mode: ImeSendMode,
        outputForCommit: String,
        editIntent: String?,
        sessionId: Int,
        packageName: String?,
        isSessionCurrent: (Int, String?) -> Boolean,
        replaceCurrentInputText: (String) -> Boolean,
        enqueuePendingCommit: (String, Int, String?) -> Unit
    ): ImeCommitResult {
        return commitCoordinator.commit(
            mode = mode,
            outputForCommit = outputForCommit,
            editIntent = editIntent,
            sessionId = sessionId,
            packageName = packageName,
            isSessionCurrent = isSessionCurrent,
            replaceCurrentInputText = replaceCurrentInputText,
            enqueuePendingCommit = enqueuePendingCommit
        )
    }
}
