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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import com.sanogueralorenzo.voice.summary.LiteRtPromptTemplates
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

@Composable
fun PromptBenchmarkingScreen(
    onOpenModels: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val appContext = remember(context) { context.applicationContext }
    val scope = rememberCoroutineScope()
    val settingsStore = remember(appContext) { VoiceSettingsStore(appContext) }
    val gateway = remember(appContext) { LiteRtPromptBenchmarkGateway(appContext) }
    val cases = remember { PromptBenchmarkSuite.defaultCases() }

    DisposableEffect(gateway) {
        onDispose {
            gateway.release()
        }
    }

    var runnerState by remember {
        mutableStateOf(
            PromptBenchmarkRunnerState(
                isRunning = false,
                currentCaseIndex = 0,
                totalCases = cases.size,
                currentRunIndex = 0,
                repeats = PromptBenchmarkRunner.DEFAULT_REPEATS,
                errorMessage = null
            )
        )
    }
    var sessionResult by remember { mutableStateOf<PromptBenchmarkSessionResult?>(null) }
    var runJob by remember { mutableStateOf<Job?>(null) }

    val modelAvailable = remember {
        mutableStateOf(ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm))
    }
    val rewriteEnabled = remember {
        mutableStateOf(settingsStore.isLiteRtRewriteEnabled())
    }

    fun runBenchmark() {
        if (runnerState.isRunning || !modelAvailable.value) return
        sessionResult = null
        runnerState = runnerState.copy(
            isRunning = true,
            currentCaseIndex = 0,
            currentRunIndex = 0,
            errorMessage = null
        )

        val customInstructions = settingsStore.customInstructions()
        val instructionSnapshot = LiteRtPromptTemplates.benchmarkInstructionSnapshot(customInstructions)

        runJob = scope.launch {
            try {
                val result = PromptBenchmarkRunner.runAll(
                    gateway = gateway,
                    cases = cases,
                    suiteVersion = PromptBenchmarkSuite.SUITE_VERSION,
                    repeats = PromptBenchmarkRunner.DEFAULT_REPEATS,
                    modelId = ModelCatalog.liteRtLm.id,
                    customInstructions = customInstructions,
                    promptInstructionsSnapshot = instructionSnapshot,
                    onProgress = { progress ->
                        runnerState = runnerState.copy(
                            currentCaseIndex = progress.caseIndex,
                            totalCases = progress.totalCases,
                            currentRunIndex = progress.runIndex,
                            repeats = progress.repeats,
                            errorMessage = null
                        )
                    }
                )
                sessionResult = result
                runnerState = runnerState.copy(isRunning = false)
            } catch (_: CancellationException) {
                runnerState = runnerState.copy(
                    isRunning = false,
                    errorMessage = context.getString(R.string.prompt_benchmark_status_cancelled)
                )
            } catch (t: Throwable) {
                runnerState = runnerState.copy(
                    isRunning = false,
                    errorMessage = t.message ?: context.getString(R.string.prompt_benchmark_status_failed)
                )
            }
        }
    }

    fun cancelBenchmark() {
        runJob?.cancel()
        runJob = null
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

    val totalRuns = cases.size * PromptBenchmarkRunner.DEFAULT_REPEATS
    val completedRuns = if (runnerState.currentCaseIndex <= 0 || runnerState.currentRunIndex <= 0) {
        0
    } else {
        ((runnerState.currentCaseIndex - 1) * PromptBenchmarkRunner.DEFAULT_REPEATS) + runnerState.currentRunIndex
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
                        totalRuns,
                        PromptBenchmarkRunner.DEFAULT_REPEATS
                    ),
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }

        if (!modelAvailable.value) {
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

        if (!rewriteEnabled.value) {
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
                onClick = { runBenchmark() },
                enabled = !runnerState.isRunning && modelAvailable.value,
                modifier = Modifier.weight(1f)
            ) {
                Text(text = stringResource(R.string.prompt_benchmark_run_action))
            }

            OutlinedButton(
                onClick = { cancelBenchmark() },
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
