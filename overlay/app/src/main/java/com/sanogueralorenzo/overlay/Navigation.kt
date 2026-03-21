package com.sanogueralorenzo.overlay

import androidx.navigation.NavController

object NavRoutes {
    const val Home = "home"
    const val Permissions = "permissions"
}

fun NavController.navigateSingleTop(route: String) {
    navigate(route) {
        launchSingleTop = true
    }
}
