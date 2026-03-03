package com.sanogueralorenzo.overlay.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

@Composable
fun SectionCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            content()
        }
    }
    }
}

@Composable
fun StatusSection(
    icon: ImageVector,
    label: String,
    status: String,
    statusColor: Color,
    statusContainerColor: Color,
    body: String?,
    actionLabel: String?,
    onAction: (() -> Unit)?,
    helperText: String? = null,
    onSectionClick: (() -> Unit)? = null
) {
    Column(
        modifier = Modifier
            .then(
                if (onSectionClick != null) {
                    Modifier
                        .fillMaxWidth()
                        .clickable(
                            interactionSource = null,
                            indication = null,
                            onClick = onSectionClick
                        )
                } else {
                    Modifier.fillMaxWidth()
                }
            )
    ) {
        StatusRow(
            icon = icon,
            label = label,
            status = status,
            statusColor = statusColor,
            statusContainerColor = statusContainerColor
        )
        if (body != null) {
            StatusActionBlock(
                text = body,
                buttonLabel = actionLabel,
                onClick = onAction,
                helperText = helperText
            )
        }
    }
}

@Composable
fun StepSection(
    icon: ImageVector,
    chipLabel: String,
    title: String,
    body: String
) {
    Column {
        StepRow(icon = icon, title = title, chipLabel = chipLabel)
        StatusActionBlock(text = body, buttonLabel = null, onClick = null)
    }
}

@Composable
private fun StatusRow(
    icon: ImageVector,
    label: String,
    status: String,
    statusColor: Color,
    statusContainerColor: Color
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = label,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(start = 8.dp)
            )
        }
        StatusChip(
            text = status,
            contentColor = statusColor,
            containerColor = statusContainerColor
        )
    }
}

@Composable
private fun StatusChip(
    text: String,
    contentColor: Color,
    containerColor: Color
) {
    Surface(
        color = containerColor,
        shape = RoundedCornerShape(50)
    ) {
        Text(
            text = text,
            color = contentColor,
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
        )
    }
}

@Composable
private fun StatusActionBlock(
    text: String,
    buttonLabel: String?,
    onClick: (() -> Unit)?,
    helperText: String? = null
) {
    Text(
        text = text,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 8.dp)
    )
    if (buttonLabel != null && onClick != null) {
        Button(
            onClick = onClick,
            modifier = Modifier.padding(top = 8.dp)
        ) {
            Text(text = buttonLabel)
        }
    }
    if (helperText != null) {
        Text(
            text = helperText,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

@Composable
private fun StepRow(
    icon: ImageVector,
    title: String,
    chipLabel: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(start = 8.dp)
            )
        }
        StatusChip(
            text = chipLabel,
            contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    }
}
