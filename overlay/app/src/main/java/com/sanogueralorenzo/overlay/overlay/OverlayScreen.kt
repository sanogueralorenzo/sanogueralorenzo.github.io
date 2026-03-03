package com.sanogueralorenzo.overlay.overlay

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.TouchApp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.compose.collectAsState as mavericksCollectAsState
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.overlay.R
import com.sanogueralorenzo.overlay.overlay.OverlayTileService
import com.sanogueralorenzo.overlay.tiles.requestQuickSettingsTile
import com.sanogueralorenzo.overlay.ui.components.NotificationPermissionSection
import com.sanogueralorenzo.overlay.ui.components.RefreshOnResume
import com.sanogueralorenzo.overlay.ui.components.SectionCard
import com.sanogueralorenzo.overlay.ui.components.StatusSection
import com.sanogueralorenzo.overlay.ui.components.SwitchSection
import com.sanogueralorenzo.overlay.ui.components.StepSection
import com.sanogueralorenzo.overlay.ui.components.SecureSettingsPermissionSection
import com.sanogueralorenzo.overlay.ui.theme.OverlayTheme
import com.sanogueralorenzo.overlay.ui.components.rememberNotificationPermissionState
import com.sanogueralorenzo.overlay.ui.components.rememberSecureSettingsPermissionState
import androidx.core.net.toUri

