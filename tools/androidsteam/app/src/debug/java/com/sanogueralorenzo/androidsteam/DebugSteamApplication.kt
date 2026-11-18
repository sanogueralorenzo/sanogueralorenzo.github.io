package com.sanogueralorenzo.androidsteam

import android.content.Context
import com.sanogueralorenzo.androidsteam.session.SessionController

/** The private login proof still shares one owner with the activity and foreground service. */
class DebugSteamApplication : SteamApplication() {
    private var proofSession: SessionController? = null
    internal override val session get() = proofSession ?: super.session

    internal fun openProof(context: Context) {
        check(proofSession == null && super.session.state == SessionController.State.Idle)
        proofSession = SessionController(context)
    }

    internal fun closeProof() {
        check(session.state == SessionController.State.Idle)
        proofSession = null
    }
}
