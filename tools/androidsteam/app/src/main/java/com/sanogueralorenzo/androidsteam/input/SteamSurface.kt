package com.sanogueralorenzo.androidsteam.input

import android.content.Context
import android.graphics.Rect
import android.util.AttributeSet
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceView
import com.sanogueralorenzo.androidsteam.display.NativeDisplay

class SteamSurface(context: Context, attrs: AttributeSet? = null) : SurfaceView(context, attrs) {
    internal val keys = InputKeys(NativeDisplay::key)
    internal var profile: ControlProfile = ControlProfile.TOUCH
        set(value) { if (field != value) releaseInput(); field = value }
    init { isFocusable = true; isFocusableInTouchMode = true }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (width == 0 || height == 0) return false
        requestFocus()
        if (event.isFromSource(InputDevice.SOURCE_MOUSE)) return pointer(event)
        fun send(index: Int, action: Int) = NativeDisplay.touch(event.getPointerId(index), action,
            (event.getX(index) / width).coerceIn(0f, 1f), (event.getY(index) / height).coerceIn(0f, 1f))
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> send(event.actionIndex, 0)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> send(event.actionIndex, 1)
            MotionEvent.ACTION_MOVE -> repeat(event.pointerCount) { send(it, 2) }
            MotionEvent.ACTION_CANCEL -> releaseInput()
            else -> return false
        }
        if (event.actionMasked == MotionEvent.ACTION_UP) performClick()
        return true
    }
    override fun performClick(): Boolean { super.performClick(); return true }
    private fun pointer(event: MotionEvent): Boolean {
        if (width == 0 || height == 0) return false
        val button = when (event.actionButton) {
            MotionEvent.BUTTON_PRIMARY -> 272
            MotionEvent.BUTTON_SECONDARY -> 273
            MotionEvent.BUTTON_TERTIARY -> 274
            else -> 0
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_SCROLL -> NativeDisplay.scroll(-event.getAxisValue(MotionEvent.AXIS_HSCROLL), -event.getAxisValue(MotionEvent.AXIS_VSCROLL))
            MotionEvent.ACTION_BUTTON_PRESS, MotionEvent.ACTION_BUTTON_RELEASE -> NativeDisplay.pointer(
                (event.x / width).coerceIn(0f, 1f), (event.y / height).coerceIn(0f, 1f), button,
                event.actionMasked == MotionEvent.ACTION_BUTTON_PRESS)
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP, MotionEvent.ACTION_MOVE, MotionEvent.ACTION_HOVER_MOVE, MotionEvent.ACTION_HOVER_ENTER -> NativeDisplay.pointer(
                (event.x / width).coerceIn(0f, 1f), (event.y / height).coerceIn(0f, 1f), 0, false)
            MotionEvent.ACTION_CANCEL -> releaseInput()
            else -> return false
        }
        return true
    }
    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_MOUSE)) return pointer(event)
        if (event.isFromSource(InputDevice.SOURCE_JOYSTICK) && event.actionMasked == MotionEvent.ACTION_MOVE) {
            fun axis(stick: Int, hat: Int): Float {
                val dpad = event.getAxisValue(hat)
                if (kotlin.math.abs(dpad) > .5f) return dpad
                val value = event.getAxisValue(stick)
                val flat = event.device?.getMotionRange(stick, event.source)?.flat ?: .1f
                return if (kotlin.math.abs(value) > flat) value else 0f
            }
            keys.set("pad:${event.deviceId}:axes", profile.movement(axis(MotionEvent.AXIS_X, MotionEvent.AXIS_HAT_X), axis(MotionEvent.AXIS_Y, MotionEvent.AXIS_HAT_Y)))
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_GAMEPAD) || event.isFromSource(InputDevice.SOURCE_DPAD)) {
            val movement = when (keyCode) {
                KeyEvent.KEYCODE_DPAD_LEFT -> profile.movement(-1f, 0f)
                KeyEvent.KEYCODE_DPAD_RIGHT -> profile.movement(1f, 0f)
                KeyEvent.KEYCODE_DPAD_UP -> profile.movement(0f, -1f)
                KeyEvent.KEYCODE_DPAD_DOWN -> profile.movement(0f, 1f)
                else -> null
            }
            if (movement != null) {
                if (event.repeatCount == 0) keys.set("key:${event.deviceId}:$keyCode", movement)
                return true
            }
        }
        val code = SteamKeys.code(event) ?: return super.onKeyDown(keyCode, event)
        if (event.repeatCount == 0) keys.set("key:${event.deviceId}:$keyCode", setOf(code))
        return true
    }
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        val code = SteamKeys.code(event) ?: return super.onKeyUp(keyCode, event)
        keys.set("key:${event.deviceId}:$keyCode", emptySet())
        return true
    }
    fun backKey(code: Int = 1) { keys.set("back", setOf(code)); keys.set("back", emptySet()) }
    internal fun releaseInput() { keys.clear(); NativeDisplay.releaseInput() }
    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) releaseInput()
    }
    override fun onFocusChanged(gainFocus: Boolean, direction: Int, previouslyFocusedRect: Rect?) {
        super.onFocusChanged(gainFocus, direction, previouslyFocusedRect)
        if (!gainFocus) releaseInput()
    }
    override fun onDetachedFromWindow() { releaseInput(); super.onDetachedFromWindow() }
}
