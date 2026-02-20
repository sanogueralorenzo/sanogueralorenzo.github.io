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
fun SetupStep5KeyboardEnableScreen(
    onOpenImeSettings: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_enable_keyboard),
        body = {
            Text(
                text = stringResource(R.string.setup_enable_keyboard_intro),
                style = MaterialTheme.typography.bodyMedium
            )
        },
        actions = {
            Button(
                onClick = onOpenImeSettings,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_continue))
            }
        }
    )
}
