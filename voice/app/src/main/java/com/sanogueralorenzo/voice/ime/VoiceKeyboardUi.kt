package com.sanogueralorenzo.voice.ime

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random

private val IdleColor = Color(0xFFB7BEC6)
private val ActiveColor = Color(0xFF1A2026)
private val ActionColor = Color(0x33FFFFFF)
private val KeyboardBarColor = Color.Black
private val KeyboardBarHeight = 84.dp

private data class ActivePillVisualState(
    val mode: VoiceKeyboardMode,
    val audioLevel: Float
)

private enum class VisualizerMode {
    RECORDING_BARS,
    PROCESSING_DOTS,
    IDLE_HIDDEN
}

@Composable
fun VoiceKeyboardImeContent(
    state: VoiceKeyboardState,
    onIdleTap: () -> Unit,
    onEditTap: () -> Unit,
    onDeleteTap: () -> Unit,
    onSendTap: () -> Unit,
    onDebugToggle: () -> Unit,
    onDebugLongPress: () -> Unit,
    modifier: Modifier = Modifier
) {
    val density = LocalDensity.current
    val bottomSystemInset = with(density) { state.bottomInsetPx.toDp() }
    val keyboardContainerHeight = KeyboardBarHeight + bottomSystemInset

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(keyboardContainerHeight)
            .background(KeyboardBarColor),
        contentAlignment = if (bottomSystemInset > 0.dp) Alignment.TopCenter else Alignment.Center
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
                state.audioLevel
            ) {
                if (state.mode == VoiceKeyboardMode.IDLE) {
                    delay(IdleCollapseFadeOutMs.toLong())
                    retainedActive = null
                } else {
                    retainedActive = ActivePillVisualState(
                        mode = state.mode,
                        audioLevel = state.audioLevel
                    )
                }
            }
            val activeVisual = if (state.mode == VoiceKeyboardMode.IDLE) retainedActive else ActivePillVisualState(
                mode = state.mode,
                audioLevel = state.audioLevel
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
                Box(
                    modifier = Modifier
                        .width(width)
                        .height(PillTouchHeight)
                        .then(
                            if (state.mode == VoiceKeyboardMode.IDLE) {
                                Modifier
                            } else {
                                Modifier
                            }
                        )
                        .clickable(
                            enabled = state.mode == VoiceKeyboardMode.IDLE,
                            interactionSource = interactionSource,
                            indication = null,
                            onClick = onIdleTap
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
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
                            .clip(RoundedCornerShape(999.dp)),
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
                                        mode = activeVisual.mode,
                                        level = activeVisual.audioLevel,
                                        onDeleteTap = onDeleteTap,
                                        onSendTap = onSendTap
                                    )
                                }
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
                    active = state.inlineDebugEnabled,
                    onTap = onDebugToggle,
                    onLongPress = onDebugLongPress
                )
            }
        }
    }
}

@Composable
private fun ActivePillContent(
    mode: VoiceKeyboardMode,
    level: Float,
    onDeleteTap: () -> Unit,
    onSendTap: () -> Unit
) {
    val visualizerMode = when (mode) {
        VoiceKeyboardMode.RECORDING -> VisualizerMode.RECORDING_BARS
        VoiceKeyboardMode.PROCESSING -> VisualizerMode.PROCESSING_DOTS
        VoiceKeyboardMode.IDLE -> VisualizerMode.IDLE_HIDDEN
    }
    val isRecording = mode == VoiceKeyboardMode.RECORDING

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            ActionIconButton(
                icon = Icons.Rounded.Delete,
                contentDescription = stringResource(R.string.ime_delete_recording),
                fromStart = true,
                visible = isRecording,
                onTap = onDeleteTap
            )
            MorphingVoiceVisualizer(
                level = level,
                mode = visualizerMode
            )
            ActionIconButton(
                icon = Icons.AutoMirrored.Rounded.Send,
                contentDescription = stringResource(R.string.ime_send_recording),
                fromStart = false,
                visible = isRecording,
                onTap = onSendTap
            )
        }
    }
}

