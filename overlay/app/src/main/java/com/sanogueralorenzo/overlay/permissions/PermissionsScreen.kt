package com.sanogueralorenzo.overlay.permissions

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.airbnb.mvrx.compose.collectAsState as mavericksCollectAsState
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.overlay.R
import com.sanogueralorenzo.overlay.overlay.OverlayTileService
import com.sanogueralorenzo.overlay.tiles.requestQuickSettingsTile
import com.sanogueralorenzo.overlay.ui.components.DesktopOsOption
import com.sanogueralorenzo.overlay.ui.components.RefreshOnResume

fun NavGraphBuilder.permissionsRoute(
    route: String,
    onBack: () -> Unit
) {
    composable(route) {
        val permissionsViewModel: PermissionsViewModel = mavericksViewModel()
        val state by permissionsViewModel.mavericksCollectAsState()
        val activity = LocalContext.current as? ComponentActivity
        PermissionsScreen(
            state = state,
            onBack = onBack,
            onRefreshPermissions = { permissionsViewModel.refreshPermissions() },
            onOpenOverlaySettings = { activity?.openOverlaySettings() },
            onRequestTile = {
                activity?.requestAddTile { permissionsViewModel.setTileAdded(true) }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PermissionsScreen(
    state: PermissionsState,
    onBack: () -> Unit,
    onRefreshPermissions: () -> Unit,
    onOpenOverlaySettings: () -> Unit,
    onRequestTile: () -> Unit
) {
    val context = LocalContext.current
    val clipboardManager = LocalClipboardManager.current
    var showSecureSettingsDialog by rememberSaveable { mutableStateOf(false) }
    var selectedDesktopOs by rememberSaveable { mutableStateOf(DesktopOsOption.Windows) }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) {
        onRefreshPermissions()
    }

    RefreshOnResume {
        onRefreshPermissions()
    }

    val copyCommandAndNotify: (String) -> Unit = { command ->
        clipboardManager.setText(AnnotatedString(command))
        Toast.makeText(
            context,
            context.getString(R.string.adb_command_copied_message),
            Toast.LENGTH_SHORT
        ).show()
    }

    val isOverlayGranted = state.overlayPermission() == true
    val isTileAdded = state.tileAdded() == true
    val notificationGranted = state.notificationPermission() == true
    val secureSettingsGranted = state.secureSettingsPermission() == true
    val scrollState = rememberScrollState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(R.string.permissions_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.back_button)
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState)
                .padding(20.dp),
            verticalArrangement = Arrangement.Top,
            horizontalAlignment = Alignment.Start
        ) {
            Text(
                text = stringResource(R.string.overlay_setup_title),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            ElevatedCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
            ) {
                PermissionActionRow(
                    title = stringResource(R.string.overlay_permission_label),
                    status = if (isOverlayGranted) {
                        stringResource(R.string.permission_status_granted)
                    } else {
                        stringResource(R.string.permission_status_required)
                    },
                    isGranted = isOverlayGranted,
                    description = if (!isOverlayGranted) {
                        stringResource(R.string.setup_overlay_body)
                    } else {
                        null
                    },
                    actionLabel = if (!isOverlayGranted) {
                        stringResource(R.string.open_settings_button)
                    } else {
                        null
                    },
                    onAction = if (!isOverlayGranted) onOpenOverlaySettings else null
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                PermissionActionRow(
                    title = stringResource(R.string.quick_settings_tile_section_label),
                    status = if (isTileAdded) {
                        stringResource(R.string.permission_status_granted)
                    } else {
                        stringResource(R.string.permission_status_required)
                    },
                    isGranted = isTileAdded,
                    description = if (!isTileAdded) {
                        stringResource(R.string.setup_tile_body)
                    } else {
                        null
                    },
                    actionLabel = if (!isTileAdded) {
                        stringResource(R.string.request_tile_button)
                    } else {
                        null
                    },
                    onAction = if (!isTileAdded) onRequestTile else null
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                PermissionActionRow(
                    title = stringResource(R.string.notification_permission_label),
                    status = if (notificationGranted) {
                        stringResource(R.string.permission_status_granted)
                    } else {
                        stringResource(R.string.permission_status_required)
                    },
                    isGranted = notificationGranted,
                    description = if (!notificationGranted) {
                        stringResource(R.string.notification_permission_body)
                    } else {
                        null
                    },
                    actionLabel = if (!notificationGranted) {
                        stringResource(R.string.request_notifications_button)
                    } else {
                        null
                    },
                    onAction = if (!notificationGranted) {
                        { notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }
                    } else {
                        null
                    }
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                PermissionActionRow(
                    title = stringResource(R.string.secure_settings_permission_label),
                    status = if (secureSettingsGranted) {
                        stringResource(R.string.permission_status_granted)
                    } else {
                        stringResource(R.string.permission_status_required)
                    },
                    isGranted = secureSettingsGranted,
                    description = if (!secureSettingsGranted) {
                        stringResource(R.string.secure_settings_permission_brief)
                    } else {
                        null
                    },
                    actionLabel = if (!secureSettingsGranted) {
                        stringResource(R.string.open_adb_setup_button)
                    } else {
                        null
                    },
                    onAction = if (!secureSettingsGranted) {
                        { showSecureSettingsDialog = true }
                    } else {
                        null
                    }
                )
            }
        }
    }

    if (!secureSettingsGranted && showSecureSettingsDialog) {
        AlertDialog(
            onDismissRequest = { showSecureSettingsDialog = false },
            title = { Text(text = stringResource(R.string.secure_settings_permission_label)) },
            text = {
                Column {
                    Text(text = stringResource(R.string.secure_settings_permission_body))
                    Text(
                        text = stringResource(R.string.choose_desktop_os_label),
                        modifier = Modifier.padding(top = 16.dp)
                    )
                    DesktopOption.values().forEach { option ->
                        DesktopOptionButton(
                            label = option.label,
                            selected = selectedDesktopOs == option.option,
                            onClick = { selectedDesktopOs = option.option },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp)
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        copyCommandAndNotify(state.secureSettingsCommands.forOption(selectedDesktopOs))
                        showSecureSettingsDialog = false
                    }
                ) {
                    Text(text = stringResource(R.string.copy_adb_setup_command_button))
                }
            },
            dismissButton = {
                TextButton(onClick = { showSecureSettingsDialog = false }) {
                    Text(text = stringResource(R.string.cancel_button))
                }
            }
        )
    }
}

private data class DesktopOption(
    val option: DesktopOsOption,
    val label: String
) {
    companion object {
        @Composable
        fun values(): List<DesktopOption> {
            return listOf(
                DesktopOption(
                    option = DesktopOsOption.Windows,
                    label = stringResource(R.string.desktop_os_windows)
                ),
                DesktopOption(
                    option = DesktopOsOption.Mac,
                    label = stringResource(R.string.desktop_os_mac)
                ),
                DesktopOption(
                    option = DesktopOsOption.Linux,
                    label = stringResource(R.string.desktop_os_linux)
                )
            )
        }
    }
}

@Composable
private fun DesktopOptionButton(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (selected) {
        Button(
            onClick = onClick,
            modifier = modifier
        ) {
            Text(text = label)
        }
    } else {
        OutlinedButton(
            onClick = onClick,
            modifier = modifier
        ) {
            Text(text = label)
        }
    }
}

@Composable
private fun PermissionActionRow(
    title: String,
    status: String,
    isGranted: Boolean,
    description: String?,
    actionLabel: String?,
    onAction: (() -> Unit)?
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge
            )
            Text(
                text = status,
                style = MaterialTheme.typography.bodySmall,
                color = if (isGranted) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.error
                }
            )
            if (description != null) {
                Text(
                    text = description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 2.dp, end = 12.dp)
                )
            }
        }
        if (actionLabel != null && onAction != null) {
            Button(onClick = onAction) {
                Text(text = actionLabel)
            }
        }
    }
}

fun ComponentActivity.openOverlaySettings() {
    val intent = Intent(
        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
        "package:$packageName".toUri()
    )
    startActivity(intent)
}

fun ComponentActivity.requestAddTile(onAdded: () -> Unit) {
    val component = ComponentName(this, OverlayTileService::class.java)
    requestQuickSettingsTile(
        component = component,
        label = getString(R.string.quick_settings_tile_label),
        iconRes = R.drawable.ic_qs_black,
        onAdded = onAdded
    )
}
