package com.sanogueralorenzo.overlay

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.rememberNavController
import com.sanogueralorenzo.overlay.about.aboutRoute
import com.sanogueralorenzo.overlay.autotimeout.autoTimeoutRoute
import com.sanogueralorenzo.overlay.overlay.overlayRoute

@Composable
fun AppRoot() {
    val navController = rememberNavController()
    Surface(color = MaterialTheme.colorScheme.background) {
        NavHost(
            navController = navController,
            startDestination = NavRoutes.Overlay
        ) {
            overlayRoute(
                route = NavRoutes.Overlay,
                onOpenAutoTimeout = { navController.navigateSingleTop(NavRoutes.AutoTimeout) },
                onOpenAbout = { navController.navigateSingleTop(NavRoutes.About) }
            )
            autoTimeoutRoute(
                route = NavRoutes.AutoTimeout,
                onBack = { navController.popBackStack() }
            )
            aboutRoute(
                route = NavRoutes.About,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
