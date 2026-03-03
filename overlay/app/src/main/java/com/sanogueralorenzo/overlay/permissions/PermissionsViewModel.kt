package com.sanogueralorenzo.overlay.permissions

import com.airbnb.mvrx.Async
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.Uninitialized
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.overlay.OverlayApp
import com.sanogueralorenzo.overlay.ui.components.SecureSettingsCommands
import kotlinx.coroutines.launch

data class PermissionsState(
    val overlayPermission: Async<Boolean> = Uninitialized,
    val tileAdded: Async<Boolean> = Uninitialized,
    val notificationPermission: Async<Boolean> = Uninitialized,
    val secureSettingsPermission: Async<Boolean> = Uninitialized,
    val secureSettingsCommands: SecureSettingsCommands = SecureSettingsCommands(
        mac = "",
        windows = "",
        linux = ""
    )
) : MavericksState

class PermissionsViewModel(
    initialState: PermissionsState,
    private val repository: PermissionsRepository
) : MavericksViewModel<PermissionsState>(initialState) {

    init {
        repository.tileAddedFlow().setOnEach { copy(tileAdded = Success(it)) }
        setState { copy(secureSettingsCommands = repository.secureSettingsCommands()) }
        refreshPermissions()
    }

    fun refreshPermissions() {
        suspend { repository.isOverlayPermissionGranted() }
            .execute { copy(overlayPermission = it) }
        suspend { repository.isNotificationPermissionGranted() }
            .execute { copy(notificationPermission = it) }
        suspend { repository.isWriteSecureSettingsPermissionGranted() }
            .execute { copy(secureSettingsPermission = it) }
    }

    fun setTileAdded(added: Boolean) {
        viewModelScope.launch {
            repository.setTileAdded(added)
        }
    }

    companion object : MavericksViewModelFactory<PermissionsViewModel, PermissionsState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: PermissionsState
        ): PermissionsViewModel {
            val app = viewModelContext.app() as OverlayApp
            return PermissionsViewModel(state, app.appGraph.permissionsRepository)
        }
    }
}
