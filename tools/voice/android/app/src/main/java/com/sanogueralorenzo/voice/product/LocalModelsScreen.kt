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
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.audio.DictationLanguage

@Composable
fun LocalModelsScreen() {
    val viewModel = mavericksViewModel<LocalModelsViewModel, LocalModelsState>()
    val state by viewModel.collectAsStateWithLifecycle()
    var pendingRemoval by remember { mutableStateOf<DictationLanguage?>(null) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { GestureExplanationCard() }
        state.models.forEach { model ->
            item(key = model.language.name) {
                LanguageModelCard(
                    model = model,
                    enabledCount = state.enabledCount,
                    operationInProgress = state.operationInProgress,
                    onEnabledChange = { enabled ->
                        viewModel.setEnabled(model.language, enabled)
                    },
                    onMoveEarlier = { viewModel.moveEarlier(model.language) },
                    onMoveLater = { viewModel.moveLater(model.language) },
                    onDownload = { viewModel.download(model.language) },
                    onRemove = { pendingRemoval = model.language }
                )
            }
        }
        item { Spacer(modifier = Modifier.height(4.dp)) }
    }

    pendingRemoval?.let { language ->
        AlertDialog(
            onDismissRequest = { pendingRemoval = null },
            title = {
                Text(
                    text = stringResource(
                        R.string.models_remove_title,
                        languageName(language)
                    )
                )
            },
            text = { Text(text = stringResource(R.string.models_remove_body)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingRemoval = null
                        viewModel.remove(language)
                    }
                ) {
                    Text(text = stringResource(R.string.models_remove))
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingRemoval = null }) {
                    Text(text = stringResource(R.string.product_action_cancel))
                }
            }
        )
    }
}

@Composable
private fun GestureExplanationCard() {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.models_explanation),
                style = MaterialTheme.typography.bodyLarge
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureChip(text = stringResource(R.string.models_first_gesture))
                GestureChip(text = stringResource(R.string.models_second_gesture))
            }
        }
    }
}

@Composable
private fun GestureChip(text: String) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(50)
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
        )
    }
}

@Composable
private fun LanguageModelCard(
    model: LanguageModelState,
    enabledCount: Int,
    operationInProgress: Boolean,
    onEnabledChange: (Boolean) -> Unit,
    onMoveEarlier: () -> Unit,
    onMoveLater: () -> Unit,
    onDownload: () -> Unit,
    onRemove: () -> Unit
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = languageName(model.language),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = modelDetail(model.language),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = model.enabled,
                    enabled = !operationInProgress && (!model.enabled || enabledCount > 1),
                    onCheckedChange = onEnabledChange
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                GestureChip(text = gestureLabel(model, enabledCount))
                Spacer(modifier = Modifier.weight(1f))
                if (model.enabled && model.orderIndex != null && enabledCount > 1) {
                    IconButton(
                        onClick = onMoveEarlier,
                        enabled = !operationInProgress && model.orderIndex > 0
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.KeyboardArrowUp,
                            contentDescription = stringResource(R.string.models_move_earlier)
                        )
                    }
                    IconButton(
                        onClick = onMoveLater,
                        enabled = !operationInProgress && model.orderIndex < enabledCount - 1
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.KeyboardArrowDown,
                            contentDescription = stringResource(R.string.models_move_later)
                        )
                    }
                }
            }

            ModelStorageRow(
                model = model,
                operationInProgress = operationInProgress,
                onDownload = onDownload,
                onRemove = onRemove
            )
            model.error?.takeIf { it.isNotBlank() }?.let { error ->
                Text(
                    text = error,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}

@Composable
private fun ModelStorageRow(
    model: LanguageModelState,
    operationInProgress: Boolean,
    onDownload: () -> Unit,
    onRemove: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = if (model.ready) Icons.Rounded.Check else Icons.Outlined.ErrorOutline,
            contentDescription = null,
            tint = if (model.ready) {
                MaterialTheme.colorScheme.onSurfaceVariant
            } else {
                MaterialTheme.colorScheme.outline
            },
            modifier = Modifier.size(20.dp)
        )
        Text(
            text = stringResource(
                if (model.ready) R.string.models_downloaded else R.string.models_not_downloaded
            ),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .padding(start = 8.dp)
                .weight(1f)
        )
        when {
            model.downloading -> ModelDownloadProgress(model.progress)
            model.removing -> Text(
                text = stringResource(R.string.models_remove),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            model.ready -> TextButton(
                onClick = onRemove,
                enabled = !operationInProgress
            ) {
                Icon(
                    imageVector = Icons.Outlined.DeleteOutline,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(text = stringResource(R.string.models_remove))
            }
            model.enabled -> Button(
                onClick = onDownload,
                enabled = !operationInProgress
            ) {
                Text(text = stringResource(R.string.models_download))
            }
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
private fun gestureLabel(model: LanguageModelState, enabledCount: Int): String {
    if (!model.enabled) return stringResource(R.string.models_disabled)
    if (enabledCount == 1) return stringResource(R.string.models_only_gesture)
    return stringResource(
        if (model.orderIndex == 0) R.string.models_first_gesture
        else R.string.models_second_gesture
    )
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
