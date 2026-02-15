package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.settings.ResponseStyle
import kotlin.math.roundToInt

@Composable
fun ResponseStyleScreen(
    responseStyleLevel: Int,
    onResponseStyleLevelChange: (Int) -> Unit
) {
    val normalizedLevel = ResponseStyle.normalize(responseStyleLevel)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.response_style_section_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = stringResource(R.string.response_style_section_description),
            style = MaterialTheme.typography.bodyMedium
        )

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = stringResource(R.string.response_style_slider_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = levelLabel(normalizedLevel),
                    style = MaterialTheme.typography.bodyMedium
                )
                Slider(
                    value = normalizedLevel.toFloat(),
                    onValueChange = { raw ->
                        val nextLevel = ResponseStyle.normalize(raw.roundToInt())
                        if (nextLevel != normalizedLevel) {
                            onResponseStyleLevelChange(nextLevel)
                        }
                    },
                    valueRange = ResponseStyle.MIN_LEVEL.toFloat()..ResponseStyle.MAX_LEVEL.toFloat(),
                    steps = ResponseStyle.LEVEL_COUNT - 2
                )
                Row(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = stringResource(R.string.response_style_consistent),
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        text = stringResource(R.string.response_style_creative),
                        style = MaterialTheme.typography.bodySmall,
                        textAlign = TextAlign.End,
                        modifier = Modifier.weight(1f)
                    )
                }
                Text(
                    text = stringResource(R.string.response_style_hint),
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@Composable
private fun levelLabel(level: Int): String {
    return when (level) {
        0 -> stringResource(R.string.response_style_level_0)
        1 -> stringResource(R.string.response_style_level_1)
        2 -> stringResource(R.string.response_style_level_2)
        3 -> stringResource(R.string.response_style_level_3)
        4 -> stringResource(R.string.response_style_level_4)
        else -> stringResource(R.string.response_style_level_5)
    }
}
