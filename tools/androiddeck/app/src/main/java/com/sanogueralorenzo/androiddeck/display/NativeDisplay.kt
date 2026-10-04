package com.sanogueralorenzo.androiddeck.display

import android.view.Surface

internal object NativeDisplay {
    init { System.loadLibrary("deck-display") }
    external fun start(socket: String, surface: Surface, refresh: Int)
    external fun attach(surface: Surface?)
    external fun stop()
    external fun snapshot(): LongArray
}
