package com.sanogueralorenzo.overlay.help

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.sanogueralorenzo.overlay.R
import com.sanogueralorenzo.overlay.ui.components.SectionCard
import com.sanogueralorenzo.overlay.ui.components.StepSection

fun NavGraphBuilder.helpRoute(
    route: String,
    onBack: () -> Unit
) {
    composable(route) {
        HelpScreen(onBack = onBack)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpScreen(
    onBack: () -> Unit
) {
    val scrollState = rememberScrollState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(R.string.help_title)) },
                windowInsets = TopAppBarDefaults.windowInsets.only(WindowInsetsSides.Horizontal),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.back_button)
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState)
                .padding(16.dp),
            verticalArrangement = Arrangement.Top
        ) {
            SectionCard(title = stringResource(R.string.how_it_works_label)) {
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
    }
}
