package com.sanogueralorenzo.overlay.home

import androidx.compose.runtime.getValue
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
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.airbnb.mvrx.compose.collectAsState as mavericksCollectAsState
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.overlay.R
import com.sanogueralorenzo.overlay.ui.components.RefreshOnResume
import com.sanogueralorenzo.overlay.ui.components.SectionCard
import com.sanogueralorenzo.overlay.ui.components.StepSection

fun NavGraphBuilder.homeRoute(
    route: String,
    onOpenPermissions: () -> Unit
) {
    composable(route) {
        val viewModel: HomeViewModel = mavericksViewModel()
        val state by viewModel.mavericksCollectAsState()
        RefreshOnResume(viewModel::refreshPermissions)
        HomeScreen(
            state = state,
            onOpenPermissions = onOpenPermissions
        )
    }
}

@Composable
fun HomeScreen(
    state: HomeState,
    onOpenPermissions: () -> Unit
) {
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
                HomeHowItWorksSection()
            }
            item {
                HomePermissionsSection(
                    allRequirementsGranted = state.allRequirementsGranted,
                    onOpenPermissions = onOpenPermissions
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
                .padding(horizontal = 16.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                painter = painterResource(id = R.drawable.ic_qs_black),
                contentDescription = stringResource(R.string.app_name),
                modifier = Modifier.size(96.dp)
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = stringResource(R.string.home_title),
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = stringResource(R.string.home_purpose_title),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun HomeHowItWorksSection() {
    SectionCard(title = stringResource(R.string.home_next_steps_title)) {
        StepSection(
            icon = Icons.Outlined.PlayArrow,
            chipLabel = stringResource(R.string.step_one_chip),
            title = stringResource(R.string.step_one_title),
            body = stringResource(R.string.step_one_body)
        )
        StepSection(
            icon = Icons.Outlined.KeyboardArrowDown,
            chipLabel = stringResource(R.string.step_two_chip),
            title = stringResource(R.string.step_two_title),
            body = stringResource(R.string.step_two_body)
        )
        StepSection(
            icon = Icons.Outlined.GridView,
            chipLabel = stringResource(R.string.step_three_chip),
            title = stringResource(R.string.step_three_title),
            body = stringResource(R.string.step_three_body)
        )
        StepSection(
            icon = ImageVector.vectorResource(R.drawable.ic_step_power),
            chipLabel = stringResource(R.string.step_four_chip),
            title = stringResource(R.string.step_four_title),
            body = stringResource(R.string.step_four_body)
        )
    }
}

@Composable
private fun HomePermissionsSection(
    allRequirementsGranted: Boolean,
    onOpenPermissions: () -> Unit
) {
    val status = if (allRequirementsGranted) {
        HomePermissionStatus(
            subtitle = stringResource(R.string.home_permissions_all_granted),
            icon = Icons.Rounded.Check,
            color = Color.White
        )
    } else {
        HomePermissionStatus(
            subtitle = stringResource(R.string.overlay_setup_title),
            icon = Icons.Outlined.ErrorOutline,
            color = MaterialTheme.colorScheme.error
        )
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(R.string.permissions_title),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        ElevatedCard(
            onClick = onOpenPermissions,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = status.icon,
                    contentDescription = null,
                    tint = status.color,
                    modifier = Modifier.size(24.dp)
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(1.dp)
                ) {
                    Text(
                        text = stringResource(R.string.open_permissions_button),
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Text(
                        text = status.subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

private data class HomePermissionStatus(
    val subtitle: String,
    val icon: ImageVector,
    val color: Color
)
