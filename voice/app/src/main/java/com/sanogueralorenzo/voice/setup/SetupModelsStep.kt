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
    modelMessage: String?,
    updatesMessage: String?,
    onAllowMobileDataChange: (Boolean) -> Unit,
    onDownloadModels: () -> Unit
) {
    val modelsReady = liteRtReady && moonshineReady
    val allDownloadsReady = modelsReady && promptReady
    val downloadInProgress = liteRtDownloading || moonshineDownloading || promptDownloading
    val requiresMobileDataApproval = !connectedToWifi
    val canStartDownload = !downloadInProgress &&
        !allDownloadsReady &&
        (!requiresMobileDataApproval || allowMobileDataDownloads)

    val liteRtRatio = when {
        liteRtReady -> 1f
        liteRtDownloading -> liteRtProgress.coerceIn(0, 100) / 100f
        else -> 0f
    }
    val moonshineRatio = when {
        moonshineReady -> 1f
        moonshineDownloading -> moonshineProgress.coerceIn(0, 100) / 100f
        else -> 0f
    }
    val totalModelBytes =
        (ModelCatalog.moonshineMediumStreamingTotalBytes + ModelCatalog.liteRtLm.sizeBytes).toDouble()
            .coerceAtLeast(1.0)
    val completedModelBytes = (ModelCatalog.moonshineMediumStreamingTotalBytes.toDouble() * moonshineRatio) +
        (ModelCatalog.liteRtLm.sizeBytes.toDouble() * liteRtRatio)
    val modelProgressPercent = ((completedModelBytes / totalModelBytes) * 100.0).toFloat().coerceIn(0f, 100f)
    val totalProgressPercent = if (modelsReady) {
        100f
    } else {
        modelProgressPercent
    }
    val shouldShowTotalProgress =
        downloadInProgress || liteRtReady || moonshineReady || promptReady

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
            if (shouldShowTotalProgress) {
                if (downloadInProgress) {
                    Text(
                        text = stringResource(R.string.setup_download_sequence_status),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                LinearProgressIndicator(
                    progress = { totalProgressPercent / 100f },
                    modifier = Modifier.fillMaxWidth()
                )
            }
            if (allDownloadsReady) {
                Text(
                    text = stringResource(R.string.setup_models_ready),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (requiresMobileDataApproval && !allDownloadsReady) {
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
            if (requiresMobileDataApproval && !allDownloadsReady) {
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
