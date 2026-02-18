package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.TextButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R

@Composable
fun KeyboardTestBar(
    value: String,
    onValueChange: (String) -> Unit,
    voiceImeSelected: Boolean,
    onRequestKeyboardPicker: () -> Unit
) {
    var showKeyboardDialog by remember { mutableStateOf(false) }

    RoundedInputBar(
        value = value,
        onValueChange = onValueChange,
        enabled = voiceImeSelected,
        onBlockedTap = { showKeyboardDialog = true }
    )

    if (showKeyboardDialog) {
        AlertDialog(
            onDismissRequest = { showKeyboardDialog = false },
            title = { Text(text = stringResource(R.string.setup_input_keyboard_required_title)) },
            text = { Text(text = stringResource(R.string.setup_input_keyboard_required_body)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showKeyboardDialog = false
                        onRequestKeyboardPicker()
                    }
                ) {
                    Text(text = stringResource(R.string.setup_choose_keyboard))
                }
            },
            dismissButton = {
                TextButton(onClick = { showKeyboardDialog = false }) {
                    Text(text = stringResource(android.R.string.cancel))
                }
            }
        )
    }
}

@Composable
fun HomeScreen(
    onOpenPromptBenchmarking: () -> Unit,
    onOpenTheming: () -> Unit,
    onOpenCheckUpdates: () -> Unit,
    onOpenSettings: () -> Unit
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SectionCard(
                title = stringResource(R.string.home_section_prompt_benchmarking_title),
                description = stringResource(R.string.home_section_prompt_benchmarking_description),
                onClick = onOpenPromptBenchmarking
            )
        }
        item {
            SectionCard(
                title = stringResource(R.string.home_section_theming_title),
                description = stringResource(R.string.home_section_theming_description),
                onClick = onOpenTheming
            )
        }
        item {
            SectionCard(
                title = stringResource(R.string.home_section_settings_title),
                description = stringResource(R.string.home_section_settings_description),
                onClick = onOpenSettings
            )
        }
        item {
            SectionCard(
                title = stringResource(R.string.home_section_check_updates_title),
                description = stringResource(R.string.home_section_check_updates_description),
                onClick = onOpenCheckUpdates
            )
        }
    }
}

@Composable
private fun SectionCard(
    title: String,
    description: String,
    onClick: () -> Unit
) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            Text(text = description, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
