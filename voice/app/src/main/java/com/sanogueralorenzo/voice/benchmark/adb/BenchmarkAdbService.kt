package com.sanogueralorenzo.voice.benchmark.adb

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.di.appGraph
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.benchmark.LiteRtBenchmarkGateway
import com.sanogueralorenzo.voice.benchmark.BenchmarkDatasetParser
import com.sanogueralorenzo.voice.benchmark.BenchmarkReportFormatter
import com.sanogueralorenzo.voice.benchmark.BenchmarkRunner
import com.sanogueralorenzo.voice.benchmark.BenchmarkScoring
import com.sanogueralorenzo.voice.prompt.LiteRtPromptTemplates
import com.sanogueralorenzo.voice.summary.LiteRtRuntimeConfig
import com.sanogueralorenzo.voice.prompt.PromptTemplateStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class BenchmarkAdbService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != BenchmarkAdbContracts.ACTION_RUN) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        startForegroundCompat()

        scope.launch {
            try {
                runBenchmark(intent)
            } catch (error: Throwable) {
                Log.e(TAG, "Unhandled benchmark service error", error)
                writeFatalStatusFromIntent(intent, error)
            } finally {
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun runBenchmark(intent: Intent) {
        val runId = intent.getStringExtra(BenchmarkAdbContracts.EXTRA_RUN_ID)
            ?.trim()
            ?.ifBlank { null }
            ?: "run_${System.currentTimeMillis()}"
        val promptRelPathRaw = intent.getStringExtra(BenchmarkAdbContracts.EXTRA_PROMPT_REL_PATH)
            ?.trim()
            .orEmpty()
        val promptRelPath = if (promptRelPathRaw == BenchmarkAdbContracts.APP_DEFAULT_PROMPT_SENTINEL) {
            ""
        } else {
            promptRelPathRaw
        }
        val datasetRelPath = intent.getStringExtra(BenchmarkAdbContracts.EXTRA_DATASET_REL_PATH)
            ?.trim()
            .orEmpty()
        val outputRelPath = intent.getStringExtra(BenchmarkAdbContracts.EXTRA_OUTPUT_REL_PATH)
            ?.trim()
            ?.ifBlank { null }
            ?: "${BenchmarkAdbContracts.DEFAULT_RESULTS_DIR}/$runId.result.json"

        val request = BenchmarkRunRequest(
            runId = runId,
            promptRelPath = promptRelPath,
            datasetRelPath = datasetRelPath,
            outputRelPath = outputRelPath
        )

        val statusRelPath = "${BenchmarkAdbContracts.DEFAULT_RESULTS_DIR}/$runId.status.json"
        val reportRelPath = "${BenchmarkAdbContracts.DEFAULT_RESULTS_DIR}/$runId.report.txt"
        val statusFile = resolveAppFile(statusRelPath) ?: return
        val resultFile = resolveAppFile(request.outputRelPath)
        val reportFile = resolveAppFile(reportRelPath)

        val startedAt = System.currentTimeMillis()
        writeStatus(
            statusFile = statusFile,
            status = BenchmarkRunStatus(
                runId = runId,
                state = "running",
                updatedAtMs = startedAt,
                startedAtMs = startedAt,
                message = "Starting benchmark run",
                resultRelPath = request.outputRelPath,
                reportRelPath = reportRelPath
            )
        )

        if (!ModelStore.isModelReadyStrict(applicationContext, ModelCatalog.liteRtLm)) {
            writeStatus(
                statusFile = statusFile,
                status = BenchmarkRunStatus(
                    runId = runId,
                    state = "failed",
                    updatedAtMs = System.currentTimeMillis(),
                    startedAtMs = startedAt,
                    error = "LiteRT model is not ready",
                    resultRelPath = request.outputRelPath,
                    reportRelPath = reportRelPath
                )
            )
            return
        }
        if (request.promptRelPath.isBlank() && !PromptTemplateStore(applicationContext).isPromptReady()) {
            writeStatus(
                statusFile = statusFile,
                status = BenchmarkRunStatus(
                    runId = runId,
                    state = "failed",
                    updatedAtMs = System.currentTimeMillis(),
                    startedAtMs = startedAt,
                    error = "Prompt is not ready",
                    resultRelPath = request.outputRelPath,
                    reportRelPath = reportRelPath
                )
            )
            return
        }

        val datasetFile = resolveAppFile(request.datasetRelPath)
        val promptFile = request.promptRelPath.takeIf { it.isNotBlank() }?.let { resolveAppFile(it) }
        if (request.promptRelPath.isNotBlank() && (promptFile == null || !promptFile.exists())) {
            writeStatus(
                statusFile = statusFile,
                status = BenchmarkRunStatus(
                    runId = runId,
                    state = "failed",
                    updatedAtMs = System.currentTimeMillis(),
                    startedAtMs = startedAt,
                    error = "Prompt file not found: ${request.promptRelPath}",
                    resultRelPath = request.outputRelPath,
                    reportRelPath = reportRelPath
                )
            )
            return
        }
        if (datasetFile == null || !datasetFile.exists()) {
            writeStatus(
                statusFile = statusFile,
                status = BenchmarkRunStatus(
                    runId = runId,
                    state = "failed",
                    updatedAtMs = System.currentTimeMillis(),
                    startedAtMs = startedAt,
                    error = "Dataset file not found: ${request.datasetRelPath}",
                    resultRelPath = request.outputRelPath,
                    reportRelPath = reportRelPath
                )
            )
            return
        }
        if (resultFile == null || reportFile == null) {
            writeStatus(
                statusFile = statusFile,
                status = BenchmarkRunStatus(
                    runId = runId,
                    state = "failed",
                    updatedAtMs = System.currentTimeMillis(),
                    startedAtMs = startedAt,
                    error = "Invalid output path",
                    resultRelPath = request.outputRelPath,
                    reportRelPath = reportRelPath
                )
            )
            return
        }

        val promptTemplate = if (promptFile != null) {
            runCatching { promptFile.readText() }.getOrElse { error ->
                writeStatus(
                    statusFile = statusFile,
                    status = BenchmarkRunStatus(
                        runId = runId,
                        state = "failed",
                        updatedAtMs = System.currentTimeMillis(),
                        startedAtMs = startedAt,
                        error = "Failed reading prompt file: ${error.message}",
                        resultRelPath = request.outputRelPath,
                        reportRelPath = reportRelPath
                    )
                )
                return
            }
        } else {
            null
        }

        val datasetCases = runCatching {
            datasetFile.bufferedReader().useLines { lines ->
                lines
                    .map { it.trim() }
                    .filter { it.isNotBlank() && !it.startsWith("#") }
                    .toList()
            }.mapIndexedNotNull { index, line ->
                BenchmarkDatasetParser.parseLineToCase(
                    line = line,
                    fallbackIndex = index + 1
                )
            }
        }.getOrElse { error ->
            writeStatus(
                statusFile = statusFile,
                status = BenchmarkRunStatus(
                    runId = runId,
                    state = "failed",
                    updatedAtMs = System.currentTimeMillis(),
                    startedAtMs = startedAt,
                    error = "Failed parsing dataset: ${error.message}",
                    resultRelPath = request.outputRelPath,
                    reportRelPath = reportRelPath
                )
            )
            return
        }

        if (datasetCases.isEmpty()) {
            writeStatus(
                statusFile = statusFile,
                status = BenchmarkRunStatus(
                    runId = runId,
                    state = "failed",
                    updatedAtMs = System.currentTimeMillis(),
                    startedAtMs = startedAt,
                    error = "Dataset is empty",
                    resultRelPath = request.outputRelPath,
                    reportRelPath = reportRelPath
                )
            )
            return
        }

        val gateway = LiteRtBenchmarkGateway(
            context = applicationContext,
            composePolicy = applicationContext.appGraph().liteRtComposePolicy,
            deterministicComposeRewriter = applicationContext.appGraph().deterministicComposeRewriter,
            composeLlmGate = applicationContext.appGraph().liteRtComposeLlmGate
        )
        val activePromptTemplate = if (promptTemplate.isNullOrBlank()) {
            PromptTemplateStore(applicationContext).currentPromptTemplate()
        } else {
            promptTemplate
        }
        val session = runCatching {
            BenchmarkRunner.runAll(
                gateway = gateway,
                cases = datasetCases,
                suiteVersion = "v1+adb_device",
                repeats = BenchmarkRunner.DEFAULT_REPEATS,
                modelId = ModelCatalog.liteRtLm.id,
                promptInstructionsSnapshot = LiteRtPromptTemplates.benchmarkInstructionSnapshot(
                    rewriteInstructionOverride = activePromptTemplate?.trim()
                ),
                runtimeConfigSnapshot = LiteRtRuntimeConfig.reportSnapshot(),
                composePromptTemplateOverride = promptTemplate,
                onProgress = { progress ->
                    writeStatus(
                        statusFile = statusFile,
                        status = BenchmarkRunStatus(
                            runId = runId,
                            state = "running",
                            updatedAtMs = System.currentTimeMillis(),
                            startedAtMs = startedAt,
                            message = "Running benchmark",
                            progress = progress,
                            resultRelPath = request.outputRelPath,
                            reportRelPath = reportRelPath
                        )
                    )
                }
            )
        }.onFailure { error ->
            Log.e(TAG, "ADB benchmark run failed", error)
        }.getOrNull()
        gateway.release()

        if (session == null) {
            writeStatus(
                statusFile = statusFile,
                status = BenchmarkRunStatus(
                    runId = runId,
                    state = "failed",
                    updatedAtMs = System.currentTimeMillis(),
                    startedAtMs = startedAt,
                    error = "Benchmark execution failed",
                    resultRelPath = request.outputRelPath,
                    reportRelPath = reportRelPath
                )
            )
            return
        }

        reportFile.parentFile?.mkdirs()
        reportFile.writeText(BenchmarkReportFormatter.toPlainText(session))

        val summaryCases = session.cases.map { caseResult ->
            val output = BenchmarkScoring.benchmarkOutputText(caseResult.runs)
            val lastRun = caseResult.runs.lastOrNull()
            JSONObject().apply {
                put("id", caseResult.caseDef.id)
                put("input", caseResult.caseDef.composeInput.orEmpty())
                put("expected", caseResult.caseDef.expectedOutput.orEmpty())
                put("actual", output)
                put("passed", BenchmarkScoring.isCasePassed(caseResult))
                put("success", caseResult.runs.all { it.success })
                put("latency_ms", caseResult.avgLatencyMs)
                put("backend", lastRun?.backend ?: "n/a")
                put("error", lastRun?.errorMessage ?: "")
                put("error_type", lastRun?.errorType ?: "")
            }
        }
        val passCount = session.cases.count { BenchmarkScoring.isCasePassed(it) }
        val failCount = session.totalCases - passCount
        val resultJson = JSONObject().apply {
            put("run_id", runId)
            put("suite_version", session.suiteVersion)
            put("model_id", session.modelId)
            put("timestamp_ms", session.timestampMs)
            put("prompt_file", request.promptRelPath.ifBlank { "(app_default)" })
            put("dataset_file", request.datasetRelPath)
            put("prompt_instructions", session.promptInstructionsSnapshot)
            put("runtime_config", session.runtimeConfigSnapshot)
            put(
                "summary",
                JSONObject().apply {
                    put("total_cases", session.totalCases)
                    put("pass_count", passCount)
                    put("fail_count", failCount)
                    put(
                        "pass_rate",
                        if (session.totalCases > 0) {
                            passCount.toDouble() / session.totalCases.toDouble() * 100.0
                        } else {
                            0.0
                        }
                    )
                    put("total_elapsed_ms", session.totalElapsedMs)
                    put("avg_latency_ms", session.avgLatencyMs)
                }
            )
            put("cases", JSONArray(summaryCases))
        }

        resultFile.parentFile?.mkdirs()
        resultFile.writeText(resultJson.toString(2))

        writeStatus(
            statusFile = statusFile,
            status = BenchmarkRunStatus(
                runId = runId,
                state = "completed",
                updatedAtMs = System.currentTimeMillis(),
                startedAtMs = startedAt,
                message = "Benchmark completed",
                resultRelPath = request.outputRelPath,
                reportRelPath = reportRelPath
            )
        )
    }

    private fun writeStatus(statusFile: File, status: BenchmarkRunStatus) {
        runCatching {
            statusFile.parentFile?.mkdirs()
            statusFile.writeText(status.toJson().toString(2))
        }.onFailure { error ->
            Log.e(TAG, "Failed writing status file: ${statusFile.absolutePath}", error)
        }
    }

    private fun resolveAppFile(relativePath: String): File? {
        val sanitized = relativePath.trim().trimStart('/')
        if (sanitized.isBlank()) return null
        val candidate = File(filesDir, sanitized)
        val filesRoot = filesDir.canonicalFile
        val resolved = candidate.canonicalFile
        return if (
            resolved.path == filesRoot.path ||
            resolved.path.startsWith(filesRoot.path + File.separator)
        ) {
            resolved
        } else {
            null
        }
    }

    private fun writeFatalStatusFromIntent(intent: Intent, error: Throwable) {
        val runId = intent.getStringExtra(BenchmarkAdbContracts.EXTRA_RUN_ID)
            ?.trim()
            ?.ifBlank { null }
            ?: return
        val statusFile = resolveAppFile("${BenchmarkAdbContracts.DEFAULT_RESULTS_DIR}/$runId.status.json")
            ?: return
        writeStatus(
            statusFile = statusFile,
            status = BenchmarkRunStatus(
                runId = runId,
                state = "failed",
                updatedAtMs = System.currentTimeMillis(),
                error = error.message ?: "Unhandled benchmark service error"
            )
        )
    }

    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Benchmark (Debug)",
                NotificationManager.IMPORTANCE_LOW
            )
            manager?.createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Running benchmark")
            .setContentText("Device benchmark is running")
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private companion object {
        private const val TAG = "BenchmarkAdbSvc"
        private const val NOTIFICATION_CHANNEL_ID = "benchmark_debug"
        private const val NOTIFICATION_ID = 12041
    }
}
