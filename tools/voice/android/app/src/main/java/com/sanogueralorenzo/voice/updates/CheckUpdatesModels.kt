package com.sanogueralorenzo.voice.updates

import com.airbnb.mvrx.MavericksState

data class CheckUpdatesState(
    val updatesRunning: Boolean = false,
    val updatesMessage: String? = null,
    val modelMessage: String? = null
) : MavericksState
