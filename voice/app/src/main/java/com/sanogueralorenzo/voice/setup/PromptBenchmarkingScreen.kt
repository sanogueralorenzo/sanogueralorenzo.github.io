package com.sanogueralorenzo.voice.setup

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.di.appGraph

@Composable
fun PromptBenchmarkingScreen(
    onOpenModels: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val appContext = remember(context) { context.applicationContext }
    val appGraph = remember(appContext) { appContext.appGraph() }
    val lifecycleOwner = LocalLifecycleOwner.current
    val cases = remember { PromptBenchmarkSuite.defaultCases() }
    val gateway = remember(appContext) { LiteRtPromptBenchmarkGateway(appContext) }
    val viewModel = remember(appContext, appGraph, gateway, cases) {
        PromptBenchmarkingViewModel(
            initialState = PromptBenchmarkingUiState(
                runnerState = PromptBenchmarkRunnerState(
                    isRunning = false,
                    currentCaseIndex = 0,
                    totalCases = cases.size,
                    currentRunIndex = 0,
                    repeats = PromptBenchmarkRunner.DEFAULT_REPEATS,
                    errorMessage = null
                )
            ),
            appContext = appContext,
            settingsStore = appGraph.settingsStore,
            gateway = gateway,
            cases = cases
        )
    }
    val uiState by viewModel.collectAsStateWithLifecycle()

    DisposableEffect(gateway) {
        onDispose { gateway.release() }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshPrerequisites()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(Unit) {
        viewModel.refreshPrerequisites()
    }

    fun shareResult(result: PromptBenchmarkSessionResult) {
        val reportText = PromptBenchmarkReportFormatter.toPlainText(result)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.prompt_benchmark_share_subject))
            putExtra(Intent.EXTRA_TEXT, reportText)
        }
        context.startActivity(
            Intent.createChooser(
                shareIntent,
                context.getString(R.string.prompt_benchmark_share_chooser)
            )
        )
    }

    val runnerState = uiState.runnerState
    val sessionResult = uiState.sessionResult
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
                    text = stringResource(R.string.prompt_benchmark_section_title),
                    style = MaterialTheme.typography.titleLarge
                )
                Text(
                    text = stringResource(R.string.prompt_benchmark_intro),
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    text = stringResource(
                        R.string.prompt_benchmark_suite_stats,
                        cases.size,
                        cases.size * PromptBenchmarkRunner.DEFAULT_REPEATS,
                        PromptBenchmarkRunner.DEFAULT_REPEATS
                    ),
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }

        if (!uiState.modelAvailable) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = stringResource(R.string.prompt_benchmark_model_missing),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    OutlinedButton(onClick = onOpenModels) {
                        Text(text = stringResource(R.string.prompt_benchmark_open_models))
                    }
                }
            }
        }

        if (!uiState.rewriteEnabled) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = stringResource(R.string.prompt_benchmark_rewrite_disabled_warning),
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
                enabled = !runnerState.isRunning && uiState.modelAvailable,
                modifier = Modifier.weight(1f)
            ) {
                Text(text = stringResource(R.string.prompt_benchmark_run_action))
            }

            OutlinedButton(
                onClick = { viewModel.cancelBenchmark() },
                enabled = runnerState.isRunning,
                modifier = Modifier.weight(1f)
            ) {
                Text(text = stringResource(R.string.prompt_benchmark_cancel_action))
            }

            OutlinedButton(
                onClick = { sessionResult?.let { shareResult(it) } },
                enabled = !runnerState.isRunning && sessionResult != null,
                modifier = Modifier.weight(1f)
            ) {
                Text(text = stringResource(R.string.prompt_benchmark_share_action))
            }
        }

        if (runnerState.isRunning) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = stringResource(
                            R.string.prompt_benchmark_progress,
                            runnerState.currentCaseIndex,
                            runnerState.totalCases,
                            runnerState.currentRunIndex,
                            runnerState.repeats
                        ),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    LinearProgressIndicator(
                        progress = { progress },
                        modifier = Modifier.fillMaxWidth()
                    )
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
                item {
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                text = stringResource(R.string.prompt_benchmark_summary_title),
                                style = MaterialTheme.typography.titleMedium
                            )
                            Text(
                                text = stringResource(
                                    R.string.prompt_benchmark_summary_runs,
                                    result.totalCases,
                                    result.totalRuns,
                                    result.totalFailures
                                ),
                                style = MaterialTheme.typography.bodySmall
                            )
                            Text(
                                text = stringResource(
                                    R.string.prompt_benchmark_summary_latency,
                                    result.avgLatencyMs,
                                    result.minLatencyMs,
                                    result.maxLatencyMs
                                ),
                                style = MaterialTheme.typography.bodySmall
                            )
                            Text(
                                text = stringResource(
                                    R.string.prompt_benchmark_summary_consistency,
                                    result.stableCasesCount,
                                    result.totalCases
                                ),
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                }

                items(result.cases, key = { it.caseDef.id }) { caseResult ->
                    PromptBenchmarkCaseCard(caseResult = caseResult)
                }
            }
        }
    }
}

@Composable
private fun PromptBenchmarkCaseCard(caseResult: PromptBenchmarkCaseResult) {
    val caseDef = caseResult.caseDef
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = "${caseDef.id} - ${caseDef.title}",
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(
                    R.string.prompt_benchmark_case_meta,
                    caseDef.category,
                    caseDef.type.name
                ),
                style = MaterialTheme.typography.bodySmall
            )

            when (caseDef.type) {
                PromptBenchmarkCaseType.COMPOSE -> {
                    Text(
                        text = stringResource(R.string.prompt_benchmark_before_label),
                        style = MaterialTheme.typography.labelLarge
                    )
                    Text(
                        text = caseDef.composeInput.orEmpty(),
                        style = MaterialTheme.typography.bodySmall
                    )
                }

                PromptBenchmarkCaseType.EDIT -> {
                    Text(
                        text = stringResource(R.string.prompt_benchmark_before_original_label),
                        style = MaterialTheme.typography.labelLarge
                    )
                    Text(
                        text = caseDef.editOriginal.orEmpty(),
                        style = MaterialTheme.typography.bodySmall
                    )
                    Text(
                        text = stringResource(R.string.prompt_benchmark_before_instruction_label),
                        style = MaterialTheme.typography.labelLarge
                    )
                    Text(
                        text = caseDef.editInstruction.orEmpty(),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }

            caseResult.runs.forEach { run ->
                Text(
                    text = stringResource(R.string.prompt_benchmark_run_title, run.runIndex),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = stringResource(
                        R.string.prompt_benchmark_run_meta,
                        run.latencyMs,
                        run.backend ?: "n/a",
                        if (run.success) "success" else "failure"
                    ),
                    style = MaterialTheme.typography.bodySmall
                )
                if (!run.success) {
                    Text(
                        text = stringResource(
                            R.string.prompt_benchmark_run_error,
                            run.errorType ?: "unknown",
                            run.errorMessage ?: "none"
                        ),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Text(
                    text = run.output ?: stringResource(R.string.prompt_benchmark_run_failed_output),
                    style = MaterialTheme.typography.bodySmall
                )
            }

            Text(
                text = stringResource(
                    R.string.prompt_benchmark_case_summary,
                    caseResult.uniqueOutputsCount,
                    caseResult.avgLatencyMs,
                    caseResult.minLatencyMs,
                    caseResult.maxLatencyMs
                ),
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}
