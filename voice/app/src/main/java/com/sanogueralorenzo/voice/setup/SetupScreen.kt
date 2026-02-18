package com.sanogueralorenzo.voice.setup

import android.content.Context
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.ui.VoicePillVisualizer
import com.sanogueralorenzo.voice.ui.VoicePillVisualizerWidth
import com.sanogueralorenzo.voice.ui.VoiceVisualizerMode
import kotlinx.coroutines.delay
import java.util.Locale

@Composable
fun SetupSplashScreen(
    onFinished: () -> Unit
) {
    val moveProgress = remember { Animatable(0f) }
    var freezeBars by remember { mutableStateOf(false) }
    var fadeOut by remember { mutableStateOf(false) }
    val splashAlpha by animateFloatAsState(
        targetValue = if (fadeOut) 0f else 1f,
        animationSpec = tween(durationMillis = SetupSplashFadeOutMs, easing = FastOutSlowInEasing),
        label = "setup_splash_alpha"
    )
    val levelTransition = rememberInfiniteTransition(label = "setup_splash_audio")
    val fakeAudioLevel by levelTransition.animateFloat(
        initialValue = 0.32f,
        targetValue = 0.95f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 420, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "setup_splash_audio_level"
    )

    LaunchedEffect(Unit) {
        delay(SetupSplashCenterHoldMs.toLong())
        moveProgress.animateTo(
            targetValue = 1f,
            animationSpec = tween(durationMillis = SetupSplashTravelMs, easing = FastOutSlowInEasing)
        )
        freezeBars = true
        delay(SetupSplashFrozenHoldMs.toLong())
        fadeOut = true
        delay(SetupSplashFadeOutMs.toLong())
        onFinished()
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer { alpha = splashAlpha }
    ) {
        val startTop = (maxHeight - SetupLogoSize) * 0.5f
        val endTop = SetupScreenOuterPadding + SetupLogoVerticalPadding
        val animatedTop = lerp(startTop, endTop, moveProgress.value)

        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .offset(y = animatedTop)
                .size(SetupLogoSize),
            contentAlignment = Alignment.Center
        ) {
            if (freezeBars) {
                Image(
                    painter = painterResource(id = R.drawable.ic_logo_bars),
                    contentDescription = null,
                    modifier = Modifier.size(SetupLogoSize)
                )
            } else {
                VoicePillVisualizer(
                    level = fakeAudioLevel,
                    mode = VoiceVisualizerMode.RECORDING_BARS
                )
            }
        }
    }
}

@Composable
fun SetupIntroScreen(
    onContinue: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_intro),
        body = {
            Text(
                text = stringResource(R.string.setup_intro_message),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(R.string.setup_intro_bullet_mic),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_intro_bullet_keyboard),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_intro_bullet_models),
                style = MaterialTheme.typography.bodySmall
            )
        },
        actions = {
            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_intro_continue))
            }
        }
    )
}

@Composable
fun SetupMicPermissionScreen(
    onGrantMic: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_microphone),
        body = {
            Text(
                text = stringResource(R.string.setup_mic_intro),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(R.string.setup_mic_bullet_while_using),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_mic_bullet_local),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_mic_bullet_offline_after_download),
                style = MaterialTheme.typography.bodySmall
            )
        },
        actions = {
            Button(
                onClick = onGrantMic,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_grant_mic))
            }
        }
    )
}

@Composable
fun SetupEnableKeyboardScreen(
    onOpenImeSettings: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_enable_keyboard),
        body = {
            Text(
                text = stringResource(R.string.setup_enable_keyboard_intro),
                style = MaterialTheme.typography.bodyMedium
            )
        },
        actions = {
            Button(
                onClick = onOpenImeSettings,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_enable_keyboard))
            }
        }
    )
}

@Composable
fun SetupChooseKeyboardScreen(
    onShowImePicker: () -> Unit
) {
    SetupStepScaffold(
        title = stringResource(R.string.setup_step_choose_keyboard),
        body = {
            Text(
                text = stringResource(R.string.setup_choose_keyboard_intro),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(R.string.setup_keyboard_button_recommendation),
                style = MaterialTheme.typography.bodySmall
            )
        },
        actions = {
            Button(
                onClick = onShowImePicker,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_choose_keyboard))
            }
        }
    )
}

