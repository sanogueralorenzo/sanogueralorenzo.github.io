package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R

@Composable
fun CheckUpdatesScreen(
    updatesRunning: Boolean,
    updatesMessage: String?,
    modelMessage: String?,
    onCheckUpdates: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.check_updates_section_description),
            style = MaterialTheme.typography.bodyMedium
        )
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (!updatesMessage.isNullOrBlank()) {
                    Text(
                        text = updatesMessage,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                if (!modelMessage.isNullOrBlank()) {
                    Text(
                        text = modelMessage,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Button(
                    onClick = onCheckUpdates,
                    enabled = !updatesRunning,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = stringResource(R.string.settings_updates_action))
                }
            }
        }
    }
}
