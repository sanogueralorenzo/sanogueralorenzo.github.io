package com.sanogueralorenzo.voice

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.sanogueralorenzo.voice.di.appGraph
import com.sanogueralorenzo.voice.setup.SetupRepository
import com.sanogueralorenzo.voice.settings.SettingsFlowScreen
import com.sanogueralorenzo.voice.setup.SetupFlowScreen

private object MainRoute {
    const val SETUP_FLOW = "main_setup_flow"
    const val SETTINGS_FLOW = "main_settings_flow"
}

@Composable
fun MainNavHost() {
    val context = LocalContext.current
    val appContext = remember(context) { context.applicationContext }
    val appGraph = remember(appContext) { appContext.appGraph() }
    val setupRepository = remember(appGraph) { appGraph.setupRepository }
    val navController = rememberNavController()
    val startDestination = remember(setupRepository) {
        if (setupRepository.requiredStep() != SetupRepository.RequiredStep.COMPLETE) {
            MainRoute.SETUP_FLOW
        } else {
            MainRoute.SETTINGS_FLOW
        }
    }

    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {
        composable(MainRoute.SETUP_FLOW) {
            SetupFlowScreen(
                onSetupComplete = {
                    navController.navigate(MainRoute.SETTINGS_FLOW) {
                        popUpTo(MainRoute.SETUP_FLOW) { inclusive = true }
                        launchSingleTop = true
                    }
                }
            )
        }
        composable(MainRoute.SETTINGS_FLOW) {
            SettingsFlowScreen()
        }
    }
}
