package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog

data class SetupDownloadModelsStepState(
    val connectedToWifi: Boolean,
    val allowMobileDataDownloads: Boolean,
    val liteRtReady: Boolean,
    val moonshineReady: Boolean,
    val promptReady: Boolean,
    val liteRtDownloading: Boolean,
    val moonshineDownloading: Boolean,
    val promptDownloading: Boolean,
    val liteRtProgress: Int,
    val moonshineProgress: Int,
    val promptProgress: Int,
    val modelMessage: String?,
    val updatesMessage: String?
)

private data class SetupDownloadModelsPresentation(
    val allDownloadsReady: Boolean,
    val downloadInProgress: Boolean,
    val requiresMobileDataApproval: Boolean,
    val canStartDownload: Boolean,
    val shouldShowTotalProgress: Boolean,
    val totalProgressFraction: Float,
    val downloadingTarget: DownloadTarget?
)

private enum class DownloadTarget {
    MOONSHINE,
    LITERT,
    PROMPT
}

@Composable
fun SetupDownloadModelsScreen(
    state: SetupDownloadModelsStepState,
    onAllowMobileDataChange: (Boolean) -> Unit,
    onDownloadModels: () -> Unit
) {
    val presentation = buildSetupDownloadModelsPresentation(state)
    val downloadingModelLabel = when (presentation.downloadingTarget) {
        DownloadTarget.MOONSHINE -> stringResource(R.string.setup_model_moonshine)
        DownloadTarget.LITERT -> stringResource(R.string.setup_model_litert)
        DownloadTarget.PROMPT -> stringResource(R.string.setup_model_prompt)
        null -> null
    }

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
            if (!state.updatesMessage.isNullOrBlank()) {
                Text(
                    text = state.updatesMessage,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (!state.modelMessage.isNullOrBlank()) {
                Text(
                    text = state.modelMessage,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (presentation.shouldShowTotalProgress) {
                if (presentation.downloadInProgress && downloadingModelLabel != null) {
                    Text(
                        text = stringResource(R.string.setup_download_status_model, downloadingModelLabel),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                LinearProgressIndicator(
                    progress = { presentation.totalProgressFraction },
                    modifier = Modifier.fillMaxWidth()
                )
            }
            if (presentation.allDownloadsReady) {
                Text(
                    text = stringResource(R.string.setup_models_ready),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (presentation.requiresMobileDataApproval && !presentation.allDownloadsReady) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = state.allowMobileDataDownloads,
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
            if (presentation.requiresMobileDataApproval && !presentation.allDownloadsReady) {
                Text(
                    text = stringResource(R.string.setup_models_mobile_data_warning),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            Button(
                onClick = onDownloadModels,
                enabled = presentation.canStartDownload,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_download_models))
            }
        }
    )
}

private fun buildSetupDownloadModelsPresentation(
    state: SetupDownloadModelsStepState
): SetupDownloadModelsPresentation {
    val modelsReady = state.liteRtReady && state.moonshineReady
    val allDownloadsReady = modelsReady && state.promptReady
    val downloadInProgress = state.liteRtDownloading || state.moonshineDownloading || state.promptDownloading
    val requiresMobileDataApproval = !state.connectedToWifi
    val canStartDownload = !downloadInProgress &&
        !allDownloadsReady &&
        (!requiresMobileDataApproval || state.allowMobileDataDownloads)

    val liteRtRatio = when {
        state.liteRtReady -> 1f
        state.liteRtDownloading -> state.liteRtProgress.coerceIn(0, 100) / 100f
        else -> 0f
    }
    val moonshineRatio = when {
        state.moonshineReady -> 1f
        state.moonshineDownloading -> state.moonshineProgress.coerceIn(0, 100) / 100f
        else -> 0f
    }
    val promptRatio = when {
        state.promptReady -> 1f
        state.promptDownloading -> state.promptProgress.coerceIn(0, 100) / 100f
        else -> 0f
    }

    val totalModelBytes =
        (ModelCatalog.moonshineMediumStreamingTotalBytes + ModelCatalog.liteRtLm.sizeBytes).toDouble()
            .coerceAtLeast(1.0)
    val completedModelBytes = (ModelCatalog.moonshineMediumStreamingTotalBytes.toDouble() * moonshineRatio) +
        (ModelCatalog.liteRtLm.sizeBytes.toDouble() * liteRtRatio)
    val modelProgressFraction = (completedModelBytes / totalModelBytes).toFloat().coerceIn(0f, 1f)
    val totalProgressFraction = ((modelProgressFraction * 0.99f) + (promptRatio * 0.01f)).coerceIn(0f, 1f)
    val shouldShowTotalProgress =
        downloadInProgress || state.liteRtReady || state.moonshineReady || state.promptReady
    val downloadingTarget = when {
        state.moonshineDownloading -> DownloadTarget.MOONSHINE
        state.liteRtDownloading -> DownloadTarget.LITERT
        state.promptDownloading -> DownloadTarget.PROMPT
        else -> null
    }

    return SetupDownloadModelsPresentation(
        allDownloadsReady = allDownloadsReady,
        downloadInProgress = downloadInProgress,
        requiresMobileDataApproval = requiresMobileDataApproval,
        canStartDownload = canStartDownload,
        shouldShowTotalProgress = shouldShowTotalProgress,
        totalProgressFraction = totalProgressFraction,
        downloadingTarget = downloadingTarget
    )
}
