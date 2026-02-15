package com.sanogueralorenzo.overlay.ui.components

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import com.sanogueralorenzo.overlay.R

fun hasNotificationPermission(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.POST_NOTIFICATIONS
    ) == PackageManager.PERMISSION_GRANTED
}

@Composable
fun rememberNotificationPermissionState(): NotificationPermissionState {
    val context = LocalContext.current
    var hasPermission by remember { mutableStateOf(hasNotificationPermission(context)) }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
    }
    return NotificationPermissionState(
        hasPermission = hasPermission,
        refresh = { hasPermission = hasNotificationPermission(context) },
        requestPermission = { launcher.launch(Manifest.permission.POST_NOTIFICATIONS) }
    )
}

data class NotificationPermissionState(
    val hasPermission: Boolean,
    val refresh: () -> Unit,
    val requestPermission: () -> Unit
)

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
