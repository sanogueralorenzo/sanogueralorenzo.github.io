package com.sanogueralorenzo.overlay.autotimeout

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.overlay.OverlayApp
import kotlinx.coroutines.launch

data class AutoTimeoutState(
    val deviceAdminActive: Boolean = false,
    val autoLockMinutes: Int = 0,
    val isTileAdded: Boolean = false
) : MavericksState

class AutoTimeoutViewModel(
    initialState: AutoTimeoutState,
    private val repository: AutoTimeoutRepository
) : MavericksViewModel<AutoTimeoutState>(initialState) {
    init {
        repository.autoLockMinutesFlow().setOnEach { copy(autoLockMinutes = it) }
        repository.tileAddedFlow().setOnEach { copy(isTileAdded = it) }
        refreshState()
    }

    fun refreshState() {
        val isAdmin = repository.isDeviceAdminActive()
        setState { copy(deviceAdminActive = isAdmin) }
        viewModelScope.launch {
            val minutes = repository.readAutoLockMinutes()
            if (!isAdmin && minutes > 0) {
                repository.setAutoLockMinutes(0)
            }
        }
    }

    fun setAutoLockMinutes(minutes: Int) {
        viewModelScope.launch {
            repository.setAutoLockMinutes(minutes)
        }
    }

    fun setTileAdded(added: Boolean) {
        viewModelScope.launch {
            repository.setTileAdded(added)
        }
    }

    companion object : MavericksViewModelFactory<AutoTimeoutViewModel, AutoTimeoutState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: AutoTimeoutState
        ): AutoTimeoutViewModel {
            val app = viewModelContext.app() as OverlayApp
            return AutoTimeoutViewModel(state, app.appGraph.autoTimeoutRepository)
        }
    }
}
