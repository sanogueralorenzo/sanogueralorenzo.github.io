package com.sanogueralorenzo.androidsteam.input

import android.content.Context
import android.util.AttributeSet
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import com.sanogueralorenzo.androidsteam.R

/** Own each pointer from down to up, so direct touch also works after a control starts first. */
class InputOverlay(context: Context, attrs: AttributeSet? = null) : FrameLayout(context, attrs) {
    private val surface get() = findViewById<SteamSurface>(R.id.surface)
    private val keyboard get() = findViewById<TouchControls>(R.id.keyboard_controls)
    private val xbox get() = findViewById<OnScreenControls>(R.id.xbox_controls)
    private val owners = mutableMapOf<Int, View>()
    internal var extraKeys: List<TouchKey>
        get() = keyboard.extraKeys
        set(value) { keyboard.extraKeys = value }

    internal fun configure(profile: ControlProfile, pad: PadBridge) {
        release()
        keyboard.surface = surface
        surface.pad = pad
        xbox.pad = pad
        xbox.visibility = if (profile == ControlProfile.XBOX) VISIBLE else GONE
        keyboard.visibility = if (profile == ControlProfile.ARROWS || profile == ControlProfile.WASD) VISIBLE else GONE
        surface.requestFocus()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_MOUSE)) {
            route(event, surface, (0 until event.pointerCount).toList())
            return true
        }
        if (event.actionMasked == MotionEvent.ACTION_DOWN) release()
        if (event.actionMasked == MotionEvent.ACTION_DOWN || event.actionMasked == MotionEvent.ACTION_POINTER_DOWN) {
            val i = event.actionIndex
            val x = event.getX(i); val y = event.getY(i)
            owners[event.getPointerId(i)] = when {
                xbox.visibility == VISIBLE && xbox.hitTest(x, y) -> xbox
                keyboard.visibility == VISIBLE && keyboard.hitTest(x, y) -> keyboard
                else -> surface
            }
        }
        owners.values.toSet().forEach { target ->
            val indices = (0 until event.pointerCount).filter { owners[event.getPointerId(it)] === target }
            if (indices.isNotEmpty()) route(event, target, indices)
        }
        if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_POINTER_UP)
            owners.remove(event.getPointerId(event.actionIndex))
        if (event.actionMasked == MotionEvent.ACTION_CANCEL) release()
        return true
    }

    private fun route(event: MotionEvent, target: View, indices: List<Int>) {
        val changed = indices.indexOf(event.actionIndex)
        val action = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> when {
                changed < 0 -> MotionEvent.ACTION_MOVE
                indices.size == 1 -> MotionEvent.ACTION_DOWN
                else -> MotionEvent.ACTION_POINTER_DOWN or (changed shl MotionEvent.ACTION_POINTER_INDEX_SHIFT)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> when {
                changed < 0 -> MotionEvent.ACTION_MOVE
                indices.size == 1 -> MotionEvent.ACTION_UP
                else -> MotionEvent.ACTION_POINTER_UP or (changed shl MotionEvent.ACTION_POINTER_INDEX_SHIFT)
            }
            else -> event.actionMasked
        }
        val properties = indices.map { i -> MotionEvent.PointerProperties().also { event.getPointerProperties(i, it) } }.toTypedArray()
        val coordinates = indices.map { i -> MotionEvent.PointerCoords().also { event.getPointerCoords(i, it) } }.toTypedArray()
        val split = MotionEvent.obtain(event.downTime, event.eventTime, action, indices.size, properties, coordinates,
            event.metaState, event.buttonState, event.xPrecision, event.yPrecision, event.deviceId, event.edgeFlags, event.source, event.flags)
        split.offsetLocation(-target.left.toFloat(), -target.top.toFloat())
        try { target.onTouchEvent(split) } finally { split.recycle() }
    }

    internal fun release() {
        owners.clear(); keyboard.release(); xbox.releaseAll(); xbox.pad?.releaseTouch()
    }
    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        if (!hasWindowFocus) release()
        super.onWindowFocusChanged(hasWindowFocus)
    }
    override fun onDetachedFromWindow() { release(); super.onDetachedFromWindow() }
}
