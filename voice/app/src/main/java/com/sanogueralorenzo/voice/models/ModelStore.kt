package com.sanogueralorenzo.voice.models

import android.content.Context
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * Resolves model files from either app-internal storage or bundled assets and verifies integrity.
 *
 * Integrity checks use: expected size -> hash marker/cache -> optional strict hash computation.
 */
object ModelStore {
    private const val HASH_MARKER_SUFFIX = ".sha256"
    private val verifyLock = Any()
    private val verifiedCache = HashMap<String, CacheEntry>()

    private data class CacheEntry(
        val expectedHash: String,
        val sizeBytes: Long,
        val lastModified: Long
    )

    fun modelFile(context: Context, spec: ModelSpec): File {
        return File(context.filesDir, "models/${spec.subdir}/${spec.fileName}")
    }

    fun isModelReady(context: Context, spec: ModelSpec): Boolean {
        val target = modelFile(context, spec)
        if (target.exists()) {
            return isOnDiskModelReadyQuick(target, spec)
        }
        return assetExists(context, spec)
    }

    fun isModelReadyStrict(context: Context, spec: ModelSpec): Boolean {
        val target = modelFile(context, spec)
        if (target.exists()) {
            return isOnDiskModelValid(target, spec, strictHash = true)
        }
        return assetExists(context, spec)
    }

    fun isModelPresent(context: Context, spec: ModelSpec): Boolean {
        val target = modelFile(context, spec)
        if (target.exists()) return true
        return assetExists(context, spec)
    }

    fun ensureModelFile(context: Context, spec: ModelSpec): File? {
        val target = modelFile(context, spec)
        if (target.exists()) {
            if (isOnDiskModelValid(target, spec, strictHash = true)) {
                return target
            }
            deleteModelAndMarkers(target)
        }
        if (!assetExists(context, spec)) return null
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, "${target.name}.asset_tmp")
        return try {
            context.assets.open("${spec.subdir}/${spec.fileName}").use { input ->
                temp.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            if (!isOnDiskModelValid(temp, spec, strictHash = true)) {
                temp.delete()
                return null
            }
            if (target.exists()) {
                target.delete()
            }
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }
            target
        } catch (e: Exception) {
            temp.delete()
            null
        }
    }

    internal fun markModelVerified(target: File, spec: ModelSpec) {
        if (!target.exists()) return
        if (spec.sizeBytes > 0L && target.length() != spec.sizeBytes) return
        if (spec.sha256.isBlank()) return
        val hash = spec.sha256.trim().lowercase()
        writeHashMarker(target, hash)
        cacheVerified(target, hash)
    }

    private fun assetExists(context: Context, spec: ModelSpec): Boolean {
        return try {
            context.assets.list(spec.subdir)?.contains(spec.fileName) == true
        } catch (e: Exception) {
            false
        }
    }

    private fun isOnDiskModelValid(target: File, spec: ModelSpec, strictHash: Boolean): Boolean {
        if (!target.exists()) return false
        val actualSize = target.length()
        if (spec.sizeBytes > 0L && actualSize != spec.sizeBytes) {
            clearVerifiedCache(target)
            return false
        }
        if (spec.sha256.isBlank()) return true

        val expected = spec.sha256.lowercase()
        if (isCachedVerified(target, expected)) {
            return true
        }
        val markerValue = hashMarkerFile(target).takeIf { it.exists() }?.readText()?.trim()?.lowercase()
        if (markerValue == expected) {
            cacheVerified(target, expected)
            return true
        }
        if (!strictHash) {
            return true
        }

        synchronized(verifyLock) {
            val markerAfterLock = hashMarkerFile(target).takeIf { it.exists() }?.readText()?.trim()?.lowercase()
            if (markerAfterLock == expected) {
                cacheVerified(target, expected)
                return true
            }
            val actual = sha256(target)?.lowercase() ?: return false
            if (actual != expected) {
                clearVerifiedCache(target)
                return false
            }
            writeHashMarker(target, expected)
            cacheVerified(target, expected)
            return true
        }
    }

    private fun isOnDiskModelReadyQuick(target: File, spec: ModelSpec): Boolean {
        if (!target.exists()) return false
        val actualSize = target.length()
        if (spec.sizeBytes > 0L && actualSize != spec.sizeBytes) {
            clearVerifiedCache(target)
            return false
        }
        if (spec.sha256.isBlank()) return true
        val expected = spec.sha256.lowercase()
        if (isCachedVerified(target, expected)) {
            return true
        }
        val markerValue = hashMarkerFile(target).takeIf { it.exists() }?.readText()?.trim()?.lowercase()
        if (markerValue == expected) {
            cacheVerified(target, expected)
            return true
        }
        return false
    }

    private fun deleteModelAndMarkers(target: File) {
        target.delete()
        hashMarkerFile(target).delete()
        clearVerifiedCache(target)
    }

    private fun hashMarkerFile(target: File): File {
        return File(target.parentFile, "${target.name}$HASH_MARKER_SUFFIX")
    }

    private fun writeHashMarker(target: File, hash: String) {
        runCatching {
            hashMarkerFile(target).writeText(hash.trim().lowercase())
        }
    }

    private fun sha256(file: File): String? {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    digest.update(buffer, 0, read)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            null
        }
    }

    private fun isCachedVerified(target: File, expectedHash: String): Boolean {
        val key = target.absolutePath
        val cached = synchronized(verifyLock) { verifiedCache[key] } ?: return false
        if (cached.expectedHash != expectedHash) return false
        if (cached.sizeBytes != target.length()) return false
        if (cached.lastModified != target.lastModified()) return false
        return true
    }

    private fun cacheVerified(target: File, expectedHash: String) {
        synchronized(verifyLock) {
            verifiedCache[target.absolutePath] = CacheEntry(
                expectedHash = expectedHash,
                sizeBytes = target.length(),
                lastModified = target.lastModified()
            )
        }
    }

    private fun clearVerifiedCache(target: File) {
        synchronized(verifyLock) {
            verifiedCache.remove(target.absolutePath)
        }
    }
}
