package com.sanogueralorenzo.voice.overlay

import android.accessibilityservice.AccessibilityService
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/** Owns the invisible floating microphone window and its persisted position and size. */
internal class OverlayWindowController(
    private val service: AccessibilityService,
    private val repository: OverlayRepository,
    private val onTap: () -> Unit,
    private val onLongPress: () -> Boolean
) {
    private val windowManager: WindowManager
        get() = service.getSystemService(AccessibilityService.WINDOW_SERVICE) as WindowManager

    private var view: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    fun observeSettings(scope: CoroutineScope) {
        scope.launch {
            repository.bubbleSizeDpFlow().collectLatest { sizeDp ->
                if (view != null && params != null) {
                    show(repository.currentConfig().copy(bubbleSizeDp = sizeDp))
                }
            }
        }
        scope.launch {
            repository.bubbleXFlow().collectLatest { x ->
                applyPosition(targetX = x, targetY = null)
            }
        }
        scope.launch {
            repository.bubbleYFlow().collectLatest { y ->
                applyPosition(targetX = null, targetY = y)
            }
        }
    }

    fun show(config: OverlayConfig) {
        val bubbleSizePx = dpToPx(config.bubbleSizeDp)
        val configuredPosition = if (config.hasCustomBubblePosition) {
            config.bubbleX to config.bubbleY
        } else {
            defaultPosition(bubbleSizePx)
        }
        val safePosition = clampPosition(
            x = configuredPosition.first,
            y = configuredPosition.second,
            bubbleSizePx = bubbleSizePx
        )
        if (config.hasCustomBubblePosition) {
            if (safePosition.first != config.bubbleX || safePosition.second != config.bubbleY) {
                repository.setBubblePosition(safePosition.first, safePosition.second)
            }
        } else {
            repository.setDefaultBubblePosition(safePosition.first, safePosition.second)
        }

        val currentView = view
        if (currentView == null) {
            val bubble = buildView()
            val layoutParams = WindowManager.LayoutParams(
                bubbleSizePx,
                bubbleSizePx,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = safePosition.first
                y = safePosition.second
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) setFitInsetsTypes(0)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                }
            }
            windowManager.addView(bubble, layoutParams)
            view = bubble
            params = layoutParams
            updateVisual(bubble)
            return
        }

        val layoutParams = params ?: return
        if (
            layoutParams.x != safePosition.first ||
            layoutParams.y != safePosition.second ||
            layoutParams.width != bubbleSizePx ||
            layoutParams.height != bubbleSizePx
        ) {
            layoutParams.width = bubbleSizePx
            layoutParams.height = bubbleSizePx
            layoutParams.x = safePosition.first
            layoutParams.y = safePosition.second
            windowManager.updateViewLayout(currentView, layoutParams)
        }
        updateVisual(currentView)
    }

    fun hide() {
        view?.let { bubble ->
            bubble.animate().cancel()
            runCatching { windowManager.removeView(bubble) }
        }
        view = null
        params = null
    }

    private fun applyPosition(targetX: Int?, targetY: Int?) {
        val bubble = view ?: return
        val layoutParams = params ?: return
        val safePosition = clampPosition(
            x = targetX ?: layoutParams.x,
            y = targetY ?: layoutParams.y,
            bubbleSizePx = layoutParams.width.coerceAtLeast(1)
        )
        if (layoutParams.x == safePosition.first && layoutParams.y == safePosition.second) return
        layoutParams.x = safePosition.first
        layoutParams.y = safePosition.second
        windowManager.updateViewLayout(bubble, layoutParams)
    }

    private fun clampPosition(x: Int, y: Int, bubbleSizePx: Int): Pair<Int, Int> {
        val displaySize = displaySize()
        val maxX = (displaySize.x - bubbleSizePx).coerceAtLeast(0)
        val maxY = (displaySize.y - bubbleSizePx).coerceAtLeast(0)
        return x.coerceIn(0, maxX) to y.coerceIn(0, maxY)
    }

    private fun defaultPosition(bubbleSizePx: Int): Pair<Int, Int> {
        val displaySize = displaySize()
        val keyboardTopPx = visibleInputMethodTopPx()
            ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
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
            density = service.resources.displayMetrics.density
        )
    }

    private fun visibleInputMethodTopPx(): Int? {
        val inputMethodWindow = service.windows.firstOrNull { window ->
            window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
        } ?: return null
        val bounds = Rect()
        inputMethodWindow.getBoundsInScreen(bounds)
        return bounds.top.takeIf { bounds.height() > 0 }
    }

    private fun displaySize(): Point {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            Point(bounds.width(), bounds.height())
        } else {
            @Suppress("DEPRECATION")
            Point().also { point -> windowManager.defaultDisplay.getRealSize(point) }
        }
    }

    private fun buildView(): TextView {
        return TextView(service).apply {
            text = ""
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
                setStroke(dpToPx(2), Color.TRANSPARENT)
            }
            elevation = 0f
            setOnClickListener { onTap() }
            setOnLongClickListener { onLongPress() }
        }
    }

    private fun updateVisual(bubble: TextView) {
        val background = bubble.background as? GradientDrawable ?: return
        background.setColor(Color.TRANSPARENT)
        background.setStroke(dpToPx(2), Color.TRANSPARENT)
        bubble.elevation = 0f
        bubble.text = ""
        bubble.gravity = Gravity.CENTER
        bubble.setPadding(0, 0, 0, 0)
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            service.resources.displayMetrics
        ).toInt()
    }
}
