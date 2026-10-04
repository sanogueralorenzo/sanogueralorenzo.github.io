package com.sanogueralorenzo.androidsteam

import android.app.Application
import com.sanogueralorenzo.androidsteam.runtime.RuntimeController
import com.sanogueralorenzo.androidsteam.session.SessionController

class SteamApplication : Application() {
    internal val runtime by lazy { RuntimeController(this) }
    internal val session by lazy { SessionController(this) }
}
