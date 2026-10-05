package com.sanogueralorenzo.androidsteam

import android.app.Application
import com.sanogueralorenzo.androidsteam.runtime.RuntimeController
import com.sanogueralorenzo.androidsteam.session.SessionController
import com.sanogueralorenzo.androidsteam.library.LibraryController
import com.sanogueralorenzo.androidsteam.library.LibraryArtwork

class SteamApplication : Application() {
    internal val runtime by lazy { RuntimeController(this) }
    internal val session by lazy { SessionController(this) }
    internal val library by lazy { LibraryController(this) }
    internal val artwork by lazy { LibraryArtwork(this) }
}
