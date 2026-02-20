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
fun SetupStep2IntroScreen(
    onContinue: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_intro),
        body = {
            Text(
                text = stringResource(R.string.setup_intro_description),
                style = MaterialTheme.typography.bodyMedium
            )
        },
        actions = {
            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_intro_continue))
            }
        }
    )
}
