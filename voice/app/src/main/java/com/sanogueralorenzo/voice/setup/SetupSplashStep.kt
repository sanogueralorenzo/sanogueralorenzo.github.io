package com.sanogueralorenzo.voice.setup

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.times
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.random.Random

@Composable
fun SetupSplashScreen(
    onFinished: () -> Unit
) {
    val moveProgress = remember { Animatable(0f) }
    var settleBars by remember { mutableStateOf(false) }
    val levelTransition = rememberInfiniteTransition(label = "setup_splash_audio")
    val fakeAudioLevel by levelTransition.animateFloat(
        initialValue = 0.32f,
        targetValue = 0.95f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 420, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "setup_splash_audio_level"
    )

    LaunchedEffect(Unit) {
        delay(SetupSplashCenterHoldMs.toLong())
        moveProgress.animateTo(
            targetValue = 1f,
            animationSpec = tween(durationMillis = SetupSplashTravelMs, easing = FastOutSlowInEasing)
        )
        settleBars = true
        delay(SetupSplashSettleMs.toLong())
        delay(SetupSplashFrozenHoldMs.toLong())
        onFinished()
    }

    BoxWithConstraints(
        modifier = Modifier.fillMaxSize()
    ) {
        val startTop = (maxHeight - SetupLogoSize) * 0.5f
        val endTop = SetupLogoTopOffset
        val animatedTop = lerp(startTop, endTop, moveProgress.value)

        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .offset(y = animatedTop)
                .size(SetupLogoSize),
            contentAlignment = Alignment.Center
        ) {
            SetupSplashBars(
                level = fakeAudioLevel,
                settleToLogo = settleBars,
                modifier = Modifier.size(SetupLogoSize)
            )
        }
    }
}

@Composable
private fun SetupSplashBars(
    level: Float,
    settleToLogo: Boolean,
    modifier: Modifier = Modifier
) {
    val normalizedLevel by rememberUpdatedState(level.coerceIn(0f, 1f))
    val bars = remember { List(SetupBarCount) { Animatable(1f) } }
    val recordingEnabled = !settleToLogo

    LaunchedEffect(settleToLogo) {
        if (!settleToLogo) return@LaunchedEffect
        bars.forEach { bar ->
            launch {
                bar.animateTo(
                    targetValue = 1f,
                    animationSpec = tween(
                        durationMillis = SetupSplashSettleMs,
                        easing = FastOutSlowInEasing
                    )
                )
            }
        }
    }

    LaunchedEffect(recordingEnabled) {
        if (!recordingEnabled) return@LaunchedEffect
        val random = Random(System.currentTimeMillis())
        val noise = FloatArray(SetupBarCount)
        coroutineScope {
            while (true) {
                val talking = normalizedLevel >= SetupTalkingThreshold
                for (index in bars.indices) {
                    val target = if (talking) {
                        noise[index] = (noise[index] * SetupNoiseMemory +
                            ((random.nextFloat() * 2f) - 1f) * SetupNoiseInputRandom)
                            .coerceIn(-1f, 1f)
                        val randomScale = SetupTalkingBase + (random.nextFloat() * SetupTalkingRange)
                        val jitter = noise[index] * SetupTalkingJitter
                        (randomScale + jitter).coerceIn(SetupIdleScaleFloor, 1f)
                    } else {
                        noise[index] = 0f
                        SetupIdlePattern[index]
                    }
                    if (!talking && abs(target - bars[index].value) < SetupIdleSettleEpsilon) {
                        continue
                    }
                    val rising = target >= bars[index].value
                    launch {
                        bars[index].animateTo(
                            targetValue = target,
                            animationSpec = tween(
                                durationMillis = if (rising) {
                                    SetupTalkingAttackDurationMs
                                } else {
                                    SetupTalkingReleaseDurationMs
                                },
                                easing = FastOutSlowInEasing
                            )
                        )
                    }
                }
                delay(if (talking) SetupTalkingFrameMs else SetupIdleFrameMs)
            }
        }
    }

    Box(modifier = modifier) {
        repeat(SetupBarCount) { index ->
            val left = SetupLogoSize * (SetupLogoBarLeft[index] / SetupLogoViewport)
            val width = SetupLogoSize * (SetupLogoBarWidth / SetupLogoViewport)
            val bottom = SetupLogoSize * (SetupLogoBarBottom[index] / SetupLogoViewport)
            val fullHeight = SetupLogoSize * (SetupLogoBarHeight[index] / SetupLogoViewport)
            val height = fullHeight * bars[index].value
            val top = bottom - height
            Box(
                modifier = Modifier
                    .offset(x = left, y = top)
                    .size(width = width, height = height)
                    .clip(RoundedCornerShape(percent = 50))
                    .background(Color.White)
            )
        }
    }
}

private const val SetupSplashCenterHoldMs = 3_000
private const val SetupSplashTravelMs = 700
private const val SetupSplashSettleMs = 220
private const val SetupSplashFrozenHoldMs = 300

private const val SetupLogoViewport = 108f
private const val SetupBarCount = 5
private const val SetupLogoBarWidth = 10f
private val SetupLogoBarLeft = floatArrayOf(20f, 34f, 48f, 62f, 76f)
private val SetupLogoBarBottom = floatArrayOf(68f, 74f, 70f, 76f, 72f)
private val SetupLogoBarHeight = floatArrayOf(28f, 40f, 32f, 44f, 36f)

private const val SetupIdleScaleFloor = 0.56f
private const val SetupTalkingThreshold = 0.07f
private const val SetupTalkingBase = 0.58f
private const val SetupTalkingRange = 0.42f
private const val SetupTalkingJitter = 0.13f
private val SetupIdlePattern = floatArrayOf(0.70f, 0.90f, 0.76f, 0.95f, 0.82f)
private const val SetupNoiseMemory = 0.56f
private const val SetupNoiseInputRandom = 0.40f
private const val SetupTalkingAttackDurationMs = 90
private const val SetupTalkingReleaseDurationMs = 170
private const val SetupIdleSettleEpsilon = 0.012f
private const val SetupTalkingFrameMs = 80L
private const val SetupIdleFrameMs = 120L
