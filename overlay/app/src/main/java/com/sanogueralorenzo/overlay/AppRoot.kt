package com.sanogueralorenzo.overlay

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.rememberNavController
import com.sanogueralorenzo.overlay.help.helpRoute
import com.sanogueralorenzo.overlay.home.homeRoute
import com.sanogueralorenzo.overlay.permissions.permissionsRoute

@Composable
fun AppRoot() {
    val navController = rememberNavController()
    val navigateBackToHome: () -> Unit = {
        if (!navController.popBackStack(NavRoutes.Home, false)) {
            navController.navigateSingleTop(NavRoutes.Home)
        }
    }
    Surface(color = MaterialTheme.colorScheme.background) {
        NavHost(
            navController = navController,
            startDestination = NavRoutes.Home
        ) {
            homeRoute(
                route = NavRoutes.Home,
                onOpenHelp = { navController.navigateSingleTop(NavRoutes.Help) },
                onOpenPermissions = { navController.navigateSingleTop(NavRoutes.Permissions) }
            )
            helpRoute(
                route = NavRoutes.Help,
                onBack = navigateBackToHome
            )
            permissionsRoute(
                route = NavRoutes.Permissions,
                onBack = navigateBackToHome
            )
        }
    }
}
