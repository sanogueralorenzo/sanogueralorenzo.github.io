package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.sanogueralorenzo.voice.R

@Composable
fun SetupSelectKeyboardScreen(
    onDone: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_select_keyboard),
        body = {
            Text(
                text = stringResource(R.string.setup_select_keyboard_step_message),
                style = MaterialTheme.typography.bodyMedium
            )
        },
        actions = {
            Button(
                onClick = onDone,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_done))
            }
        }
    )
}
