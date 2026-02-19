package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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
    onIntroContinue: () -> Unit,
    onSetupStateChanged: () -> Unit,
    modifier: Modifier = Modifier
) {
    val navController = rememberNavController()
    var splashCompleted by rememberSaveable { mutableStateOf(false) }
    val backStackEntry = navController.currentBackStackEntryAsState().value
    val currentRoute = backStackEntry?.destination?.route
    val effectiveRequiredRoute = if (!splashCompleted) SetupRoute.SETUP_SPLASH else requiredRoute

    LaunchedEffect(effectiveRequiredRoute, currentRoute) {
        if (currentRoute != effectiveRequiredRoute) {
            navController.navigateClearingBackStack(effectiveRequiredRoute)
        }
    }

    NavHost(
        navController = navController,
        startDestination = requiredRoute,
        modifier = modifier.fillMaxSize()
    ) {
        composable(SetupRoute.SETUP_SPLASH) {
            SetupSplashScreen(
                onFinished = { splashCompleted = true }
            )
        }

        composable(SetupRoute.SETUP_INTRO) {
            SetupIntroScreen(
                onContinue = { onIntroContinue() }
            )
        }

        composable(SetupRoute.SETUP_MIC) {
            SetupMicPermissionScreen(
                onGrantMic = onGrantMic
            )
        }

        composable(SetupRoute.SETUP_ENABLE_KEYBOARD) {
            SetupEnableKeyboardScreen(
                onOpenImeSettings = onOpenImeSettings
            )
        }

        composable(SetupRoute.SETUP_MODELS) {
            SetupDownloadModelsScreen(
                onModelsReady = onSetupStateChanged
            )
        }

        composable(SetupRoute.SETUP_SELECT_KEYBOARD) {
            SetupSelectKeyboardScreen(
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
