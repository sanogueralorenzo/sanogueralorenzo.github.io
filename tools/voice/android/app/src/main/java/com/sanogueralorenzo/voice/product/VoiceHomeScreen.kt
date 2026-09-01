package com.sanogueralorenzo.voice.product

import android.Manifest
import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material3.Button
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
import com.sanogueralorenzo.voice.ui.OnLifecycle

@Composable
fun VoiceHomeScreen(
    onOpenModels: () -> Unit,
    onOpenMicPosition: () -> Unit
) {
    val context = LocalContext.current
    val viewModel = mavericksViewModel<VoiceHomeViewModel, VoiceHomeState>()
    val state by viewModel.collectAsStateWithLifecycle()
    val microphonePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { viewModel.refreshStatus() }

    OnLifecycle(Lifecycle.Event.ON_RESUME) { viewModel.refreshStatus() }

    VoiceHomeContent(
        state = state,
        onOpenModels = onOpenModels,
        onGrantMicrophone = {
            microphonePermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        },
        onOpenVoiceService = {
            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        },
        onOpenMicPosition = onOpenMicPosition
    )
}

@Composable
private fun VoiceHomeContent(
    state: VoiceHomeState,
    onOpenModels: () -> Unit,
    onGrantMicrophone: () -> Unit,
    onOpenVoiceService: () -> Unit,
    onOpenMicPosition: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { ProductHero() }
        item { HowItWorksCard() }
        item {
            StatusSection(
                state = state,
                onOpenModels = onOpenModels,
                onGrantMicrophone = onGrantMicrophone,
                onOpenVoiceService = onOpenVoiceService
            )
        }
        item {
            MicPositionCard(
                enabled = state.voiceServiceEnabled,
                onClick = onOpenMicPosition
            )
        }
        item { Spacer(modifier = Modifier.height(4.dp)) }
    }
}

@Composable
private fun ProductHero() {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_logo),
                contentDescription = null,
                modifier = Modifier.size(72.dp),
                tint = Color.Unspecified
            )
            Text(
                text = stringResource(R.string.product_hero_title),
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun HowItWorksCard() {
    Section(title = stringResource(R.string.product_how_it_works)) {
        ProductStep(number = 1, text = stringResource(R.string.product_step_open_field))
        HorizontalDivider()
        ProductStep(number = 2, text = stringResource(R.string.product_step_tap_mic))
        HorizontalDivider()
        ProductStep(number = 3, text = stringResource(R.string.product_step_text_appears))
    }
}

@Composable
private fun ProductStep(number: Int, text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 13.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = number.toString(),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary
        )
        Text(text = text, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun StatusSection(
    state: VoiceHomeState,
    onOpenModels: () -> Unit,
    onGrantMicrophone: () -> Unit,
    onOpenVoiceService: () -> Unit
) {
    Section(title = stringResource(R.string.product_status)) {
        StatusRow(
            title = stringResource(R.string.product_status_models),
            ready = state.modelsReady,
            loading = state.loading,
            actionLabel = stringResource(R.string.product_action_download),
            onAction = onOpenModels
        )
        HorizontalDivider(modifier = Modifier.padding(start = 54.dp))
        StatusRow(
            title = stringResource(R.string.product_status_microphone),
            ready = state.microphoneAllowed,
            loading = state.loading,
            actionLabel = stringResource(R.string.product_action_allow),
            onAction = onGrantMicrophone
        )
        HorizontalDivider(modifier = Modifier.padding(start = 54.dp))
        StatusRow(
            title = stringResource(R.string.product_status_service),
            ready = state.voiceServiceEnabled,
            loading = state.loading,
            actionLabel = stringResource(R.string.product_action_enable),
            onAction = onOpenVoiceService
        )
    }
}

@Composable
private fun StatusRow(
    title: String,
    ready: Boolean,
    loading: Boolean,
    actionLabel: String,
    onAction: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val statusColor = if (ready) Color(0xFF16883B) else MaterialTheme.colorScheme.error
        Icon(
            imageVector = if (ready) Icons.Rounded.CheckCircle else Icons.Rounded.ErrorOutline,
            contentDescription = null,
            tint = if (loading) MaterialTheme.colorScheme.outline else statusColor,
            modifier = Modifier.size(24.dp)
        )
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f)
        )
        if (!ready && !loading) {
            Button(onClick = onAction) {
                Text(text = actionLabel)
            }
        }
    }
}

@Composable
private fun MicPositionCard(enabled: Boolean, onClick: () -> Unit) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.product_mic_position_title),
                    style = MaterialTheme.typography.bodyLarge
                )
                Text(
                    text = stringResource(
                        if (enabled) R.string.product_mic_position_body
                        else R.string.product_mic_position_requires_service
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant
                else MaterialTheme.colorScheme.outline
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
