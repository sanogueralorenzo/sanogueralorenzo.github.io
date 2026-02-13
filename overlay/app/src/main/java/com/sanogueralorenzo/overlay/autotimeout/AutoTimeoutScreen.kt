package com.sanogueralorenzo.overlay.autotimeout

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.airbnb.mvrx.compose.collectAsState as mavericksCollectAsState
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.overlay.R
import com.sanogueralorenzo.overlay.overlay.OverlayDeviceAdminReceiver
import com.sanogueralorenzo.overlay.tiles.requestQuickSettingsTile
import com.sanogueralorenzo.overlay.ui.components.NotificationPermissionSection
import com.sanogueralorenzo.overlay.ui.components.RefreshOnResume
import com.sanogueralorenzo.overlay.ui.components.SectionCard
import com.sanogueralorenzo.overlay.ui.components.StatusSection
import com.sanogueralorenzo.overlay.ui.components.StepSection
import com.sanogueralorenzo.overlay.ui.components.rememberNotificationPermissionState

fun NavGraphBuilder.autoTimeoutRoute(
    route: String,
    onBack: () -> Unit
) {
    composable(route) {
        val autoTimeoutViewModel: AutoTimeoutViewModel = mavericksViewModel()
        val state by autoTimeoutViewModel.mavericksCollectAsState()
        val activity = LocalContext.current as? ComponentActivity
        AutoTimeoutScreen(
            state = state,
            onSaveMinutes = { minutes -> autoTimeoutViewModel.setAutoLockMinutes(minutes) },
            onEnableDeviceAdmin = { activity?.requestDeviceAdmin() },
            onRequestTile = { activity?.requestAutoTimeoutTile { autoTimeoutViewModel.setTileAdded(true) } },
            onRefreshState = { autoTimeoutViewModel.refreshState() },
            onBack = onBack
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AutoTimeoutScreen(
    state: AutoTimeoutState,
    onSaveMinutes: (Int) -> Unit,
    onEnableDeviceAdmin: () -> Unit,
    onRequestTile: () -> Unit,
    onRefreshState: () -> Unit,
    onBack: () -> Unit
) {
    val scrollState = rememberScrollState()
    val notificationPermission = rememberNotificationPermissionState()
    RefreshOnResume {
        onRefreshState()
        notificationPermission.refresh()
    }

    val timerValueLabel = if (state.autoLockMinutes > 0) {
        stringResource(R.string.auto_lock_minutes_value_format, state.autoLockMinutes)
    } else {
        stringResource(R.string.auto_lock_off_label)
    }
    val timerStatusColor = if (state.autoLockMinutes > 0) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val timerStatusContainer = if (state.autoLockMinutes > 0) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }

    var showTimerDialog by rememberSaveable { mutableStateOf(false) }
    var timerInput by rememberSaveable { mutableStateOf(state.autoLockMinutes.toString()) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(R.string.timer_section_title)) },
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
                .padding(16.dp),
            verticalArrangement = Arrangement.Top,
            horizontalAlignment = Alignment.Start
        ) {
            val requirementsMet = state.deviceAdminActive &&
                state.isTileAdded &&
                notificationPermission.hasPermission
            if (!requirementsMet) {
                SectionCard(
                    title = stringResource(R.string.overlay_setup_title)
                ) {
                    StatusSection(
                        icon = Icons.Outlined.Lock,
                        label = stringResource(R.string.device_admin_label),
                        status = if (state.deviceAdminActive) {
                            stringResource(R.string.permission_status_granted)
                        } else {
                            stringResource(R.string.permission_status_required)
                        },
                        statusColor = if (state.deviceAdminActive) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.error
                        },
                        statusContainerColor = if (state.deviceAdminActive) {
                            MaterialTheme.colorScheme.primaryContainer
                        } else {
                            MaterialTheme.colorScheme.errorContainer
                        },
                        body = if (!state.deviceAdminActive) {
                            stringResource(R.string.setup_device_admin_body)
                        } else {
                            null
                        },
                        actionLabel = if (!state.deviceAdminActive) {
                            stringResource(R.string.enable_device_admin_button)
                        } else {
                            null
                        },
                        onAction = if (!state.deviceAdminActive) onEnableDeviceAdmin else null
                    )
                    StatusSection(
                        icon = Icons.Outlined.GridView,
                        label = stringResource(R.string.auto_timeout_tile_label),
                        status = if (state.isTileAdded) {
                            stringResource(R.string.permission_status_granted)
                        } else {
                            stringResource(R.string.permission_status_required)
                        },
                        statusColor = if (state.isTileAdded) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.error
                        },
                        statusContainerColor = if (state.isTileAdded) {
                            MaterialTheme.colorScheme.primaryContainer
                        } else {
                            MaterialTheme.colorScheme.errorContainer
                        },
                        body = if (!state.isTileAdded) {
                            stringResource(R.string.auto_timeout_tile_body)
                        } else {
                            null
                        },
                        actionLabel = if (!state.isTileAdded) {
                            stringResource(R.string.request_tile_button)
                        } else {
                            null
                        },
                        onAction = if (!state.isTileAdded) onRequestTile else null
                    )
                    NotificationPermissionSection(
                        hasPermission = notificationPermission.hasPermission,
                        onRequestPermission = notificationPermission.requestPermission
                    )
                }
                Spacer(modifier = Modifier.height(24.dp))
            }

            SectionCard(title = stringResource(R.string.how_it_works_label)) {
                StepSection(
                    icon = Icons.Outlined.Timer,
                    chipLabel = stringResource(R.string.step_one_chip),
                    title = stringResource(R.string.auto_timeout_step_one_title),
                    body = stringResource(R.string.auto_timeout_step_one_body)
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
                    title = stringResource(R.string.auto_timeout_step_three_title),
                    body = stringResource(R.string.auto_timeout_step_three_body)
                )
                StepSection(
                    icon = ImageVector.vectorResource(R.drawable.ic_step_power),
                    chipLabel = stringResource(R.string.step_four_chip),
                    title = stringResource(R.string.step_four_title),
                    body = stringResource(R.string.auto_timeout_step_four_body)
                )
            }

            Spacer(modifier = Modifier.height(24.dp))
            SectionCard(title = stringResource(R.string.auto_timeout_settings_title)) {
                StatusSection(
                    icon = Icons.Outlined.Timer,
                    label = stringResource(R.string.auto_timeout_timer_setting_title),
                    status = timerValueLabel,
                    statusColor = timerStatusColor,
                    statusContainerColor = timerStatusContainer,
                    body = stringResource(R.string.auto_timeout_timer_setting_body),
                    actionLabel = if (state.deviceAdminActive) {
                        stringResource(R.string.edit_timer_button)
                    } else {
                        null
                    },
                    onAction = if (state.deviceAdminActive) {
                        {
                            timerInput = state.autoLockMinutes.toString()
                            showTimerDialog = true
                        }
                    } else {
                        null
                    },
                    helperText = if (!state.deviceAdminActive) {
                        stringResource(R.string.auto_timeout_timer_requires_admin)
                    } else {
                        null
                    }
                )
            }
        }
    }

    if (showTimerDialog && state.deviceAdminActive) {
        AlertDialog(
            onDismissRequest = { showTimerDialog = false },
            title = { Text(text = stringResource(R.string.auto_lock_dialog_title)) },
            text = {
                Column {
                    Text(
                        text = stringResource(R.string.auto_lock_dialog_description),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 12.dp)
                    )
                    OutlinedTextField(
                        value = timerInput,
                        onValueChange = { value -> timerInput = value.filter { it.isDigit() } },
                        label = { Text(text = stringResource(R.string.auto_lock_minutes_label)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onSaveMinutes(timerInput.toIntOrNull() ?: 0)
                        showTimerDialog = false
                    }
                ) {
                    Text(text = stringResource(R.string.save_timer_button))
                }
            },
            dismissButton = {
                TextButton(onClick = { showTimerDialog = false }) {
                    Text(text = stringResource(R.string.cancel_button))
                }
            }
        )
    }
}


private fun ComponentActivity.requestDeviceAdmin() {
    val component = ComponentName(this, OverlayDeviceAdminReceiver::class.java)
    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, component)
        putExtra(
            DevicePolicyManager.EXTRA_ADD_EXPLANATION,
            getString(R.string.device_admin_explanation)
        )
    }
    startActivity(intent)
}

private fun ComponentActivity.requestAutoTimeoutTile(onAdded: () -> Unit) {
    val component = ComponentName(this, AutoTimeoutTileService::class.java)
    requestQuickSettingsTile(
        component = component,
        label = getString(R.string.auto_timeout_tile_label),
        iconRes = R.drawable.ic_qs_timer,
        onAdded = onAdded
    )
}
