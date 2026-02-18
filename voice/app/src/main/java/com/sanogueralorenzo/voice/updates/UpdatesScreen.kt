package com.sanogueralorenzo.voice.updates

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R

@Composable
fun UpdatesScreen(
    promptVersion: String?,
    promptDownloading: Boolean,
    promptProgress: Int,
    onDownloadPrompt: () -> Unit
) {
    val viewModel = mavericksViewModel<CheckUpdatesViewModel, CheckUpdatesUiState>()
    val state by viewModel.collectAsStateWithLifecycle()
    val updatesRunning = state.updatesRunning
    val updatesMessage = state.updatesMessage
    val modelMessage = state.modelMessage

    DisposableEffect(viewModel) {
        onDispose { viewModel.shutdown() }
    }

    val promptVersionDate = promptVersion ?: stringResource(R.string.updates_prompt_version_unknown)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.updates_section_description),
            style = MaterialTheme.typography.bodyMedium
        )

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = stringResource(R.string.updates_prompt_row_title),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = stringResource(
                            R.string.updates_prompt_row_version_date,
                            promptVersionDate
                        ),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Button(
                    onClick = onDownloadPrompt,
                    enabled = !promptDownloading && !updatesRunning
                ) {
                    Text(
                        text = if (promptDownloading) {
                            stringResource(
                                R.string.setup_status_downloading,
                                promptProgress.coerceIn(0, 100)
                            )
                        } else {
                            stringResource(R.string.updates_prompt_download_action)
                        }
                    )
                }
            }
        }

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
                    onClick = viewModel::checkForUpdates,
                    enabled = !updatesRunning,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = stringResource(R.string.updates_check_action))
                }
            }
        }
    }
}
