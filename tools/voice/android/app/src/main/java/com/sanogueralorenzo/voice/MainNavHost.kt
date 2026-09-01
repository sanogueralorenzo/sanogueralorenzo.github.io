package com.sanogueralorenzo.voice

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.sanogueralorenzo.voice.overlay.OverlayPositionScreen
import com.sanogueralorenzo.voice.product.LocalModelsScreen
import com.sanogueralorenzo.voice.product.VoiceHomeScreen

private object VoiceRoute {
    const val HOME = "voice_home"
    const val MIC_POSITION = "voice_mic_position"
    const val LOCAL_MODELS = "voice_local_models"
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun MainNavHost() {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val route = backStackEntry?.destination?.route
    val isHome = route == null || route == VoiceRoute.HOME

    Scaffold(
        topBar = {
            if (!isHome) {
                TopAppBar(
                    title = {
                        Text(
                            text = stringResource(
                                if (route == VoiceRoute.LOCAL_MODELS) {
                                    R.string.models_title
                                } else {
                                    R.string.product_mic_position_title
                                }
                            )
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = { navController.popBackStack() }) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                                contentDescription = stringResource(R.string.main_back)
                            )
                        }
                    },
                    actions = {
                        if (route == VoiceRoute.MIC_POSITION) {
                            TextButton(onClick = { navController.popBackStack() }) {
                                Text(text = stringResource(R.string.main_done))
                            }
                        }
                    }
                )
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = VoiceRoute.HOME,
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            composable(VoiceRoute.HOME) {
                VoiceHomeScreen(
                    onOpenLocalModels = { navController.navigate(VoiceRoute.LOCAL_MODELS) },
                    onOpenMicPosition = { navController.navigate(VoiceRoute.MIC_POSITION) }
                )
            }
            composable(VoiceRoute.LOCAL_MODELS) {
                LocalModelsScreen()
            }
            composable(VoiceRoute.MIC_POSITION) {
                OverlayPositionScreen()
            }
        }
    }
}
