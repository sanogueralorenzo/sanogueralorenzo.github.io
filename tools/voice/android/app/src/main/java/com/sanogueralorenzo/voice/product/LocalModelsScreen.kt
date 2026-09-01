package com.sanogueralorenzo.voice.product

import android.content.ClipData
import androidx.compose.foundation.background
import androidx.compose.foundation.draganddrop.dragAndDropSource
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.ui.draganddrop.DragAndDropTransferData
import androidx.compose.ui.draganddrop.toAndroidDragEvent
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.audio.DictationLanguage

@Composable
fun LocalModelsScreen() {
    val viewModel = mavericksViewModel<LocalModelsViewModel, LocalModelsState>()
    val state = viewModel.collectAsStateWithLifecycle().value

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
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
                            onDownload = { viewModel.download(model.language) },
                            onMoveBefore = viewModel::moveBefore
                        )
                        if (index < state.models.lastIndex) {
                            HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LanguageModelRow(
    model: LanguageModelState,
    downloadedCount: Int,
    loading: Boolean,
    operationInProgress: Boolean,
    onDownload: () -> Unit,
    onMoveBefore: (DictationLanguage, DictationLanguage) -> Unit
) {
    val reorderEnabled = downloadedCount > 1 && model.ready && !operationInProgress
    val dropTarget = remember(model.language, onMoveBefore) {
        object : DragAndDropTarget {
            override fun onDrop(event: DragAndDropEvent): Boolean {
                val dragged = event.toAndroidDragEvent().localState as? DictationLanguage
                    ?: return false
                if (dragged == model.language) return false
                onMoveBefore(dragged, model.language)
                return true
            }
        }
    }
    val dropModifier = if (reorderEnabled) {
        Modifier.dragAndDropTarget(
            shouldStartDragAndDrop = { event ->
                val dragged = event.toAndroidDragEvent().localState as? DictationLanguage
                dragged != null && dragged != model.language
            },
            target = dropTarget
        )
    } else {
        Modifier
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(dropModifier)
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
                model.ready && reorderEnabled -> DragHandle(model.language)
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
private fun DragHandle(language: DictationLanguage) {
    Icon(
        imageVector = Icons.Rounded.DragHandle,
        contentDescription = stringResource(R.string.models_drag_language),
        tint = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .size(40.dp)
            .dragAndDropSource(transferData = {
                DragAndDropTransferData(
                    clipData = ClipData.newPlainText(DRAG_LABEL, language.name),
                    localState = language
                )
            })
            .padding(8.dp)
    )
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
private fun modelSubtitle(model: LanguageModelState, downloadedCount: Int): String {
    val detail = modelDetail(model.language)
    if (!model.ready) return detail
    val gesture = if (downloadedCount == 1) {
        stringResource(R.string.models_only_gesture)
    } else if (model.orderIndex == 0) {
        stringResource(R.string.models_first_gesture)
    } else {
        stringResource(R.string.models_second_gesture)
    }
    return "$detail · $gesture"
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
private fun modelDetail(language: DictationLanguage): String {
    return stringResource(
        when (language) {
            DictationLanguage.ENGLISH -> R.string.models_english_detail
            DictationLanguage.SPANISH -> R.string.models_spanish_detail
        }
    )
}

private const val DRAG_LABEL = "Voice language"
