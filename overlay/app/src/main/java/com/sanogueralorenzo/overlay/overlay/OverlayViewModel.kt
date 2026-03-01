package com.sanogueralorenzo.overlay.overlay

import com.airbnb.mvrx.Async
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.Uninitialized
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.overlay.OverlayApp
import kotlinx.coroutines.launch

data class OverlayState(
    val overlayPermission: Async<Boolean> = Uninitialized,
    val tileAdded: Async<Boolean> = Uninitialized,
    val longPressDismissEnabled: Async<Boolean> = Uninitialized
) : MavericksState

class OverlayViewModel(
    initialState: OverlayState,
    private val repository: OverlayRepository
) : MavericksViewModel<OverlayState>(initialState) {
    init {
        repository.tileAddedFlow().setOnEach { copy(tileAdded = Success(it)) }
        repository.longPressDismissEnabledFlow()
            .setOnEach { copy(longPressDismissEnabled = Success(it)) }
        refreshOverlay()
    }

    fun refreshOverlay() {
        suspend { repository.isOverlayGranted() }
            .execute { copy(overlayPermission = it) }
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
