package com.sanogueralorenzo.overlay.home

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.overlay.OverlayApp
import com.sanogueralorenzo.overlay.permissions.PermissionsRepository

data class HomeState(
    val allRequirementsGranted: Boolean = false
) : MavericksState

class HomeViewModel(
    initialState: HomeState,
    private val repository: PermissionsRepository
) : MavericksViewModel<HomeState>(initialState) {

    init {
        repository.allRequirementsGrantedFlow().setOnEach {
            copy(allRequirementsGranted = it)
        }
        refreshPermissions()
    }

    fun refreshPermissions() {
        repository.refreshPermissionStates()
    }

    companion object : MavericksViewModelFactory<HomeViewModel, HomeState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: HomeState
        ): HomeViewModel {
            val app = viewModelContext.app() as OverlayApp
            return HomeViewModel(state, app.appGraph.permissionsRepository)
        }
    }
}
