package com.sanogueralorenzo.voice.ime

import android.os.SystemClock
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.BugReport
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder
import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random
import java.util.Locale
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val IdleColor = Color(0xFFB7BEC6)
private val ActiveColor = Color(0xFF1A2026)
private val ActionColor = Color(0x33FFFFFF)
private val KeyboardBarColor = Color.Black
private val KeyboardBarHeight = 132.dp
private val SecondaryTextColor = Color(0xFFD5DCE3)

private data class ActivePillVisualState(
    val mode: VoiceKeyboardMode,
    val audioLevel: Float,
    val stage: VoiceProcessingStage,
    val processingStartedAtMs: Long
)

@Composable
fun VoiceKeyboardImeContent(
    state: VoiceKeyboardState,
    onIdleTap: () -> Unit,
    onEditTap: () -> Unit,
    onDeleteTap: () -> Unit,
    onSendTap: () -> Unit,
    onDebugTap: () -> Unit,
    onDebugDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(KeyboardBarHeight)
            .background(KeyboardBarColor),
        contentAlignment = Alignment.Center
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .height(KeyboardBarHeight),
            contentAlignment = Alignment.Center
        ) {
            val targetWidth = when (state.mode) {
                VoiceKeyboardMode.IDLE -> (maxWidth * 0.38f).coerceInDp(120.dp, 220.dp)
                VoiceKeyboardMode.RECORDING -> (maxWidth * 0.92f).coerceAtMost(420.dp)
                VoiceKeyboardMode.PROCESSING -> (maxWidth * 0.84f).coerceInDp(230.dp, 380.dp)
            }
            val idleHeight = 14.dp
            val idleHeightAnimated by animateDpAsState(
                targetValue = if (state.mode == VoiceKeyboardMode.IDLE) idleHeight else 0.dp,
                animationSpec = spring(
                    dampingRatio = 0.9f,
                    stiffness = 500f
                ),
                label = "pill_idle_height"
            )

            val width by animateDpAsState(
                targetValue = targetWidth,
                animationSpec = spring(
                    dampingRatio = 0.88f,
                    stiffness = 460f
                ),
                label = "pill_width"
            )
            val pillColor by animateColorAsState(
                targetValue = if (state.mode == VoiceKeyboardMode.IDLE) IdleColor else ActiveColor,
                animationSpec = tween(durationMillis = 280, easing = FastOutSlowInEasing),
                label = "pill_color"
            )
            var retainedActive by remember { mutableStateOf<ActivePillVisualState?>(null) }
            LaunchedEffect(
                state.mode,
                state.audioLevel,
                state.stage,
                state.processingStartedAtMs
            ) {
                if (state.mode == VoiceKeyboardMode.IDLE) {
                    delay(IdleCollapseFadeOutMs.toLong())
                    retainedActive = null
                } else {
                    retainedActive = ActivePillVisualState(
                        mode = state.mode,
                        audioLevel = state.audioLevel,
                        stage = state.stage,
                        processingStartedAtMs = state.processingStartedAtMs
                    )
                }
            }
            val activeVisual = if (state.mode == VoiceKeyboardMode.IDLE) retainedActive else ActivePillVisualState(
                mode = state.mode,
                audioLevel = state.audioLevel,
                stage = state.stage,
                processingStartedAtMs = state.processingStartedAtMs
            )
            val activeContentAlpha by animateFloatAsState(
                targetValue = if (state.mode == VoiceKeyboardMode.IDLE) 0f else 1f,
                animationSpec = tween(
                    durationMillis = if (state.mode == VoiceKeyboardMode.IDLE) IdleCollapseFadeOutMs else ActiveFadeInMs,
                    easing = FastOutSlowInEasing
                ),
                label = "active_content_alpha"
            )

            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                val interactionSource = remember { MutableInteractionSource() }
                Surface(
                    modifier = Modifier
                        .width(width)
                        .then(
                            if (state.mode == VoiceKeyboardMode.IDLE) {
                                Modifier.height(idleHeightAnimated.coerceAtLeast(1.dp))
                            } else {
                                Modifier
                            }
                        )
                        .animateContentSize(
                            animationSpec = spring(
                                dampingRatio = 0.9f,
                                stiffness = 520f
                            )
                        )
                        .clip(RoundedCornerShape(999.dp))
                        .clickable(
                            enabled = state.mode == VoiceKeyboardMode.IDLE,
                            interactionSource = interactionSource,
                            indication = null,
                            onClick = onIdleTap
                        ),
                    color = pillColor,
                    shape = RoundedCornerShape(999.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .wrapContentHeight(),
                        contentAlignment = Alignment.Center
                    ) {
                        if (activeVisual != null) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .graphicsLayer { alpha = activeContentAlpha }
                            ) {
                                ActivePillContent(
                                    isRecording = activeVisual.mode == VoiceKeyboardMode.RECORDING,
                                    level = activeVisual.audioLevel,
                                    stage = activeVisual.stage,
                                    processingStartedAtMs = activeVisual.processingStartedAtMs,
                                    onDeleteTap = onDeleteTap,
                                    onSendTap = onSendTap
                                )
                            }
                        }
                    }
                }
            }

            if (state.mode == VoiceKeyboardMode.IDLE) {
                IdleEditButton(
                    visible = state.canEditCurrentInput,
                    onTap = onEditTap
                )
                IdleDebugButton(
                    hasMetrics = state.lastDebugMetrics != null,
                    onTap = onDebugTap
                )
            }
        }
    }

    if (state.debugDialogVisible) {
        DebugMetricsDialog(
            metrics = state.lastDebugMetrics,
            onDismiss = onDebugDismiss
        )
    }
}

