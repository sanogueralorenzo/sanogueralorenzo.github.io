package com.sanogueralorenzo.overlay

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.sanogueralorenzo.overlay.ui.theme.OverlayTheme

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { OverlayTheme { AppRoot() } }
    }
}
