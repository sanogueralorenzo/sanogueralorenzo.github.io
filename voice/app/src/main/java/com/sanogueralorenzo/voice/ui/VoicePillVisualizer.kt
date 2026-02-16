package com.sanogueralorenzo.voice.ui

import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random

enum class VoiceVisualizerMode {
    RECORDING_BARS,
    PROCESSING_DOTS,
    IDLE_HIDDEN
}

@Composable
fun VoicePillVisualizer(
    level: Float,
    mode: VoiceVisualizerMode,
    modifier: Modifier = Modifier
) {
    val normalizedLevel by rememberUpdatedState(level.coerceIn(0f, 1f))
    val bars = remember { List(BarCount) { androidx.compose.animation.core.Animatable(IdleBarFloor) } }
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
        if (mode != VoiceVisualizerMode.RECORDING_BARS) {
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

    val showBars = mode == VoiceVisualizerMode.RECORDING_BARS
    Box(
        modifier = modifier
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
                            targetValue = if (mode == VoiceVisualizerMode.PROCESSING_DOTS) {
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

val VoicePillVisualizerWidth = 106.dp

private const val BarCount = 5
private val VisualizerHeight = 34.dp
private val VisualizerWidth = VoicePillVisualizerWidth
private val BarSlotWidth = 10.dp
private val BarSpacing = 5.dp
private val BarWidth = 6.dp
private val MaxBarHeight = 24.dp
private val MinBarHeight = 8.dp
private val DotSize = 7.dp
private val ProcessingDotJumpAmplitude = 7.dp
private const val DotJumpWindow = 0.22f
private const val DotsCycleDurationMs = 920
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
