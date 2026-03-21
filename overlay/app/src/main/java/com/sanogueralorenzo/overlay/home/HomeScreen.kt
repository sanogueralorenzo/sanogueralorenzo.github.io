package com.sanogueralorenzo.overlay.home

import androidx.compose.runtime.getValue
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.airbnb.mvrx.Async
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.Uninitialized
import com.airbnb.mvrx.ViewModelContext
import com.airbnb.mvrx.compose.collectAsState as mavericksCollectAsState
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.overlay.OverlayApp
import com.sanogueralorenzo.overlay.R
import com.sanogueralorenzo.overlay.permissions.PermissionsRepository
import com.sanogueralorenzo.overlay.ui.components.RefreshOnResume

data class HomeState(
    val overlayPermission: Async<Boolean> = Uninitialized,
    val tileAdded: Async<Boolean> = Uninitialized,
    val notificationPermission: Async<Boolean> = Uninitialized,
    val secureSettingsPermission: Async<Boolean> = Uninitialized
) : MavericksState {
    val allRequirementsGranted: Boolean
        get() = overlayPermission() == true &&
            tileAdded() == true &&
            notificationPermission() == true &&
            secureSettingsPermission() == true
}

class HomeViewModel(
    initialState: HomeState,
    private val repository: PermissionsRepository
) : MavericksViewModel<HomeState>(initialState) {

    init {
        repository.tileAddedFlow().setOnEach { copy(tileAdded = Success(it)) }
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

fun NavGraphBuilder.homeRoute(
    route: String,
    onOpenHelp: () -> Unit,
    onOpenPermissions: () -> Unit
) {
    composable(route) {
        val homeViewModel: HomeViewModel = mavericksViewModel()
        val state by homeViewModel.mavericksCollectAsState()
        RefreshOnResume {
            homeViewModel.refreshPermissions()
        }
        HomeScreen(
            state = state,
            onOpenHelp = onOpenHelp,
            onOpenPermissions = onOpenPermissions
        )
    }
}

@Composable
fun HomeScreen(
    state: HomeState,
    onOpenHelp: () -> Unit,
    onOpenPermissions: () -> Unit
) {
    val permissionStatusIcon = if (state.allRequirementsGranted) "✅" else "⚠️"
    val nextStepsItems = listOf(
        HomeMenuItem(
            title = stringResource(R.string.open_help_button),
            subtitle = stringResource(R.string.how_it_works_label),
            leadingEmoji = "👀",
            onClick = onOpenHelp
        ),
        HomeMenuItem(
            title = stringResource(R.string.open_permissions_button),
            subtitle = stringResource(R.string.overlay_setup_title),
            leadingEmoji = permissionStatusIcon,
            onClick = onOpenPermissions
        )
    )

    Scaffold { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                HomeHero()
            }
            item {
                HomeSectionCard(
                    title = stringResource(R.string.home_next_steps_title),
                    items = nextStepsItems
                )
            }
            item {
                Spacer(modifier = Modifier.height(4.dp))
            }
        }
    }
}

@Composable
private fun HomeHero() {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                painter = painterResource(id = R.drawable.ic_qs_black),
                contentDescription = stringResource(R.string.app_name),
                modifier = Modifier.size(128.dp)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = stringResource(R.string.home_title),
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = stringResource(R.string.home_purpose_title),
                style = MaterialTheme.typography.titleLarge,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.home_purpose_body),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

private data class HomeMenuItem(
    val title: String,
    val subtitle: String?,
    val onClick: () -> Unit,
    val leadingEmoji: String
)

@Composable
private fun HomeSectionCard(
    title: String,
    items: List<HomeMenuItem>
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp)
            ) {
                items.forEachIndexed { index, item ->
                    HomeMenuRow(item = item)
                    if (index < items.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 58.dp),
                            color = MaterialTheme.colorScheme.outlineVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeMenuRow(item: HomeMenuItem) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = item.onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier.size(24.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = item.leadingEmoji,
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(1.dp)
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyLarge
            )
            if (!item.subtitle.isNullOrBlank()) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Icon(
            imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp)
        )
    }
}
