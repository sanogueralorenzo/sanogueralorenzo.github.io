package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R

@Composable
fun KeyboardTestBar(
    value: String,
    onValueChange: (String) -> Unit
) {
    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.home_keyboard_test_title),
                style = MaterialTheme.typography.titleSmall
            )
            OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.fillMaxWidth(),
                minLines = 2,
                maxLines = 4,
                placeholder = { Text(text = stringResource(R.string.home_keyboard_test_placeholder)) }
            )
        }
    }
}

@Composable
fun HomeScreen(
    onOpenSetup: () -> Unit,
    onOpenModels: () -> Unit,
    onOpenOnboarding: () -> Unit,
    onOpenPromptBenchmarking: () -> Unit,
    onOpenResponseStyle: () -> Unit,
    onOpenSettings: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SectionCard(
            title = stringResource(R.string.home_section_setup_title),
            description = stringResource(R.string.home_section_setup_description),
            onClick = onOpenSetup
        )
        SectionCard(
            title = stringResource(R.string.home_section_models_title),
            description = stringResource(R.string.home_section_models_description),
            onClick = onOpenModels
        )
        SectionCard(
            title = stringResource(R.string.home_section_onboarding_title),
            description = stringResource(R.string.home_section_onboarding_description),
            onClick = onOpenOnboarding
        )
        SectionCard(
            title = stringResource(R.string.home_section_prompt_benchmarking_title),
            description = stringResource(R.string.home_section_prompt_benchmarking_description),
            onClick = onOpenPromptBenchmarking
        )
        SectionCard(
            title = stringResource(R.string.home_section_response_style_title),
            description = stringResource(R.string.home_section_response_style_description),
            onClick = onOpenResponseStyle
        )
        SectionCard(
            title = stringResource(R.string.home_section_settings_title),
            description = stringResource(R.string.home_section_settings_description),
            onClick = onOpenSettings
        )
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
