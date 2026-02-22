package com.sanogueralorenzo.voice.overlay

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.audio.MoonshineTranscriber
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder
import com.sanogueralorenzo.voice.di.appGraph
import com.sanogueralorenzo.voice.ime.ImeOperation
import com.sanogueralorenzo.voice.ime.ImeSpeechProcessorEntryPoint
import com.sanogueralorenzo.voice.ime.ImeSpeechProcessorRequest
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.summary.EditInstructionRules
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException

class OverlayAccessibilityService : AccessibilityService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val processingExecutor = Executors.newSingleThreadExecutor()

    @Volatile
    private var inFlight: Future<*>? = null

    @Volatile
    private var recorder: VoiceAudioRecorder? = null

    private var overlayView: TextView? = null
    private var overlayParams: WindowManager.LayoutParams? = null

    private val appGraph by lazy(LazyThreadSafetyMode.NONE) { applicationContext.appGraph() }
    private val overlayRepository by lazy(LazyThreadSafetyMode.NONE) {
        OverlayRepository(
            context = applicationContext,
            setupRepository = appGraph.setupRepository
        )
    }
    private val moonshineTranscriber by lazy(LazyThreadSafetyMode.NONE) { MoonshineTranscriber(this) }
    private val speechProcessor by lazy(LazyThreadSafetyMode.NONE) {
        ImeSpeechProcessorEntryPoint.create(
            moonshineTranscriber = moonshineTranscriber,
            asrRuntimeStatusStore = appGraph.asrRuntimeStatusStore,
            preferencesRepository = appGraph.preferencesRepository,
            summaryEngine = appGraph.summaryEngine,
            composePreLlmRules = appGraph.composePreLlmRules,
            logTag = TAG
        )
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        runningService = this
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOWS_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                AccessibilityEvent.TYPE_VIEW_FOCUSED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 0
        }
        evaluateOverlayVisibility()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        evaluateOverlayVisibility()
    }

    override fun onInterrupt() = Unit

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_REFRESH) {
            evaluateOverlayVisibility()
        }
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onDestroy() {
        if (runningService === this) {
            runningService = null
        }
        stopForegroundIfNeeded()
        hideBubble()
        stopRecordingDiscard()
        inFlight?.cancel(true)
        processingExecutor.shutdownNow()
        runCatching { moonshineTranscriber.release() }
        super.onDestroy()
    }

    private fun evaluateOverlayVisibility() {
        val config = overlayRepository.currentConfig()
        val imeVisible = isInputMethodWindowVisible()
        val focusedEditable = hasFocusedEditableInput()
        val shouldShow = if (overlayView == null) {
            config.overlayEnabled &&
                !overlayRepository.isVoiceImeSelected() &&
                imeVisible
        } else {
            config.overlayEnabled &&
                !overlayRepository.isVoiceImeSelected() &&
                imeVisible &&
                focusedEditable
        }

        if (shouldShow) {
            showOrUpdateBubble(config)
        } else {
            hideBubble()
            stopRecordingDiscard()
        }
    }

    private fun isInputMethodWindowVisible(): Boolean {
        return windows.any { window ->
            window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
        }
    }

    private fun hasFocusedEditableInput(): Boolean {
        val directFocused = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (directFocused?.isEditable == true) return true
        return windows.any { window ->
            window.root
                ?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                ?.isEditable == true
        }
    }

    private fun showOrUpdateBubble(config: OverlayConfig) {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val bubbleSizePx = dpToPx(BUBBLE_SIZE_DP)
        val safePosition = clampBubblePosition(
            x = config.bubbleX,
            y = config.bubbleY,
            bubbleSizePx = bubbleSizePx,
            windowManager = wm
        )
        if (safePosition.first != config.bubbleX || safePosition.second != config.bubbleY) {
            overlayRepository.setBubblePosition(safePosition.first, safePosition.second)
        }
        val view = overlayView
        if (view == null) {
            val bubble = buildBubbleView()
            val params = WindowManager.LayoutParams(
                bubbleSizePx,
                bubbleSizePx,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = safePosition.first
                y = safePosition.second
            }
            wm.addView(bubble, params)
            overlayView = bubble
            overlayParams = params
            updateBubbleVisual(BubbleVisualState.IDLE)
            return
        }

        val params = overlayParams ?: return
        if (params.x != safePosition.first || params.y != safePosition.second) {
            params.x = safePosition.first
            params.y = safePosition.second
            wm.updateViewLayout(view, params)
        }
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

    private fun hideBubble() {
        val view = overlayView ?: return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        runCatching { wm.removeView(view) }
        overlayView = null
        overlayParams = null
    }

    private fun buildBubbleView(): TextView {
        val bubble = TextView(this).apply {
            text = "●"
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#1B1F23"))
            }
            elevation = dpToPx(10).toFloat()
        }

        val touchSlopPx = dpToPx(6)
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
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val deltaX = (event.rawX - initialRawX).toInt()
                    val deltaY = (event.rawY - initialRawY).toInt()
                    if (!moved && (kotlin.math.abs(deltaX) > touchSlopPx || kotlin.math.abs(deltaY) > touchSlopPx)) {
                        moved = true
                    }
                    params.x = initialX + deltaX
                    params.y = initialY + deltaY
                    wm.updateViewLayout(view, params)
                    true
                }

                MotionEvent.ACTION_UP -> {
                    if (moved) {
                        overlayRepository.setBubblePosition(params.x, params.y)
                    } else {
                        onBubbleTapped()
                    }
                    true
                }

                else -> false
            }
        }

        return bubble
    }

    private fun onBubbleTapped() {
        if (inFlight != null) return

        val config = overlayRepository.currentConfig()
        if (config.positioningMode) {
            overlayRepository.setPositioningMode(false)
            showToast(getString(R.string.overlay_position_saved))
            return
        }

        val activeRecorder = recorder
        if (activeRecorder == null) {
            startRecording()
        } else {
            recorder = null
            submitProcessing(activeRecorder)
        }
    }

    private fun startRecording() {
        if (!overlayRepository.hasRecordAudioPermission()) {
            showToast(getString(R.string.overlay_microphone_required))
            return
        }
        if (!isMoonshineReady()) {
            showToast(getString(R.string.overlay_asr_not_ready))
            return
        }

        startForegroundForRecording()
        val audioRecorder = VoiceAudioRecorder(
            onLevelChanged = { },
            onAudioFrame = { }
        )
        if (!audioRecorder.start()) {
            stopForegroundIfNeeded()
            showToast(getString(R.string.overlay_recording_start_failed))
            return
        }
        recorder = audioRecorder
        updateBubbleVisual(BubbleVisualState.RECORDING)
    }

    private fun submitProcessing(activeRecorder: VoiceAudioRecorder) {
        updateBubbleVisual(BubbleVisualState.PROCESSING)
        try {
            inFlight = processingExecutor.submit {
                processRecording(activeRecorder)
            }
        } catch (_: RejectedExecutionException) {
            activeRecorder.stopAndGetPcm()
            stopForegroundIfNeeded()
            updateBubbleVisual(BubbleVisualState.IDLE)
        }
    }

    private fun processRecording(activeRecorder: VoiceAudioRecorder) {
        val sourceText = readFocusedInputText()
        val result = try {
            speechProcessor.process(
                request = ImeSpeechProcessorRequest(
                    recorder = activeRecorder,
                    sourceTextSnapshot = sourceText
                ),
                onShowRewriting = {
                    mainHandler.post { updateBubbleVisual(BubbleVisualState.PROCESSING) }
                }
            )
        } catch (_: Throwable) {
            null
        }

        if (result != null) {
            val committed = commitResult(result)
            if (!committed && result.output.isNotBlank()) {
                showToast(getString(R.string.overlay_commit_failed))
            }
        }

        mainHandler.post {
            inFlight = null
            stopForegroundIfNeeded()
            updateBubbleVisual(BubbleVisualState.IDLE)
        }
    }

    private fun commitResult(result: com.sanogueralorenzo.voice.ime.ImeSpeechProcessorResult): Boolean {
        val shouldPreserveBlankEdit =
            result.operation == ImeOperation.EDIT &&
                result.output.isBlank() &&
                result.editIntent != EditInstructionRules.EditIntent.DELETE_ALL.name

        if (result.output.isBlank() && result.operation == ImeOperation.APPEND) {
            return false
        }
        if (result.output.isBlank() && shouldPreserveBlankEdit) {
            return true
        }

        return replaceFocusedInputText(result.output)
    }

    private fun readFocusedInputText(): String {
        val node = findFocusedEditableNode() ?: return ""
        return node.text?.toString().orEmpty()
    }

    private fun replaceFocusedInputText(text: String): Boolean {
        val node = findFocusedEditableNode() ?: return false
        val setTextArgs = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        val set = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, setTextArgs)
        if (set && text.isNotEmpty()) {
            val selectionArgs = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, text.length)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, text.length)
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

    private fun isMoonshineReady(): Boolean {
        return ModelCatalog.moonshineMediumStreamingSpecs.all { spec ->
            ModelStore.isModelReadyStrict(applicationContext, spec)
        }
    }

    private fun stopRecordingDiscard() {
        val activeRecorder = recorder ?: return
        recorder = null
        processingExecutor.submit {
            activeRecorder.stopAndGetPcm()
        }
        stopForegroundIfNeeded()
        updateBubbleVisual(BubbleVisualState.IDLE)
    }

    private fun startForegroundForRecording() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                getString(R.string.overlay_notification_channel),
                NotificationManager.IMPORTANCE_LOW
            )
            manager?.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.overlay_notification_title))
            .setContentText(getString(R.string.overlay_notification_text))
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun updateBubbleVisual(state: BubbleVisualState) {
        val bubble = overlayView ?: return
        val color = when (state) {
            BubbleVisualState.IDLE -> Color.parseColor("#1B1F23")
            BubbleVisualState.RECORDING -> Color.parseColor("#C62828")
            BubbleVisualState.PROCESSING -> Color.parseColor("#1565C0")
        }
        val background = bubble.background as? GradientDrawable ?: return
        background.setColor(color)
    }

    private fun showToast(message: String) {
        mainHandler.post {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private enum class BubbleVisualState {
        IDLE,
        RECORDING,
        PROCESSING
    }

    companion object {
        const val ACTION_REFRESH = "com.sanogueralorenzo.voice.overlay.REFRESH"

        fun requestRefresh(context: Context) {
            runningService?.mainHandler?.post {
                runningService?.evaluateOverlayVisibility()
            }
        }

        @Volatile
        private var runningService: OverlayAccessibilityService? = null

        private const val TAG = "OverlayService"
        private const val BUBBLE_SIZE_DP = 56
        private const val NOTIFICATION_CHANNEL_ID = "overlay_recording"
        private const val NOTIFICATION_ID = 12057
    }
}