@Composable
private fun MorphingVoiceVisualizer(
    level: Float,
    mode: VisualizerMode
) {
    val normalizedLevel by rememberUpdatedState(level.coerceIn(0f, 1f))
    val bars = remember { List(BarCount) { Animatable(IdleBarFloor) } }
    val dotsTransition = rememberInfiniteTransition(label = "processing_dots")
    val dotsPhase by dotsTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = DotsCycleDurationMs, easing = LinearEasing)
        ),
        label = "processing_dots_phase"
    )

    LaunchedEffect(mode) {
        if (mode != VisualizerMode.RECORDING_BARS) {
            bars.forEach { it.snapTo(IdleBarFloor) }
            return@LaunchedEffect
        }
        val random = Random(System.currentTimeMillis())
        val idlePatternShift = random.nextInt(BarCount)
        val idlePattern = FloatArray(BarCount) { index ->
            val templateValue = IdlePatternTemplate[(index + idlePatternShift) % BarCount]
            (templateValue + ((random.nextFloat() * 2f) - 1f) * IdlePatternSeedJitter).coerceIn(IdleBarFloor, 1f)
        }
        val noise = FloatArray(BarCount)
        bars.forEachIndexed { index, bar ->
            bar.snapTo(idlePattern[index])
        }
        coroutineScope {
            while (true) {
                val talking = normalizedLevel >= TalkingThreshold
                for (i in bars.indices) {
                    val target = if (talking) {
                        noise[i] = (noise[i] * NoiseMemory + ((random.nextFloat() * 2f) - 1f) * NoiseInputRandom)
                            .coerceIn(-1f, 1f)
                        val randomHeight = TalkingBase + (random.nextFloat() * TalkingRange)
                        val jitter = noise[i] * TalkingJitter
                        (randomHeight + jitter).coerceIn(IdleBarFloor, 1f)
                    } else {
                        noise[i] = 0f
                        idlePattern[i]
                    }
                    if (!talking && abs(target - bars[i].value) < IdleSettleEpsilon) {
                        continue
                    }
                    val rising = target >= bars[i].value
                    val duration = if (rising) {
                        if (talking) TalkingAttackDurationMs else IdleSettleDurationMs
                    } else {
                        if (talking) TalkingReleaseDurationMs else IdleSettleDurationMs
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
                delay(if (talking) TalkingFrameMs else IdleFrameMs)
            }
        }
    }

    val showBars = mode == VisualizerMode.RECORDING_BARS

    Box(
        modifier = Modifier
            .height(VisualizerHeight)
            .width(VisualizerWidth),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(VisualizerHeight),
            horizontalArrangement = Arrangement.spacedBy(BarSpacing, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically
        ) {
            bars.forEachIndexed { index, bar ->
                val targetWidth = if (showBars) BarWidth else DotSize
                val width by animateDpAsState(
                    targetValue = targetWidth,
                    animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing),
                    label = "bar_width_$index"
                )
                Box(
                    modifier = Modifier
                        .width(BarSlotWidth)
                        .height(VisualizerHeight),
                    contentAlignment = Alignment.Center
                ) {
                    if (!showBars) {
                        val rise by animateDpAsState(
                            targetValue = if (mode == VisualizerMode.PROCESSING_DOTS) {
                                -(ProcessingDotJumpAmplitude * dotJumpPhase(dotsPhase, index))
                            } else {
                                0.dp
                            },
                            animationSpec = tween(durationMillis = 90, easing = LinearOutSlowInEasing),
                            label = "dot_jump_$index"
                        )
                        Box(
                            modifier = Modifier
                                .offset(y = rise)
                                .width(width)
                                .height(DotSize)
                                .clip(RoundedCornerShape(99.dp))
                                .background(Color.White)
                        )
                    } else {
                        val height = barHeightFor(bar.value)
                        Box(
                            modifier = Modifier
                                .width(width)
                                .height(height)
                                .clip(RoundedCornerShape(999.dp))
                                .background(Color.White)
                        )
                    }
                }
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
                    contentDescription = stringResource(R.string.ime_edit_instruction),
                    tint = Color.White
                )
            }
        }
    }
}

@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun IdleDebugButton(
    active: Boolean,
    onTap: () -> Unit,
    onLongPress: () -> Unit
) {
    val containerColor by animateColorAsState(
        targetValue = if (active) Color(0x52FFFFFF) else Color(0x29FFFFFF),
        animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing),
        label = "debug_container_color"
    )
    val alpha by animateFloatAsState(
        targetValue = if (active) 1f else 0.65f,
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
                .combinedClickable(
                    onClick = onTap,
                    onLongClick = onLongPress
                ),
            shape = RoundedCornerShape(999.dp),
            color = containerColor
        ) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.BugReport,
                    contentDescription = if (active) {
                        stringResource(R.string.ime_debug_disable)
                    } else {
                        stringResource(R.string.ime_debug_enable)
                    },
                    tint = Color.White
                )
            }
        }
    }
}

private fun Dp.coerceInDp(min: Dp, max: Dp): Dp {
    return when {
        this < min -> min
        this > max -> max
        else -> this
    }
}

private fun barHeightFor(value: Float): Dp {
    val clamped = value.coerceIn(IdleBarFloor, 1f)
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
private val VisualizerHeight = 34.dp
private val VisualizerWidth = 106.dp
private val BarSlotWidth = 10.dp
private val BarSpacing = 5.dp
private val BarWidth = 6.dp
private val MaxBarHeight = 24.dp
private val MinBarHeight = 8.dp
private val DotSize = 7.dp
private val ProcessingDotJumpAmplitude = 7.dp
private const val DotJumpWindow = 0.22f
private const val DotsCycleDurationMs = 920
private val IconContainerSize = 38.dp
private val IconSlotSize = 44.dp
private const val IdleBarFloor = 0.30f
private const val TalkingThreshold = 0.07f
private const val TalkingBase = 0.30f
private const val TalkingRange = 0.62f
private const val TalkingJitter = 0.15f
private const val IdlePatternSeedJitter = 0.02f
private val IdlePatternTemplate = floatArrayOf(0.36f, 0.54f, 0.42f, 0.58f, 0.46f)
private const val NoiseMemory = 0.56f
private const val NoiseInputRandom = 0.44f
private const val TalkingAttackDurationMs = 90
private const val TalkingReleaseDurationMs = 170
private const val IdleSettleDurationMs = 180
private const val IdleSettleEpsilon = 0.012f
private const val TalkingFrameMs = 80L
private const val IdleFrameMs = 120L
private const val ActiveFadeInMs = 180
private const val IdleCollapseFadeOutMs = 240
private val PillTouchHeight = 50.dp
