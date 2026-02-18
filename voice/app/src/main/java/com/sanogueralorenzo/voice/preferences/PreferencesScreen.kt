package com.sanogueralorenzo.voice.preferences

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.R

@Composable
fun PreferencesScreen(
    viewModel: PreferencesViewModel
) {
    val uiState by viewModel.collectAsStateWithLifecycle()
    PreferencesScreenContent(
        rewriteEnabled = uiState.rewriteEnabled,
        onRewriteEnabledChange = viewModel::setRewriteEnabled
    )
}

@Composable
private fun PreferencesScreenContent(
    rewriteEnabled: Boolean,
    onRewriteEnabledChange: (Boolean) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.preferences_section_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = stringResource(R.string.preferences_section_description),
            style = MaterialTheme.typography.bodyMedium
        )

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.preferences_rewrite_toggle_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = stringResource(R.string.preferences_rewrite_toggle_description),
                    style = MaterialTheme.typography.bodySmall
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = if (rewriteEnabled) {
                            stringResource(R.string.preferences_rewrite_enabled)
                        } else {
                            stringResource(R.string.preferences_rewrite_disabled)
                        },
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Switch(
                        checked = rewriteEnabled,
                        onCheckedChange = onRewriteEnabledChange
                    )
                }
            }
        }

    }
}
