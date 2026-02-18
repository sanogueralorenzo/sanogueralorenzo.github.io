package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ui.components.VoiceInput

@Composable
fun SetupSelectKeyboardScreen(
    value: String,
    onValueChange: (String) -> Unit,
    voiceImeSelected: Boolean,
    onRequestKeyboardPicker: () -> Unit,
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
            VoiceInput(
                value = value,
                onValueChange = onValueChange,
                voiceImeSelected = voiceImeSelected,
                onRequestKeyboardPicker = onRequestKeyboardPicker,
                autoFocusOnResume = true
            )
            Spacer(modifier = Modifier.height(16.dp))
            Button(
                onClick = onDone,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_done))
            }
        }
    )
}
