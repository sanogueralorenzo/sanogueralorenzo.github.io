package com.sanogueralorenzo.androidsteam.input

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.hypot

/** Fixed movement/actions with up to four optional, per-game keyboard buttons. */
class TouchControls(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    internal var surface: SteamSurface? = null
    internal var extraKeys: List<TouchKey> = emptyList()
        set(value) { if (field == value) return; release(); field = value; invalidate() }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private val radius get() = 58f * density
    private val stickX get() = 100f * density
    private val stickY get() = height - 100f * density
    private var stickPointer: Int? = null
    private var stickDx = 0f
    private var stickDy = 0f
    private val buttons = mutableMapOf<Int, Int>()
    private val buttonCodes = intArrayOf(1, 57, 28)
    private val buttonLabels = arrayOf("Esc", "Space", "Enter")

    init { contentDescription = "Game keyboard controls" }

    private fun buttonX(index: Int) = width - (if (index < 3) 210f - index * 76f else 58f + (index - 3) * 68f) * density
    private fun buttonY(index: Int) = height - (if (index < 3) 70f else 142f) * density
    private fun code(index: Int) = if (index < 3) buttonCodes[index] else extraKeys[index - 3].code
    private fun label(index: Int) = if (index < 3) buttonLabels[index] else extraKeys[index - 3].label

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        paint.color = 0x60212C38
        canvas.drawCircle(stickX, stickY, radius, paint)
        paint.color = 0xA079D4FF.toInt()
        canvas.drawCircle(stickX + stickDx * radius, stickY + stickDy * radius, 23f * density, paint)
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = 13f * density
        repeat(3 + extraKeys.size) { index ->
            paint.color = if (buttons.containsValue(code(index))) 0xC079D4FF.toInt() else 0xA0212C38.toInt()
            canvas.drawCircle(buttonX(index), buttonY(index), 29f * density, paint)
            paint.color = 0xFFF1F5F9.toInt()
            canvas.drawText(label(index), buttonX(index), buttonY(index) - (paint.ascent() + paint.descent()) / 2, paint)
        }
    }

    internal fun hitTest(x: Float, y: Float): Boolean = hypot(x - stickX, y - stickY) <= radius ||
        (0 until 3 + extraKeys.size).any { hypot(x - buttonX(it), y - buttonY(it)) <= 32f * density }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        fun press(index: Int): Boolean {
            val id = event.getPointerId(index)
            val x = event.getX(index); val y = event.getY(index)
            if (stickPointer == null && hypot(x - stickX, y - stickY) <= radius) {
                stickPointer = id
                move(x, y)
                return true
            }
            repeat(3 + extraKeys.size) { button ->
                if (hypot(x - buttonX(button), y - buttonY(button)) <= 32f * density) {
                    buttons[id] = code(button)
                    surface?.keys?.set("touch:$id", setOf(code(button)))
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
