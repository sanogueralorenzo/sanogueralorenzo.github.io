package com.sanogueralorenzo.voice.ime

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ui.VoicePillVisualizer
import com.sanogueralorenzo.voice.ui.VoicePillVisualizerWidth
import com.sanogueralorenzo.voice.ui.VoiceVisualizerMode
import kotlinx.coroutines.delay

private val KeyboardBarHeight = 84.dp
private val KeyboardParentVerticalTrim = 8.dp

private data class ActivePillVisualState(
    val mode: VoiceKeyboardMode,
    val audioLevel: Float
)

@Composable
fun VoiceKeyboardImeContent(
    state: VoiceKeyboardState,
    onIdleTap: () -> Unit,
    onDeleteTap: () -> Unit,
    onSendTap: () -> Unit,
    onDebugToggle: () -> Unit,
    onDebugLongPress: () -> Unit,
    showDebugButton: Boolean = true,
    modifier: Modifier = Modifier
) {
    val density = LocalDensity.current
    val bottomSystemInset = with(density) { state.bottomInsetPx.toDp() }
    val keyboardVisibleHeight = KeyboardBarHeight - (KeyboardParentVerticalTrim * 2)
    val keyboardContainerHeight = keyboardVisibleHeight + bottomSystemInset
    val colors = rememberVoiceKeyboardColors()

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(keyboardContainerHeight)
            .background(colors.keyboardBackground),
        contentAlignment = if (bottomSystemInset > 0.dp) Alignment.TopCenter else Alignment.Center
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .height(keyboardVisibleHeight),
            contentAlignment = Alignment.Center
        ) {
            val targetWidth = when (state.mode) {
                VoiceKeyboardMode.IDLE -> VoicePillVisualizerWidth
                VoiceKeyboardMode.RECORDING,
                VoiceKeyboardMode.PROCESSING -> (maxWidth * 0.92f).coerceAtMost(420.dp)
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
                targetValue = if (state.mode == VoiceKeyboardMode.IDLE) colors.idlePill else colors.activePill,
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
                                        onSendTap = onSendTap,
                                        actionContainerColor = colors.actionContainer,
                                        actionIconTint = colors.actionIcon,
                                        visualizerColor = colors.activeVisualizer
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if (state.mode == VoiceKeyboardMode.IDLE && showDebugButton) {
                IdleDebugButton(
                    active = state.inlineDebugEnabled,
                    onTap = onDebugToggle,
                    onLongPress = onDebugLongPress,
                    inactiveContainerColor = colors.idleAuxContainer,
                    activeContainerColor = colors.idleAuxContainerActive,
                    iconTint = colors.idleAuxIcon,
                    inactiveAlpha = colors.idleDebugInactiveAlpha
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
    onSendTap: () -> Unit,
    actionContainerColor: Color,
    actionIconTint: Color,
    visualizerColor: Color
) {
    val visualizerMode = when (mode) {
        VoiceKeyboardMode.RECORDING -> VoiceVisualizerMode.RECORDING_BARS
        VoiceKeyboardMode.PROCESSING -> VoiceVisualizerMode.PROCESSING_DOTS
        VoiceKeyboardMode.IDLE -> VoiceVisualizerMode.IDLE_HIDDEN
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
                icon = Icons.Rounded.Stop,
                contentDescription = stringResource(R.string.ime_delete_recording),
                fromStart = true,
                visible = isRecording,
                onTap = onDeleteTap,
                containerColor = actionContainerColor,
                iconTint = actionIconTint
            )
            VoicePillVisualizer(
                level = level,
                mode = visualizerMode,
                barColor = visualizerColor
            )
            ActionIconButton(
                icon = Icons.AutoMirrored.Rounded.Send,
                contentDescription = stringResource(R.string.ime_send_recording),
                fromStart = false,
                visible = isRecording,
                onTap = onSendTap,
                containerColor = actionContainerColor,
                iconTint = actionIconTint
            )
        }
    }
}

@Composable
private fun ActionIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    fromStart: Boolean,
    visible: Boolean,
    onTap: () -> Unit,
    containerColor: Color,
    iconTint: Color
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
            color = containerColor
        ) {
            Box(
                modifier = Modifier.size(IconContainerSize),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = contentDescription,
                    tint = iconTint
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
    onLongPress: () -> Unit,
    inactiveContainerColor: Color,
    activeContainerColor: Color,
    iconTint: Color,
    inactiveAlpha: Float
) {
    val containerColor by animateColorAsState(
        targetValue = if (active) activeContainerColor else inactiveContainerColor,
        animationSpec = tween(durationMillis = 180, easing = FastOutSlowInEasing),
        label = "debug_container_color"
    )
    val alpha by animateFloatAsState(
        targetValue = if (active) 1f else inactiveAlpha,
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
                    tint = iconTint
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
private val IconContainerSize = 38.dp
private val IconSlotSize = 44.dp
private const val ActiveFadeInMs = 180
private const val IdleCollapseFadeOutMs = 240
private val PillTouchHeight = 50.dp
