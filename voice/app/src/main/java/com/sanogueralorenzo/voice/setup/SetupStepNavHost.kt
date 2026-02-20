package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController

object SetupRoute {
    const val SETUP_SPLASH = "setup_splash"
    const val SETUP_INTRO = "setup_intro"
    const val SETUP_MIC = "setup_mic"
    const val SETUP_ENABLE_KEYBOARD = "setup_enable_keyboard"
    const val SETUP_MODELS = "setup_models"
    const val SETUP_SELECT_KEYBOARD = "setup_select_keyboard"
}

@Composable
fun SetupStepNavHost(
    requiredRoute: String,
    onGrantMic: () -> Unit,
    onOpenImeSettings: () -> Unit,
    onShowImePicker: () -> Unit,
    onSplashFinished: () -> Unit,
    onIntroContinue: () -> Unit,
    onSetupStateChanged: () -> Unit,
    modifier: Modifier = Modifier
) {
    val navController = rememberNavController()
    val backStackEntry = navController.currentBackStackEntryAsState().value
    val currentRoute = backStackEntry?.destination?.route

    LaunchedEffect(requiredRoute, currentRoute) {
        if (currentRoute != requiredRoute) {
            navController.navigateClearingBackStack(requiredRoute)
        }
    }

    NavHost(
        navController = navController,
        startDestination = requiredRoute,
        modifier = modifier.fillMaxSize()
    ) {
        composable(SetupRoute.SETUP_SPLASH) {
            SetupStep1SplashScreen(onFinished = onSplashFinished)
        }

        composable(SetupRoute.SETUP_INTRO) {
            SetupStep2IntroScreen(
                onContinue = onIntroContinue
            )
        }

        composable(SetupRoute.SETUP_MIC) {
            SetupStep4MicPermissionScreen(
                onGrantMic = onGrantMic
            )
        }

        composable(SetupRoute.SETUP_ENABLE_KEYBOARD) {
            SetupStep5KeyboardEnableScreen(
                onOpenImeSettings = onOpenImeSettings
            )
        }

        composable(SetupRoute.SETUP_MODELS) {
            SetupStep3ModelsDownloadScreen(
                onModelsReady = onSetupStateChanged
            )
        }

        composable(SetupRoute.SETUP_SELECT_KEYBOARD) {
            SetupStep6KeyboardSelectScreen(
                onRequestKeyboardPicker = onShowImePicker,
                onDone = onSetupStateChanged
            )
        }
    }
}

private fun NavHostController.navigateClearingBackStack(route: String) {
    while (popBackStack()) {
        // Keep popping until the stack is empty so required setup step can take over.
    }
    navigate(route) {
        launchSingleTop = true
    }
}
