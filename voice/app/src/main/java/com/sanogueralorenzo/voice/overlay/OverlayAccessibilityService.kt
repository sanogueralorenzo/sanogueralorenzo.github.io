package com.sanogueralorenzo.voice.overlay

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.Intent
import android.content.res.Configuration
import android.database.ContentObserver
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import java.util.concurrent.TimeoutException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class OverlayAccessibilityService : AccessibilityService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val processingExecutor = Executors.newSingleThreadExecutor()
    private val chunkExecutor = Executors.newSingleThreadExecutor()
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @Volatile
    private var inFlight: Future<*>? = null

    @Volatile
    private var recorder: VoiceAudioRecorder? = null
    private var recorderChunkSessionId: Int = 0
    private val chunkLock = Any()
    private val chunkSessionCounter = AtomicInteger(0)
    private var activeChunkSessionId: Int = 0
    private val activeChunkFutures = mutableListOf<Future<*>>()

    private var overlayView: TextView? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var systemDialogReceiverRegistered = false
    private var imeSettingsObserverRegistered = false
    private var isBubbleDragging = false
    private var resizeAnchorCenterX: Float? = null
    private var resizeAnchorCenterY: Float? = null

    private val systemDialogReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_CLOSE_SYSTEM_DIALOGS,
                Intent.ACTION_SCREEN_OFF -> {
                    cancelRecordingIfActive()
                }
            }
        }
    }
    private val imeSettingsObserver = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean) {
            evaluateOverlayVisibility()
        }
    }

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
        registerSystemDialogReceiverIfNeeded()
        registerImeSettingsObserverIfNeeded()
        startBubbleSizeObserver()
        startBubblePositionObservers()
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOWS_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = flags or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
            notificationTimeout = 0
        }
        evaluateOverlayVisibility()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        evaluateOverlayVisibility()
    }

    override fun onKeyEvent(event: KeyEvent?): Boolean {
        if (event?.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_BACK) {
            cancelRecordingIfActive()
        }
        return super.onKeyEvent(event)
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
        serviceScope.cancel()
        unregisterSystemDialogReceiverIfNeeded()
        unregisterImeSettingsObserverIfNeeded()
        stopForegroundIfNeeded()
        hideBubble()
        stopRecordingDiscard()
        inFlight?.cancel(true)
        processingExecutor.shutdownNow()
        endChunkSession(activeChunkSessionId, cancelPending = true)
        chunkExecutor.shutdownNow()
        runCatching { moonshineTranscriber.release() }
        super.onDestroy()
    }

    private fun evaluateOverlayVisibility() {
        val config = overlayRepository.currentConfig()
        val shouldShowByContext = (config.overlayEnabled || positionPreviewActive) &&
            !overlayRepository.isVoiceImeSelected() &&
            isInputMethodWindowVisible()
        val shouldKeepVisibleForActiveWork = recorder != null || inFlight != null
        val shouldShow = shouldShowByContext || shouldKeepVisibleForActiveWork

        if (shouldShow) {
            showOrUpdateBubble(config)
        } else {
            hideBubble()
            if (recorder != null) {
                stopRecordingDiscard()
            }
        }
    }

    private fun isInputMethodWindowVisible(): Boolean {
        return windows.any { window ->
            window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
        }
    }

    private fun cancelRecordingIfActive() {
        stopRecordingDiscard()
    }

    private fun registerSystemDialogReceiverIfNeeded() {
        if (systemDialogReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        val registered = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(systemDialogReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(systemDialogReceiver, filter)
            }
        }.isSuccess
        systemDialogReceiverRegistered = registered
    }

    private fun unregisterSystemDialogReceiverIfNeeded() {
        if (!systemDialogReceiverRegistered) return
        runCatching { unregisterReceiver(systemDialogReceiver) }
        systemDialogReceiverRegistered = false
    }

    private fun registerImeSettingsObserverIfNeeded() {
        if (imeSettingsObserverRegistered) return
        val registered = runCatching {
            contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(Settings.Secure.DEFAULT_INPUT_METHOD),
                false,
                imeSettingsObserver
            )
            contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(Settings.Secure.ENABLED_INPUT_METHODS),
                false,
                imeSettingsObserver
            )
        }.isSuccess
        imeSettingsObserverRegistered = registered
    }

    private fun unregisterImeSettingsObserverIfNeeded() {
        if (!imeSettingsObserverRegistered) return
        runCatching { contentResolver.unregisterContentObserver(imeSettingsObserver) }
        imeSettingsObserverRegistered = false
    }

    private fun showOrUpdateBubble(config: OverlayConfig) {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val bubbleSizePx = dpToPx(config.bubbleSizeDp)
        val desiredX = if (isBubbleDragging) {
            overlayParams?.x ?: config.bubbleX
        } else {
            config.bubbleX
        }
        val desiredY = if (isBubbleDragging) {
            overlayParams?.y ?: config.bubbleY
        } else {
            config.bubbleY
        }
        val safePosition = clampBubblePosition(
            x = desiredX,
            y = desiredY,
            bubbleSizePx = bubbleSizePx,
            windowManager = wm
        )
        if (!isBubbleDragging && (safePosition.first != config.bubbleX || safePosition.second != config.bubbleY)) {
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
            captureResizeAnchorFromParams(params)
            updateBubbleVisual(currentBubbleVisualState())
            return
        }

        val params = overlayParams ?: return
        if (
            params.x != safePosition.first ||
            params.y != safePosition.second ||
            params.width != bubbleSizePx ||
            params.height != bubbleSizePx
        ) {
            params.width = bubbleSizePx
            params.height = bubbleSizePx
            params.x = safePosition.first
            params.y = safePosition.second
            wm.updateViewLayout(view, params)
            captureResizeAnchorFromParams(params)
        }
        updateBubbleVisual(currentBubbleVisualState())
    }

    private fun startBubbleSizeObserver() {
        serviceScope.launch {
            overlayRepository.bubbleSizeDpFlow().collectLatest { sizeDp ->
                applyBubbleSizeDp(sizeDp)
            }
        }
    }

    private fun startBubblePositionObservers() {
        serviceScope.launch {
            overlayRepository.bubbleXFlow().collectLatest { x ->
                applyBubblePosition(targetX = x, targetY = null)
            }
        }
        serviceScope.launch {
            overlayRepository.bubbleYFlow().collectLatest { y ->
                applyBubblePosition(targetX = null, targetY = y)
            }
        }
    }

    private fun applyBubblePosition(targetX: Int?, targetY: Int?) {
        if (isBubbleDragging) return
        val view = overlayView ?: return
        val params = overlayParams ?: return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val bubbleSizePx = params.width.coerceAtLeast(1)
        val safePosition = clampBubblePosition(
            x = targetX ?: params.x,
            y = targetY ?: params.y,
            bubbleSizePx = bubbleSizePx,
            windowManager = wm
        )
        if (params.x == safePosition.first && params.y == safePosition.second) return
        params.x = safePosition.first
        params.y = safePosition.second
        wm.updateViewLayout(view, params)
        captureResizeAnchorFromParams(params)
    }

    private fun applyBubbleSizeDp(sizeDp: Int) {
        val view = overlayView ?: return
        val params = overlayParams ?: return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val newSizePx = dpToPx(sizeDp)
        val oldSizePx = params.width.coerceAtLeast(1)
        val centerX = resizeAnchorCenterX ?: (params.x + (oldSizePx / 2f))
        val centerY = resizeAnchorCenterY ?: (params.y + (oldSizePx / 2f))
        val centeredX = (centerX - (newSizePx / 2f)).roundToInt()
        val centeredY = (centerY - (newSizePx / 2f)).roundToInt()
        val safePosition = clampBubblePosition(
            x = centeredX,
            y = centeredY,
            bubbleSizePx = newSizePx,
            windowManager = wm
        )
        if (
            params.width == newSizePx &&
            params.height == newSizePx &&
            params.x == safePosition.first &&
            params.y == safePosition.second
        ) {
            return
        }
        params.width = newSizePx
        params.height = newSizePx
        params.x = safePosition.first
        params.y = safePosition.second
        wm.updateViewLayout(view, params)
        overlayRepository.setBubblePosition(params.x, params.y)
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
        isBubbleDragging = false
        clearResizeAnchor()
        val view = overlayView ?: return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        runCatching { wm.removeView(view) }
        overlayView = null
        overlayParams = null
    }

    private fun buildBubbleView(): TextView {
        val bubble = TextView(this).apply {
            text = ""
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#1B1F23"))
                setStroke(dpToPx(2), Color.parseColor("#1B1F23"))
            }
            elevation = dpToPx(10).toFloat()
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
                    if (!moved && (kotlin.math.abs(deltaX) > touchSlopPx || kotlin.math.abs(deltaY) > touchSlopPx)) {
                        moved = true
                    }
                    val bubbleSizePx = params.width.coerceAtLeast(1)
                    val safePosition = clampBubblePosition(
                        x = initialX + deltaX,
                        y = initialY + deltaY,
                        bubbleSizePx = bubbleSizePx,
                        windowManager = wm
                    )
                    params.x = safePosition.first
                    params.y = safePosition.second
                    wm.updateViewLayout(view, params)
                    true
                }

                MotionEvent.ACTION_UP -> {
                    isBubbleDragging = false
                    if (moved) {
                        overlayRepository.setBubblePosition(params.x, params.y)
                        captureResizeAnchorFromParams(params)
                    } else {
                        onBubbleTapped()
                    }
                    true
                }

                MotionEvent.ACTION_CANCEL -> {
                    isBubbleDragging = false
                    if (moved) {
                        overlayRepository.setBubblePosition(params.x, params.y)
                        captureResizeAnchorFromParams(params)
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

        val activeRecorder = recorder
        if (activeRecorder == null) {
            startRecording()
        } else {
            recorder = null
            val chunkSessionId = recorderChunkSessionId
            recorderChunkSessionId = 0
            submitProcessing(activeRecorder, chunkSessionId)
        }
    }

    private fun startRecording() {
        if (recorder != null) return
        if (!overlayRepository.hasRecordAudioPermission()) {
            showToast(getString(R.string.overlay_microphone_required))
            return
        }
        if (!isMoonshineReady()) {
            showToast(getString(R.string.overlay_asr_not_ready))
            return
        }

        startForegroundForRecording()
        val chunkSessionId = beginChunkSession()
        val audioRecorder = VoiceAudioRecorder(
            onLevelChanged = { },
            onAudioFrame = { frame ->
                enqueueMoonshineAudioFrame(chunkSessionId, frame)
            }
        )
        if (!audioRecorder.start()) {
            endChunkSession(chunkSessionId, cancelPending = true)
            stopForegroundIfNeeded()
            showToast(getString(R.string.overlay_recording_start_failed))
            return
        }
        enqueueMoonshineSessionStart(chunkSessionId)
        recorder = audioRecorder
        recorderChunkSessionId = chunkSessionId
        updateBubbleVisual(BubbleVisualState.RECORDING)
    }

    private fun submitProcessing(activeRecorder: VoiceAudioRecorder, chunkSessionId: Int) {
        updateBubbleVisual(BubbleVisualState.PROCESSING)
        try {
            inFlight = processingExecutor.submit {
                processRecording(activeRecorder, chunkSessionId)
            }
        } catch (_: RejectedExecutionException) {
            activeRecorder.stopAndGetPcm()
            endChunkSession(chunkSessionId, cancelPending = true)
            stopForegroundIfNeeded()
            updateBubbleVisual(BubbleVisualState.IDLE)
        }
    }

    private fun processRecording(activeRecorder: VoiceAudioRecorder, chunkSessionId: Int) {
        val sourceText = readFocusedInputText()
        val result = try {
            speechProcessor.process(
                request = ImeSpeechProcessorRequest(
                    recorder = activeRecorder,
                    sourceTextSnapshot = sourceText,
                    chunkSessionId = chunkSessionId
                ),
                awaitChunkSessionQuiescence = { awaitChunkSessionQuiescence(it) },
                finalizeMoonshineTranscript = { finalizeMoonshineTranscript(it) },
                onShowRewriting = {
                    mainHandler.post { updateBubbleVisual(BubbleVisualState.PROCESSING) }
                }
            )
        } catch (_: Throwable) {
            cancelPendingChunkWork(chunkSessionId)
            null
        } finally {
            endChunkSession(chunkSessionId, cancelPending = false)
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
        val text = node.text?.toString().orEmpty().trim()
        if (text.isBlank()) return ""
        if (isHintText(node, text)) return ""
        return text
    }

    private fun isHintText(node: AccessibilityNodeInfo, text: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (node.isShowingHintText) return true
        val hint = node.hintText?.toString()?.trim().orEmpty()
        if (hint.isBlank()) return false
        return text.equals(hint, ignoreCase = true)
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

    private fun beginChunkSession(): Int {
        val id = chunkSessionCounter.incrementAndGet()
        synchronized(chunkLock) {
            activeChunkSessionId = id
            activeChunkFutures.clear()
        }
        return id
    }

    private fun endChunkSession(sessionId: Int, cancelPending: Boolean) {
        synchronized(chunkLock) {
            if (sessionId == 0 || activeChunkSessionId != sessionId) return
            if (cancelPending) {
                activeChunkFutures.forEach { it.cancel(true) }
            }
            activeChunkFutures.clear()
            activeChunkSessionId = 0
        }
    }

    private fun enqueueMoonshineSessionStart(sessionId: Int) {
        if (sessionId == 0) return
        val isActive = synchronized(chunkLock) { activeChunkSessionId == sessionId }
        if (!isActive) return
        try {
            val future = chunkExecutor.submit {
                synchronized(chunkLock) {
                    if (activeChunkSessionId != sessionId) return@submit
                }
                moonshineTranscriber.startSession()
            }
            synchronized(chunkLock) {
                if (activeChunkSessionId == sessionId) {
                    activeChunkFutures.add(future)
                } else {
                    future.cancel(true)
                }
            }
        } catch (_: RejectedExecutionException) {
            // Ignore late work during shutdown.
        }
    }

    private fun enqueueMoonshineAudioFrame(sessionId: Int, pcm: ShortArray) {
        if (sessionId == 0 || pcm.isEmpty()) return
        val isActive = synchronized(chunkLock) { activeChunkSessionId == sessionId }
        if (!isActive) return
        try {
            val future = chunkExecutor.submit {
                synchronized(chunkLock) {
                    if (activeChunkSessionId != sessionId) return@submit
                }
                moonshineTranscriber.addAudio(
                    pcm = pcm,
                    sampleRateHz = VoiceAudioRecorder.SAMPLE_RATE_HZ
                )
            }
            synchronized(chunkLock) {
                if (activeChunkSessionId == sessionId) {
                    activeChunkFutures.add(future)
                } else {
                    future.cancel(true)
                }
            }
        } catch (_: RejectedExecutionException) {
            // Ignore late work during shutdown.
        }
    }

    private fun awaitChunkSessionQuiescence(sessionId: Int) {
        if (sessionId == 0) return
        val waitDeadlineMs = android.os.SystemClock.uptimeMillis() + CHUNK_WAIT_TOTAL_MS
        while (true) {
            val pending = synchronized(chunkLock) {
                if (activeChunkSessionId != sessionId) return
                activeChunkFutures.removeAll { it.isDone || it.isCancelled }
                activeChunkFutures.toList()
            }
            if (pending.isEmpty()) break
            val remainingMs = waitDeadlineMs - android.os.SystemClock.uptimeMillis()
            if (remainingMs <= 0L) {
                cancelPendingChunkWork(sessionId)
                break
            }
            var deadlineReached = false
            for (future in pending) {
                val remainingForFutureMs = waitDeadlineMs - android.os.SystemClock.uptimeMillis()
                if (remainingForFutureMs <= 0L) {
                    cancelPendingChunkWork(sessionId)
                    deadlineReached = true
                    break
                }
                val timeoutMs = minOf(remainingForFutureMs, CHUNK_WAIT_SLICE_MS)
                runCatching {
                    future.get(timeoutMs, TimeUnit.MILLISECONDS)
                }.onFailure { error ->
                    if (error is TimeoutException) return@onFailure
                    future.cancel(true)
                    moonshineTranscriber.cancelActive()
                }
            }
            if (deadlineReached) break
        }
    }

    private fun finalizeMoonshineTranscript(sessionId: Int): String {
        return try {
            val future = chunkExecutor.submit<String> {
                synchronized(chunkLock) {
                    if (activeChunkSessionId != sessionId) return@submit ""
                }
                moonshineTranscriber.stopSessionAndGetTranscript()
            }
            future.get(MOONSHINE_FINALIZE_WAIT_MS, TimeUnit.MILLISECONDS)
        } catch (_: Throwable) {
            moonshineTranscriber.cancelActive()
            ""
        }
    }

    private fun cancelPendingChunkWork(sessionId: Int) {
        synchronized(chunkLock) {
            if (activeChunkSessionId != sessionId) return
            activeChunkFutures.forEach { it.cancel(true) }
            activeChunkFutures.clear()
        }
        moonshineTranscriber.cancelActive()
    }

    private fun stopRecordingDiscard() {
        val activeRecorder = recorder ?: return
        val chunkSessionId = recorderChunkSessionId
        recorder = null
        recorderChunkSessionId = 0
        moonshineTranscriber.cancelActive()
        endChunkSession(chunkSessionId, cancelPending = true)
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
        val previewIdleColor = if (isSystemInDarkTheme()) Color.WHITE else Color.BLACK
        val color = when (state) {
            BubbleVisualState.IDLE -> if (positionPreviewActive) previewIdleColor else Color.TRANSPARENT
            BubbleVisualState.RECORDING -> Color.parseColor("#C62828")
            BubbleVisualState.PROCESSING -> Color.parseColor("#1565C0")
        }
        val background = bubble.background as? GradientDrawable ?: return
        background.setColor(color)
        val strokeColor = if (state == BubbleVisualState.IDLE && positionPreviewActive) {
            Color.parseColor("#1B1F23")
        } else {
            color
        }
        background.setStroke(dpToPx(2), strokeColor)
        bubble.text = ""
        bubble.gravity = Gravity.CENTER
        bubble.setPadding(0, 0, 0, 0)
    }

    private fun isSystemInDarkTheme(): Boolean {
        val nightMask = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return nightMask == Configuration.UI_MODE_NIGHT_YES
    }

    private fun currentBubbleVisualState(): BubbleVisualState {
        return when {
            inFlight != null -> BubbleVisualState.PROCESSING
            recorder != null -> BubbleVisualState.RECORDING
            else -> BubbleVisualState.IDLE
        }
    }

    private fun captureResizeAnchorFromParams(params: WindowManager.LayoutParams) {
        val sizePx = params.width.coerceAtLeast(1)
        resizeAnchorCenterX = params.x + (sizePx / 2f)
        resizeAnchorCenterY = params.y + (sizePx / 2f)
    }

    private fun clearResizeAnchor() {
        resizeAnchorCenterX = null
        resizeAnchorCenterY = null
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

        fun setPositionPreviewActive(context: Context, active: Boolean) {
            positionPreviewActive = active
            requestRefresh(context)
        }

        @Volatile
        private var runningService: OverlayAccessibilityService? = null
        @Volatile
        private var positionPreviewActive: Boolean = false

        private const val TAG = "OverlayService"
        private const val NOTIFICATION_CHANNEL_ID = "overlay_recording"
        private const val NOTIFICATION_ID = 12057
        private const val CHUNK_WAIT_TOTAL_MS = 7_000L
        private const val CHUNK_WAIT_SLICE_MS = 180L
        private const val MOONSHINE_FINALIZE_WAIT_MS = 4_500L
    }
}
