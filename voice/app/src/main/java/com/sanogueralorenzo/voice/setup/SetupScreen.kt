package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ui.VoicePillVisualizer
import com.sanogueralorenzo.voice.ui.VoiceVisualizerMode

@Composable
fun SetupScreen(
    micGranted: Boolean,
    voiceImeEnabled: Boolean,
    keyboardSelectionConfirmed: Boolean,
    onGrantMic: () -> Unit,
    onOpenImeSettings: () -> Unit,
    onShowImePicker: () -> Unit,
    onDone: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            SetupHeroAnimation()
            Text(
                text = stringResource(R.string.setup_section_title),
                style = MaterialTheme.typography.titleLarge
            )
            if (!micGranted) {
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.setup_mic_intro),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Text(
                            text = stringResource(R.string.setup_mic_bullet_while_using),
                            style = MaterialTheme.typography.bodySmall
                        )
                        Text(
                            text = stringResource(R.string.setup_mic_bullet_local),
                            style = MaterialTheme.typography.bodySmall
                        )
                        Text(
                            text = stringResource(R.string.setup_mic_bullet_offline_after_download),
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            } else {
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        if (keyboardSelectionConfirmed) {
                            Text(
                                text = stringResource(R.string.setup_keyboard_welcome),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        } else {
                            Text(
                                text = stringResource(R.string.setup_keyboard_intro),
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Text(
                                text = stringResource(R.string.setup_keyboard_button_recommendation),
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                }
            }
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (!micGranted) {
                Button(
                    onClick = onGrantMic,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = stringResource(R.string.setup_grant_mic))
                }
            } else {
                if (keyboardSelectionConfirmed) {
                    Button(
                        onClick = onDone,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = stringResource(R.string.setup_done))
                    }
                } else {
                    if (!voiceImeEnabled) {
                        Button(
                            onClick = onOpenImeSettings,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(text = stringResource(R.string.setup_enable_keyboard))
                        }
                    }
                    Button(
                        onClick = onShowImePicker,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = stringResource(R.string.setup_choose_keyboard))
                    }
                }
            }
        }
    }
}

@Composable
private fun SetupHeroAnimation() {
    val level = 0.05f

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .wrapContentHeight()
            .padding(vertical = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        VoicePillVisualizer(
            level = level,
            mode = VoiceVisualizerMode.RECORDING_BARS
        )
    }
}
