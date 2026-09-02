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
import android.database.ContentObserver
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.audio.DictationLanguage
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
import com.sanogueralorenzo.voice.audio.MoonshineMicTranscriber
import com.sanogueralorenzo.voice.dictation.DictationSession
import com.sanogueralorenzo.voice.keyboard.VoiceKeyboardStatusReader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class OverlayAccessibilityService : AccessibilityService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var activeRecording: OverlayRecording? = null

    private var overlayView: TextView? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var systemDialogReceiverRegistered = false
    private var imeSettingsObserverRegistered = false
    private var keyboardCloseStopScheduled = false
    private val keyboardCloseStopRunnable = Runnable {
        keyboardCloseStopScheduled = false
        if (!isInputMethodWindowVisible()) {
            stopRecordingAndProcess()
            evaluateOverlayVisibility()
        }
    }

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

    private val overlayRepository by lazy(LazyThreadSafetyMode.NONE) {
        OverlayRepository(context = applicationContext)
    }
    private val languagePreferences by lazy(LazyThreadSafetyMode.NONE) {
        DictationLanguagePreferences(this)
    }
    private val dictationSession by lazy(LazyThreadSafetyMode.NONE) {
        DictationSession(
            transcriber = MoonshineMicTranscriber(this),
            listener = object : DictationSession.Listener {
                override fun onTextChanged(text: String) {
                    replaceFocusedInputText(text)
                }

                override fun onCompleted(result: DictationSession.Result) {
                    activeRecording = null
                    if (result.hasTranscript && !replaceFocusedInputText(result.text)) {
                        showToast(getString(R.string.overlay_commit_failed))
                    }
                    stopForegroundIfNeeded()
                    evaluateOverlayVisibility()
                }

                override fun onCancelled() {
                    restoreOriginalText()
                    stopForegroundIfNeeded()
                    evaluateOverlayVisibility()
                }

                override fun onError(error: Throwable?) {
                    if (error != null) {
                        android.util.Log.w(TAG, "Moonshine overlay recording failed", error)
                    }
                    restoreOriginalText()
                    stopForegroundIfNeeded()
                    evaluateOverlayVisibility()
                    showToast(getString(R.string.overlay_recording_start_failed))
                }
            }
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
        warmupMoonshine()
        serviceScope.launch {
            overlayRepository.readConfig()
            evaluateOverlayVisibility()
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        evaluateOverlayVisibility()
    }

    override fun onKeyEvent(event: KeyEvent?): Boolean {
        if (event?.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_BACK) {
            stopRecordingAndProcess()
        }
        return super.onKeyEvent(event)
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (runningService === this) {
            runningService = null
        }
        serviceScope.cancel()
        cancelKeyboardCloseStop()
        unregisterSystemDialogReceiverIfNeeded()
        unregisterImeSettingsObserverIfNeeded()
        stopForegroundIfNeeded()
        activeRecording?.let { replaceFocusedInputText(it.originalText) }
        activeRecording = null
        dictationSession.destroy()
        hideBubble()
        super.onDestroy()
    }

    private fun evaluateOverlayVisibility() {
        val config = overlayRepository.currentConfig()
        val inputMethodVisible = isInputMethodWindowVisible()
        if (inputMethodVisible || !dictationSession.isActive) {
            cancelKeyboardCloseStop()
        } else {
            scheduleKeyboardCloseStop()
        }
        val shouldShowByContext = config.overlayEnabled &&
            inputMethodVisible &&
            !positioningActive &&
            !VoiceKeyboardStatusReader.read(this).selected
        val shouldKeepVisibleForActiveWork = dictationSession.isActive
        val shouldShow = shouldShowByContext || shouldKeepVisibleForActiveWork

        if (shouldShow) {
            showOrUpdateBubble(config)
        } else {
            hideBubble()
        }
    }

    private fun isInputMethodWindowVisible(): Boolean {
        return windows.any { window ->
            window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
        }
    }

    private fun scheduleKeyboardCloseStop() {
        if (keyboardCloseStopScheduled) return
        keyboardCloseStopScheduled = true
        mainHandler.postDelayed(keyboardCloseStopRunnable, KEYBOARD_CLOSE_CONFIRMATION_MS)
    }

    private fun cancelKeyboardCloseStop() {
        if (!keyboardCloseStopScheduled) return
        mainHandler.removeCallbacks(keyboardCloseStopRunnable)
        keyboardCloseStopScheduled = false
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
            ContextCompat.registerReceiver(
                this,
                systemDialogReceiver,
                filter,
                ContextCompat.RECEIVER_EXPORTED
            )
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
        val configuredPosition = if (config.hasCustomBubblePosition) {
            config.bubbleX to config.bubbleY
        } else {
            defaultBubblePosition(bubbleSizePx = bubbleSizePx, windowManager = wm)
        }
        val safePosition = clampBubblePosition(
            x = configuredPosition.first,
            y = configuredPosition.second,
            bubbleSizePx = bubbleSizePx,
            windowManager = wm
        )
        if (config.hasCustomBubblePosition) {
            if (safePosition.first != config.bubbleX || safePosition.second != config.bubbleY) {
                overlayRepository.setBubblePosition(safePosition.first, safePosition.second)
            }
        } else {
            overlayRepository.setDefaultBubblePosition(safePosition.first, safePosition.second)
        }
        val view = overlayView
        if (view == null) {
            val bubble = buildBubbleView()
            val params = WindowManager.LayoutParams(
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
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setFitInsetsTypes(0)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                }
            }
            wm.addView(bubble, params)
            overlayView = bubble
            overlayParams = params
            updateBubbleVisual()
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
        }
        updateBubbleVisual()
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
    }

    private fun applyBubbleSizeDp(sizeDp: Int) {
        if (overlayView == null || overlayParams == null) return
        val config = overlayRepository.currentConfig()
        showOrUpdateBubble(config.copy(bubbleSizeDp = sizeDp))
    }

    private fun clampBubblePosition(
        x: Int,
        y: Int,
        bubbleSizePx: Int,
        windowManager: WindowManager
    ): Pair<Int, Int> {
        val displaySize = displaySize(windowManager)
        val maxX = (displaySize.x - bubbleSizePx).coerceAtLeast(0)
        val maxY = (displaySize.y - bubbleSizePx).coerceAtLeast(0)
        return x.coerceIn(0, maxX) to y.coerceIn(0, maxY)
    }

    private fun defaultBubblePosition(
        bubbleSizePx: Int,
        windowManager: WindowManager
    ): Pair<Int, Int> {
        val displaySize = displaySize(windowManager)
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
            density = resources.displayMetrics.density
        )
    }

    private fun visibleInputMethodTopPx(): Int? {
        val inputMethodWindow = windows.firstOrNull { window ->
            window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
        } ?: return null
        val bounds = Rect()
        inputMethodWindow.getBoundsInScreen(bounds)
        return bounds.top.takeIf { bounds.height() > 0 }
    }

    private fun displaySize(windowManager: WindowManager): Point {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            Point(bounds.width(), bounds.height())
        } else {
            @Suppress("DEPRECATION")
            Point().also { point -> windowManager.defaultDisplay.getRealSize(point) }
        }
    }

    private fun hideBubble() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        overlayView?.let { view ->
            view.animate().cancel()
            runCatching { wm.removeView(view) }
        }
        overlayView = null
        overlayParams = null
    }

    private fun buildBubbleView(): TextView {
        return TextView(this).apply {
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
            setOnClickListener { onBubbleTapped() }
            setOnLongClickListener {
                if (!dictationSession.isActive) {
                    startRecording(languagePreferences.secondaryOrPrimary())
                    true
                } else {
                    false
                }
            }
        }
    }

    private fun onBubbleTapped() {
        if (!dictationSession.isActive) {
            startRecording(languagePreferences.primary())
        } else if (dictationSession.state == DictationSession.State.RECORDING) {
            stopRecordingAndProcess()
        }
    }

    private fun stopRecordingAndProcess(): Boolean {
        cancelKeyboardCloseStop()
        return dictationSession.stop()
    }

    private fun startRecording(language: DictationLanguage) {
        if (dictationSession.isActive || activeRecording != null) return
        if (!overlayRepository.hasRecordAudioPermission()) {
            showToast(getString(R.string.overlay_microphone_required))
            return
        }
        if (!dictationSession.isReady(language)) {
            showToast(getString(R.string.overlay_asr_not_ready))
            return
        }

        val originalText = readFocusedInputText()
        activeRecording = OverlayRecording(originalText)
        startForegroundForRecording()
        if (!dictationSession.start(language = language, originalText = originalText)) {
            activeRecording = null
            stopForegroundIfNeeded()
        }
    }

    private fun warmupMoonshine() {
        dictationSession.warmup(languagePreferences.primary())
    }

    private fun readFocusedInputText(): String {
        val node = findFocusedEditableNode() ?: return ""
        val text = node.text?.toString().orEmpty().trim()
        if (text.isBlank()) return ""
        if (isHintText(node, text)) return ""
        return text
    }

    private fun isHintText(node: AccessibilityNodeInfo, text: String): Boolean {
        val showingHintText = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            node.isShowingHintText
        val hintText = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            node.hintText?.toString()
        } else {
            null
        }
        return textRepresentsHint(
            text = text,
            showingHintText = showingHintText,
            hintText = hintText,
            hasEditableContent = { selectionConfirmsEditableContent(node, text.length) }
        )
    }

    private fun selectionConfirmsEditableContent(
        node: AccessibilityNodeInfo,
        textLength: Int
    ): Boolean {
        val originalStart = node.textSelectionStart
        val originalEnd = node.textSelectionEnd
        if (originalStart == textLength && originalEnd == textLength) return true

        val supportsSelection = node.actionList.any { action ->
            action.id == AccessibilityNodeInfo.ACTION_SET_SELECTION
        }
        if (!supportsSelection) return true

        val moveToEndArgs = Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, textLength)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, textLength)
        }
        if (!node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, moveToEndArgs)) {
            return false
        }

        val refreshed = node.refresh()
        val reachesReportedTextEnd = !refreshed ||
            (node.textSelectionStart == textLength && node.textSelectionEnd == textLength)

        if (originalStart >= 0 && originalEnd >= 0) {
            val restoreArgs = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, originalStart)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, originalEnd)
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, restoreArgs)
        }
        return reachesReportedTextEnd
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

    private fun stopRecordingDiscard() {
        dictationSession.cancel()
    }

    private fun restoreOriginalText() {
        val recording = activeRecording ?: return
        activeRecording = null
        replaceFocusedInputText(recording.originalText)
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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
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
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun updateBubbleVisual() {
        val bubble = overlayView ?: return
        val background = bubble.background as? GradientDrawable ?: return
        background.setColor(Color.TRANSPARENT)
        background.setStroke(dpToPx(2), Color.TRANSPARENT)
        bubble.elevation = 0f
        bubble.text = ""
        bubble.gravity = Gravity.CENTER
        bubble.setPadding(0, 0, 0, 0)
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

    private data class OverlayRecording(val originalText: String)

    companion object {
        fun setPositioningActive(active: Boolean) {
            if (positioningActive == active) return
            positioningActive = active
            runningService?.mainHandler?.post {
                runningService?.evaluateOverlayVisibility()
            }
        }

        @Volatile
        private var runningService: OverlayAccessibilityService? = null
        @Volatile
        private var positioningActive: Boolean = false

        private const val NOTIFICATION_CHANNEL_ID = "overlay_recording"
        private const val NOTIFICATION_ID = 12057
        private const val KEYBOARD_CLOSE_CONFIRMATION_MS = 200L
        private const val TAG = "VoiceOverlay"
    }
}
