package com.sanogueralorenzo.androidsteam

import android.app.Application
import com.sanogueralorenzo.androidsteam.setup.SetupController
import com.sanogueralorenzo.androidsteam.setup.SetupInstaller
import com.sanogueralorenzo.androidsteam.session.SessionController
import com.sanogueralorenzo.androidsteam.library.LibraryController
import com.sanogueralorenzo.androidsteam.library.LibraryArtwork

open class SteamApplication : Application() {
    internal val preparation by lazy { SetupInstaller(this) }
    internal val setup by lazy { SetupController(this, preparation) }
    private val defaultSession by lazy { SessionController(this) }
    internal open val session get() = defaultSession
    internal val library by lazy { LibraryController(this) }
    internal val artwork by lazy { LibraryArtwork(this) }
}
