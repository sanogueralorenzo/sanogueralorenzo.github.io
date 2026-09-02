package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R

@Composable
fun InputTypeSetupRow(
    selected: VoiceInputType?,
    loading: Boolean,
    onSelect: (VoiceInputType) -> Unit
) {
    SetupRowContainer {
        SetupStatusIcon(ready = selected != null, loading = loading)
        Text(
            text = stringResource(R.string.product_status_type),
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f)
        )
        FilterChip(
            selected = selected == VoiceInputType.KEYBOARD,
            onClick = { onSelect(VoiceInputType.KEYBOARD) },
            enabled = !loading,
            label = { Text(stringResource(R.string.product_type_keyboard)) }
        )
        FilterChip(
            selected = selected == VoiceInputType.OVERLAY,
            onClick = { onSelect(VoiceInputType.OVERLAY) },
            enabled = !loading,
            label = { Text(stringResource(R.string.product_type_overlay)) }
        )
    }
}

@Composable
fun LocalModelsSetupRow(
    ready: Boolean,
    loading: Boolean,
    onClick: () -> Unit
) {
    SetupRowContainer(modifier = Modifier.clickable(onClick = onClick)) {
        SetupStatusIcon(ready = ready, loading = loading)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = stringResource(R.string.product_status_models),
                style = MaterialTheme.typography.bodyLarge
            )
            if (!ready && !loading) {
                Text(
                    text = stringResource(R.string.models_download_required),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (!ready && !loading) {
            Button(onClick = onClick) {
                Text(text = stringResource(R.string.product_action_download))
            }
        } else {
            SetupArrow()
        }
    }
}

@Composable
fun SetupStatusRow(
    title: String,
    subtitle: String? = null,
    completedTitle: String? = null,
    completedSubtitle: String? = null,
    ready: Boolean,
    loading: Boolean,
    actionLabel: String,
    onAction: () -> Unit,
    onCompletedAction: (() -> Unit)? = null
) {
    val clickModifier = if (ready && onCompletedAction != null) {
        Modifier.clickable(onClick = onCompletedAction)
    } else {
        Modifier
    }
    SetupRowContainer(modifier = clickModifier) {
        SetupStatusIcon(ready = ready, loading = loading)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = if (ready) completedTitle ?: title else title,
                style = MaterialTheme.typography.bodyLarge
            )
            val displayedSubtitle = if (ready) completedSubtitle ?: subtitle else subtitle
            displayedSubtitle?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (!ready && !loading) {
            Button(onClick = onAction) { Text(text = actionLabel) }
        } else if (ready && onCompletedAction != null) {
            SetupArrow()
        }
    }
}

@Composable
private fun SetupRowContainer(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = SETUP_ROW_HEIGHT)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content
    )
}

@Composable
private fun SetupStatusIcon(ready: Boolean, loading: Boolean) {
    val statusColor = if (ready) {
        MaterialTheme.colorScheme.onSurfaceVariant
    } else {
        MaterialTheme.colorScheme.error
    }
    Icon(
        imageVector = if (ready) Icons.Rounded.Check else Icons.Outlined.ErrorOutline,
        contentDescription = null,
        tint = if (loading) MaterialTheme.colorScheme.outline else statusColor,
        modifier = Modifier.size(24.dp)
    )
}

@Composable
private fun SetupArrow() {
    Icon(
        imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

private val SETUP_ROW_HEIGHT = 56.dp
