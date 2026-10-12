package com.sanogueralorenzo.amarchy.desktop

import android.content.Context
import android.graphics.Rect
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.text.InputType
import com.sanogueralorenzo.amarchy.display.NativeDisplay
import com.sanogueralorenzo.amarchy.session.WorkspaceController

/** Touch acts as a mouse; Android's IME commits Unicode through the Linux keyboard. */
internal class DesktopSurface(context: Context, private val workspace: WorkspaceController) : SurfaceView(context) {
    private val held = mutableSetOf<Int>()
    private var scrolling = false
    private var lastY = 0f
    init {
        isFocusable = true; isFocusableInTouchMode = true
        contentDescription = "Omarchy desktop"
        holder.setFixedSize(1280, 720)
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        val fittedWidth = minOf(width, height * 16 / 9)
        setMeasuredDimension(fittedWidth, fittedWidth * 9 / 16)
    }
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_MOUSE)) return mouse(event)
        if (width == 0 || height == 0) return false
        requestFocus()
        val x = (event.x / width).coerceIn(0f, 1f)
        val y = (event.y / height).coerceIn(0f, 1f)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { scrolling = false; lastY = event.y; NativeDisplay.pointer(x, y, 272, true) }
            MotionEvent.ACTION_POINTER_DOWN -> { scrolling = true; NativeDisplay.pointer(x, y, 272, false); lastY = event.y }
            MotionEvent.ACTION_MOVE -> if (scrolling) {
                NativeDisplay.scroll(0f, (lastY - event.y) / (32 * resources.displayMetrics.density)); lastY = event.y
            } else NativeDisplay.pointer(x, y, 0, false)
            MotionEvent.ACTION_UP -> { NativeDisplay.pointer(x, y, 272, false); performClick() }
            MotionEvent.ACTION_CANCEL -> release()
        }
        return true
    }
    override fun performClick(): Boolean { super.performClick(); return true }
    private fun mouse(event: MotionEvent): Boolean {
        if (width == 0 || height == 0) return false
        val button = when (event.actionButton) { MotionEvent.BUTTON_PRIMARY -> 272; MotionEvent.BUTTON_SECONDARY -> 273; MotionEvent.BUTTON_TERTIARY -> 274; else -> 0 }
        when (event.actionMasked) {
            MotionEvent.ACTION_SCROLL -> NativeDisplay.scroll(-event.getAxisValue(MotionEvent.AXIS_HSCROLL), -event.getAxisValue(MotionEvent.AXIS_VSCROLL))
            MotionEvent.ACTION_BUTTON_PRESS, MotionEvent.ACTION_BUTTON_RELEASE -> NativeDisplay.pointer(event.x / width, event.y / height, button, event.actionMasked == MotionEvent.ACTION_BUTTON_PRESS)
            else -> NativeDisplay.pointer((event.x / width).coerceIn(0f, 1f), (event.y / height).coerceIn(0f, 1f), 0, false)
        }
        return true
    }
    override fun onGenericMotionEvent(event: MotionEvent): Boolean = if (event.isFromSource(InputDevice.SOURCE_MOUSE)) mouse(event) else super.onGenericMotionEvent(event)
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val code = DesktopKeys.code(event) ?: return super.onKeyDown(keyCode, event)
        if (event.repeatCount == 0) { held += code; NativeDisplay.key(code, true) }
        return true
    }
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        val code = DesktopKeys.code(event) ?: return super.onKeyUp(keyCode, event)
        held -= code; NativeDisplay.key(code, false); return true
    }
    override fun onCheckIsTextEditor() = true
    override fun onCreateInputConnection(attributes: EditorInfo): InputConnection {
        attributes.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        attributes.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_ACTION_NONE
        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean { workspace.type(text?.toString().orEmpty()); return true }
            override fun setComposingText(text: CharSequence?, newCursorPosition: Int) = true
            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                repeat(beforeLength.coerceAtMost(100)) { workspace.shortcut(14) }; repeat(afterLength.coerceAtMost(100)) { workspace.shortcut(111) }; return true
            }
            override fun sendKeyEvent(event: KeyEvent): Boolean = dispatchKeyEvent(event)
            override fun performEditorAction(actionCode: Int): Boolean { workspace.shortcut(28); return true }
        }
    }
    private fun release() { held.clear(); NativeDisplay.releaseInput() }
    override fun onWindowFocusChanged(hasWindowFocus: Boolean) { super.onWindowFocusChanged(hasWindowFocus); if (!hasWindowFocus) release() }
    override fun onFocusChanged(gainFocus: Boolean, direction: Int, previouslyFocusedRect: Rect?) { super.onFocusChanged(gainFocus, direction, previouslyFocusedRect); if (!gainFocus) release() }
    override fun onDetachedFromWindow() { release(); super.onDetachedFromWindow() }
}
