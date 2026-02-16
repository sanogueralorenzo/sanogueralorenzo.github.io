package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
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
    RoundedInputBar(value = value, onValueChange = onValueChange)
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
    LazyColumn(
        modifier = Modifier
            .fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SectionCard(
                title = stringResource(R.string.home_section_setup_title),
                description = stringResource(R.string.home_section_setup_description),
                onClick = onOpenSetup
            )
        }
        item {
            SectionCard(
                title = stringResource(R.string.home_section_models_title),
                description = stringResource(R.string.home_section_models_description),
                onClick = onOpenModels
            )
        }
        item {
            SectionCard(
                title = stringResource(R.string.home_section_onboarding_title),
                description = stringResource(R.string.home_section_onboarding_description),
                onClick = onOpenOnboarding
            )
        }
        item {
            SectionCard(
                title = stringResource(R.string.home_section_prompt_benchmarking_title),
                description = stringResource(R.string.home_section_prompt_benchmarking_description),
                onClick = onOpenPromptBenchmarking
            )
        }
        item {
            SectionCard(
                title = stringResource(R.string.home_section_response_style_title),
                description = stringResource(R.string.home_section_response_style_description),
                onClick = onOpenResponseStyle
            )
        }
        item {
            SectionCard(
                title = stringResource(R.string.home_section_settings_title),
                description = stringResource(R.string.home_section_settings_description),
                onClick = onOpenSettings
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