fun NavGraphBuilder.overlayRoute(
    route: String,
    onOpenAutoTimeout: () -> Unit,
    onOpenAbout: () -> Unit
) {
    composable(route) {
        val overlayViewModel: OverlayViewModel = mavericksViewModel()
        val state by overlayViewModel.mavericksCollectAsState()
        val activity = LocalContext.current as? ComponentActivity
        OverlayScreen(
            state = state,
            onOpenOverlaySettings = { activity?.openOverlaySettings() },
            onRequestTile = {
                activity?.requestAddTile { overlayViewModel.setTileAdded(true) }
            },
            onOpenAutoTimeout = onOpenAutoTimeout,
            onRefreshOverlay = { overlayViewModel.refreshOverlay() },
            onOpenAbout = onOpenAbout,
            onSetLongPressDismissEnabled = { enabled ->
                overlayViewModel.setLongPressDismissEnabled(enabled)
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OverlayScreen(
    state: OverlayState,
    onOpenOverlaySettings: () -> Unit,
    onRequestTile: () -> Unit,
    onOpenAutoTimeout: () -> Unit,
    onRefreshOverlay: () -> Unit,
    onOpenAbout: () -> Unit,
    onSetLongPressDismissEnabled: (Boolean) -> Unit
) {
    val scrollState = rememberScrollState()
    val context = LocalContext.current
    val clipboardManager = LocalClipboardManager.current
    val copyCommandAndNotify: (String) -> Unit = { command ->
        clipboardManager.setText(AnnotatedString(command))
        Toast.makeText(
            context,
            context.getString(R.string.adb_command_copied_message),
            Toast.LENGTH_SHORT
        ).show()
    }
    val notificationPermission = rememberNotificationPermissionState()
    val secureSettingsPermission = rememberSecureSettingsPermissionState()
    RefreshOnResume {
        onRefreshOverlay()
        notificationPermission.refresh()
        secureSettingsPermission.refresh()
    }

    val permissionsResolved = state.overlayPermission is Success &&
        state.tileAdded is Success
    val isOverlayGranted = state.overlayPermission() == true
    val isTileAdded = state.tileAdded() == true
    val longPressEnabled = state.longPressDismissEnabled() == true
    val allGranted = isOverlayGranted &&
        isTileAdded &&
        notificationPermission.hasPermission &&
        secureSettingsPermission.hasPermission

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(R.string.overlay_title)) },
                actions = {
                    IconButton(onClick = onOpenAbout) {
                        Icon(
                            imageVector = Icons.Outlined.Info,
                            contentDescription = stringResource(R.string.open_about_button)
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
                .padding(16.dp),
            verticalArrangement = Arrangement.Top,
            horizontalAlignment = Alignment.Start
        ) {
            if (permissionsResolved && !allGranted) {
                SectionCard(
                    title = stringResource(R.string.overlay_setup_title)
                ) {
                    StatusSection(
                        icon = Icons.Outlined.Layers,
                        label = stringResource(R.string.overlay_permission_label),
                        status = if (isOverlayGranted) {
                            stringResource(R.string.permission_status_granted)
                        } else {
                            stringResource(R.string.permission_status_required)
                        },
                        statusColor = if (isOverlayGranted) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.error
                        },
                        statusContainerColor = if (isOverlayGranted) {
                            MaterialTheme.colorScheme.primaryContainer
                        } else {
                            MaterialTheme.colorScheme.errorContainer
                        },
                        body = if (!isOverlayGranted) {
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
                    StatusSection(
                        icon = Icons.Outlined.GridView,
                        label = stringResource(R.string.quick_settings_tile_section_label),
                        status = if (isTileAdded) {
                            stringResource(R.string.permission_status_granted)
                        } else {
                            stringResource(R.string.permission_status_required)
                        },
                        statusColor = if (isTileAdded) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.error
                        },
                        statusContainerColor = if (isTileAdded) {
                            MaterialTheme.colorScheme.primaryContainer
                        } else {
                            MaterialTheme.colorScheme.errorContainer
                        },
                        body = if (!isTileAdded) {
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
                    NotificationPermissionSection(
                        hasPermission = notificationPermission.hasPermission,
                        onRequestPermission = notificationPermission.requestPermission
                    )
                    SecureSettingsPermissionSection(
                        hasPermission = secureSettingsPermission.hasPermission,
                        commands = secureSettingsPermission.commands,
                        onCopyCommand = copyCommandAndNotify
                    )
                }
            }
            if (permissionsResolved && !allGranted) {
                Spacer(modifier = Modifier.height(16.dp))
            }
            SectionCard(title = stringResource(R.string.how_it_works_label)) {
                StepSection(
                    icon = Icons.Outlined.PlayArrow,
                    chipLabel = stringResource(R.string.step_one_chip),
                    title = stringResource(R.string.step_one_title),
                    body = stringResource(R.string.step_one_body)
                )
                StepSection(
                    icon = Icons.Outlined.KeyboardArrowDown,
                    chipLabel = stringResource(R.string.step_two_chip),
                    title = stringResource(R.string.step_two_title),
                    body = stringResource(R.string.step_two_body)
                )
                StepSection(
                    icon = Icons.Outlined.GridView,
                    chipLabel = stringResource(R.string.step_three_chip),
                    title = stringResource(R.string.step_three_title),
                    body = stringResource(R.string.step_three_body)
                )
                StepSection(
                    icon = ImageVector.vectorResource(R.drawable.ic_step_power),
                    chipLabel = stringResource(R.string.step_four_chip),
                    title = stringResource(R.string.step_four_title),
                    body = stringResource(R.string.step_four_body)
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
            SectionCard(title = stringResource(R.string.overlay_settings_title)) {
                SwitchSection(
                    icon = Icons.Outlined.TouchApp,
                    label = stringResource(R.string.long_press_dismiss_title),
                    checked = longPressEnabled,
                    onCheckedChange = onSetLongPressDismissEnabled,
                    body = stringResource(R.string.long_press_dismiss_body)
                )
                StatusSection(
                    icon = Icons.Outlined.Timer,
                    label = stringResource(R.string.auto_timeout_section_title),
                    status = stringResource(R.string.auto_timeout_setup_button),
                    statusColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    statusContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    body = stringResource(R.string.auto_timeout_setup_description),
                    actionLabel = null,
                    onAction = null,
                    onSectionClick = onOpenAutoTimeout
                )
            }
        }
    }
}


@Preview(showBackground = true)
@Composable
private fun OverlayScreenPreview() {
    OverlayTheme {
        OverlayScreen(
            state = OverlayState(
                overlayPermission = Success(false),
                tileAdded = Success(false),
                longPressDismissEnabled = Success(false)
            ),
            onOpenOverlaySettings = {},
            onRequestTile = {},
            onOpenAutoTimeout = {},
            onRefreshOverlay = {},
            onOpenAbout = {},
            onSetLongPressDismissEnabled = {}
        )
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
