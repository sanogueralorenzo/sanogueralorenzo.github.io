package com.sanogueralorenzo.voice.setup

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import java.util.Locale

@Composable
fun ModelsScreen(
    liteRtReady: Boolean,
    moonshineReady: Boolean,
    liteRtDownloading: Boolean,
    moonshineDownloading: Boolean,
    liteRtProgress: Int,
    moonshineProgress: Int,
    downloadMessage: String?,
    updatesMessage: String?,
    onDownloadAll: () -> Unit,
    onDownloadLiteRt: () -> Unit,
    onDownloadMoonshine: () -> Unit,
    onCheckUpdates: () -> Unit,
    actionsEnabled: Boolean
) {
    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.models_section_title),
            style = MaterialTheme.typography.titleLarge
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = onDownloadAll,
                enabled = actionsEnabled && !(liteRtReady && moonshineReady)
            ) {
                Text(text = stringResource(R.string.setup_download_all))
            }
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.models_check_updates_section_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = stringResource(R.string.models_check_updates_section_description),
                    style = MaterialTheme.typography.bodyMedium
                )
                OutlinedButton(
                    onClick = onCheckUpdates,
                    enabled = actionsEnabled
                ) {
                    Text(text = stringResource(R.string.models_check_updates_action))
                }
                if (!updatesMessage.isNullOrBlank()) {
                    Text(text = updatesMessage, style = MaterialTheme.typography.bodySmall)
                }
            }
        }

        if (!downloadMessage.isNullOrBlank()) {
            Text(text = downloadMessage, style = MaterialTheme.typography.bodySmall)
        }

        Text(
            text = stringResource(
                R.string.setup_model_row,
                stringResource(R.string.setup_model_litert),
                humanReadableSize(context, ModelCatalog.liteRtLm.sizeBytes),
                modelStatus(context, liteRtReady, liteRtDownloading, liteRtProgress)
            ),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(text = ModelCatalog.liteRtLm.notes, style = MaterialTheme.typography.bodySmall)
        Button(
            onClick = onDownloadLiteRt,
            enabled = actionsEnabled && !liteRtReady
        ) {
            Text(text = stringResource(R.string.setup_download_litert))
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
            text = stringResource(R.string.setup_model_moonshine_note),
            style = MaterialTheme.typography.bodySmall
        )
        Button(
            onClick = onDownloadMoonshine,
            enabled = actionsEnabled && !moonshineReady
        ) {
            Text(text = stringResource(R.string.setup_download_moonshine))
        }
    }
}

private fun modelStatus(context: Context, ready: Boolean, downloading: Boolean, progress: Int): String {
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
