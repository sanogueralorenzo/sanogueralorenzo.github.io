package com.sanogueralorenzo.overlay

import androidx.navigation.NavController

fun NavController.navigateSingleTop(route: String) {
    navigate(route) {
        launchSingleTop = true
    }
}
