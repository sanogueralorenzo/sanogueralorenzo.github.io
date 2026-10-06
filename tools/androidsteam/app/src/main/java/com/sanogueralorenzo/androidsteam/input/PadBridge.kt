package com.sanogueralorenzo.androidsteam.input

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import java.io.File
import kotlin.math.abs

/** One session-owned Xbox device. Touch and physical input merge without releasing each other.
 * Android button/axis mapping adapted from DroidDeck 05608ac4d4da33cfebcc0d6783064ec04ac75aee (GPL-3.0).
 */
internal class PadBridge : AutoCloseable {
    private var ring: PadRing? = null
    private val touch = PadState()
    private val devices = mutableMapOf<Int, PadState>()
    private val merged = PadState()

    @Synchronized fun start(directory: File) {
        check(ring == null) { "Controller already belongs to a Steam session." }
        val input = File(directory, "input").apply { check(mkdirs()) { "Cannot prepare controller input." } }
        val rings = File(directory, "input-rings").apply { check(mkdirs()) { "Cannot prepare controller transport." } }
        ring = PadRing(rings)
        check(File(input, "event0").createNewFile()) { "Cannot publish Xbox controller." }
        File(directory, "uinput").createNewFile()
        touch.clear(); devices.clear()
    }

    @Synchronized fun applyTouch(mutation: (PadState) -> Unit) { mutation(touch); publish() }
    @Synchronized fun releaseTouch() { touch.clear(); publish() }
    @Synchronized fun releaseAll() { touch.clear(); devices.clear(); publish() }
    @Synchronized fun removeDevice(id: Int) { devices.remove(id); publish() }
    @Synchronized override fun close() { releaseAll(); ring?.close(); ring = null }

    @Synchronized fun key(event: KeyEvent): Boolean {
        if (!controller(event.device)) return false
        val state = devices.getOrPut(event.deviceId) { PadState() }
        val down = event.action == KeyEvent.ACTION_DOWN
        val button = when (event.keyCode) {
            KeyEvent.KEYCODE_BUTTON_A -> PadState.A
            KeyEvent.KEYCODE_BUTTON_B -> PadState.B
            KeyEvent.KEYCODE_BUTTON_X -> PadState.X
            KeyEvent.KEYCODE_BUTTON_Y -> PadState.Y
            KeyEvent.KEYCODE_BUTTON_L1 -> PadState.LB
            KeyEvent.KEYCODE_BUTTON_R1 -> PadState.RB
            KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BACK -> PadState.SELECT
            KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_MENU -> PadState.START
            KeyEvent.KEYCODE_BUTTON_THUMBL -> PadState.L3
            KeyEvent.KEYCODE_BUTTON_THUMBR -> PadState.R3
            KeyEvent.KEYCODE_BUTTON_MODE, KeyEvent.KEYCODE_HOME -> PadState.GUIDE
            else -> null
        }
        if (button != null) state.press(button, down)
        else when (event.keyCode) {
            KeyEvent.KEYCODE_BUTTON_L2 -> state.leftTrigger = if (down) 1f else 0f
            KeyEvent.KEYCODE_BUTTON_R2 -> state.rightTrigger = if (down) 1f else 0f
            KeyEvent.KEYCODE_DPAD_UP -> state.up = down
            KeyEvent.KEYCODE_DPAD_RIGHT -> state.right = down
            KeyEvent.KEYCODE_DPAD_DOWN -> state.down = down
            KeyEvent.KEYCODE_DPAD_LEFT -> state.left = down
            else -> return false
        }
        publish(); return true
    }

    @Synchronized fun motion(event: MotionEvent): Boolean {
        if (!controller(event.device) || event.actionMasked != MotionEvent.ACTION_MOVE) return false
        val state = devices.getOrPut(event.deviceId) { PadState() }
        fun axis(code: Int): Float {
            val value = event.getAxisValue(code)
            return if (abs(value) > maxOf(.12f, event.device?.getMotionRange(code, event.source)?.flat ?: 0f)) value else 0f
        }
        state.leftX = axis(MotionEvent.AXIS_X); state.leftY = axis(MotionEvent.AXIS_Y)
        state.rightX = axis(MotionEvent.AXIS_Z); state.rightY = axis(MotionEvent.AXIS_RZ)
        state.leftTrigger = maxOf(event.getAxisValue(MotionEvent.AXIS_LTRIGGER), event.getAxisValue(MotionEvent.AXIS_BRAKE))
        state.rightTrigger = maxOf(event.getAxisValue(MotionEvent.AXIS_RTRIGGER), event.getAxisValue(MotionEvent.AXIS_GAS))
        val hx = event.getAxisValue(MotionEvent.AXIS_HAT_X); val hy = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        state.left = hx < -.5f; state.right = hx > .5f; state.up = hy < -.5f; state.down = hy > .5f
        publish(); return true
    }

    private fun publish() {
        merged.copyFrom(touch)
        for (state in devices.values) {
            fun strongest(a: Float, b: Float) = if (abs(b) > abs(a)) b else a
            merged.leftX = strongest(merged.leftX, state.leftX); merged.leftY = strongest(merged.leftY, state.leftY)
            merged.rightX = strongest(merged.rightX, state.rightX); merged.rightY = strongest(merged.rightY, state.rightY)
            merged.leftTrigger = maxOf(merged.leftTrigger, state.leftTrigger); merged.rightTrigger = maxOf(merged.rightTrigger, state.rightTrigger)
            merged.up = merged.up || state.up; merged.right = merged.right || state.right
            merged.down = merged.down || state.down; merged.left = merged.left || state.left
            (0..PadState.GUIDE).forEach { if (state.isDown(it)) merged.press(it, true) }
        }
        ring?.write(merged)
    }

    private fun controller(device: InputDevice?) = device != null && !device.isVirtual &&
        (device.supportsSource(InputDevice.SOURCE_GAMEPAD) || device.supportsSource(InputDevice.SOURCE_JOYSTICK))
}