@Composable
private fun ActivePillContent(
    isRecording: Boolean,
    level: Float,
    stage: VoiceProcessingStage,
    processingStartedAtMs: Long,
    onDeleteTap: () -> Unit,
    onSendTap: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = if (isRecording) 11.dp else 9.dp),
        verticalArrangement = Arrangement.spacedBy(if (isRecording) 0.dp else 5.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            ActionIconButton(
                icon = Icons.Rounded.Delete,
                contentDescription = "Delete recording",
                fromStart = true,
                visible = isRecording,
                onTap = onDeleteTap
            )
            MorphingVoiceVisualizer(
                level = level,
                loading = !isRecording
            )
            ActionIconButton(
                icon = Icons.AutoMirrored.Rounded.Send,
                contentDescription = "Send recording",
                fromStart = false,
                visible = isRecording,
                onTap = onSendTap
            )
        }
        if (!isRecording) {
            ProcessingStatusLabel(
                stage = stage,
                processingStartedAtMs = processingStartedAtMs
            )
        }
    }
}

@Composable
private fun ProcessingStatusLabel(
    stage: VoiceProcessingStage,
    processingStartedAtMs: Long
) {
    val elapsedSeconds by produceState(initialValue = 0, key1 = processingStartedAtMs) {
        if (processingStartedAtMs <= 0L) {
            value = 0
            return@produceState
        }
        while (true) {
            value = ((SystemClock.elapsedRealtime() - processingStartedAtMs) / 1000L).toInt()
            delay(250L)
        }
    }
    val label = if (stage == VoiceProcessingStage.TRANSCRIBING) {
        "Transcribing"
    } else {
        "Rewriting"
    }
    Text(
        modifier = Modifier.fillMaxWidth(),
        text = "$label \u00b7 ${formatElapsed(elapsedSeconds)}",
        color = SecondaryTextColor,
        textAlign = TextAlign.Center,
        fontWeight = FontWeight.Medium
    )
}

