package com.sanogueralorenzo.voice.product

import android.Manifest
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.OpenWith
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ui.OnLifecycle

@Composable
fun VoiceHomeScreen(
    onOpenLocalModels: () -> Unit,
    onOpenMicPosition: () -> Unit
) {
    val context = LocalContext.current
    val viewModel = mavericksViewModel<VoiceHomeViewModel, VoiceHomeState>()
    val state by viewModel.collectAsStateWithLifecycle()
    val microphonePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { viewModel.refreshStatus() }

    OnLifecycle(Lifecycle.Event.ON_START) {
        viewModel.refreshStatus()
    }
    VoiceHomeContent(
        state = state,
        onOpenLocalModels = onOpenLocalModels,
        onGrantMicrophone = {
            microphonePermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        },
        onOpenVoiceService = {
            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        },
        onOpenVoiceKeyboard = {
            if (state.voiceKeyboardEnabled) {
                context.getSystemService(InputMethodManager::class.java)
                    ?.showInputMethodPicker()
            } else {
                context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
            }
        },
        onSelectInputType = viewModel::selectInputType,
        onOpenMicPosition = onOpenMicPosition
    )
}

@Composable
private fun VoiceHomeContent(
    state: VoiceHomeState,
    onOpenLocalModels: () -> Unit,
    onGrantMicrophone: () -> Unit,
    onOpenVoiceService: () -> Unit,
    onOpenVoiceKeyboard: () -> Unit,
    onSelectInputType: (VoiceInputType) -> Unit,
    onOpenMicPosition: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { ProductHero() }
        item { HowItWorksCard(inputType = state.inputType) }
        item {
            StatusSection(
                state = state,
                onOpenLocalModels = onOpenLocalModels,
                onGrantMicrophone = onGrantMicrophone,
                onOpenVoiceService = onOpenVoiceService,
                onOpenVoiceKeyboard = onOpenVoiceKeyboard,
                onSelectInputType = onSelectInputType,
                onOpenMicPosition = onOpenMicPosition
            )
        }
        item { Spacer(modifier = Modifier.height(4.dp)) }
    }

}

@Composable
private fun ProductHero() {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_logo),
                contentDescription = stringResource(R.string.app_name),
                modifier = Modifier.size(96.dp),
                tint = Color.Unspecified
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.Start
            ) {
                Text(
                    text = stringResource(R.string.app_name),
                    style = MaterialTheme.typography.headlineSmall,
                    textAlign = TextAlign.Start
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = stringResource(R.string.product_hero_title),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Start
                )
            }
        }
    }
}

@Composable
private fun HowItWorksCard(inputType: VoiceInputType?) {
    StepSectionCard(title = stringResource(R.string.product_get_started)) {
        ProductStep(
            icon = Icons.Outlined.Settings,
            chipLabel = stringResource(R.string.product_step_one_chip),
            title = stringResource(R.string.product_step_setup_title),
            body = stringResource(R.string.product_step_setup_body)
        )
        if (inputType == VoiceInputType.OVERLAY) {
            ProductStep(
                icon = Icons.Outlined.OpenWith,
                chipLabel = stringResource(R.string.product_step_two_chip),
                title = stringResource(R.string.product_step_position_title),
                body = stringResource(R.string.product_step_position_body)
            )
        }
        ProductStep(
            icon = Icons.Outlined.Mic,
            chipLabel = stringResource(
                if (inputType == VoiceInputType.OVERLAY) {
                    R.string.product_step_three_chip
                } else {
                    R.string.product_step_two_chip
                }
            ),
            title = stringResource(R.string.product_step_record_title),
            body = stringResource(R.string.product_step_record_body)
        )
    }
}

@Composable
private fun StepSectionCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
                verticalArrangement = Arrangement.spacedBy(16.dp),
                content = content
            )
        }
    }
}

@Composable
private fun ProductStep(
    icon: ImageVector,
    chipLabel: String,
    title: String,
    body: String
) {
    Column {
        ProductStepHeader(icon = icon, chipLabel = chipLabel, title = title)
        Text(
            text = body,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

@Composable
private fun ProductStepHeader(
    icon: ImageVector,
    chipLabel: String,
    title: String
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
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(50)
        ) {
            Text(
                text = chipLabel,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
            )
        }
    }
}

@Composable
private fun StatusSection(
    state: VoiceHomeState,
    onOpenLocalModels: () -> Unit,
    onGrantMicrophone: () -> Unit,
    onOpenVoiceService: () -> Unit,
    onOpenVoiceKeyboard: () -> Unit,
    onSelectInputType: (VoiceInputType) -> Unit,
    onOpenMicPosition: () -> Unit
) {
    Section(title = stringResource(R.string.product_status)) {
        TypeStatusRow(
            selected = state.inputType,
            loading = state.loading,
            onSelect = onSelectInputType
        )
        HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
        StatusRow(
            title = stringResource(R.string.product_status_microphone),
            ready = state.microphoneAllowed,
            loading = state.loading,
            actionLabel = stringResource(R.string.product_action_allow),
            onAction = onGrantMicrophone
        )
        when (state.inputType) {
            VoiceInputType.OVERLAY -> {
                HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                StatusRow(
                    title = stringResource(R.string.product_status_service),
                    subtitle = stringResource(R.string.product_status_service_hint),
                    completedTitle = stringResource(R.string.product_mic_position_title),
                    completedSubtitle = stringResource(R.string.product_mic_position_body),
                    ready = state.voiceServiceEnabled,
                    loading = state.loading,
                    actionLabel = stringResource(R.string.product_action_enable),
                    onAction = onOpenVoiceService,
                    onCompletedAction = onOpenMicPosition
                )
            }

            VoiceInputType.KEYBOARD -> {
                HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                StatusRow(
                    title = stringResource(R.string.product_status_voice_keyboard),
                    ready = state.voiceKeyboardSelected,
                    loading = state.loading,
                    actionLabel = stringResource(
                        if (state.voiceKeyboardEnabled) {
                            R.string.product_action_select
                        } else {
                            R.string.product_action_enable
                        }
                    ),
                    onAction = onOpenVoiceKeyboard
                )
            }

            null -> Unit
        }
        HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
        LocalModelsStatusRow(
            ready = state.modelsReady,
            loading = state.loading,
            onClick = onOpenLocalModels
        )
    }
}

@Composable
private fun TypeStatusRow(
    selected: VoiceInputType?,
    loading: Boolean,
    onSelect: (VoiceInputType) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = SETUP_ROW_HEIGHT)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = if (selected != null) Icons.Rounded.Check else Icons.Outlined.ErrorOutline,
            contentDescription = null,
            tint = when {
                loading -> MaterialTheme.colorScheme.outline
                selected != null -> MaterialTheme.colorScheme.onSurfaceVariant
                else -> MaterialTheme.colorScheme.error
            },
            modifier = Modifier.size(24.dp)
        )
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
private fun LocalModelsStatusRow(
    ready: Boolean,
    loading: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = SETUP_ROW_HEIGHT)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
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
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun StatusRow(
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
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = SETUP_ROW_HEIGHT)
            .then(
                if (ready && onCompletedAction != null) {
                    Modifier.clickable(onClick = onCompletedAction)
                } else {
                    Modifier
                }
            )
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
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
            Button(onClick = onAction) {
                Text(text = actionLabel)
            }
        } else if (ready && onCompletedAction != null) {
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.fillMaxWidth()) { content() }
        }
    }
}

private val SETUP_ROW_HEIGHT = 56.dp
