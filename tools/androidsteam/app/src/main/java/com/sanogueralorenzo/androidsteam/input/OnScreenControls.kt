// Input handling adapted from DroidDeck 05608ac4d4da33cfebcc0d6783064ec04ac75aee (GPL-3.0).
// Compact layout and visual design by Android Steam contributors.
package com.sanogueralorenzo.androidsteam.input

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import android.util.AttributeSet
import android.view.WindowInsets
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/** Compact edge controls with faint buttons and sticks visible only during touch. */
class OnScreenControls(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    internal var pad: PadBridge? = null

    private class Control(
        val id: String,
        val group: String,
        val stick: Int,
        val radiusDp: Float,
        val offsetXDp: Float,
        val offsetYDp: Float,
    ) {
        var target = id
        var radius = 0f
        var hitRadius = 0f
        var cx = 0f
        var cy = 0f
        var pressedBy = -1
        var kx = 0f
        var ky = 0f
        var ax = 0f
        var ay = 0f
        var clicked = false
        var lastUp = 0L
        val wide = id in shoulderIds
        val halfW get() = if (wide) radius * SHOULDER_WIDTH else radius
        val halfH get() = if (wide) radius * SHOULDER_HEIGHT else radius

        fun contains(x: Float, y: Float, padding: Float = 0f): Boolean {
            val dx = x - cx
            val dy = y - cy
            if (wide) return abs(dx) <= max(halfW, hitRadius) + padding &&
                abs(dy) <= max(halfH, hitRadius) + padding
            val hit = hitRadius + padding
            return dx * dx + dy * dy <= hit * hit
        }

        fun drag(x: Float, y: Float) {
            var dx = x - ax
            var dy = y - ay
            val d = sqrt(dx * dx + dy * dy)
            if (d > radius) { dx = dx / d * radius; dy = dy / d * radius }
            kx = dx; ky = dy
        }
    }

    private val controls = listOf(
        Control("up", "dpad", -1, 14f, 0f, -32f),
        Control("right", "dpad", -1, 14f, 32f, 0f),
        Control("down", "dpad", -1, 14f, 0f, 32f),
        Control("left", "dpad", -1, 14f, -32f, 0f),
        Control("ls", "ls", 0, 30f, 0f, 0f),
        Control("rs", "rs", 1, 30f, 0f, 0f),
        Control("a", "face", -1, 18f, 0f, 34f),
        Control("b", "face", -1, 18f, 34f, 0f),
        Control("x", "face", -1, 18f, -34f, 0f),
        Control("y", "face", -1, 18f, 0f, -34f),
        Control("lb", "lb", -1, 18f, 0f, 0f),
        Control("rb", "rb", -1, 18f, 0f, 0f),
        Control("lt", "lt", -1, 18f, 0f, 0f),
        Control("rt", "rt", -1, 18f, 0f, 0f),
        Control("select", "select", -1, 14f, 0f, 0f),
        Control("start", "start", -1, 14f, 0f, 0f),
        Control("guide", "guide", -1, 14f, 0f, 0f),
    )

    private var safe = Rect()
    private var fit = 1f

    private val idleFill = Color.argb(8, 0, 0, 0)
    private val heldFill = Color.argb(44, 255, 255, 255)
    private val idleStroke = Color.argb(30, 255, 255, 255)
    private val heldStroke = Color.argb(160, 190, 225, 255)
    private val idleText = Color.argb(54, 255, 255, 255)
    private val heldText = Color.argb(230, 255, 255, 255)
    private val stickFill = Color.argb(8, 255, 255, 255)
    private val knobFill = Color.argb(70, 255, 255, 255)

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val arrow = Path()
    private val box = RectF()
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
    }

    private fun dp(value: Float) = value * resources.displayMetrics.density
    private fun scaled(value: Float) = dp(value) * fit

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        relayout()
    }

    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        val cutout = insets.displayCutout
        val fresh = Rect(cutout?.safeInsetLeft ?: 0, cutout?.safeInsetTop ?: 0, cutout?.safeInsetRight ?: 0, cutout?.safeInsetBottom ?: 0)
        if (fresh != safe) { safe = fresh; relayout() }
        return super.onApplyWindowInsets(insets)
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        if (!hasWindowFocus) releaseAll()
        super.onWindowFocusChanged(hasWindowFocus)
    }
    override fun performClick(): Boolean { super.performClick(); return true }

    override fun onDetachedFromWindow() {
        releaseAll()
        super.onDetachedFromWindow()
    }

    private fun relayout() {
        if (width <= 0 || height <= 0) return
        releaseAll()
        fit = ((height - safe.top - safe.bottom) / dp(360f)).coerceIn(0.7f, 1f)
        stroke.strokeWidth = dp(1f)
        for (control in controls) {
            control.radius = scaled(control.radiusDp)
            control.hitRadius = max(control.radius, scaled(24f))
        }
        val left = safe.left.toFloat()
        val right = (width - safe.right).toFloat()
        val bottom = (height - safe.bottom).toFloat()
        val shoulderY = safe.top + scaled(36f)
        put("lt", left + scaled(44f), shoulderY)
        put("lb", left + scaled(112f), shoulderY)
        put("select", left + scaled(172f), shoulderY)
        put("rt", right - scaled(44f), shoulderY)
        put("rb", right - scaled(112f), shoulderY)
        put("start", right - scaled(172f), shoulderY)
        put("ls", left + scaled(68f), bottom - scaled(124f))
        put("dpad", left + scaled(144f), bottom - scaled(58f))
        put("face", right - scaled(68f), bottom - scaled(124f))
        put("rs", right - scaled(144f), bottom - scaled(58f))
        put("guide", (left + right) / 2f, bottom - scaled(28f))
        invalidate()
    }

    private fun put(group: String, x: Float, y: Float) {
        for (control in controls) {
            if (control.group != group) continue
            control.cx = x + scaled(control.offsetXDp)
            control.cy = y + scaled(control.offsetYDp)
        }
    }

    private fun label(control: Control): String = when (control.target) {
        "select" -> "⧉"
        "start" -> "☰"
        "guide" -> "◉"
        else -> control.target.uppercase()
    }

    override fun onDraw(canvas: Canvas) {
        for (control in controls) {
            val held = control.pressedBy != -1
            val radius = control.radius
            if (control.stick >= 0) {
                if (!held) continue
                fill.color = stickFill
                canvas.drawCircle(control.ax, control.ay, radius, fill)
                stroke.color = Color.argb(80, 255, 255, 255)
                canvas.drawCircle(control.ax, control.ay, radius, stroke)
                fill.color = knobFill
                canvas.drawCircle(control.ax + control.kx, control.ay + control.ky, radius * 0.38f, fill)
                stroke.color = heldStroke
                canvas.drawCircle(control.ax + control.kx, control.ay + control.ky, radius * 0.38f, stroke)
                continue
            }
            fill.color = if (held) heldFill else idleFill
            stroke.color = if (held) heldStroke else idleStroke
            text.color = if (held) heldText else idleText
            val direction = directions.indexOf(control.target)
            // D-pad arrows stay faint without four persistent button circles.
            if (direction >= 0) {
                if (held) canvas.drawCircle(control.cx, control.cy, radius, fill)
                drawArrow(canvas, control.cx, control.cy, radius * 0.42f, direction)
                continue
            }
            if (control.wide) {
                box.set(control.cx - control.halfW, control.cy - control.halfH,
                    control.cx + control.halfW, control.cy + control.halfH)
                canvas.drawRoundRect(box, control.halfH, control.halfH, fill)
                canvas.drawRoundRect(box, control.halfH, control.halfH, stroke)
                text.textSize = scaled(11f)
            } else {
                canvas.drawCircle(control.cx, control.cy, radius, fill)
                canvas.drawCircle(control.cx, control.cy, radius, stroke)
                text.textSize = scaled(if (control.group == "face") 13f else 11f)
            }
            canvas.drawText(label(control), control.cx,
                control.cy - (text.ascent() + text.descent()) / 2f, text)
        }
    }

    private fun drawArrow(canvas: Canvas, x: Float, y: Float, size: Float, direction: Int) {
        val (fx, fy) = when (direction) {
            0 -> 0f to -1f
            1 -> 1f to 0f
            2 -> 0f to 1f
            else -> -1f to 0f
        }
        arrow.reset()
        arrow.moveTo(x + fx * size, y + fy * size)
        arrow.lineTo(x - fx * size * 0.7f - fy * size, y - fy * size * 0.7f + fx * size)
        arrow.lineTo(x - fx * size * 0.7f + fy * size, y - fy * size * 0.7f - fx * size)
        arrow.close()
        fill.color = text.color
        canvas.drawPath(arrow, fill)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val index = event.actionIndex
                val x = event.getX(index)
                val y = event.getY(index)
                val control = controlAt(x, y) ?: adaptiveStickAt(x, y) ?: return false
                if (control.pressedBy != -1) return true
                control.pressedBy = event.getPointerId(index)
                if (control.stick >= 0) {
                    control.clicked = control.lastUp > 0L && event.eventTime - control.lastUp < DOUBLE_TAP_MS
                    control.ax = event.getX(index)
                    control.ay = event.getY(index)
                    control.drag(event.getX(index), event.getY(index))
                }
                requestUnbufferedDispatch(event)
                apply()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                var changed = false
                for (index in 0 until event.pointerCount) {
                    val pointer = event.getPointerId(index)
                    val x = event.getX(index)
                    val y = event.getY(index)
                    val stick = controls.firstOrNull { it.stick >= 0 && it.pressedBy == pointer }
                    if (stick != null) { stick.drag(x, y); changed = true; continue }
                    val over = controlAt(x, y)?.takeIf { it.stick < 0 }
                    for (control in controls) {
                        if (control.stick < 0 && control.pressedBy == pointer && control !== over) {
                            control.pressedBy = -1
                            changed = true
                        }
                    }
                    if (over != null && over.pressedBy == -1) {
                        over.pressedBy = pointer
                        changed = true
                    }
                }
                if (changed) apply()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                val pointer = event.getPointerId(event.actionIndex)
                if (event.actionMasked == MotionEvent.ACTION_CANCEL) {
                    releaseAll()
                    return true
                }
                var changed = false
                for (control in controls) {
                    if (control.pressedBy == pointer || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                        if (control.pressedBy != -1) changed = true
                        if (control.stick >= 0 && control.pressedBy != -1) control.lastUp = if (control.clicked || event.actionMasked == MotionEvent.ACTION_CANCEL) 0L else event.eventTime
                        control.pressedBy = -1
                        control.clicked = false
                        control.kx = 0f; control.ky = 0f
                    }
                }
                if (changed) apply()
                if (event.actionMasked == MotionEvent.ACTION_UP) performClick()
                return true
            }
        }
        return false
    }


    internal fun hitTest(x: Float, y: Float) = controlAt(x, y) != null || adaptiveStickAt(x, y) != null

    private fun controlAt(x: Float, y: Float): Control? =
        controls.filter { it.stick < 0 && it.contains(x, y) }
            .minByOrNull { val dx = x - it.cx; val dy = y - it.cy; dx * dx + dy * dy }

    private fun adaptiveStickAt(x: Float, y: Float): Control? {
        if (x < safe.left || x >= width - safe.right || y < safe.top || y >= height - safe.bottom) return null
        if (controls.any { it.stick < 0 && it.contains(x, y, scaled(2f)) }) return null
        return controls.filter {
            val dx = x - it.cx; val dy = y - it.cy
            val reach = scaled(52f)
            it.stick >= 0 && it.pressedBy == -1 && dx * dx + dy * dy <= reach * reach
        }.minByOrNull { val dx = x - it.cx; val dy = y - it.cy; dx * dx + dy * dy }
    }

    private fun apply() {
        pad?.applyTouch { state ->
            state.clear()
            for (control in controls) {
                if (control.stick == 0) {
                    state.leftX = control.kx / control.radius; state.leftY = control.ky / control.radius
                    state.press(PadState.L3, control.clicked)
                } else if (control.stick == 1) {
                    state.rightX = control.kx / control.radius; state.rightY = control.ky / control.radius
                    state.press(PadState.R3, control.clicked)
                } else write(state, control.target, control.pressedBy != -1)
            }
        }
        invalidate()
    }

    private fun write(state: PadState, target: String, down: Boolean) {
        when (target) {
            "a" -> state.press(PadState.A, down)
            "b" -> state.press(PadState.B, down)
            "x" -> state.press(PadState.X, down)
            "y" -> state.press(PadState.Y, down)
            "lb" -> state.press(PadState.LB, down)
            "rb" -> state.press(PadState.RB, down)
            "select" -> state.press(PadState.SELECT, down)
            "start" -> state.press(PadState.START, down)
            "l3" -> state.press(PadState.L3, down)
            "r3" -> state.press(PadState.R3, down)
            "guide" -> state.press(PadState.GUIDE, down)
            "lt" -> state.leftTrigger = if (down) 1f else 0f
            "rt" -> state.rightTrigger = if (down) 1f else 0f
            "up" -> state.up = down
            "right" -> state.right = down
            "down" -> state.down = down
            "left" -> state.left = down
        }
    }

    fun releaseAll() {
        invalidate()
        controls.forEach {
            it.pressedBy = -1
            it.clicked = false
            it.lastUp = 0L
            it.kx = 0f; it.ky = 0f
        }
        apply()
    }

    private companion object {
        const val DOUBLE_TAP_MS = 300L
        const val SHOULDER_WIDTH = 1.45f
        const val SHOULDER_HEIGHT = 0.7f
        val shoulderIds = setOf("lb", "rb", "lt", "rt")
        val directions = listOf("up", "right", "down", "left")
    }
}