@Composable
private fun MorphingVoiceVisualizer(
    level: Float,
    loading: Boolean
) {
    val normalizedLevel by rememberUpdatedState(level.coerceIn(0f, 1f))
    val bars = remember { List(BarCount) { Animatable(IdleBarFloor) } }
    val dotsTransition = rememberInfiniteTransition(label = "dots")
    val dotsPhase by dotsTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = DotsCycleDurationMs, easing = LinearEasing)
        ),
        label = "dots_phase"
    )

    LaunchedEffect(loading) {
        if (loading) {
            return@LaunchedEffect
        }
        val random = Random(SystemClock.uptimeMillis())
        val noise = FloatArray(BarCount)
        while (true) {
            val talking = normalizedLevel >= TalkingThreshold
            coroutineScope {
                for (i in 0 until BarCount) {
                    noise[i] = (noise[i] * NoiseMemory + ((random.nextFloat() * 2f) - 1f) * NoiseInputRandom)
                        .coerceIn(-1f, 1f)
                    val randomHeight = if (talking) {
                        TalkingBase + (random.nextFloat() * TalkingRange)
                    } else {
                        IdleBase + (random.nextFloat() * IdleRange)
                    }
                    val jitter = noise[i] * if (talking) TalkingJitter else IdleJitter
                    val target = (randomHeight + jitter).coerceIn(IdleBarFloor, 1f)
                    val rising = target >= bars[i].value
                    val duration = if (rising) {
                        if (talking) TalkingAttackDurationMs else IdleAttackDurationMs
                    } else {
                        if (talking) TalkingReleaseDurationMs else IdleReleaseDurationMs
                    }
                    launch {
                        bars[i].animateTo(
                            targetValue = target,
                            animationSpec = tween(
                                durationMillis = duration,
                                easing = if (rising) FastOutLinearInEasing else LinearOutSlowInEasing
                            )
                        )
                    }
                }
            }
            delay(if (talking) TalkingFrameMs else IdleFrameMs)
        }
    }

    Box(
        modifier = Modifier
            .height(44.dp)
            .width(106.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.Bottom
        ) {
            bars.forEachIndexed { index, bar ->
                val targetWidth = if (loading) DotSize else BarWidth
                val targetHeight = if (loading) {
                    DotSize
                } else {
                    barHeightFor(bar.value)
                }
                val rise by animateDpAsState(
                    targetValue = if (loading) -(DotJumpAmplitude * dotJumpPhase(dotsPhase, index)) else 0.dp,
                    animationSpec = tween(durationMillis = 90, easing = LinearOutSlowInEasing),
                    label = "dot_jump_$index"
                )
                val width by animateDpAsState(
                    targetValue = targetWidth,
                    animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing),
                    label = "bar_width_$index"
                )
                val height by animateDpAsState(
                    targetValue = targetHeight,
                    animationSpec = tween(durationMillis = 200, easing = FastOutSlowInEasing),
                    label = "bar_height_$index"
                )
                Box(
                    modifier = Modifier
                        .offset(y = rise)
                        .width(width)
                        .height(height)
                        .clip(RoundedCornerShape(99.dp))
                        .background(Color.White)
                )
            }
        }
    }
}

@Composable
private fun ActionIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    fromStart: Boolean,
    visible: Boolean,
    onTap: () -> Unit
) {
    val slotWidth by animateDpAsState(
        targetValue = if (visible) IconSlotSize else 0.dp,
        animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing),
        label = "action_slot"
    )
    val alpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(durationMillis = 160, easing = LinearOutSlowInEasing),
        label = "action_alpha"
    )
    val scale by animateFloatAsState(
        targetValue = if (visible) 1f else 0.86f,
        animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing),
        label = "action_scale"
    )
    val offsetX by animateDpAsState(
        targetValue = if (visible) 0.dp else if (fromStart) (-10).dp else 10.dp,
        animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing),
        label = "action_offset"
    )

    Box(
        modifier = Modifier
            .width(slotWidth)
            .height(IconContainerSize),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            modifier = Modifier
                .size(IconContainerSize)
                .offset(x = offsetX)
                .graphicsLayer {
                    this.alpha = alpha
                    scaleX = scale
                    scaleY = scale
                }
                .clip(RoundedCornerShape(999.dp))
                .clickable(enabled = visible, onClick = onTap),
            shape = RoundedCornerShape(999.dp),
            color = ActionColor
        ) {
            Box(
                modifier = Modifier.size(IconContainerSize),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = contentDescription,
                    tint = Color.White
                )
            }
        }
    }
}

@Composable
private fun IdleEditButton(
    visible: Boolean,
    onTap: () -> Unit
) {
    val alpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing),
        label = "edit_alpha"
    )
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 18.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        Surface(
            modifier = Modifier
                .size(34.dp)
                .graphicsLayer { this.alpha = alpha }
                .clip(RoundedCornerShape(999.dp))
                .clickable(enabled = visible, onClick = onTap),
            shape = RoundedCornerShape(999.dp),
            color = Color(0x29FFFFFF)
        ) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.Edit,
                    contentDescription = "Edit current text with voice instruction",
                    tint = Color.White
                )
            }
        }
    }
}

@Composable
private fun IdleDebugButton(
    hasMetrics: Boolean,
    onTap: () -> Unit
) {
    val alpha by animateFloatAsState(
        targetValue = if (hasMetrics) 1f else 0.45f,
        animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing),
        label = "debug_alpha"
    )
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(end = 18.dp),
        contentAlignment = Alignment.CenterEnd
    ) {
        Surface(
            modifier = Modifier
                .size(34.dp)
                .graphicsLayer { this.alpha = alpha }
                .clip(RoundedCornerShape(999.dp))
                .clickable(enabled = hasMetrics, onClick = onTap),
            shape = RoundedCornerShape(999.dp),
            color = Color(0x29FFFFFF)
        ) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.BugReport,
                    contentDescription = "Show debug metrics",
                    tint = Color.White
                )
            }
        }
    }
}

