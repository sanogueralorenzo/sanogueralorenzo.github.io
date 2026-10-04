package com.sanogueralorenzo.androidsteam.input

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.hypot

/** One fixed layout with a digital movement stick and three keyboard actions. */
class TouchControls(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    internal var surface: SteamSurface? = null
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private val radius get() = 58f * density
    private val stickX get() = 100f * density
    private val stickY get() = height - 100f * density
    private val buttonY get() = height - 70f * density
    private var stickPointer: Int? = null
    private var stickDx = 0f
    private var stickDy = 0f
    private val buttons = mutableMapOf<Int, Int>()
    private val buttonCodes = intArrayOf(1, 57, 28)
    private val buttonLabels = arrayOf("Esc", "Space", "Enter")

    init { contentDescription = "Game keyboard controls" }

    private fun buttonX(index: Int) = width - (210f - index * 76f) * density

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        paint.color = 0x60212C38
        canvas.drawCircle(stickX, stickY, radius, paint)
        paint.color = 0xA079D4FF.toInt()
        canvas.drawCircle(stickX + stickDx * radius, stickY + stickDy * radius, 23f * density, paint)
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = 13f * density
        repeat(3) { index ->
            paint.color = if (buttons.containsValue(buttonCodes[index])) 0xC079D4FF.toInt() else 0xA0212C38.toInt()
            canvas.drawCircle(buttonX(index), buttonY, 29f * density, paint)
            paint.color = 0xFFF1F5F9.toInt()
            canvas.drawText(buttonLabels[index], buttonX(index), buttonY - (paint.ascent() + paint.descent()) / 2, paint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        fun press(index: Int): Boolean {
            val id = event.getPointerId(index)
            val x = event.getX(index); val y = event.getY(index)
            if (stickPointer == null && hypot(x - stickX, y - stickY) <= radius) {
                stickPointer = id
                move(x, y)
                return true
            }
            repeat(3) { button ->
                if (hypot(x - buttonX(button), y - buttonY) <= 32f * density) {
                    buttons[id] = buttonCodes[button]
                    surface?.keys?.set("touch:$id", setOf(buttonCodes[button]))
                    return true
                }
            }
            return false
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> if (!press(event.actionIndex)) return false
            MotionEvent.ACTION_POINTER_DOWN -> press(event.actionIndex)
            MotionEvent.ACTION_MOVE -> stickPointer?.let { id ->
                event.findPointerIndex(id).takeIf { it >= 0 }?.let { move(event.getX(it), event.getY(it)) }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val id = event.getPointerId(event.actionIndex)
                if (stickPointer == id) {
                    stickPointer = null; stickDx = 0f; stickDy = 0f
                    surface?.keys?.set("touch:stick", emptySet())
                }
                buttons.remove(id)
                surface?.keys?.set("touch:$id", emptySet())
                if (event.actionMasked == MotionEvent.ACTION_UP) performClick()
            }
            MotionEvent.ACTION_CANCEL -> release()
            else -> return false
        }
        invalidate()
        return true
    }

    private fun move(x: Float, y: Float) {
        val dx = (x - stickX) / radius; val dy = (y - stickY) / radius
        val length = maxOf(1f, hypot(dx, dy))
        stickDx = dx / length; stickDy = dy / length
        surface?.let { it.keys.set("touch:stick", it.profile.movement(stickDx, stickDy)) }
    }

    internal fun release() {
        surface?.keys?.set("touch:stick", emptySet())
        buttons.keys.forEach { surface?.keys?.set("touch:$it", emptySet()) }
        buttons.clear(); stickPointer = null; stickDx = 0f; stickDy = 0f
        invalidate()
    }

    override fun performClick(): Boolean { super.performClick(); return true }
    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        if (!hasWindowFocus) release()
        super.onWindowFocusChanged(hasWindowFocus)
    }
    override fun onDetachedFromWindow() { release(); super.onDetachedFromWindow() }
}
