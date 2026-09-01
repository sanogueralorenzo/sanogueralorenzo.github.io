package com.sanogueralorenzo.voice

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme
import java.time.Duration
import java.time.Instant

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            keepSplashVisibleThroughAnimation()
        }
        enableEdgeToEdge()
        setContent {
            VoiceTheme {
                MainNavHost()
            }
        }
    }

    private fun keepSplashVisibleThroughAnimation() {
        splashScreen.setOnExitAnimationListener { splashView ->
            val animationStart = splashView.iconAnimationStart
            val animationDuration = splashView.iconAnimationDuration
            val remainingDuration = if (animationStart != null && animationDuration != null) {
                Duration.between(
                    Instant.now(),
                    animationStart.plus(animationDuration)
                ).toMillis().coerceAtLeast(0L)
            } else {
                SplashDurationMs
            }
            splashView.postDelayed(splashView::remove, remainingDuration)
        }
    }

    private companion object {
        const val SplashDurationMs = 600L
    }
}
