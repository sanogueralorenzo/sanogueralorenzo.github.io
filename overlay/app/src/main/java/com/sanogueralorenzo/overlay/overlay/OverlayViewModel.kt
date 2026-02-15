package com.sanogueralorenzo.overlay.overlay

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.overlay.OverlayApp
import kotlinx.coroutines.launch

data class OverlayState(
    val isOverlayGranted: Boolean = false,
    val isTileAdded: Boolean = false,
    val isLongPressDismissEnabled: Boolean = false
) : MavericksState

class OverlayViewModel(
    initialState: OverlayState,
    private val repository: OverlayRepository
) : MavericksViewModel<OverlayState>(initialState) {
    init {
        repository.tileAddedFlow().setOnEach { copy(isTileAdded = it) }
        repository.longPressDismissEnabledFlow()
            .setOnEach { copy(isLongPressDismissEnabled = it) }
        refreshOverlay()
    }

    fun refreshOverlay() {
        val isOverlayGranted = repository.isOverlayGranted()
        setState { copy(isOverlayGranted = isOverlayGranted) }
    }

    fun setTileAdded(added: Boolean) {
        viewModelScope.launch {
            repository.setTileAdded(added)
        }
    }

    fun setLongPressDismissEnabled(enabled: Boolean) {
        viewModelScope.launch {
            repository.setLongPressDismissEnabled(enabled)
        }
    }

    companion object : MavericksViewModelFactory<OverlayViewModel, OverlayState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: OverlayState
        ): OverlayViewModel {
            val app = viewModelContext.app() as OverlayApp
            return OverlayViewModel(state, app.appGraph.overlayRepository)
        }
    }
}
