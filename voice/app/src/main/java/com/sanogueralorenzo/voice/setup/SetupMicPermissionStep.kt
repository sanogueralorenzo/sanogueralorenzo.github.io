package com.sanogueralorenzo.voice.setup

import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.res.stringResource
import com.sanogueralorenzo.voice.R

@Composable
fun SetupMicPermissionScreen(
    onGrantMic: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_microphone),
        body = {
            Text(
                text = stringResource(R.string.setup_mic_intro),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(R.string.setup_mic_bullet_while_using),
                style = MaterialTheme.typography.bodySmall
            )
        },
        actions = {
            Button(
                onClick = onGrantMic,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_grant_mic))
            }
        }
    )
}
