package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.BuildConfig
import com.sanogueralorenzo.voice.R

@Composable
fun HomeScreen(
    onOpenPromptBenchmarking: () -> Unit,
    onOpenTheme: () -> Unit,
    onOpenUpdates: () -> Unit,
    onOpenPreferences: () -> Unit
) {
    var showLanguagesComingSoonDialog by remember { mutableStateOf(false) }

    val menuItems = mutableListOf(
        HomeMenuItem(
            icon = Icons.Outlined.Language,
            title = stringResource(R.string.home_menu_languages_title),
            subtitle = stringResource(R.string.home_menu_languages_subtitle),
            onClick = { showLanguagesComingSoonDialog = true }
        ),
        HomeMenuItem(
            icon = Icons.Outlined.Tune,
            title = stringResource(R.string.home_menu_preferences),
            onClick = onOpenPreferences
        ),
        HomeMenuItem(
            icon = Icons.Outlined.Palette,
            title = stringResource(R.string.home_menu_theme),
            onClick = onOpenTheme
        ),
    )

    if (BuildConfig.DEBUG) {
        menuItems += HomeMenuItem(
            icon = Icons.Outlined.ContentPaste,
            title = stringResource(R.string.home_menu_prompt_benchmark),
            onClick = onOpenPromptBenchmarking
        )
    }

    menuItems += listOf(
        HomeMenuItem(
            icon = Icons.Outlined.Info,
            title = stringResource(R.string.home_menu_updates),
            onClick = onOpenUpdates
        ),
        HomeMenuItem(
            icon = Icons.Outlined.HelpOutline,
            title = stringResource(R.string.home_menu_help)
        )
    )

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        itemsIndexed(menuItems) { index, item ->
            HomeMenuRow(item = item)
            if (index == 0) {
                Spacer(modifier = Modifier.height(8.dp))
            }
        }
    }

    if (showLanguagesComingSoonDialog) {
        AlertDialog(
            onDismissRequest = { showLanguagesComingSoonDialog = false },
            text = { Text(text = stringResource(R.string.home_languages_coming_soon_message)) },
            confirmButton = {
                TextButton(onClick = { showLanguagesComingSoonDialog = false }) {
                    Text(text = stringResource(android.R.string.ok))
                }
            }
        )
    }
}

private data class HomeMenuItem(
    val icon: ImageVector,
    val title: String,
    val subtitle: String? = null,
    val onClick: (() -> Unit)? = null
)

@Composable
private fun HomeMenuRow(
    item: HomeMenuItem
) {
    val textColor = MaterialTheme.colorScheme.onSurface
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (item.onClick != null) {
                    Modifier.clickable(onClick = item.onClick)
                } else {
                    Modifier
                }
            )
            .padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalAlignment = Alignment.Top
    ) {
        Icon(
            imageVector = item.icon,
            contentDescription = null,
            tint = textColor,
            modifier = Modifier
                .size(28.dp)
                .padding(top = 1.dp)
        )
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.titleLarge,
                color = textColor
            )
            if (!item.subtitle.isNullOrBlank()) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.bodyLarge,
                    color = textColor
                )
            }
        }
    }
}
