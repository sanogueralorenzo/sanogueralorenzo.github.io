package com.sanogueralorenzo.androidsteam.input

import android.content.Context
import android.graphics.Rect
import android.util.AttributeSet
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceView
import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import com.sanogueralorenzo.androidsteam.R

class SteamSurface(context: Context, attrs: AttributeSet? = null) : SurfaceView(context, attrs) {
    private val fitSteamAspect = context.obtainStyledAttributes(attrs, R.styleable.SteamSurface).let { values ->
        try { values.getBoolean(R.styleable.SteamSurface_fitSteamAspect, false) } finally { values.recycle() }
    }
    internal var pad: PadBridge? = null
    private val releaseBack = Runnable { keys.set("back", emptySet()) }
    internal val keys = InputKeys(NativeDisplay::key)
    internal var profile: ControlProfile = ControlProfile.TOUCH
        set(value) { if (field != value) releaseInput(); field = value }
    init { isFocusable = true; isFocusableInTouchMode = true }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if (fitSteamAspect) {
            // The session's fixed 1280×720 buffer must keep its proportions on wide phones.
            val contentWidth = minOf(measuredWidth, measuredHeight * 16 / 9)
            setMeasuredDimension(contentWidth, contentWidth * 9 / 16)
        }
    }

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
        if (pad?.motion(event) == true) return true
        return super.onGenericMotionEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (pad?.key(event) == true) return true
        val code = SteamKeys.code(event) ?: return super.onKeyDown(keyCode, event)
        if (event.repeatCount == 0) keys.set("key:${event.deviceId}:$keyCode", setOf(code))
        return true
    }
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (pad?.key(event) == true) return true
        val code = SteamKeys.code(event) ?: return super.onKeyUp(keyCode, event)
        keys.set("key:${event.deviceId}:$keyCode", emptySet())
        return true
    }
    fun backKey(code: Int = 1) { removeCallbacks(releaseBack); keys.set("back", setOf(code)); postDelayed(releaseBack, 150) }
    internal fun releaseInput() { removeCallbacks(releaseBack); keys.clear(); pad?.releaseAll(); NativeDisplay.releaseInput() }
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
