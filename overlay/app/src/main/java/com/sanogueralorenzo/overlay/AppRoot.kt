package com.sanogueralorenzo.overlay

import android.os.Build
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.rememberNavController
import com.sanogueralorenzo.overlay.about.aboutRoute
import com.sanogueralorenzo.overlay.autotimeout.autoTimeoutRoute
import com.sanogueralorenzo.overlay.overlay.overlayRoute
import com.sanogueralorenzo.overlay.settings.informationRoute

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
                canRequestTile = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                onOpenAutoTimeout = { navController.navigateSingleTop(NavRoutes.AutoTimeout) },
                onOpenInformation = { navController.navigateSingleTop(NavRoutes.Information) }
            )
            aboutRoute(
                route = NavRoutes.About,
                onBack = { navController.popBackStack() }
            )
            informationRoute(
                route = NavRoutes.Information,
                onOpenAbout = { navController.navigateSingleTop(NavRoutes.About) },
                onBack = { navController.popBackStack() }
            )
            autoTimeoutRoute(
                route = NavRoutes.AutoTimeout,
                canRequestTile = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
