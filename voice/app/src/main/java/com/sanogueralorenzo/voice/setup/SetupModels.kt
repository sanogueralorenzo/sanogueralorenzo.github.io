package com.sanogueralorenzo.voice.setup

import com.airbnb.mvrx.Async
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.Uninitialized

data class SetupUiState(
    val micGranted: Boolean = false,
    val voiceImeEnabled: Boolean = false,
    val voiceImeSelected: Boolean = false,
    val wifiConnected: Boolean = true,
    val introDismissed: Boolean = false,
    val requiredStep: SetupRepository.RequiredStep = SetupRepository.RequiredStep.INTRO,
    val liteRtReady: Boolean = false,
    val moonshineReady: Boolean = false,
    val promptReady: Boolean = false,
    val liteRtProgress: Int = 0,
    val moonshineProgress: Int = 0,
    val promptProgress: Int = 0,
    val liteRtDownloading: Boolean = false,
    val moonshineDownloading: Boolean = false,
    val promptDownloading: Boolean = false,
    val promptVersion: String? = null,
    val updatesRunning: Boolean = false,
    val modelMessage: String? = null,
    val updatesMessage: String? = null,
    val settingsKeyboardTestInput: String = "",
    val themeKeyboardTestInput: String = "",
    val modelReadinessAsync: Async<ModelReadiness> = Uninitialized,
    val updatesAsync: Async<ModelUpdatesOutcome> = Uninitialized
) : MavericksState
