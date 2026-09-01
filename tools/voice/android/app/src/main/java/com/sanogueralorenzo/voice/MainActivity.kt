package com.sanogueralorenzo.voice

import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.animation.PathInterpolator
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme

class MainActivity : ComponentActivity() {
    private var homeLogoBounds: RectF? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashStartedAt = SystemClock.uptimeMillis()
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            configureSplashTransition(splashStartedAt)
        }
        enableEdgeToEdge()
        setContent {
            VoiceTheme {
                MainNavHost(onHomeLogoPositioned = { homeLogoBounds = it })
            }
        }
    }

    private fun configureSplashTransition(splashStartedAt: Long) {
        val centeredAnimationEnd = splashStartedAt + CenteredAnimationDurationMs
        val targetWaitEnd = splashStartedAt + TargetWaitTimeoutMs
        splashScreen.setOnExitAnimationListener { splashView ->
            val iconView = splashView.iconView
            if (iconView == null) {
                splashView.remove()
                return@setOnExitAnimationListener
            }

            fun startWhenTargetIsReady() {
                val target = homeLogoBounds
                val now = SystemClock.uptimeMillis()
                if (target == null) {
                    if (now < targetWaitEnd) {
                        splashView.postDelayed(::startWhenTargetIsReady, TargetPollIntervalMs)
                    } else {
                        splashView.remove()
                    }
                    return
                }

                val targetScale = target.width() / iconView.width
                iconView.scaleX = targetScale
                iconView.scaleY = targetScale
                val travelDelay = (centeredAnimationEnd - now).coerceAtLeast(0L)

                splashView.postDelayed(
                    {
                        val latestTarget = homeLogoBounds ?: target
                        val iconLocation = IntArray(2)
                        iconView.getLocationInWindow(iconLocation)
                        val iconCenterX = iconLocation[0] + (iconView.width / 2f)
                        val iconCenterY = iconLocation[1] + (iconView.height / 2f)

                        iconView.animate()
                            .translationX(latestTarget.centerX() - iconCenterX)
                            .translationY(latestTarget.centerY() - iconCenterY)
                            .setDuration(TravelDurationMs)
                            .setInterpolator(PathInterpolator(0.4f, 0f, 0.2f, 1f))
                            .withEndAction(splashView::remove)
                            .start()
                    },
                    travelDelay
                )
            }

            startWhenTargetIsReady()
        }
    }

    private companion object {
        const val CenteredAnimationDurationMs = 500L
        const val TravelDurationMs = 500L
        const val TargetWaitTimeoutMs = 1_200L
        const val TargetPollIntervalMs = 16L
    }
}
