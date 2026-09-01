package com.sanogueralorenzo.voice.keyboard

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import kotlinx.coroutines.delay

internal enum class CompactKeyboardMode {
    IDLE,
    RECORDING,
    PROCESSING
}

internal data class CompactKeyboardState(
    val mode: CompactKeyboardMode = CompactKeyboardMode.IDLE,
    val speechActive: Boolean = false,
    val bottomInsetPx: Int = 0
)

private data class CompactKeyboardColors(
    val background: Color,
    val idlePill: Color,
    val activePill: Color,
    val visualizer: Color,
    val actionContainer: Color,
    val actionIcon: Color
)

@Composable
internal fun CompactKeyboardContent(
    state: CompactKeyboardState,
    isDarkTheme: Boolean,
    onIdleTap: () -> Unit,
    onDiscardTap: () -> Unit,
    onSendTap: () -> Unit,
    modifier: Modifier = Modifier
) {
    val density = LocalDensity.current
    val bottomSystemInset = with(density) { state.bottomInsetPx.toDp() }
    val visibleHeight = KEYBOARD_BAR_HEIGHT - KEYBOARD_VERTICAL_TRIM * 2
    val colors = compactKeyboardColors(isDarkTheme)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(visibleHeight + bottomSystemInset)
            .background(colors.background),
        contentAlignment = Alignment.TopCenter
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .height(visibleHeight),
            contentAlignment = Alignment.Center
        ) {
            val targetWidth = when (state.mode) {
                CompactKeyboardMode.IDLE -> KeyboardVisualizerWidth
                CompactKeyboardMode.RECORDING,
                CompactKeyboardMode.PROCESSING -> (maxWidth * 0.92f).coerceAtMost(420.dp)
            }
            val idleHeight by animateDpAsState(
                targetValue = if (state.mode == CompactKeyboardMode.IDLE) 14.dp else 0.dp,
                animationSpec = spring(dampingRatio = 0.9f, stiffness = 500f),
                label = "keyboard_idle_height"
            )
            val width by animateDpAsState(
                targetValue = targetWidth,
                animationSpec = spring(dampingRatio = 0.88f, stiffness = 460f),
                label = "keyboard_pill_width"
            )
            val pillColor by animateColorAsState(
                targetValue = if (state.mode == CompactKeyboardMode.IDLE) {
                    colors.idlePill
                } else {
                    colors.activePill
                },
                animationSpec = tween(durationMillis = 280, easing = FastOutSlowInEasing),
                label = "keyboard_pill_color"
            )
            var retainedActiveMode by remember { mutableStateOf<CompactKeyboardMode?>(null) }
            LaunchedEffect(state.mode) {
                if (state.mode == CompactKeyboardMode.IDLE) {
                    delay(IDLE_COLLAPSE_FADE_OUT_MS.toLong())
                    retainedActiveMode = null
                } else {
                    retainedActiveMode = state.mode
                }
            }
            val activeMode = if (state.mode == CompactKeyboardMode.IDLE) {
                retainedActiveMode
            } else {
                state.mode
            }
            val activeAlpha by animateFloatAsState(
                targetValue = if (state.mode == CompactKeyboardMode.IDLE) 0f else 1f,
                animationSpec = tween(
                    durationMillis = if (state.mode == CompactKeyboardMode.IDLE) {
                        IDLE_COLLAPSE_FADE_OUT_MS
                    } else {
                        ACTIVE_FADE_IN_MS
                    },
                    easing = FastOutSlowInEasing
                ),
                label = "keyboard_active_content_alpha"
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(EXPANDED_PILL_HEIGHT)
                    .clickable(
                        enabled = state.mode == CompactKeyboardMode.IDLE,
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = onIdleTap
                    ),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .width(width)
                        .height(EXPANDED_PILL_HEIGHT),
                    contentAlignment = Alignment.Center
                ) {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .then(
                                if (state.mode == CompactKeyboardMode.IDLE) {
                                    Modifier.height(idleHeight.coerceAtLeast(1.dp))
                                } else {
                                    Modifier
                                }
                            )
                            .animateContentSize(
                                animationSpec = spring(dampingRatio = 0.9f, stiffness = 520f)
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
                            activeMode?.let { mode ->
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .graphicsLayer { alpha = activeAlpha }
                                ) {
                                    ActiveKeyboardContent(
                                        mode = mode,
                                        speechActive = state.speechActive,
                                        colors = colors,
                                        onDiscardTap = onDiscardTap,
                                        onSendTap = onSendTap
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ActiveKeyboardContent(
    mode: CompactKeyboardMode,
    speechActive: Boolean,
    colors: CompactKeyboardColors,
    onDiscardTap: () -> Unit,
    onSendTap: () -> Unit
) {
    val isRecording = mode == CompactKeyboardMode.RECORDING
    val visualizerMode = when (mode) {
        CompactKeyboardMode.RECORDING -> if (speechActive) {
            KeyboardVisualizerMode.RECORDING_BARS_ACTIVE
        } else {
            KeyboardVisualizerMode.RECORDING_BARS_IDLE
        }
        CompactKeyboardMode.PROCESSING -> KeyboardVisualizerMode.PROCESSING_DOTS
        CompactKeyboardMode.IDLE -> KeyboardVisualizerMode.IDLE_HIDDEN
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(EXPANDED_PILL_HEIGHT)
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            AnimatedActionButton(
                visible = isRecording,
                fromStart = true,
                icon = Icons.Rounded.Stop,
                contentDescription = stringResource(R.string.keyboard_discard_recording),
                colors = colors,
                onTap = onDiscardTap
            )
            KeyboardVisualizer(
                mode = visualizerMode,
                color = colors.visualizer
            )
            AnimatedActionButton(
                visible = isRecording,
                fromStart = false,
                icon = Icons.AutoMirrored.Rounded.Send,
                contentDescription = stringResource(R.string.keyboard_send_recording),
                colors = colors,
                onTap = onSendTap
            )
        }
    }
}

@Composable
private fun AnimatedActionButton(
    visible: Boolean,
    fromStart: Boolean,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    colors: CompactKeyboardColors,
    onTap: () -> Unit
) {
    val slotWidth by animateDpAsState(
        targetValue = if (visible) ICON_SLOT_SIZE else 0.dp,
        animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing),
        label = "keyboard_action_slot"
    )
    val alpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(durationMillis = 160, easing = LinearOutSlowInEasing),
        label = "keyboard_action_alpha"
    )
    val scale by animateFloatAsState(
        targetValue = if (visible) 1f else 0.86f,
        animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing),
        label = "keyboard_action_scale"
    )
    val offsetX by animateDpAsState(
        targetValue = if (visible) 0.dp else if (fromStart) (-10).dp else 10.dp,
        animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing),
        label = "keyboard_action_offset"
    )
    Box(
        modifier = Modifier
            .width(slotWidth)
            .height(ICON_CONTAINER_SIZE),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            modifier = Modifier
                .size(ICON_CONTAINER_SIZE)
                .offset(x = offsetX)
                .graphicsLayer {
                    this.alpha = alpha
                    scaleX = scale
                    scaleY = scale
                }
                .clip(RoundedCornerShape(999.dp))
                .clickable(enabled = visible, onClick = onTap),
            shape = RoundedCornerShape(999.dp),
            color = colors.actionContainer
        ) {
            Box(modifier = Modifier.size(ICON_CONTAINER_SIZE), contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = icon,
                    contentDescription = contentDescription,
                    tint = colors.actionIcon
                )
            }
        }
    }
}

private fun compactKeyboardColors(isDarkTheme: Boolean): CompactKeyboardColors {
    return if (isDarkTheme) {
        CompactKeyboardColors(
            background = Color(0xFF131519),
            idlePill = Color(0xFF78808A),
            activePill = Color(0xFF1A2026),
            visualizer = Color.White,
            actionContainer = Color(0x33FFFFFF),
            actionIcon = Color.White
        )
    } else {
        CompactKeyboardColors(
            background = Color(0xFFE8EAED),
            idlePill = Color(0xFFA9B0B8),
            activePill = Color(0xFFF6F7F8),
            visualizer = Color(0xFF202124),
            actionContainer = Color(0x1F000000),
            actionIcon = Color(0xFF202124)
        )
    }
}

private val KEYBOARD_BAR_HEIGHT = 84.dp
private val KEYBOARD_VERTICAL_TRIM = 8.dp
private val EXPANDED_PILL_HEIGHT = 50.dp
private val ICON_CONTAINER_SIZE = 38.dp
private val ICON_SLOT_SIZE = 44.dp
private const val ACTIVE_FADE_IN_MS = 180
private const val IDLE_COLLAPSE_FADE_OUT_MS = 240