@Composable
private fun DebugMetricsDialog(
    metrics: VoiceDebugMetrics?,
    onDismiss: () -> Unit
) {
    val body = remember(metrics) {
        if (metrics == null) {
            "No sent-message metrics yet."
        } else {
            buildString {
                appendLine("Session: ${metrics.sessionId}")
                appendLine("Path: ${metrics.transcriptionPath.name}")
                appendLine("Committed: ${if (metrics.committed) "yes" else "no"}")
                appendLine("Total: ${metrics.totalMs} ms")
                appendLine("Transcribe: ${metrics.transcribeMs} ms")
                appendLine("  chunk wait: ${metrics.chunkWaitMs} ms")
                appendLine("  stream finalize: ${metrics.streamingFinalizeMs} ms")
                appendLine("  one-shot fallback: ${metrics.oneShotMs} ms")
                appendLine("Rewrite: ${metrics.rewriteMs} ms")
                appendLine("  attempted: ${if (metrics.rewriteAttempted) "yes" else "no"}")
                appendLine("  applied: ${if (metrics.rewriteApplied) "yes" else "no"}")
                if (!metrics.rewriteFallbackReason.isNullOrBlank()) {
                    appendLine("  fallback reason: ${metrics.rewriteFallbackReason}")
                }
                appendLine("Audio: ${metrics.inputSamples} samples (${approxAudioSeconds(metrics.inputSamples)} s)")
                append("Chars: transcript=${metrics.transcriptChars}, output=${metrics.outputChars}")
            }
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Close")
            }
        },
        title = {
            Text(
                text = "Last sent message debug",
                fontWeight = FontWeight.SemiBold
            )
        },
        text = {
            Text(text = body)
        }
    )
}

private fun Dp.coerceInDp(min: Dp, max: Dp): Dp {
    return when {
        this < min -> min
        this > max -> max
        else -> this
    }
}

private fun formatElapsed(elapsedSeconds: Int): String {
    val safe = elapsedSeconds.coerceAtLeast(0)
    val minutes = safe / 60
    val seconds = safe % 60
    return "%02d:%02d".format(minutes, seconds)
}

private fun approxAudioSeconds(samples: Int): String {
    val seconds = (samples.coerceAtLeast(0).toDouble() / VoiceAudioRecorder.SAMPLE_RATE_HZ.toDouble())
    return String.format(Locale.US, "%.2f", seconds)
}

private fun barHeightFor(value: Float): Dp {
    val clamped = value.coerceIn(0f, 1f)
    return MinBarHeight + ((MaxBarHeight - MinBarHeight) * clamped)
}

private fun dotJumpPhase(phase: Float, index: Int): Float {
    val start = index.toFloat() / BarCount.toFloat()
    val end = start + DotJumpWindow
    val local = when {
        phase in start..end -> (phase - start) / DotJumpWindow
        end > 1f && phase < (end - 1f) -> (phase + 1f - start) / DotJumpWindow
        else -> return 0f
    }
    return sin(local * PI).toFloat().coerceIn(0f, 1f)
}

private const val BarCount = 5
private val BarWidth = 8.dp
private val MinBarHeight = 8.dp
private val MaxBarHeight = 42.dp
private val DotSize = 8.dp
private val DotJumpAmplitude = 9.dp
private const val DotJumpWindow = 0.22f
private const val DotsCycleDurationMs = 920
private val IconContainerSize = 38.dp
private val IconSlotSize = 44.dp
private const val IdleBarFloor = 0.18f
private const val TalkingThreshold = 0.07f
private const val TalkingBase = 0.30f
private const val TalkingRange = 0.62f
private const val IdleBase = 0.20f
private const val IdleRange = 0.14f
private const val TalkingJitter = 0.15f
private const val IdleJitter = 0.06f
private const val NoiseMemory = 0.56f
private const val NoiseInputRandom = 0.44f
private const val TalkingAttackDurationMs = 90
private const val TalkingReleaseDurationMs = 170
private const val IdleAttackDurationMs = 140
private const val IdleReleaseDurationMs = 220
private const val TalkingFrameMs = 80L
private const val IdleFrameMs = 120L
private const val ActiveFadeInMs = 180
private const val IdleCollapseFadeOutMs = 240
