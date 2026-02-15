package com.sanogueralorenzo.voice.setup

import com.airbnb.mvrx.Async
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.Uninitialized

data class SetupUiState(
    val micGranted: Boolean = false,
    val liteRtReady: Boolean = false,
    val moonshineReady: Boolean = false,
    val liteRtProgress: Int = 0,
    val moonshineProgress: Int = 0,
    val liteRtDownloading: Boolean = false,
    val moonshineDownloading: Boolean = false,
    val updatesRunning: Boolean = false,
    val modelMessage: String? = null,
    val updatesMessage: String? = null,
    val keyboardTestInput: String = "",
    val liteRtRewriteEnabled: Boolean = true,
    val responseStyleLevel: Int = 0,
    val customInstructions: String = "",
    val modelReadinessAsync: Async<ModelReadiness> = Uninitialized,
    val updatesAsync: Async<ModelUpdatesOutcome> = Uninitialized
) : MavericksState

data class SetupActions(
    val onOpenSetup: () -> Unit,
    val onOpenModels: () -> Unit,
    val onOpenOnboarding: () -> Unit,
    val onOpenPromptBenchmarking: () -> Unit,
    val onOpenResponseStyle: () -> Unit,
    val onOpenSettings: () -> Unit,
    val onGrantMic: () -> Unit,
    val onOpenImeSettings: () -> Unit,
    val onShowImePicker: () -> Unit,
    val onDownloadAll: () -> Unit,
    val onDownloadLiteRt: () -> Unit,
    val onDownloadMoonshine: () -> Unit,
    val onCheckUpdates: () -> Unit
)