@Composable
fun SetupDownloadModelsScreen(
    connectedToWifi: Boolean,
    allowMobileDataDownloads: Boolean,
    liteRtReady: Boolean,
    moonshineReady: Boolean,
    promptReady: Boolean,
    liteRtDownloading: Boolean,
    moonshineDownloading: Boolean,
    promptDownloading: Boolean,
    liteRtProgress: Int,
    moonshineProgress: Int,
    promptProgress: Int,
    promptVersion: String?,
    modelMessage: String?,
    updatesMessage: String?,
    onAllowMobileDataChange: (Boolean) -> Unit,
    onDownloadModels: () -> Unit
) {
    val context = LocalContext.current
    val modelsReady = liteRtReady && moonshineReady && promptReady
    val downloadInProgress = liteRtDownloading || moonshineDownloading || promptDownloading
    val requiresMobileDataApproval = !connectedToWifi
    val canStartDownload = !downloadInProgress &&
        !modelsReady &&
        (!requiresMobileDataApproval || allowMobileDataDownloads)

    SetupStepScaffold(
        title = stringResource(R.string.setup_step_models),
        body = {
            Text(
                text = stringResource(R.string.setup_models_intro),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(R.string.setup_models_intro_bullet_asr),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_models_intro_bullet_it),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_models_intro_bullet_prompt),
                style = MaterialTheme.typography.bodySmall
            )
            if (!updatesMessage.isNullOrBlank()) {
                Text(
                    text = updatesMessage,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (!modelMessage.isNullOrBlank()) {
                Text(
                    text = modelMessage,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            Text(
                text = stringResource(
                    R.string.setup_model_row,
                    stringResource(R.string.setup_model_moonshine),
                    humanReadableSize(context, ModelCatalog.moonshineMediumStreamingTotalBytes),
                    modelStatus(context, moonshineReady, moonshineDownloading, moonshineProgress)
                ),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(
                    R.string.setup_model_row,
                    stringResource(R.string.setup_model_litert),
                    humanReadableSize(context, ModelCatalog.liteRtLm.sizeBytes),
                    modelStatus(context, liteRtReady, liteRtDownloading, liteRtProgress)
                ),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(
                    R.string.setup_model_row,
                    stringResource(R.string.setup_model_prompt),
                    promptVersion?.let { stringResource(R.string.setup_prompt_version_value, it) }
                        ?: stringResource(R.string.setup_prompt_version_missing),
                    modelStatus(context, promptReady, promptDownloading, promptProgress)
                ),
                style = MaterialTheme.typography.bodyMedium
            )
            if (modelsReady) {
                Text(
                    text = stringResource(R.string.setup_models_ready),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (requiresMobileDataApproval && !modelsReady) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = allowMobileDataDownloads,
                        onCheckedChange = onAllowMobileDataChange
                    )
                    Text(
                        text = stringResource(R.string.setup_allow_mobile_data),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        },
        actions = {
            if (requiresMobileDataApproval && !modelsReady) {
                Text(
                    text = stringResource(R.string.setup_models_mobile_data_warning),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            Button(
                onClick = onDownloadModels,
                enabled = canStartDownload,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_download_models))
            }
        }
    )
}

@Composable
private fun SetupStepScaffold(
    title: String,
    body: @Composable () -> Unit,
    actions: @Composable () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(SetupScreenOuterPadding),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            SetupTopIcon()
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge
            )
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    body()
                }
            }
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            actions()
        }
    }
}

@Composable
private fun SetupTopIcon() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .wrapContentHeight()
            .padding(vertical = SetupLogoVerticalPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Image(
            painter = painterResource(id = R.drawable.ic_logo),
            contentDescription = stringResource(R.string.app_name),
            modifier = Modifier.size(SetupLogoSize)
        )
    }
}

private fun modelStatus(
    context: Context,
    ready: Boolean,
    downloading: Boolean,
    progress: Int
): String {
    return when {
        ready -> context.getString(R.string.setup_status_ready)
        downloading -> context.getString(R.string.setup_status_downloading, progress)
        else -> context.getString(R.string.setup_status_missing)
    }
}

private fun humanReadableSize(context: Context, bytes: Long): String {
    if (bytes <= 0L) return context.getString(R.string.setup_unknown_value)
    val mb = bytes / (1024.0 * 1024.0)
    return String.format(Locale.US, "%.0f MB", mb)
}

private val SetupScreenOuterPadding = 20.dp
private val SetupLogoVerticalPadding = 20.dp
private val SetupLogoSize = VoicePillVisualizerWidth
private const val SetupSplashCenterHoldMs = 3_000
private const val SetupSplashTravelMs = 700
private const val SetupSplashFrozenHoldMs = 300
private const val SetupSplashFadeOutMs = 240
