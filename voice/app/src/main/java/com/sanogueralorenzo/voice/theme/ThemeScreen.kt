package com.sanogueralorenzo.voice.theme

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
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.R

@Composable
fun ThemeScreen(
    viewModel: ThemeViewModel
) {
    val uiState by viewModel.collectAsStateWithLifecycle()
    ThemeScreenContent(
        keyboardThemeMode = uiState.keyboardThemeMode,
        onThemeModeChange = viewModel::setKeyboardThemeMode
    )
}

@Composable
private fun ThemeScreenContent(
    keyboardThemeMode: KeyboardThemeMode,
    onThemeModeChange: (KeyboardThemeMode) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.theming_section_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = stringResource(R.string.theming_section_description),
            style = MaterialTheme.typography.bodyMedium
        )

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ThemeOptionRow(
                    title = stringResource(R.string.theming_option_auto),
                    selected = keyboardThemeMode == KeyboardThemeMode.AUTO,
                    onClick = { onThemeModeChange(KeyboardThemeMode.AUTO) }
                )
                ThemeOptionRow(
                    title = stringResource(R.string.theming_option_light),
                    selected = keyboardThemeMode == KeyboardThemeMode.LIGHT,
                    onClick = { onThemeModeChange(KeyboardThemeMode.LIGHT) }
                )
                ThemeOptionRow(
                    title = stringResource(R.string.theming_option_dark),
                    selected = keyboardThemeMode == KeyboardThemeMode.DARK,
                    onClick = { onThemeModeChange(KeyboardThemeMode.DARK) }
                )
            }
        }

        Text(
            text = stringResource(R.string.theming_input_hint),
            style = MaterialTheme.typography.bodySmall
        )
    }
}

@Composable
private fun ThemeOptionRow(
    title: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge
        )
        RadioButton(
            selected = selected,
            onClick = onClick
        )
    }
}
