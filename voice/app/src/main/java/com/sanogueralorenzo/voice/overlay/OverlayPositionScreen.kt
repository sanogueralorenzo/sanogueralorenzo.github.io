package com.sanogueralorenzo.voice.overlay

import androidx.lifecycle.Lifecycle
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.Alignment
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ui.OnLifecycle

@Composable
fun OverlayPositionScreen() {
    val context = LocalContext.current
    val viewModel = mavericksViewModel<OverlayPositionViewModel, OverlayPositionState>()
    val state by viewModel.collectAsStateWithLifecycle()
    var numberInput by rememberSaveable { mutableStateOf("") }

    OnLifecycle(Lifecycle.Event.ON_START, Lifecycle.Event.ON_RESUME) {
        viewModel.refreshStatus()
        OverlayAccessibilityService.setPositionPreviewActive(context, true)
    }
    OnLifecycle(Lifecycle.Event.ON_PAUSE, Lifecycle.Event.ON_STOP) {
        OverlayAccessibilityService.setPositionPreviewActive(context, false)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.overlay_position_instructions_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = stringResource(R.string.overlay_position_instructions_body),
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    text = stringResource(R.string.overlay_position_mic_indicator_note),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.overlay_position_size_label, state.bubbleSizeDp),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(SIZE_BUTTON_SPACING),
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            FilledTonalIconButton(
                                modifier = Modifier.size(SIZE_BUTTON_SIZE),
                                onClick = { viewModel.adjustBubbleSizeDp(-1) }
                            ) {
                                Text(text = "-")
                            }
                            FilledTonalIconButton(
                                modifier = Modifier.size(SIZE_BUTTON_SIZE),
                                onClick = { viewModel.adjustBubbleSizeDp(1) }
                            ) {
                                Text(text = "+")
                            }
                        }
                    }

                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = stringResource(R.string.overlay_position_nudge_label),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Box(
                            modifier = Modifier.size(D_PAD_TRACK_SIZE),
                            contentAlignment = Alignment.Center
                        ) {
                            DPadButton(
                                modifier = Modifier
                                    .size(D_PAD_BUTTON_SIZE)
                                    .align(Alignment.TopCenter),
                                icon = Icons.Rounded.KeyboardArrowUp,
                                contentDescription = stringResource(R.string.overlay_position_nudge_up),
                                onClick = {
                                    viewModel.nudgeBubblePosition(0, -1)
                                }
                            )
                            DPadButton(
                                modifier = Modifier
                                    .size(D_PAD_BUTTON_SIZE)
                                    .align(Alignment.BottomCenter),
                                icon = Icons.Rounded.KeyboardArrowDown,
                                contentDescription = stringResource(R.string.overlay_position_nudge_down),
                                onClick = {
                                    viewModel.nudgeBubblePosition(0, 1)
                                }
                            )
                            DPadButton(
                                modifier = Modifier
                                    .size(D_PAD_BUTTON_SIZE)
                                    .align(Alignment.CenterStart),
                                icon = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                                contentDescription = stringResource(R.string.overlay_position_nudge_left),
                                onClick = {
                                    viewModel.nudgeBubblePosition(-1, 0)
                                }
                            )
                            DPadButton(
                                modifier = Modifier
                                    .size(D_PAD_BUTTON_SIZE)
                                    .align(Alignment.CenterEnd),
                                icon = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                                contentDescription = stringResource(R.string.overlay_position_nudge_right),
                                onClick = {
                                    viewModel.nudgeBubblePosition(1, 0)
                                }
                            )
                        }
                    }
                }
            }
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.overlay_position_number_input_label),
                    style = MaterialTheme.typography.bodyMedium
                )
                TextField(
                    value = numberInput,
                    onValueChange = { value ->
                        numberInput = value
                    },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
            }
        }

        if (!state.accessibilityServiceEnabled) {
            Text(
                text = stringResource(R.string.overlay_position_enable_accessibility_note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        } else if (state.voiceImeSelected) {
            Text(
                text = stringResource(R.string.overlay_voice_ime_selected_warning),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }
    }
}

@Composable
private fun DPadButton(
    modifier: Modifier,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    onClick: () -> Unit
) {
    FilledTonalIconButton(
        modifier = modifier,
        onClick = onClick
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription
        )
    }
}

private val SIZE_BUTTON_SIZE = 44.dp
private val SIZE_BUTTON_SPACING = 8.dp
private val D_PAD_BUTTON_SIZE = 44.dp
private val D_PAD_GAP = 0.dp
private val D_PAD_TRACK_SIZE = (D_PAD_BUTTON_SIZE * 3) + (D_PAD_GAP * 2)
