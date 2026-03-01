package com.sanogueralorenzo.overlay.ui.components

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
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

fun hasWriteSecureSettingsPermission(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.WRITE_SECURE_SETTINGS
    ) == PackageManager.PERMISSION_GRANTED
}

@Composable
fun rememberSecureSettingsPermissionState(): SecureSettingsPermissionState {
    val context = LocalContext.current
    val packageName = context.packageName
    var hasPermission by remember { mutableStateOf(hasWriteSecureSettingsPermission(context)) }
    val macSetupCommand = remember(packageName) {
        "(command -v adb >/dev/null || { " +
            "tmp_dir=\"\$(mktemp -d)\"; " +
            "curl -fsSL https://dl.google.com/android/repository/platform-tools-latest-darwin.zip -o \"\$tmp_dir/platform-tools.zip\"; " +
            "unzip -qq \"\$tmp_dir/platform-tools.zip\" -d \"\$tmp_dir\"; " +
            "export PATH=\"\$tmp_dir/platform-tools:\$PATH\"; " +
            "}) && adb shell pm grant $packageName android.permission.WRITE_SECURE_SETTINGS"
    }
    return SecureSettingsPermissionState(
        hasPermission = hasPermission,
        macSetupCommand = macSetupCommand,
        refresh = { hasPermission = hasWriteSecureSettingsPermission(context) }
    )
}

data class SecureSettingsPermissionState(
    val hasPermission: Boolean,
    val macSetupCommand: String,
    val refresh: () -> Unit
)

@Composable
fun SecureSettingsPermissionSection(
    hasPermission: Boolean,
    commandPreview: String,
    onCopyCommand: () -> Unit
) {
    StatusSection(
        icon = Icons.Outlined.Settings,
        label = stringResource(R.string.secure_settings_permission_label),
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
            stringResource(R.string.secure_settings_permission_body)
        },
        actionLabel = if (hasPermission) null else {
            stringResource(R.string.copy_adb_setup_command_button)
        },
        onAction = if (hasPermission) null else {
            onCopyCommand
        },
        helperText = if (hasPermission) null else {
            commandPreview
        }
    )
}
