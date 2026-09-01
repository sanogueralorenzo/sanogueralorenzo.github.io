package com.sanogueralorenzo.voice.keyboard

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

internal enum class KeyboardVisualizerMode {
    RECORDING_BARS,
    PROCESSING_DOTS,
    IDLE_HIDDEN
}

@Composable
internal fun KeyboardVisualizer(
    level: Float,
    mode: KeyboardVisualizerMode,
    color: Color,
    modifier: Modifier = Modifier
) {
    val normalizedLevel by rememberUpdatedState(level.coerceIn(0f, 1f))
    val bars = remember { List(BAR_COUNT) { androidx.compose.animation.core.Animatable(IDLE_BAR_FLOOR) } }
    val dotsTransition = rememberInfiniteTransition(label = "processing_dots")
    val dotsPhase by dotsTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = DOTS_CYCLE_DURATION_MS, easing = LinearEasing)
        ),
        label = "processing_dots_phase"
    )

    LaunchedEffect(mode) {
        if (mode != KeyboardVisualizerMode.RECORDING_BARS) {
            bars.forEach { it.snapTo(IDLE_BAR_FLOOR) }
            return@LaunchedEffect
        }
        val random = Random(System.currentTimeMillis())
        val idlePatternShift = random.nextInt(BAR_COUNT)
        val idlePattern = FloatArray(BAR_COUNT) { index ->
            val templateValue = IDLE_PATTERN_TEMPLATE[(index + idlePatternShift) % BAR_COUNT]
            (templateValue + ((random.nextFloat() * 2f) - 1f) * IDLE_PATTERN_SEED_JITTER)
                .coerceIn(IDLE_BAR_FLOOR, 1f)
        }
        val noise = FloatArray(BAR_COUNT)
        bars.forEachIndexed { index, bar -> bar.snapTo(idlePattern[index]) }
        coroutineScope {
            while (true) {
                val talking = normalizedLevel >= TALKING_THRESHOLD
                for (index in bars.indices) {
                    val target = if (talking) {
                        noise[index] = (
                            noise[index] * NOISE_MEMORY +
                                ((random.nextFloat() * 2f) - 1f) * NOISE_INPUT_RANDOM
                            ).coerceIn(-1f, 1f)
                        (
                            TALKING_BASE +
                                random.nextFloat() * TALKING_RANGE +
                                noise[index] * TALKING_JITTER
                            ).coerceIn(IDLE_BAR_FLOOR, 1f)
                    } else {
                        noise[index] = 0f
                        idlePattern[index]
                    }
                    if (!talking && abs(target - bars[index].value) < IDLE_SETTLE_EPSILON) continue
                    val rising = target >= bars[index].value
                    val duration = when {
                        talking && rising -> TALKING_ATTACK_DURATION_MS
                        talking -> TALKING_RELEASE_DURATION_MS
                        else -> IDLE_SETTLE_DURATION_MS
                    }
                    launch {
                        bars[index].animateTo(
                            targetValue = target,
                            animationSpec = tween(
                                durationMillis = duration,
                                easing = if (rising) FastOutLinearInEasing else LinearOutSlowInEasing
                            )
                        )
                    }
                }
                delay(if (talking) TALKING_FRAME_MS else IDLE_FRAME_MS)
            }
        }
    }

    val showBars = mode == KeyboardVisualizerMode.RECORDING_BARS
    Box(
        modifier = modifier
            .height(VISUALIZER_HEIGHT)
            .width(VISUALIZER_WIDTH),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(VISUALIZER_HEIGHT),
            horizontalArrangement = Arrangement.spacedBy(BAR_SPACING, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically
        ) {
            bars.forEachIndexed { index, bar ->
                val targetWidth = if (showBars) BAR_WIDTH else DOT_SIZE
                val width by animateDpAsState(
                    targetValue = targetWidth,
                    animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing),
                    label = "bar_width_$index"
                )
                Box(
                    modifier = Modifier
                        .width(BAR_SLOT_WIDTH)
                        .height(VISUALIZER_HEIGHT),
                    contentAlignment = Alignment.Center
                ) {
                    if (showBars) {
                        Box(
                            modifier = Modifier
                                .width(width)
                                .height(barHeightFor(bar.value))
                                .clip(RoundedCornerShape(999.dp))
                                .background(color)
                        )
                    } else {
                        val rise by animateDpAsState(
                            targetValue = if (mode == KeyboardVisualizerMode.PROCESSING_DOTS) {
                                -(PROCESSING_DOT_JUMP_AMPLITUDE * dotJumpPhase(dotsPhase, index))
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
                                .height(DOT_SIZE)
                                .clip(RoundedCornerShape(99.dp))
                                .background(color)
                        )
                    }
                }
            }
        }
    }
}

private fun barHeightFor(value: Float): Dp {
    val clamped = value.coerceIn(IDLE_BAR_FLOOR, 1f)
    return MIN_BAR_HEIGHT + ((MAX_BAR_HEIGHT - MIN_BAR_HEIGHT) * clamped)
}

private fun dotJumpPhase(phase: Float, index: Int): Float {
    val start = index.toFloat() / BAR_COUNT.toFloat()
    val end = start + DOT_JUMP_WINDOW
    val local = when {
        phase in start..end -> (phase - start) / DOT_JUMP_WINDOW
        end > 1f && phase < end - 1f -> (phase + 1f - start) / DOT_JUMP_WINDOW
        else -> return 0f
    }
    return sin(local * PI).toFloat().coerceIn(0f, 1f)
}

internal val KeyboardVisualizerWidth = 106.dp

private const val BAR_COUNT = 5
private val VISUALIZER_HEIGHT = 34.dp
private val VISUALIZER_WIDTH = KeyboardVisualizerWidth
private val BAR_SLOT_WIDTH = 10.dp
private val BAR_SPACING = 5.dp
private val BAR_WIDTH = 6.dp
private val MAX_BAR_HEIGHT = 24.dp
private val MIN_BAR_HEIGHT = 8.dp
private val DOT_SIZE = 7.dp
private val PROCESSING_DOT_JUMP_AMPLITUDE = 7.dp
private const val DOT_JUMP_WINDOW = 0.22f
private const val DOTS_CYCLE_DURATION_MS = 920
private const val IDLE_BAR_FLOOR = 0.30f
private const val TALKING_THRESHOLD = 0.07f
private const val TALKING_BASE = 0.30f
private const val TALKING_RANGE = 0.62f
private const val TALKING_JITTER = 0.15f
private const val IDLE_PATTERN_SEED_JITTER = 0.02f
private val IDLE_PATTERN_TEMPLATE = floatArrayOf(0.36f, 0.54f, 0.42f, 0.58f, 0.46f)
private const val NOISE_MEMORY = 0.56f
private const val NOISE_INPUT_RANDOM = 0.44f
private const val TALKING_ATTACK_DURATION_MS = 90
private const val TALKING_RELEASE_DURATION_MS = 170
private const val IDLE_SETTLE_DURATION_MS = 180
private const val IDLE_SETTLE_EPSILON = 0.012f
private const val TALKING_FRAME_MS = 80L
private const val IDLE_FRAME_MS = 120L
