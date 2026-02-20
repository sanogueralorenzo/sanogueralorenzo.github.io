package com.sanogueralorenzo.voice.benchmark

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ui.OnResume

@Composable
fun BenchmarkScreen(
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val viewModel = mavericksViewModel<BenchmarkViewModel, BenchmarkState>()
    val state by viewModel.collectAsStateWithLifecycle()

    OnResume {
        viewModel.refreshPrerequisites()
    }

    LaunchedEffect(Unit) {
        viewModel.refreshPrerequisites()
    }

    fun shareResult(result: BenchmarkSessionResult) {
        val reportText = BenchmarkReportFormatter.toPlainText(result)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.benchmark_share_subject))
            putExtra(Intent.EXTRA_TEXT, reportText)
        }
        context.startActivity(
            Intent.createChooser(
                shareIntent,
                context.getString(R.string.benchmark_share_chooser)
            )
        )
    }

    val runnerState = state.runnerState
    val sessionResult = state.sessionResult
    val totalRuns = runnerState.totalCases * runnerState.repeats
    val completedRuns = if (runnerState.currentCaseIndex <= 0 || runnerState.currentRunIndex <= 0) {
        0
    } else {
        ((runnerState.currentCaseIndex - 1) * runnerState.repeats) + runnerState.currentRunIndex
    }
    val progress = if (totalRuns == 0) {
        0f
    } else {
        (completedRuns.toFloat() / totalRuns.toFloat()).coerceIn(0f, 1f)
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.benchmark_intro),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }

        if (!state.rewriteEnabled) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = stringResource(R.string.benchmark_rewrite_disabled_warning),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(16.dp)
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Button(
                onClick = { viewModel.runBenchmark() },
                enabled = !runnerState.isRunning && state.modelAvailable,
                modifier = Modifier.weight(1f)
            ) {
                Text(text = stringResource(R.string.benchmark_run_action))
            }

            OutlinedButton(
                onClick = { viewModel.cancelBenchmark() },
                enabled = runnerState.isRunning,
                modifier = Modifier.weight(1f)
            ) {
                Text(text = stringResource(R.string.benchmark_cancel_action))
            }

            OutlinedButton(
                onClick = { sessionResult?.let { shareResult(it) } },
                enabled = !runnerState.isRunning && sessionResult != null,
                modifier = Modifier.weight(1f)
            ) {
                Text(text = stringResource(R.string.benchmark_share_action))
            }
        }

        if (runnerState.isRunning || runnerState.phase == BenchmarkRunPhase.ERROR) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = benchmarkProgressLabel(runnerState),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    if (runnerState.phase == BenchmarkRunPhase.DOWNLOADING_DATASET) {
                        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    } else {
                        LinearProgressIndicator(
                            progress = { progress },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }

        if (!runnerState.errorMessage.isNullOrBlank()) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = runnerState.errorMessage.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(16.dp)
                )
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            val result = sessionResult
            if (result != null) {
                val displayedFailures = result.cases.count { !BenchmarkScoring.isCasePassed(it) }
                val displayedPasses = result.totalCases - displayedFailures
                item {
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                text = stringResource(R.string.benchmark_summary_title),
                                style = MaterialTheme.typography.titleMedium
                            )
                            Text(
                                text = stringResource(
                                    R.string.benchmark_summary_pass,
                                    displayedPasses
                                ),
                                style = MaterialTheme.typography.bodySmall
                            )
                            Text(
                                text = stringResource(
                                    R.string.benchmark_summary_fail,
                                    displayedFailures
                                ),
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                }

                items(result.cases, key = { it.caseDef.id }) { caseResult ->
                    BenchmarkCaseCard(caseResult = caseResult)
                }
            }
        }
    }
}

@Composable
private fun benchmarkProgressLabel(state: BenchmarkRunnerState): String {
    return when (state.phase) {
        BenchmarkRunPhase.DOWNLOADING_DATASET ->
            stringResource(R.string.benchmark_progress_downloading)
        BenchmarkRunPhase.RUNNING ->
            stringResource(
                R.string.benchmark_progress_running,
                state.currentCaseIndex,
                state.totalCases
            )
        BenchmarkRunPhase.ERROR ->
            stringResource(R.string.benchmark_progress_error)
        BenchmarkRunPhase.COMPLETED ->
            stringResource(R.string.benchmark_progress_complete)
        else ->
            stringResource(R.string.benchmark_progress_idle)
    }
}

@Composable
private fun BenchmarkCaseCard(caseResult: BenchmarkCaseResult) {
    val caseDef = caseResult.caseDef
    val casePassed = BenchmarkScoring.isCasePassed(caseResult)
    val backendLabel = backendLabel(caseResult.runs)
    val inputText = benchmarkInputText(caseDef)
    val expectedText = caseDef.expectedOutput ?: stringResource(R.string.benchmark_expected_missing)
    val outputText = BenchmarkScoring.benchmarkOutputText(caseResult.runs)
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = caseDef.title,
                    style = MaterialTheme.typography.titleMedium
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Badge(
                        containerColor = if (backendLabel == "GPU") {
                            GpuBadgeGreen
                        } else {
                            MaterialTheme.colorScheme.errorContainer
                        },
                        contentColor = if (backendLabel == "GPU") {
                            Color.White
                        } else {
                            MaterialTheme.colorScheme.onErrorContainer
                        }
                    ) {
                        Text(
                            text = backendLabel,
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                    Badge(
                        containerColor = if (casePassed) {
                            MaterialTheme.colorScheme.primaryContainer
                        } else {
                            MaterialTheme.colorScheme.errorContainer
                        },
                        contentColor = if (casePassed) {
                            MaterialTheme.colorScheme.onPrimaryContainer
                        } else {
                            MaterialTheme.colorScheme.onErrorContainer
                        }
                    ) {
                        Text(
                            text = stringResource(
                                if (casePassed) {
                                    R.string.benchmark_case_pass
                                } else {
                                    R.string.benchmark_case_fail
                                }
                            ),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
            }

            Text(
                text = stringResource(R.string.benchmark_before_label),
                style = MaterialTheme.typography.labelLarge
            )
            Text(
                text = inputText,
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.benchmark_expected_label),
                style = MaterialTheme.typography.labelLarge
            )
            Text(
                text = expectedText,
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.benchmark_output_label),
                style = MaterialTheme.typography.labelLarge
            )
            Text(
                text = outputText,
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

private fun benchmarkInputText(caseDef: BenchmarkCase): String {
    return when (caseDef.type) {
        BenchmarkCaseType.COMPOSE -> caseDef.composeInput.orEmpty()
        BenchmarkCaseType.EDIT -> {
            val original = caseDef.editOriginal.orEmpty()
            val instruction = caseDef.editInstruction.orEmpty()
            "Original: $original\nInstruction: $instruction"
        }
    }
}

private fun backendLabel(runs: List<BenchmarkRunResult>): String {
    val backend = runs.firstOrNull { !it.backend.isNullOrBlank() }?.backend.orEmpty()
    return if (backend.contains("gpu", ignoreCase = true)) "GPU" else "CPU"
}

private val GpuBadgeGreen = Color(0xFF2E7D32)
