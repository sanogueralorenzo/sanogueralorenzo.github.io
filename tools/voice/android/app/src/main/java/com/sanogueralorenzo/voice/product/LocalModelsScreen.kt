package com.sanogueralorenzo.voice.product

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.progressSemantics
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.audio.DictationLanguage
import com.sanogueralorenzo.voice.models.LanguageModelStatus
import com.sanogueralorenzo.voice.ui.components.DestinationScaffold

@Composable
fun LocalModelsScreen(onBack: () -> Unit) {
    val viewModel = mavericksViewModel<LocalModelsViewModel, LocalModelsState>()
    val state = viewModel.collectAsStateWithLifecycle().value

    DestinationScaffold(
        title = stringResource(R.string.models_title),
        onBack = onBack
    ) { innerPadding ->
        LocalModelsContent(
            state = state,
            onDownload = viewModel::download,
            onSwapLanguages = viewModel::swapLanguages,
            modifier = Modifier.padding(innerPadding)
        )
    }
}

@Composable
private fun LocalModelsContent(
    state: LocalModelsState,
    onDownload: (DictationLanguage) -> Unit,
    onSwapLanguages: () -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(
                text = stringResource(R.string.models_explanation),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        item {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    state.models.forEachIndexed { index, model ->
                        LanguageModelRow(
                            model = model,
                            downloadedCount = state.downloadedCount,
                            loading = state.loading,
                            operationInProgress = state.operationInProgress,
                            onDownload = { onDownload(model.language) }
                        )
                        if (index < state.models.lastIndex) {
                            HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                        }
                    }
                }
            }
        }
        if (state.downloadedCount > 1) {
            item {
                FilledTonalButton(
                    onClick = onSwapLanguages,
                    enabled = !state.operationInProgress,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(
                        imageVector = Icons.Rounded.SwapVert,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(text = stringResource(R.string.models_swap_languages))
                }
            }
        }
    }
}

@Composable
private fun LanguageModelRow(
    model: LanguageModelStatus,
    downloadedCount: Int,
    loading: Boolean,
    operationInProgress: Boolean,
    onDownload: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = languageName(model.language),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = modelSubtitle(model, downloadedCount),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            when {
                model.downloading -> ModelDownloadProgress(model.progress)
                model.ready -> Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = stringResource(R.string.models_downloaded),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(24.dp)
                )
                !loading -> Button(
                    onClick = onDownload,
                    enabled = !operationInProgress
                ) {
                    Text(text = stringResource(R.string.models_download))
                }
            }
        }
        model.error?.takeIf(String::isNotBlank)?.let { error ->
            Text(
                text = error,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }
    }
}

@Composable
private fun ModelDownloadProgress(progress: Int) {
    val safeProgress = progress.coerceIn(0, 100)
    val progressFraction = safeProgress / 100f
    Box(
        modifier = Modifier
            .width(112.dp)
            .height(36.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .progressSemantics(progressFraction)
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(progressFraction)
                .background(MaterialTheme.colorScheme.primaryContainer)
        )
        Text(
            text = "$safeProgress%",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.align(Alignment.Center)
        )
    }
}

@Composable
private fun modelSubtitle(model: LanguageModelStatus, downloadedCount: Int): String {
    if (!model.ready) return modelSize(model.language)
    return if (downloadedCount == 1) {
        stringResource(R.string.models_only_gesture)
    } else if (model.orderIndex == 0) {
        stringResource(R.string.models_tap_gesture)
    } else {
        stringResource(R.string.models_long_press_gesture)
    }
}

@Composable
private fun languageName(language: DictationLanguage): String {
    return stringResource(
        when (language) {
            DictationLanguage.ENGLISH -> R.string.models_english_name
            DictationLanguage.SPANISH -> R.string.models_spanish_name
        }
    )
}

@Composable
private fun modelSize(language: DictationLanguage): String {
    return stringResource(
        when (language) {
            DictationLanguage.ENGLISH -> R.string.models_english_size
            DictationLanguage.SPANISH -> R.string.models_spanish_size
        }
    )
}
