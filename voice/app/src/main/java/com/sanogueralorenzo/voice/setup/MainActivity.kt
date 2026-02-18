package com.sanogueralorenzo.voice.setup

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.di.appGraph
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val appContext = applicationContext
        setContent {
            val appGraph = remember(appContext) { appContext.appGraph() }
            val appThemeMode by appGraph.settingsStore.themeModeFlow.collectAsStateWithLifecycle(
                initialValue = appGraph.settingsStore.themeMode()
            )
            VoiceTheme(themeMode = appThemeMode) {
                SetupNavHost()
            }
        }
    }
}
