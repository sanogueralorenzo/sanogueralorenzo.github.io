package com.sanogueralorenzo.voice

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.sanogueralorenzo.voice.setup.SetupNavHost
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme

class SettingsActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            VoiceTheme {
                SetupNavHost()
            }
        }
    }
}
