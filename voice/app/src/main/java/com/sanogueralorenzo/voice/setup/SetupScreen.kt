package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R

@Composable
fun SetupScreen(
    micGranted: Boolean,
    onGrantMic: () -> Unit,
    onOpenImeSettings: () -> Unit,
    onShowImePicker: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.setup_section_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = if (micGranted) {
                stringResource(R.string.setup_mic_granted)
            } else {
                stringResource(R.string.setup_mic_missing)
            },
            style = MaterialTheme.typography.bodyMedium
        )
        Button(onClick = onGrantMic) {
            Text(text = stringResource(R.string.setup_grant_mic))
        }

        Button(onClick = onOpenImeSettings) {
            Text(text = stringResource(R.string.setup_enable_keyboard))
        }
        OutlinedButton(onClick = onShowImePicker) {
            Text(text = stringResource(R.string.setup_select_keyboard))
        }
    }
}
