package com.sanogueralorenzo.voice.overlay

import androidx.lifecycle.Lifecycle
import android.Manifest
import android.content.Intent
import android.provider.Settings
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
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ui.OnLifecycle

@Composable
fun OverlayScreen() {
    val context = LocalContext.current
    val viewModel = mavericksViewModel<OverlayViewModel, OverlayState>()
    val state by viewModel.collectAsStateWithLifecycle()

    val microphonePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) {
        viewModel.refreshStatus()
        OverlayAccessibilityService.requestRefresh(context)
    }

    OnLifecycle(Lifecycle.Event.ON_RESUME) {
        viewModel.refreshStatus()
        OverlayAccessibilityService.requestRefresh(context)
    }

    OverlayScreenContent(
        state = state,
        onGrantMicrophone = {
            microphonePermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        },
        onOpenAccessibilitySettings = {
            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        },
        onOverlayEnabledChange = {
            viewModel.setOverlayEnabled(it)
            OverlayAccessibilityService.requestRefresh(context)
        },
        onPositioningModeChange = {
            viewModel.setPositioningMode(it)
            OverlayAccessibilityService.requestRefresh(context)
        },
        onResetPosition = {
            viewModel.resetBubblePosition()
            OverlayAccessibilityService.requestRefresh(context)
        }
    )
}

@Composable
private fun OverlayScreenContent(
    state: OverlayState,
    onGrantMicrophone: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit,
    onOverlayEnabledChange: (Boolean) -> Unit,
    onPositioningModeChange: (Boolean) -> Unit,
    onResetPosition: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.overlay_intro),
            style = MaterialTheme.typography.bodyMedium
        )

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp)
            ) {
                OverlayPermissionRow(
                    title = stringResource(R.string.overlay_permission_microphone),
                    granted = state.recordPermissionGranted,
                    actionLabel = stringResource(R.string.overlay_permission_grant),
                    onAction = onGrantMicrophone
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                OverlayPermissionRow(
                    title = stringResource(R.string.overlay_permission_accessibility),
                    granted = state.accessibilityServiceEnabled,
                    actionLabel = stringResource(R.string.overlay_permission_open_settings),
                    onAction = onOpenAccessibilitySettings
                )
            }
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp)
            ) {
                OverlayToggleRow(
                    title = stringResource(R.string.overlay_toggle_enable),
                    description = stringResource(R.string.overlay_toggle_enable_description),
                    checked = state.overlayEnabled,
                    onCheckedChange = onOverlayEnabledChange
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                OverlayToggleRow(
                    title = stringResource(R.string.overlay_toggle_position_mode),
                    description = stringResource(R.string.overlay_toggle_position_mode_description),
                    checked = state.positioningMode,
                    onCheckedChange = onPositioningModeChange
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = stringResource(R.string.overlay_position_value, state.bubbleX, state.bubbleY),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f)
                    )
                    Button(onClick = onResetPosition) {
                        Text(text = stringResource(R.string.overlay_position_reset))
                    }
                }
            }
        }

        if (state.voiceImeSelected) {
            Text(
                text = stringResource(R.string.overlay_voice_ime_selected_warning),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        } else {
            Text(
                text = stringResource(R.string.overlay_non_voice_ready_message),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun OverlayPermissionRow(
    title: String,
    granted: Boolean,
    actionLabel: String,
    onAction: () -> Unit
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
                text = if (granted) {
                    stringResource(R.string.overlay_status_granted)
                } else {
                    stringResource(R.string.overlay_status_required)
                },
                style = MaterialTheme.typography.bodySmall,
                color = if (granted) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.error
                }
            )
        }
        Button(onClick = onAction) {
            Text(text = actionLabel)
        }
    }
}

@Composable
private fun OverlayToggleRow(
    title: String,
    description: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f)
            )
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange
            )
        }
        Text(
            text = description,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
