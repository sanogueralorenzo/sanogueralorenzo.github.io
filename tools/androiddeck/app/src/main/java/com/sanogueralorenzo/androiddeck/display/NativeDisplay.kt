package com.sanogueralorenzo.androiddeck.display

import android.view.Surface

internal object NativeDisplay {
    init { System.loadLibrary("deck-display") }
    external fun start(socket: String, surface: Surface, refresh: Int)
    external fun startVulkan(socket: String, surface: Surface, refresh: Int, driver: String, libraries: String)
    external fun attach(surface: Surface?)
    external fun stop()
    external fun snapshot(): LongArray
}
