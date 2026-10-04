package com.sanogueralorenzo.androiddeck

import android.app.Application
import com.sanogueralorenzo.androiddeck.runtime.RuntimeController

class DeckApplication : Application() {
    internal val runtime by lazy { RuntimeController(this) }
}
