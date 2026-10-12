package com.sanogueralorenzo.amarchy.home

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.content.res.ColorStateList
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import com.sanogueralorenzo.amarchy.session.Phase
import com.sanogueralorenzo.amarchy.session.WorkspaceState

/** A single responsive home screen; preparation and recovery use the same primary action. */
internal class HomeScreen(context: Context, open: () -> Unit, cancel: () -> Unit) : FrameLayout(context) {
    private val ink = Color.rgb(239, 243, 235)
    private val muted = Color.rgb(154, 168, 154)
    private val accent = Color.rgb(184, 238, 162)
    private val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = ScrollView(context).apply { isFillViewport = true; clipToPadding = false }
    private var previousPhase = Phase.WELCOME
    private val primary = Button(context).apply {
        text = "Get started"; isAllCaps = false; textSize = 16f
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        setTextColor(Color.rgb(16, 20, 17)); minHeight = dp(56)
        background = RippleDrawable(ColorStateList.valueOf(Color.rgb(150, 210, 130)), shape(accent, 18f), null)
        setOnClickListener { open() }
    }
    private val secondary = Button(context).apply {
        text = "Cancel"; isAllCaps = false; textSize = 14f; setTextColor(muted)
        minHeight = dp(48); background = RippleDrawable(ColorStateList.valueOf(0x22ffffff), shape(Color.TRANSPARENT, 12f), null)
        setOnClickListener { cancel() }; visibility = GONE
    }
    private val statusTitle = label("", 15f, ink, "sans-serif-medium")
    private val statusDetail = label("", 14f, muted).apply { setLineSpacing(dp(4).toFloat(), 1f) }
    private val progress = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
        max = 100; progressTintList = ColorStateList.valueOf(accent)
        progressBackgroundTintList = ColorStateList.valueOf(Color.rgb(48, 61, 48))
    }
    private val status = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; setPadding(dp(18), dp(18), dp(18), dp(18))
        background = shape(Color.rgb(26, 33, 27), 16f)
        addView(statusTitle); addView(statusDetail, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
        addView(progress, LinearLayout.LayoutParams(-1, dp(12)).apply { topMargin = dp(12) })
        visibility = GONE; accessibilityLiveRegion = ACCESSIBILITY_LIVE_REGION_POLITE
    }
    private val footer = label("One setup. A workspace of your own.", 12f, muted).apply { gravity = Gravity.CENTER }

    init {
        setBackgroundColor(Color.rgb(16, 20, 17))
        val center = FrameLayout(context)
        center.addView(column, LayoutParams(-1, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
        column.setPadding(dp(26), dp(24), dp(26), dp(24))
        scroll.addView(center, LayoutParams(-1, -1))
        addView(scroll, LayoutParams(-1, -1))
        setOnApplyWindowInsetsListener { _, insets ->
            val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            scroll.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        val brand = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        brand.addView(Mark(context), LinearLayout.LayoutParams(dp(36), dp(36)))
        brand.addView(label("amarchy", 21f, ink, "sans-serif-medium"), LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(10) })
        brand.addView(label("ANDROID", 10f, muted, "monospace").apply { letterSpacing = 0.12f })
        column.addView(brand)
        column.addView(label("Your desktop.\nAnywhere.", 46f, ink, "sans-serif-medium").apply {
            letterSpacing = -0.055f; setLineSpacing(0f, 0.98f)
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(46) })
        column.addView(label("Omarchy, at home on Android.", 17f, muted).apply { setLineSpacing(dp(3).toFloat(), 1f) },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(18) })
        column.addView(WorkspaceIllustration(context), LinearLayout.LayoutParams(-1, dp(190)).apply { topMargin = dp(28) })
        column.addView(label("A little room to do big things.", 19f, ink, "sans-serif-medium"),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(26) })
        column.addView(label("Your terminal, projects, and familiar tools,\nin one personal workspace.", 14f, muted).apply {
            setLineSpacing(dp(5).toFloat(), 1f)
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(9) })
        val features = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        for (feature in listOf("ON YOUR DEVICE", "NO ROOT NEEDED")) features.addView(label(feature, 10f, accent, "monospace").apply {
            letterSpacing = 0.025f; setPadding(0, dp(12), dp(22), dp(12))
        })
        column.addView(features, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(9) })
        column.addView(status, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
        column.addView(primary, LinearLayout.LayoutParams(-1, dp(56)).apply { topMargin = dp(24) })
        column.addView(secondary, LinearLayout.LayoutParams(-1, dp(48)))
        column.addView(footer, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(16) })
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(widthMeasureSpec)
        val contentWidth = minOf(available, dp(540))
        if (column.layoutParams.width != contentWidth) column.layoutParams = column.layoutParams.apply { width = contentWidth }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    fun render(state: WorkspaceState) {
        val busy = state.phase in setOf(Phase.PREPARING, Phase.STOPPING)
        primary.isEnabled = !busy; primary.alpha = if (busy) 0.65f else 1f
        primary.text = when (state.phase) {
            Phase.PREPARING -> "Preparing your workspace…"
            Phase.STOPPING -> "Closing…"
            Phase.FAILED -> "Try again"
            else -> "Get started"
        }
        secondary.visibility = if (state.phase == Phase.PREPARING) VISIBLE else GONE
        status.visibility = if (busy || state.phase == Phase.FAILED) VISIBLE else GONE
        statusTitle.text = if (state.phase == Phase.FAILED) "Your workspace needs a moment" else state.detail
        statusDetail.text = if (state.phase == Phase.FAILED) state.detail else "You can leave the app while we prepare everything."
        progress.visibility = if (state.phase == Phase.PREPARING) VISIBLE else GONE
        progress.progress = (state.progress * 100).toInt()
        progress.isIndeterminate = state.phase == Phase.PREPARING && state.progress == 0f
        footer.text = if (state.phase == Phase.FAILED) "Retry keeps your prepared environment." else "One setup. A workspace of your own."
        if (state.phase != previousPhase && (busy || state.phase == Phase.FAILED)) scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
        previousPhase = state.phase
    }

    private fun label(text: String, size: Float, color: Int, font: String = "sans-serif") = TextView(context).apply {
        this.text = text; textSize = size; setTextColor(color); typeface = Typeface.create(font, Typeface.NORMAL)
        includeFontPadding = false
    }
    private fun shape(color: Int, radius: Float) = GradientDrawable().apply { setColor(color); cornerRadius = dp(radius).toFloat() }
    private fun dp(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()
    private fun dp(value: Float) = (value * resources.displayMetrics.density + 0.5f).toInt()
}

