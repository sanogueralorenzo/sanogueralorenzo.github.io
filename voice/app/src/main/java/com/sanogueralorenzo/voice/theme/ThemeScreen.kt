package com.sanogueralorenzo.voice.theme

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
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
fun ThemeScreen() {
    val lifecycleOwner = LocalLifecycleOwner.current
    val viewModel = mavericksViewModel<ThemeViewModel, ThemeState>()
    val state by viewModel.collectAsStateWithLifecycle()

    DisposableEffect(lifecycleOwner, viewModel) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshKeyboardThemeMode()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(viewModel) {
        viewModel.refreshKeyboardThemeMode()
    }

    ThemeScreenContent(
        keyboardThemeMode = state.keyboardThemeMode,
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
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
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
        modifier = Modifier
            .fillMaxWidth()
            .sizeIn(minHeight = 44.dp)
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge
        )
        RadioButton(
            selected = selected,
            onClick = null
        )
    }
}
