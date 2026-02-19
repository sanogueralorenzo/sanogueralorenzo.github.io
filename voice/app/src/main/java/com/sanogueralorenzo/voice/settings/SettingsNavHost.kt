package com.sanogueralorenzo.voice.settings

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.SettingsScreen
import com.sanogueralorenzo.voice.preferences.PreferencesScreen
import com.sanogueralorenzo.voice.promptbenchmark.PromptBenchmarkingScreen
import com.sanogueralorenzo.voice.theme.KeyboardThemeMode
import com.sanogueralorenzo.voice.theme.ThemeScreen
import com.sanogueralorenzo.voice.ui.components.VoiceInput
import com.sanogueralorenzo.voice.updates.UpdatesScreen

private object SettingsRoute {
    const val SETTINGS = "settings_home"
    const val PROMPT_BENCHMARKING = "settings_prompt_benchmarking"
    const val THEME = "settings_theme"
    const val UPDATES = "settings_updates"
    const val PREFERENCES = "settings_preferences"
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun SettingsNavHost(
    state: SettingsFlowState,
    keyboardThemeMode: KeyboardThemeMode,
    onSettingsInputChange: (String) -> Unit,
    onThemeInputChange: (String) -> Unit,
    onDownloadPrompt: () -> Unit,
    onShowImePicker: () -> Unit
) {
    val navController = rememberNavController()
    val backStackEntry = navController.currentBackStackEntryAsState().value
    val currentRoute = backStackEntry?.destination?.route
    val canGoBack = currentRoute != null && currentRoute != SettingsRoute.SETTINGS
    val topBarTitle = when (currentRoute) {
        SettingsRoute.PROMPT_BENCHMARKING -> stringResource(R.string.prompt_benchmark_section_title)
        SettingsRoute.THEME -> stringResource(R.string.theming_section_title)
        SettingsRoute.UPDATES -> stringResource(R.string.updates_section_title)
        SettingsRoute.PREFERENCES -> stringResource(R.string.preferences_section_title)
        else -> stringResource(R.string.main_title_voice_keyboard)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = topBarTitle,
                        fontWeight = FontWeight.SemiBold
                    )
                },
                navigationIcon = {
                    if (canGoBack) {
                        IconButton(onClick = { navController.popBackStack() }) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                                contentDescription = stringResource(R.string.main_back)
                            )
                        }
                    }
                },
                actions = {
                    IconButton(onClick = onShowImePicker) {
                        Icon(
                            imageVector = Icons.Rounded.Keyboard,
                            contentDescription = stringResource(R.string.setup_select_keyboard)
                        )
                    }
                }
            )
        },
        bottomBar = {
            when (currentRoute) {
                SettingsRoute.SETTINGS -> key("settings_input_bar") {
                    VoiceInput(
                        value = state.settingsKeyboardInput,
                        onValueChange = onSettingsInputChange,
                        voiceImeSelected = state.voiceImeSelected,
                        onRequestKeyboardPicker = onShowImePicker,
                        autoFocusOnResume = true
                    )
                }

                SettingsRoute.THEME -> key("theme_input_bar") {
                    VoiceInput(
                        value = state.themeKeyboardInput,
                        onValueChange = onThemeInputChange,
                        voiceImeSelected = state.voiceImeSelected,
                        onRequestKeyboardPicker = onShowImePicker,
                        autoFocusOnResume = false
                    )
                }

                else -> Unit
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = SettingsRoute.SETTINGS,
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            composable(SettingsRoute.SETTINGS) {
                SettingsScreen(
                    onOpenPromptBenchmarking = { navController.navigate(SettingsRoute.PROMPT_BENCHMARKING) },
                    onOpenTheme = { navController.navigate(SettingsRoute.THEME) },
                    onOpenUpdates = { navController.navigate(SettingsRoute.UPDATES) },
                    onOpenPreferences = { navController.navigate(SettingsRoute.PREFERENCES) },
                    keyboardThemeMode = keyboardThemeMode
                )
            }

            composable(SettingsRoute.PROMPT_BENCHMARKING) {
                PromptBenchmarkingScreen()
            }

            composable(SettingsRoute.THEME) {
                ThemeScreen()
            }

            composable(SettingsRoute.PREFERENCES) {
                PreferencesScreen()
            }

            composable(SettingsRoute.UPDATES) {
                UpdatesScreen(
                    promptVersion = state.promptVersion,
                    promptDownloading = state.promptDownloading,
                    promptProgress = state.promptProgress,
                    onDownloadPrompt = onDownloadPrompt
                )
            }
        }
    }
}