private class Mark(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(184, 238, 162) }
    init { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }
    override fun onDraw(canvas: Canvas) {
        val scale = width / 36f
        canvas.save(); canvas.scale(scale, scale)
        canvas.drawPath(Path().apply { moveTo(18f, 3f); lineTo(34f, 33f); lineTo(26f, 33f); lineTo(18f, 17f); lineTo(10f, 33f); lineTo(2f, 33f); close() }, paint)
        canvas.drawRect(14f, 25f, 22f, 30f, paint); canvas.restore()
    }
}

/** An illustrative workspace motif, not a screenshot or simulated Linux session. */
private class WorkspaceIllustration(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    init { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }
    override fun onDraw(canvas: Canvas) {
        val sx = width / 340f; val sy = height / 190f
        canvas.save(); canvas.scale(sx, sy)
        fun box(x: Float, y: Float, w: Float, h: Float, color: Int, radius: Float = 10f) {
            paint.color = color; canvas.drawRoundRect(RectF(x, y, x + w, y + h), radius, radius, paint)
        }
        box(0f, 0f, 340f, 190f, 0xff1b241c.toInt(), 18f)
        paint.color = 0xff263827.toInt(); canvas.drawCircle(290f, 175f, 90f, paint)
        paint.color = 0xff344d32.toInt(); canvas.drawCircle(290f, 175f, 64f, paint)
        box(18f, 18f, 304f, 12f, 0xff344236.toInt(), 6f)
        box(18f, 43f, 174f, 129f, 0xff101812.toInt())
        box(204f, 43f, 118f, 58f, 0xff263228.toInt())
        box(204f, 113f, 118f, 59f, 0xff263228.toInt())
        for (i in 0..2) { paint.color = intArrayOf(0xffb8eea2.toInt(), 0xff889780.toInt(), 0xff536551.toInt())[i]; canvas.drawCircle(31f + i * 9f, 57f, 2f, paint) }
        for ((i, length) in listOf(78f, 130f, 101f, 54f, 93f).withIndex()) box(30f, 78f + i * 15f, length, 4f,
            if (i == 0) 0xffb8eea2.toInt() else 0xff3c5140.toInt(), 2f)
        box(216f, 57f, 56f, 4f, 0xff95b888.toInt(), 2f)
        box(216f, 70f, 86f, 4f, 0xff4d6350.toInt(), 2f)
        box(216f, 128f, 36f, 4f, 0xff95b888.toInt(), 2f)
        box(216f, 141f, 74f, 4f, 0xff4d6350.toInt(), 2f)
        canvas.restore()
    }
}
