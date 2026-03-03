package com.sanogueralorenzo.overlay.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.sanogueralorenzo.overlay.R

@Composable
fun NotificationPermissionSection(
    hasPermission: Boolean,
    onRequestPermission: () -> Unit
) {
    StatusSection(
        icon = Icons.Outlined.Notifications,
        label = stringResource(R.string.notification_permission_label),
        status = stringResource(
            if (hasPermission) {
                R.string.permission_status_granted
            } else {
                R.string.permission_status_required
            }
        ),
        statusColor = if (hasPermission) {
            MaterialTheme.colorScheme.primary
        } else {
            MaterialTheme.colorScheme.error
        },
        statusContainerColor = if (hasPermission) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.errorContainer
        },
        body = if (hasPermission) null else {
            stringResource(R.string.notification_permission_body)
        },
        actionLabel = if (hasPermission) null else {
            stringResource(R.string.request_notifications_button)
        },
        onAction = if (hasPermission) null else {
            onRequestPermission
        }
    )
}
