package com.sanogueralorenzo.voice.setup.benchmark

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.setup.LiteRtPromptBenchmarkGateway
import com.sanogueralorenzo.voice.setup.PromptBenchmarkDatasetParser
import com.sanogueralorenzo.voice.setup.PromptBenchmarkReportFormatter
import com.sanogueralorenzo.voice.setup.PromptBenchmarkRunner
import com.sanogueralorenzo.voice.setup.PromptBenchmarkScoring
import com.sanogueralorenzo.voice.summary.LiteRtPromptTemplates
import com.sanogueralorenzo.voice.summary.LiteRtRuntimeConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class PromptBenchmarkAdbService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != PromptBenchmarkAdbContracts.ACTION_RUN) {
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
        val runId = intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_RUN_ID)
            ?.trim()
            ?.ifBlank { null }
            ?: "run_${System.currentTimeMillis()}"
        val promptRelPath = intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_PROMPT_REL_PATH)
            ?.trim()
            .orEmpty()
        val datasetRelPath = intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_DATASET_REL_PATH)
            ?.trim()
            .orEmpty()
        val outputRelPath = intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_OUTPUT_REL_PATH)
            ?.trim()
            ?.ifBlank { null }
            ?: "${PromptBenchmarkAdbContracts.DEFAULT_RESULTS_DIR}/$runId.result.json"

        val request = PromptBenchmarkRunRequest(
            runId = runId,
            promptRelPath = promptRelPath,
            datasetRelPath = datasetRelPath,
            outputRelPath = outputRelPath
        )

        val statusRelPath = "${PromptBenchmarkAdbContracts.DEFAULT_RESULTS_DIR}/$runId.status.json"
        val reportRelPath = "${PromptBenchmarkAdbContracts.DEFAULT_RESULTS_DIR}/$runId.report.txt"
        val statusFile = resolveAppFile(statusRelPath) ?: return
        val resultFile = resolveAppFile(request.outputRelPath)
        val reportFile = resolveAppFile(reportRelPath)

        val startedAt = System.currentTimeMillis()
        writeStatus(
            statusFile = statusFile,
            status = PromptBenchmarkRunStatus(
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
                status = PromptBenchmarkRunStatus(
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

        val promptFile = resolveAppFile(request.promptRelPath)
        val datasetFile = resolveAppFile(request.datasetRelPath)
        if (promptFile == null || !promptFile.exists()) {
            writeStatus(
                statusFile = statusFile,
                status = PromptBenchmarkRunStatus(
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
                status = PromptBenchmarkRunStatus(
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
                status = PromptBenchmarkRunStatus(
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

        val promptTemplate = runCatching { promptFile.readText() }.getOrElse { error ->
            writeStatus(
                statusFile = statusFile,
                status = PromptBenchmarkRunStatus(
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

        val datasetCases = runCatching {
            datasetFile.bufferedReader().useLines { lines ->
                lines
                    .map { it.trim() }
                    .filter { it.isNotBlank() && !it.startsWith("#") }
                    .toList()
            }.mapIndexedNotNull { index, line ->
                PromptBenchmarkDatasetParser.parseLineToCase(
                    line = line,
                    fallbackIndex = index + 1
                )
            }
        }.getOrElse { error ->
            writeStatus(
                statusFile = statusFile,
                status = PromptBenchmarkRunStatus(
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
                status = PromptBenchmarkRunStatus(
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

        val gateway = LiteRtPromptBenchmarkGateway(applicationContext)
        val session = runCatching {
            PromptBenchmarkRunner.runAll(
                gateway = gateway,
                cases = datasetCases,
                suiteVersion = "v1+adb_device",
                repeats = PromptBenchmarkRunner.DEFAULT_REPEATS,
                modelId = ModelCatalog.liteRtLm.id,
                promptInstructionsSnapshot = LiteRtPromptTemplates.benchmarkInstructionSnapshot(
                    rewriteInstructionOverride = promptTemplate.trim()
                ),
                runtimeConfigSnapshot = LiteRtRuntimeConfig.reportSnapshot(),
                composePromptTemplateOverride = promptTemplate,
                onProgress = { progress ->
                    writeStatus(
                        statusFile = statusFile,
                        status = PromptBenchmarkRunStatus(
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
                status = PromptBenchmarkRunStatus(
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
        reportFile.writeText(PromptBenchmarkReportFormatter.toPlainText(session))

        val summaryCases = session.cases.map { caseResult ->
            val output = PromptBenchmarkScoring.benchmarkOutputText(caseResult.runs)
            val lastRun = caseResult.runs.lastOrNull()
            JSONObject().apply {
                put("id", caseResult.caseDef.id)
                put("input", caseResult.caseDef.composeInput.orEmpty())
                put("expected", caseResult.caseDef.expectedOutput.orEmpty())
                put("actual", output)
                put("passed", PromptBenchmarkScoring.isCasePassed(caseResult))
                put("success", caseResult.runs.all { it.success })
                put("latency_ms", caseResult.avgLatencyMs)
                put("backend", lastRun?.backend ?: "n/a")
                put("error", lastRun?.errorMessage ?: "")
                put("error_type", lastRun?.errorType ?: "")
            }
        }
        val passCount = session.cases.count { PromptBenchmarkScoring.isCasePassed(it) }
        val failCount = session.totalCases - passCount
        val resultJson = JSONObject().apply {
            put("run_id", runId)
            put("suite_version", session.suiteVersion)
            put("model_id", session.modelId)
            put("timestamp_ms", session.timestampMs)
            put("prompt_file", request.promptRelPath)
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
            status = PromptBenchmarkRunStatus(
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

    private fun writeStatus(statusFile: File, status: PromptBenchmarkRunStatus) {
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
        val runId = intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_RUN_ID)
            ?.trim()
            ?.ifBlank { null }
            ?: return
        val statusFile = resolveAppFile("${PromptBenchmarkAdbContracts.DEFAULT_RESULTS_DIR}/$runId.status.json")
            ?: return
        writeStatus(
            statusFile = statusFile,
            status = PromptBenchmarkRunStatus(
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
                "Prompt Benchmark (Debug)",
                NotificationManager.IMPORTANCE_LOW
            )
            manager?.createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Running prompt benchmark")
            .setContentText("Device benchmark is running")
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private companion object {
        private const val TAG = "PromptBenchmarkAdbSvc"
        private const val NOTIFICATION_CHANNEL_ID = "prompt_benchmark_debug"
        private const val NOTIFICATION_ID = 12041
    }
}
