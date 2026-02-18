package com.sanogueralorenzo.voice.preferences

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

@Composable
fun PreferencesScreen() {
    val lifecycleOwner = LocalLifecycleOwner.current
    val viewModel = mavericksViewModel<PreferencesViewModel, PreferencesUiState>()
    val state by viewModel.collectAsStateWithLifecycle()

    DisposableEffect(lifecycleOwner, viewModel) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshPreferences()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(viewModel) {
        viewModel.refreshPreferences()
    }

    PreferencesScreenContent(
        llmRewriteEnabled = state.llmRewriteEnabled,
        onLlmRewriteEnabledChange = viewModel::setLlmRewriteEnabled,
        capitalizeSentencesEnabled = state.capitalizeSentencesEnabled,
        onCapitalizeSentencesEnabledChange = viewModel::setCapitalizeSentencesEnabled,
        removeDotAtEndEnabled = state.removeDotAtEndEnabled,
        onRemoveDotAtEndEnabledChange = viewModel::setRemoveDotAtEndEnabled
    )
}

@Composable
private fun PreferencesScreenContent(
    llmRewriteEnabled: Boolean,
    onLlmRewriteEnabledChange: (Boolean) -> Unit,
    capitalizeSentencesEnabled: Boolean,
    onCapitalizeSentencesEnabledChange: (Boolean) -> Unit,
    removeDotAtEndEnabled: Boolean,
    onRemoveDotAtEndEnabledChange: (Boolean) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.preferences_section_description),
            style = MaterialTheme.typography.bodyMedium
        )

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp)
            ) {
                PreferencesToggleRow(
                    title = stringResource(R.string.preferences_rewrite_toggle_title),
                    description = stringResource(R.string.preferences_rewrite_toggle_description),
                    checked = llmRewriteEnabled,
                    onCheckedChange = onLlmRewriteEnabledChange
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                PreferencesToggleRow(
                    title = stringResource(R.string.preferences_capitalize_sentences_title),
                    checked = capitalizeSentencesEnabled,
                    onCheckedChange = onCapitalizeSentencesEnabledChange
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                PreferencesToggleRow(
                    title = stringResource(R.string.preferences_remove_dot_end_title),
                    checked = removeDotAtEndEnabled,
                    onCheckedChange = onRemoveDotAtEndEnabledChange
                )
            }
        }
    }
}

@Composable
private fun PreferencesToggleRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    description: String? = null
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f)
            )
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange
            )
        }
        if (!description.isNullOrBlank()) {
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
