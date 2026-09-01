package com.sanogueralorenzo.voice

import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.ViewTreeObserver
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val splashStartedAt = SystemClock.uptimeMillis()
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            keepSplashVisibleUntil(splashStartedAt + SplashDurationMs)
        }
        enableEdgeToEdge()
        setContent {
            VoiceTheme {
                MainNavHost()
            }
        }
    }

    private fun keepSplashVisibleUntil(endTime: Long) {
        window.decorView.viewTreeObserver.addOnPreDrawListener(
            object : ViewTreeObserver.OnPreDrawListener {
                override fun onPreDraw(): Boolean {
                    if (SystemClock.uptimeMillis() < endTime) return false
                    window.decorView.viewTreeObserver.removeOnPreDrawListener(this)
                    return true
                }
            }
        )
    }

    private companion object {
        const val SplashDurationMs = 300L
    }
}
