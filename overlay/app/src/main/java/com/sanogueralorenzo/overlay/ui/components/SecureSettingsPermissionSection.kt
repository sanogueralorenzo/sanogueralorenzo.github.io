package com.sanogueralorenzo.overlay.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.overlay.R

enum class DesktopOsOption {
    Mac,
    Windows,
    Linux
}

data class SecureSettingsCommands(
    val mac: String,
    val windows: String,
    val linux: String
) {
    fun forOption(option: DesktopOsOption): String {
        return when (option) {
            DesktopOsOption.Mac -> mac
            DesktopOsOption.Windows -> windows
            DesktopOsOption.Linux -> linux
        }
    }
}

@Composable
fun SecureSettingsPermissionSection(
    hasPermission: Boolean,
    commands: SecureSettingsCommands,
    onCopyCommand: (String) -> Unit
) {
    var showSetupDialog by rememberSaveable { mutableStateOf(false) }
    var selectedOption by rememberSaveable { mutableStateOf(DesktopOsOption.Windows) }
    val status = stringResource(
        if (hasPermission) {
            R.string.permission_status_granted
        } else {
            R.string.permission_status_required
        }
    )
    val statusColor = if (hasPermission) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.error
    }
    val statusContainerColor = if (hasPermission) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        MaterialTheme.colorScheme.errorContainer
    }
    val body = if (hasPermission) {
        null
    } else {
        stringResource(R.string.secure_settings_permission_brief)
    }
    val actionLabel = if (hasPermission) {
        null
    } else {
        stringResource(R.string.open_adb_setup_button)
    }
    val osOptions = listOf(
        DesktopOsOption.Windows to stringResource(R.string.desktop_os_windows),
        DesktopOsOption.Mac to stringResource(R.string.desktop_os_mac),
        DesktopOsOption.Linux to stringResource(R.string.desktop_os_linux)
    )

    StatusSection(
        icon = Icons.Outlined.Settings,
        label = stringResource(R.string.secure_settings_permission_label),
        status = status,
        statusColor = statusColor,
        statusContainerColor = statusContainerColor,
        body = body,
        actionLabel = actionLabel,
        onAction = if (hasPermission) null else {
            { showSetupDialog = true }
        }
    )
    if (!hasPermission && showSetupDialog) {
        AlertDialog(
            onDismissRequest = { showSetupDialog = false },
            title = { Text(text = stringResource(R.string.secure_settings_permission_label)) },
            text = {
                Column {
                    Text(text = stringResource(R.string.secure_settings_permission_body))
                    Spacer(modifier = Modifier.height(12.dp))
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(text = stringResource(R.string.choose_desktop_os_label))
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        osOptions.forEach { (option, label) ->
                            OsOptionButton(
                                modifier = Modifier.fillMaxWidth(),
                                label = label,
                                selected = selectedOption == option,
                                onClick = { selectedOption = option }
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onCopyCommand(commands.forOption(selectedOption))
                        showSetupDialog = false
                    }
                ) {
                    Text(text = stringResource(R.string.copy_adb_setup_command_button))
                }
            },
            dismissButton = {
                TextButton(onClick = { showSetupDialog = false }) {
                    Text(text = stringResource(R.string.cancel_button))
                }
            }
        )
    }
}

@Composable
private fun OsOptionButton(
    modifier: Modifier,
    label: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    if (selected) {
        Button(
            modifier = modifier,
            onClick = onClick
        ) {
            Text(text = label)
        }
    } else {
        OutlinedButton(
            modifier = modifier,
            onClick = onClick
        ) {
            Text(text = label)
        }
    }
}
