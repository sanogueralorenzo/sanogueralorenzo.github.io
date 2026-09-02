package com.sanogueralorenzo.voice

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.sanogueralorenzo.voice.overlay.OverlayPositionScreen
import com.sanogueralorenzo.voice.models.LocalModelsScreen
import com.sanogueralorenzo.voice.home.VoiceHomeScreen

@Composable
fun AppRoot() {
    val navController = rememberNavController()
    Surface(color = MaterialTheme.colorScheme.background) {
        NavHost(
            navController = navController,
            startDestination = NavRoutes.Home
        ) {
            composable(NavRoutes.Home) {
                VoiceHomeScreen(
                    onOpenLocalModels = {
                        navController.navigateSingleTop(NavRoutes.LocalModels)
                    },
                    onOpenMicPosition = {
                        navController.navigateSingleTop(NavRoutes.OverlayPosition)
                    }
                )
            }
            composable(NavRoutes.LocalModels) {
                LocalModelsScreen(onBack = navController::popBackStack)
            }
            composable(NavRoutes.OverlayPosition) {
                OverlayPositionScreen(onBack = navController::popBackStack)
            }
        }
    }
}
