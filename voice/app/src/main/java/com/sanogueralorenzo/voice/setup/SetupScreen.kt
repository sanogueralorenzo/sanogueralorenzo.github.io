package com.sanogueralorenzo.voice.setup

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
    voiceImeSelected: Boolean,
    onGrantMic: () -> Unit,
    onOpenKeyboardButtonSettings: () -> Unit,
    onOpenImeSettings: () -> Unit,
    onShowImePicker: () -> Unit
) {
    val needsKeyboardSelection = voiceImeEnabled && !voiceImeSelected

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
                        Text(
                            text = stringResource(R.string.setup_keyboard_intro),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Text(
                            text = stringResource(R.string.setup_keyboard_button_recommendation),
                            style = MaterialTheme.typography.bodySmall
                        )
                        if (needsKeyboardSelection) {
                            Text(
                                text = stringResource(R.string.setup_keyboard_select_required),
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
                OutlinedButton(
                    onClick = onOpenKeyboardButtonSettings,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = stringResource(R.string.setup_open_keyboard_button_settings))
                }
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

@Composable
private fun SetupHeroAnimation() {
    val transition = rememberInfiniteTransition(label = "setup_talking_level")
    val level by transition.animateFloat(
        initialValue = 0.08f,
        targetValue = 0.92f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 760, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "setup_talking_level_value"
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(220.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Spacer(modifier = Modifier.height(12.dp))
        VoicePillVisualizer(
            level = level,
            mode = VoiceVisualizerMode.RECORDING_BARS
        )
    }
}
