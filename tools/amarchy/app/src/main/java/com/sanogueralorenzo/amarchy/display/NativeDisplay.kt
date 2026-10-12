package com.sanogueralorenzo.amarchy.display

import android.view.Surface

internal object NativeDisplay {
    init { System.loadLibrary("amarchy-display") }
    external fun start(socket: String, surface: Surface, refresh: Int)
    external fun attach(surface: Surface?)
    external fun pointer(x: Float, y: Float, button: Int, pressed: Boolean)
    external fun scroll(x: Float, y: Float)
    external fun touch(id: Int, action: Int, x: Float, y: Float)
    external fun key(code: Int, pressed: Boolean)
    external fun releaseInput()
    external fun stop()
    external fun snapshot(): LongArray
}
