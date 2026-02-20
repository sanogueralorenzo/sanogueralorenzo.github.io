package com.sanogueralorenzo.voice.prompt

import android.content.Context
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import org.json.JSONObject

class PromptTemplateStore(context: Context) {
    data class PromptTemplate(
        val version: String,
        val prompt: String
    )

    sealed interface DownloadResult {
        data class Success(val version: String) : DownloadResult
        data class AlreadyAvailable(val version: String) : DownloadResult
        data class HttpError(val code: Int) : DownloadResult
        data class NetworkError(val reason: String? = null) : DownloadResult
        data class InvalidPayload(val reason: String? = null) : DownloadResult
        data class StorageError(val reason: String? = null) : DownloadResult
        data class UnknownError(val reason: String? = null) : DownloadResult
    }

    sealed interface UpdateCheck {
        data object UpToDate : UpdateCheck
        data object UpdateAvailable : UpdateCheck
        data object Unreachable : UpdateCheck
    }

    private val appContext = context.applicationContext
    private val readinessVersion = MutableStateFlow(0)

    fun observePromptReady(): Flow<Boolean> {
        return readinessVersion
            .map { isPromptReady() }
            .distinctUntilChanged()
            .flowOn(Dispatchers.IO)
    }

    fun isPromptReady(): Boolean {
        return readLocalTemplate() != null
    }

    fun currentPromptVersion(): String? {
        return readLocalTemplate()?.version
    }

    fun currentPromptTemplate(): String? {
        return readLocalTemplate()?.prompt
    }

    suspend fun ensurePromptDownloaded(force: Boolean = false): DownloadResult = withContext(Dispatchers.IO) {
        val local = readLocalTemplate()
        if (!force && local != null) {
            return@withContext DownloadResult.AlreadyAvailable(local.version)
        }
        val remote = when (val result = fetchRemoteTemplateResult()) {
            is FetchRemoteResult.Success -> result.payload
            is FetchRemoteResult.HttpError -> return@withContext DownloadResult.HttpError(result.code)
            is FetchRemoteResult.NetworkError -> return@withContext DownloadResult.NetworkError(result.reason)
            is FetchRemoteResult.InvalidPayload -> return@withContext DownloadResult.InvalidPayload(result.reason)
            is FetchRemoteResult.UnknownError -> return@withContext DownloadResult.UnknownError(result.reason)
        }
        writeLocalPayload(remote.rawJson)?.let { error ->
            return@withContext error
        }
        val stored = readLocalTemplate()
        if (stored == null) {
            return@withContext DownloadResult.StorageError("failed to persist prompt config")
        }
        notifyPromptChanged()
        DownloadResult.Success(stored.version)
    }

    suspend fun checkForUpdates(): UpdateCheck = withContext(Dispatchers.IO) {
        val local = readLocalTemplate()
        val remote = when (val result = fetchRemoteTemplateResult()) {
            is FetchRemoteResult.Success -> result.payload
            else -> return@withContext UpdateCheck.Unreachable
        }
        if (local == null) return@withContext UpdateCheck.UpdateAvailable
        val changed = local.version != remote.template.version || local.prompt != remote.template.prompt
        if (changed) UpdateCheck.UpdateAvailable else UpdateCheck.UpToDate
    }

    private data class RemoteTemplatePayload(
        val template: PromptTemplate,
        val rawJson: String
    )

    private sealed class FetchRemoteResult {
        data class Success(val payload: RemoteTemplatePayload) : FetchRemoteResult()
        data class HttpError(val code: Int) : FetchRemoteResult()
        data class NetworkError(val reason: String? = null) : FetchRemoteResult()
        data class InvalidPayload(val reason: String? = null) : FetchRemoteResult()
        data class UnknownError(val reason: String? = null) : FetchRemoteResult()
    }

    private fun fetchRemoteTemplateResult(): FetchRemoteResult {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(SOURCE_RAW_URL).openConnection() as HttpURLConnection).apply {
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
            }
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK) {
                return FetchRemoteResult.HttpError(code)
            }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val parsed = parseTemplate(body) ?: return FetchRemoteResult.InvalidPayload("invalid prompt json")
            FetchRemoteResult.Success(RemoteTemplatePayload(parsed, body))
        } catch (error: UnknownHostException) {
            FetchRemoteResult.NetworkError(error.message)
        } catch (error: SocketTimeoutException) {
            FetchRemoteResult.NetworkError(error.message)
        } catch (error: IOException) {
            FetchRemoteResult.NetworkError(error.message)
        } catch (error: Exception) {
            FetchRemoteResult.UnknownError(error.message)
        } finally {
            connection?.disconnect()
        }
    }

    private fun writeLocalPayload(payload: String): DownloadResult? {
        val target = promptConfigFile()
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, "${target.name}.tmp")
        return try {
            temp.writeText(payload)
            if (target.exists() && !target.delete()) {
                temp.delete()
                return DownloadResult.StorageError("failed deleting old prompt")
            }
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }
            null
        } catch (error: IOException) {
            temp.delete()
            DownloadResult.StorageError(error.message)
        } catch (error: SecurityException) {
            temp.delete()
            DownloadResult.StorageError(error.message)
        } catch (error: Exception) {
            temp.delete()
            DownloadResult.UnknownError(error.message)
        }
    }

    private fun readLocalTemplate(): PromptTemplate? {
        val file = promptConfigFile()
        if (!file.exists()) return null
        return runCatching {
            val body = file.readText()
            parseTemplate(body)
        }.getOrNull()
    }

    private fun parseTemplate(raw: String): PromptTemplate? {
        return runCatching {
            val json = JSONObject(raw)
            val version = json.optString("version").trim()
            val prompt = json.optString("prompt").trim()
            if (version.isBlank() || prompt.isBlank()) return null
            Instant.parse(version)
            PromptTemplate(
                version = version,
                prompt = prompt
            )
        }.getOrNull()
    }

    private fun promptConfigFile(): File {
        return File(appContext.filesDir, PROMPT_RELATIVE_PATH)
    }

    private fun notifyPromptChanged() {
        readinessVersion.value = readinessVersion.value + 1
    }

    companion object {
        const val SOURCE_BLOB_URL: String =
            "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/blob/main/voice/scripts/prompt_a.json"
        const val SOURCE_RAW_URL: String =
            "https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/voice/scripts/prompt_a.json"
        private const val PROMPT_RELATIVE_PATH = "prompts/prompt_a.json"
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 20_000
    }
}
