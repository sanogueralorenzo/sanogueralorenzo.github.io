package com.sanogueralorenzo.voice

import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.SystemUpdate
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.theme.KeyboardThemeMode

@Composable
fun HomeScreen(
    onOpenBenchmark: () -> Unit,
    onOpenTheme: () -> Unit,
    onOpenUpdates: () -> Unit,
    onOpenPreferences: () -> Unit,
    keyboardThemeMode: KeyboardThemeMode
) {
    var showLanguagesComingSoonDialog by remember { mutableStateOf(false) }

    val generalItems = listOf(
        HomeMenuItem(
            icon = Icons.Outlined.Language,
            title = stringResource(R.string.settings_menu_languages_title),
            subtitle = stringResource(R.string.settings_menu_languages_subtitle),
            onClick = { showLanguagesComingSoonDialog = true }
        ),
        HomeMenuItem(
            icon = Icons.Outlined.Tune,
            title = stringResource(R.string.settings_menu_preferences),
            onClick = onOpenPreferences
        ),
        HomeMenuItem(
            icon = Icons.Outlined.Palette,
            title = stringResource(R.string.settings_menu_theme),
            chip = HomeItemChip(themeModeLabel(keyboardThemeMode)),
            onClick = onOpenTheme
        )
    )

    val toolItems = mutableListOf(
        HomeMenuItem(
            icon = Icons.Outlined.SystemUpdate,
            title = stringResource(R.string.settings_menu_updates),
            onClick = onOpenUpdates
        )
    )

    toolItems += HomeMenuItem(
        icon = Icons.Outlined.ContentPaste,
        title = stringResource(R.string.settings_menu_benchmark),
        onClick = onOpenBenchmark
    )

    val sections = listOf(
        HomeMenuSection(
            title = stringResource(R.string.settings_section_general),
            items = generalItems
        ),
        HomeMenuSection(
            title = stringResource(R.string.settings_section_tools),
            items = toolItems
        )
    )

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        items(sections) { section ->
            HomeSectionCard(section = section)
        }
        item { Spacer(modifier = Modifier.height(4.dp)) }
    }

    if (showLanguagesComingSoonDialog) {
        AlertDialog(
            onDismissRequest = { showLanguagesComingSoonDialog = false },
            text = { Text(text = stringResource(R.string.settings_languages_coming_soon_message)) },
            confirmButton = {
                TextButton(onClick = { showLanguagesComingSoonDialog = false }) {
                    Text(text = stringResource(android.R.string.ok))
                }
            }
        )
    }
}

private data class HomeMenuSection(
    val title: String,
    val items: List<HomeMenuItem>
)

private data class HomeMenuItem(
    val icon: ImageVector,
    val title: String,
    val subtitle: String? = null,
    val chip: HomeItemChip? = null,
    val onClick: () -> Unit
)

private data class HomeItemChip(
    val label: String,
    val tone: HomeChipTone = HomeChipTone.NEUTRAL
)

private enum class HomeChipTone {
    NEUTRAL,
    SUCCESS,
    WARNING
}

@Composable
private fun HomeSectionCard(
    section: HomeMenuSection
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = section.title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp)
            ) {
                section.items.forEachIndexed { index, item ->
                    HomeMenuRow(item = item)
                    if (index < section.items.lastIndex) {
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
    val textColor = MaterialTheme.colorScheme.onSurface
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = item.onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = item.icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(24.dp)
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(1.dp)
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyLarge,
                color = textColor
            )
            if (!item.subtitle.isNullOrBlank()) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (item.chip != null) {
            HomeRowChip(chip = item.chip)
        }
        Icon(
            imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
private fun HomeRowChip(chip: HomeItemChip) {
    val containerColor = when (chip.tone) {
        HomeChipTone.NEUTRAL -> MaterialTheme.colorScheme.surfaceContainerHighest
        HomeChipTone.SUCCESS -> MaterialTheme.colorScheme.secondaryContainer
        HomeChipTone.WARNING -> MaterialTheme.colorScheme.errorContainer
    }
    val contentColor = when (chip.tone) {
        HomeChipTone.NEUTRAL -> MaterialTheme.colorScheme.onSurfaceVariant
        HomeChipTone.SUCCESS -> MaterialTheme.colorScheme.onSecondaryContainer
        HomeChipTone.WARNING -> MaterialTheme.colorScheme.onErrorContainer
    }
    Surface(
        color = containerColor,
        shape = MaterialTheme.shapes.small
    ) {
        Text(
            text = chip.label,
            style = MaterialTheme.typography.labelSmall,
            color = contentColor,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}

@Composable
private fun themeModeLabel(mode: KeyboardThemeMode): String {
    return when (mode) {
        KeyboardThemeMode.AUTO -> stringResource(R.string.settings_chip_theme_auto)
        KeyboardThemeMode.LIGHT -> stringResource(R.string.settings_chip_theme_light)
        KeyboardThemeMode.DARK -> stringResource(R.string.settings_chip_theme_dark)
    }
}
