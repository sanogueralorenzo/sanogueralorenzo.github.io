package com.sanogueralorenzo.androiddeck

import android.app.Application
import com.sanogueralorenzo.androiddeck.runtime.RuntimeController
import com.sanogueralorenzo.androiddeck.session.SessionController

class DeckApplication : Application() {
    internal val runtime by lazy { RuntimeController(this) }
    internal val session by lazy { SessionController(this) }
}
