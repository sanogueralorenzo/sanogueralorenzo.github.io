package com.sanogueralorenzo.voice.ime

import com.sanogueralorenzo.voice.summary.EditInstructionRules

internal class ImeCommitCoordinator {
    fun commit(
        operation: ImeOperation,
        outputForCommit: String,
        editIntent: String?,
        sessionId: Int,
        packageName: String?,
        isSessionCurrent: (Int, String?) -> Boolean,
        replaceCurrentInputText: (String) -> Boolean
    ): ImeCommitResult {
        if (!isSessionCurrent(sessionId, packageName)) {
            return ImeCommitResult(
                committed = false,
                sessionMismatch = true
            )
        }

        val shouldPreserveBlankEdit = operation == ImeOperation.EDIT &&
            outputForCommit.isBlank() &&
            editIntent != EditInstructionRules.EditIntent.DELETE_ALL.name

        val committed = when {
            outputForCommit.isBlank() && operation == ImeOperation.APPEND -> false
            outputForCommit.isBlank() && shouldPreserveBlankEdit -> true
            else -> replaceCurrentInputText(outputForCommit)
        }

        return ImeCommitResult(
            committed = committed,
            sessionMismatch = false
        )
    }
}
