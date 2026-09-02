package com.sanogueralorenzo.voice.home

import android.Manifest
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.OpenWith
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.setup.InputTypeSetupRow
import com.sanogueralorenzo.voice.setup.LocalModelsSetupRow
import com.sanogueralorenzo.voice.setup.SetupStatusRow
import com.sanogueralorenzo.voice.setup.VoiceInputType
import com.sanogueralorenzo.voice.ui.OnLifecycle
import com.sanogueralorenzo.voice.ui.components.SectionCard
import com.sanogueralorenzo.voice.ui.components.StepSection

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
    SectionCard(
        title = stringResource(R.string.product_get_started),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalSpacing = 16.dp
    ) {
        StepSection(
            icon = Icons.Outlined.Settings,
            chipLabel = stringResource(R.string.product_step_one_chip),
            title = stringResource(R.string.product_step_setup_title),
            body = stringResource(R.string.product_step_setup_body)
        )
        if (inputType == VoiceInputType.OVERLAY) {
            StepSection(
                icon = Icons.Outlined.OpenWith,
                chipLabel = stringResource(R.string.product_step_two_chip),
                title = stringResource(R.string.product_step_position_title),
                body = stringResource(R.string.product_step_position_body)
            )
        }
        StepSection(
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
private fun StatusSection(
    state: VoiceHomeState,
    onOpenLocalModels: () -> Unit,
    onGrantMicrophone: () -> Unit,
    onOpenVoiceService: () -> Unit,
    onOpenVoiceKeyboard: () -> Unit,
    onSelectInputType: (VoiceInputType) -> Unit,
    onOpenMicPosition: () -> Unit
) {
    SectionCard(title = stringResource(R.string.product_status)) {
        InputTypeSetupRow(
            selected = state.inputType,
            loading = state.loading,
            onSelect = onSelectInputType
        )
        HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
        SetupStatusRow(
            title = stringResource(R.string.product_status_microphone),
            ready = state.microphoneAllowed,
            loading = state.loading,
            actionLabel = stringResource(R.string.product_action_allow),
            onAction = onGrantMicrophone
        )
        when (state.inputType) {
            VoiceInputType.OVERLAY -> {
                HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                SetupStatusRow(
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
                SetupStatusRow(
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
        LocalModelsSetupRow(
            ready = state.modelsReady,
            loading = state.loading,
            onClick = onOpenLocalModels
        )
    }
}
