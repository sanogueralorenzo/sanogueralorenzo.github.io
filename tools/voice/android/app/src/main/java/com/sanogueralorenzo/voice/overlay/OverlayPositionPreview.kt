package com.sanogueralorenzo.voice.overlay

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import kotlin.math.roundToInt

internal class OverlayPositionPreview(
    private val hostView: View,
    private val onPositionChanged: (x: Int, y: Int) -> Unit
) {
    private val context = hostView.context
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val bubbleView = buildBubbleView()

    private var layoutParams: WindowManager.LayoutParams? = null
    private var showRequested = false
    private var bubbleX = 0
    private var bubbleY = 0
    private var bubbleSizeDp = 36
    private var hasCustomPosition = false

    fun show(
        x: Int,
        y: Int,
        sizeDp: Int,
        hasCustomPosition: Boolean
    ) {
        update(x, y, sizeDp, hasCustomPosition)
        showRequested = true
        if (layoutParams != null) return
        if (hostView.applicationWindowToken == null) {
            hostView.post { attachIfRequested() }
        } else {
            attachIfRequested()
        }
    }

    fun update(
        x: Int,
        y: Int,
        sizeDp: Int,
        hasCustomPosition: Boolean
    ) {
        bubbleX = x
        bubbleY = y
        bubbleSizeDp = sizeDp
        this.hasCustomPosition = hasCustomPosition
        applyGeometry()
    }

    fun dismiss() {
        showRequested = false
        layoutParams?.let {
            runCatching { windowManager.removeView(bubbleView) }
        }
        layoutParams = null
    }

    private fun attachIfRequested() {
        if (!showRequested || layoutParams != null) return
        val sizePx = dpToPx(bubbleSizeDp)
        val initialPosition = if (hasCustomPosition) {
            clampPosition(bubbleX, bubbleY, sizePx)
        } else {
            defaultPosition()
        }
        bubbleX = initialPosition.first
        bubbleY = initialPosition.second
        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            WindowManager.LayoutParams.TYPE_APPLICATION_SUB_PANEL,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            token = hostView.applicationWindowToken
            gravity = Gravity.TOP or Gravity.START
            x = bubbleX
            y = bubbleY
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                setFitInsetsTypes(0)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
        }
        windowManager.addView(bubbleView, params)
        layoutParams = params
        if (!hasCustomPosition) {
            hasCustomPosition = true
            onPositionChanged(bubbleX, bubbleY)
        }
    }

    private fun applyGeometry() {
        val params = layoutParams ?: return
        val sizePx = dpToPx(bubbleSizeDp)
        val position = clampPosition(bubbleX, bubbleY, sizePx)
        bubbleX = position.first
        bubbleY = position.second
        if (
            params.x == bubbleX &&
            params.y == bubbleY &&
            params.width == sizePx &&
            params.height == sizePx
        ) {
            return
        }
        params.x = bubbleX
        params.y = bubbleY
        params.width = sizePx
        params.height = sizePx
        windowManager.updateViewLayout(bubbleView, params)
    }

    private fun buildBubbleView(): View {
        return View(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(if (isSystemInDarkTheme()) Color.WHITE else Color.BLACK)
                setStroke(dpToPx(2), Color.parseColor("#1B1F23"))
            }
            elevation = dpToPx(10).toFloat()
            setOnTouchListener(buildTouchListener())
        }
    }

    private fun buildTouchListener(): View.OnTouchListener {
        val touchSlopPx = ViewConfiguration.get(context).scaledTouchSlop
        var initialRawX = 0f
        var initialRawY = 0f
        var initialX = 0
        var initialY = 0
        var moved = false

        return View.OnTouchListener { _, event ->
            val params = layoutParams ?: return@OnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialRawX = event.rawX
                    initialRawY = event.rawY
                    initialX = params.x
                    initialY = params.y
                    moved = false
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val deltaX = (event.rawX - initialRawX).roundToInt()
                    val deltaY = (event.rawY - initialRawY).roundToInt()
                    if (!moved && (
                            kotlin.math.abs(deltaX) > touchSlopPx ||
                                kotlin.math.abs(deltaY) > touchSlopPx
                            )
                    ) {
                        moved = true
                    }
                    if (moved) {
                        val position = clampPosition(
                            x = initialX + deltaX,
                            y = initialY + deltaY,
                            bubbleSizePx = params.width.coerceAtLeast(1)
                        )
                        bubbleX = position.first
                        bubbleY = position.second
                        params.x = bubbleX
                        params.y = bubbleY
                        windowManager.updateViewLayout(bubbleView, params)
                    }
                    true
                }

                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL -> {
                    if (moved) {
                        onPositionChanged(bubbleX, bubbleY)
                    }
                    true
                }

                else -> false
            }
        }
    }

    private fun defaultPosition(): Pair<Int, Int> {
        val displaySize = displaySize()
        val bubbleSizePx = dpToPx(bubbleSizeDp)
        val keyboardTopPx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windowManager.currentWindowMetrics.windowInsets
                .getInsets(WindowInsets.Type.ime())
                .bottom
                .takeIf { it > 0 }
                ?.let { displaySize.y - it }
        } else {
            null
        }
        return OverlayDefaultPosition.calculate(
            displayWidthPx = displaySize.x,
            displayHeightPx = displaySize.y,
            keyboardTopPx = keyboardTopPx,
            bubbleSizePx = bubbleSizePx,
            density = context.resources.displayMetrics.density
        )
    }

    private fun clampPosition(x: Int, y: Int, bubbleSizePx: Int): Pair<Int, Int> {
        val displaySize = displaySize()
        val maxX = (displaySize.x - bubbleSizePx).coerceAtLeast(0)
        val maxY = (displaySize.y - bubbleSizePx).coerceAtLeast(0)
        return x.coerceIn(0, maxX) to y.coerceIn(0, maxY)
    }

    private fun displaySize(): Point {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            Point(bounds.width(), bounds.height())
        } else {
            Point(
                context.resources.displayMetrics.widthPixels,
                context.resources.displayMetrics.heightPixels
            )
        }
    }

    private fun isSystemInDarkTheme(): Boolean {
        val nightMask = context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK
        return nightMask == Configuration.UI_MODE_NIGHT_YES
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * context.resources.displayMetrics.density).roundToInt()
    }
}
