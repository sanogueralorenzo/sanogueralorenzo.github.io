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
fun SetupIntroScreen(
    onContinue: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_intro),
        body = {
            Text(
                text = stringResource(R.string.setup_intro_description),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(R.string.setup_intro_message),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(R.string.setup_intro_expectation_local),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_intro_expectation_warmup),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_intro_expectation_control),
                style = MaterialTheme.typography.bodySmall
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
