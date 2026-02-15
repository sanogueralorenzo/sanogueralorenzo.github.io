package com.sanogueralorenzo.voice.ime

import com.sanogueralorenzo.voice.summary.LiteRtEditHeuristics

internal class ImeCommitCoordinator {
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
        if (!isSessionCurrent(sessionId, packageName)) {
            return ImeCommitResult(
                committed = false,
                sessionMismatch = true
            )
        }

        val shouldPreserveBlankEdit = mode == ImeSendMode.EDIT_EXISTING &&
            outputForCommit.isBlank() &&
            editIntent != LiteRtEditHeuristics.EditIntent.DELETE_ALL.name

        val committed = if (outputForCommit.isBlank()) {
            if (mode == ImeSendMode.EDIT_EXISTING) {
                if (shouldPreserveBlankEdit) {
                    true
                } else {
                    replaceCurrentInputText("")
                }
            } else {
                false
            }
        } else if (mode == ImeSendMode.EDIT_EXISTING) {
            replaceCurrentInputText(outputForCommit)
        } else {
            enqueuePendingCommit(outputForCommit, sessionId, packageName)
            true
        }

        return ImeCommitResult(
            committed = committed,
            sessionMismatch = false
        )
    }
}
