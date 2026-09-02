package com.sanogueralorenzo.voice

import androidx.navigation.NavController

object NavRoutes {
    const val Home = "voice_home"
    const val OverlayPosition = "voice_mic_position"
    const val LocalModels = "voice_local_models"
}

fun NavController.navigateSingleTop(route: String) {
    navigate(route) {
        launchSingleTop = true
    }
}
