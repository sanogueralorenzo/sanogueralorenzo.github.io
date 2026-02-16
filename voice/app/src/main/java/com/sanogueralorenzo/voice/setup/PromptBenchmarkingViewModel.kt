package com.sanogueralorenzo.voice.setup

import android.content.Context
import com.airbnb.mvrx.Async
import com.airbnb.mvrx.Fail
import com.airbnb.mvrx.Loading
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.Uninitialized
import com.airbnb.mvrx.withState
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import com.sanogueralorenzo.voice.summary.LiteRtPromptTemplates
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext

data class PromptBenchmarkingUiState(
    val modelAvailable: Boolean = false,
    val rewriteEnabled: Boolean = false,
    val runnerState: PromptBenchmarkRunnerState = PromptBenchmarkRunnerState(
        isRunning = false,
        phase = PromptBenchmarkRunPhase.IDLE,
        currentCaseIndex = 0,
        totalCases = 0,
        currentRunIndex = 0,
        repeats = PromptBenchmarkRunner.DEFAULT_REPEATS,
        errorMessage = null
    ),
    val sessionResult: PromptBenchmarkSessionResult? = null,
    val benchmarkRunAsync: Async<PromptBenchmarkSessionResult> = Uninitialized,
    val prerequisitesAsync: Async<BenchmarkPrerequisites> = Uninitialized
) : MavericksState

data class BenchmarkPrerequisites(
    val modelAvailable: Boolean,
    val rewriteEnabled: Boolean
)

class PromptBenchmarkingViewModel(
    initialState: PromptBenchmarkingUiState,
    private val appContext: Context,
    private val settingsStore: VoiceSettingsStore,
    private val gateway: PromptBenchmarkGateway
) : MavericksViewModel<PromptBenchmarkingUiState>(initialState) {
    private var runJob: Job? = null

    init {
        refreshPrerequisites()
    }

    fun refreshPrerequisites() {
        suspend {
            val modelAvailable = withContext(Dispatchers.IO) {
                ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm)
            }
            BenchmarkPrerequisites(
                modelAvailable = modelAvailable,
                rewriteEnabled = settingsStore.isLiteRtRewriteEnabled()
            )
        }.execute { async ->
            when (async) {
                is Success -> copy(
                    prerequisitesAsync = async,
                    modelAvailable = async().modelAvailable,
                    rewriteEnabled = async().rewriteEnabled
                )

                else -> copy(prerequisitesAsync = async)
            }
        }
    }

    fun runBenchmark() {
        val canRun = withState(this) { state ->
            !state.runnerState.isRunning && state.modelAvailable
        }
        if (!canRun) return

        val instructionSnapshot = LiteRtPromptTemplates.benchmarkInstructionSnapshot()

        setState {
            copy(
                sessionResult = null,
                runnerState = runnerState.copy(
                    isRunning = true,
                    phase = PromptBenchmarkRunPhase.DOWNLOADING_DATASET,
                    currentCaseIndex = 0,
                    totalCases = 0,
                    currentRunIndex = 0,
                    errorMessage = null
                )
            )
        }

        runJob = suspend {
            val downloadedCases = PromptBenchmarkDatasetLoader.loadCases()
            setState {
                copy(
                    runnerState = runnerState.copy(
                        phase = PromptBenchmarkRunPhase.RUNNING,
                        totalCases = downloadedCases.size,
                        currentCaseIndex = 0,
                        currentRunIndex = 0,
                        repeats = PromptBenchmarkRunner.DEFAULT_REPEATS,
                        errorMessage = null
                    )
                )
            }
            PromptBenchmarkRunner.runAll(
                gateway = gateway,
                cases = downloadedCases,
                suiteVersion = "${PromptBenchmarkSuite.SUITE_VERSION}+remote_dataset",
                repeats = PromptBenchmarkRunner.DEFAULT_REPEATS,
                modelId = ModelCatalog.liteRtLm.id,
                promptInstructionsSnapshot = instructionSnapshot,
                onProgress = { progress ->
                    setState {
                        copy(
                            runnerState = runnerState.copy(
                                phase = PromptBenchmarkRunPhase.RUNNING,
                                currentCaseIndex = progress.caseIndex,
                                totalCases = progress.totalCases,
                                currentRunIndex = progress.runIndex,
                                repeats = progress.repeats,
                                errorMessage = null
                            )
                        )
                    }
                }
            )
        }.execute { async ->
            when (async) {
                is Loading -> copy(
                    benchmarkRunAsync = async,
                    runnerState = runnerState.copy(
                        isRunning = true,
                        phase = if (runnerState.phase == PromptBenchmarkRunPhase.IDLE) {
                            PromptBenchmarkRunPhase.DOWNLOADING_DATASET
                        } else {
                            runnerState.phase
                        },
                        errorMessage = null
                    )
                )

                is Success -> copy(
                    benchmarkRunAsync = async,
                    sessionResult = async(),
                    runnerState = runnerState.copy(
                        isRunning = false,
                        phase = PromptBenchmarkRunPhase.COMPLETED,
                        totalCases = async().totalCases,
                        currentCaseIndex = async().totalCases,
                        errorMessage = null
                    )
                )

                is Fail -> {
                    val message = if (async.error is CancellationException) {
                        appContext.getString(R.string.prompt_benchmark_status_cancelled)
                    } else {
                        async.error.message ?: appContext.getString(R.string.prompt_benchmark_status_failed)
                    }
                    copy(
                        benchmarkRunAsync = async,
                        runnerState = runnerState.copy(
                            isRunning = false,
                            phase = if (async.error is CancellationException) {
                                PromptBenchmarkRunPhase.IDLE
                            } else {
                                PromptBenchmarkRunPhase.ERROR
                            },
                            errorMessage = message
                        )
                    )
                }

                is Uninitialized -> copy(benchmarkRunAsync = async)
            }
        }
    }

    fun cancelBenchmark() {
        runJob?.cancel()
    }
}
