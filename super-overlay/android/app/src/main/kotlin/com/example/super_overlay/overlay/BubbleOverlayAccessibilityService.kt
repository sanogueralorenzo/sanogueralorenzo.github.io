package com.example.super_overlay.overlay

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import com.example.super_overlay.R
import kotlin.math.abs

class BubbleOverlayAccessibilityService : AccessibilityService(), RecognitionListener {
    private val mainHandler = Handler(Looper.getMainLooper())

    private var overlayView: TextView? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var isListening: Boolean = false
    private var isBubbleDragging: Boolean = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        runningService = this
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOWS_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 0
        }
        evaluateBubbleVisibility()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        evaluateBubbleVisibility()
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (runningService === this) {
            runningService = null
        }
        stopListeningIfNeeded()
        speechRecognizer?.destroy()
        speechRecognizer = null
        hideBubble()
        super.onDestroy()
    }

    override fun onReadyForSpeech(params: Bundle?) = Unit

    override fun onBeginningOfSpeech() = Unit

    override fun onRmsChanged(rmsdB: Float) = Unit

    override fun onBufferReceived(buffer: ByteArray?) = Unit

    override fun onEndOfSpeech() = Unit

    override fun onPartialResults(partialResults: Bundle?) = Unit

    override fun onEvent(eventType: Int, params: Bundle?) = Unit

    override fun onError(error: Int) {
        isListening = false
        updateBubbleVisual()
        if (error != SpeechRecognizer.ERROR_CLIENT) {
            showToast(getString(R.string.bubble_overlay_error_generic))
        }
    }

    override fun onResults(results: Bundle?) {
        isListening = false
        updateBubbleVisual()

        val spokenText = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.trim()
            .orEmpty()

        if (spokenText.isBlank()) {
            return
        }

        val committed = commitSpokenText(spokenText)
        if (!committed) {
            showToast(getString(R.string.bubble_overlay_error_commit))
        }
    }

    private fun evaluateBubbleVisibility() {
        val shouldShow = BubbleOverlayPreferences.isEnabled(applicationContext) &&
            isInputMethodWindowVisible()

        if (shouldShow) {
            showOrUpdateBubble()
        } else {
            hideBubble()
            stopListeningIfNeeded()
        }
    }

    private fun isInputMethodWindowVisible(): Boolean {
        return windows.any { window ->
            window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
        }
    }

    private fun showOrUpdateBubble() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val bubbleSizePx = dpToPx(BUBBLE_SIZE_DP)
        val (savedX, savedY) = BubbleOverlayPreferences.getPosition(applicationContext)
        val safe = clampBubblePosition(
            x = savedX,
            y = savedY,
            bubbleSizePx = bubbleSizePx,
            windowManager = wm
        )
        if (safe.first != savedX || safe.second != savedY) {
            BubbleOverlayPreferences.setPosition(applicationContext, safe.first, safe.second)
        }

        val existing = overlayView
        if (existing == null) {
            val bubble = buildBubbleView()
            val params = WindowManager.LayoutParams(
                bubbleSizePx,
                bubbleSizePx,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = safe.first
                y = safe.second
            }
            wm.addView(bubble, params)
            overlayView = bubble
            overlayParams = params
            updateBubbleVisual()
            return
        }

        val params = overlayParams ?: return
        if (params.x != safe.first || params.y != safe.second) {
            params.x = safe.first
            params.y = safe.second
            wm.updateViewLayout(existing, params)
        }
        updateBubbleVisual()
    }

    private fun hideBubble() {
        isBubbleDragging = false
        val view = overlayView ?: return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        runCatching { wm.removeView(view) }
        overlayView = null
        overlayParams = null
    }

    private fun buildBubbleView(): TextView {
        val bubble = TextView(this).apply {
            text = ""
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#1B1F23"))
                setStroke(dpToPx(2), Color.parseColor("#1B1F23"))
            }
            elevation = dpToPx(8).toFloat()
        }

        val touchSlopPx = ViewConfiguration.get(this).scaledTouchSlop
        var initialRawX = 0f
        var initialRawY = 0f
        var initialX = 0
        var initialY = 0
        var moved = false

        bubble.setOnTouchListener { view, event ->
            val params = overlayParams ?: return@setOnTouchListener false
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialRawX = event.rawX
                    initialRawY = event.rawY
                    initialX = params.x
                    initialY = params.y
                    moved = false
                    isBubbleDragging = true
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val deltaX = (event.rawX - initialRawX).toInt()
                    val deltaY = (event.rawY - initialRawY).toInt()
                    if (!moved && (abs(deltaX) > touchSlopPx || abs(deltaY) > touchSlopPx)) {
                        moved = true
                    }
                    val safe = clampBubblePosition(
                        x = initialX + deltaX,
                        y = initialY + deltaY,
                        bubbleSizePx = params.width.coerceAtLeast(1),
                        windowManager = wm
                    )
                    params.x = safe.first
                    params.y = safe.second
                    wm.updateViewLayout(view, params)
                    true
                }

                MotionEvent.ACTION_UP -> {
                    isBubbleDragging = false
                    if (moved) {
                        BubbleOverlayPreferences.setPosition(applicationContext, params.x, params.y)
                    } else {
                        onBubbleTapped()
                    }
                    true
                }

                MotionEvent.ACTION_CANCEL -> {
                    isBubbleDragging = false
                    if (moved) {
                        BubbleOverlayPreferences.setPosition(applicationContext, params.x, params.y)
                    }
                    true
                }

                else -> false
            }
        }

        return bubble
    }

    private fun onBubbleTapped() {
        if (!BubbleOverlayPreferences.isEnabled(applicationContext)) {
            return
        }
        if (isListening) {
            stopListeningIfNeeded()
        } else {
            startListening()
        }
    }

    private fun startListening() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            showToast(getString(R.string.bubble_overlay_error_unavailable))
            return
        }
        if (!hasRecordAudioPermission()) {
            showToast(getString(R.string.bubble_overlay_error_mic_permission))
            return
        }

        val recognizer = speechRecognizer ?: SpeechRecognizer.createSpeechRecognizer(this).also {
            it.setRecognitionListener(this)
            speechRecognizer = it
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        }

        runCatching {
            recognizer.startListening(intent)
            isListening = true
            updateBubbleVisual()
        }.onFailure {
            isListening = false
            updateBubbleVisual()
            showToast(getString(R.string.bubble_overlay_error_start))
        }
    }

    private fun stopListeningIfNeeded() {
        if (!isListening) {
            return
        }
        isListening = false
        speechRecognizer?.stopListening()
        updateBubbleVisual()
    }

    private fun commitSpokenText(text: String): Boolean {
        val node = findFocusedEditableNode() ?: return false
        val currentText = node.text?.toString().orEmpty().trim()
        val merged = if (currentText.isBlank()) {
            text
        } else {
            "$currentText $text"
        }

        val setTextArgs = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, merged)
        }
        val set = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, setTextArgs)
        if (set && merged.isNotEmpty()) {
            val selectionArgs = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, merged.length)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, merged.length)
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selectionArgs)
        }
        return set
    }

    private fun findFocusedEditableNode(): AccessibilityNodeInfo? {
        val direct = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (direct != null && direct.isEditable) {
            return direct
        }

        windows.forEach { window ->
            val root = window.root ?: return@forEach
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focused != null && focused.isEditable) {
                return focused
            }
        }
        return null
    }

    private fun hasRecordAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    private fun clampBubblePosition(
        x: Int,
        y: Int,
        bubbleSizePx: Int,
        windowManager: WindowManager
    ): Pair<Int, Int> {
        val displaySize = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            Point(bounds.width(), bounds.height())
        } else {
            @Suppress("DEPRECATION")
            Point().also { point -> windowManager.defaultDisplay.getRealSize(point) }
        }
        val maxX = (displaySize.x - bubbleSizePx).coerceAtLeast(0)
        val maxY = (displaySize.y - bubbleSizePx).coerceAtLeast(0)
        return x.coerceIn(0, maxX) to y.coerceIn(0, maxY)
    }

    private fun updateBubbleVisual() {
        val bubble = overlayView ?: return
        val background = bubble.background as? GradientDrawable ?: return
        val color = if (isListening) {
            Color.parseColor("#C62828")
        } else {
            Color.parseColor("#1B1F23")
        }
        background.setColor(color)
        background.setStroke(dpToPx(2), color)
        bubble.text = ""
        bubble.gravity = Gravity.CENTER
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private fun showToast(message: String) {
        mainHandler.post {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        private const val BUBBLE_SIZE_DP = 36

        @Volatile
        private var runningService: BubbleOverlayAccessibilityService? = null

        fun requestRefresh(context: Context) {
            runningService?.mainHandler?.post {
                runningService?.evaluateBubbleVisibility()
            }
        }
    }
}
