package com.sanogueralorenzo.androidsteam.library

import android.content.Context
import android.util.AtomicFile
import com.sanogueralorenzo.androidsteam.SteamApplication
import com.sanogueralorenzo.androidsteam.games.SteamAccount
import com.sanogueralorenzo.androidsteam.games.SteamAppInfo
import com.sanogueralorenzo.androidsteam.games.SteamGameMetadata
import com.sanogueralorenzo.androidsteam.games.SteamSettingsText
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import com.sanogueralorenzo.androidsteam.session.SessionController
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

internal data class LibraryGame(val metadata: SteamGameMetadata, val installed: Boolean,
    val size: Long, val flags: Int, val downloaded: Long, val downloadTotal: Long,
    val lastPlayed: Long?, val playtimeMinutes: Long?, val artwork: File?) {
    val appId get() = metadata.appId
    val name get() = metadata.name
    val pending get() = flags and (2 or 8 or 512 or 1024 or 1_048_576 or 2_097_152) != 0
}

internal data class LibrarySnapshot(val account: String, val checked: Long, val games: List<LibraryGame>)

/** Product metadata + account-scoped live licenses; neither artwork nor files prove ownership. */
internal class SteamLibrary(private val context: Context) {
    private val root = File(context.filesDir, "home/.local/share/Steam")
    private val local get() = SteamAccount(root).localConfig()
    private fun cache(account: String) = File(context.filesDir, "library/$account.json")

    fun read(): LibrarySnapshot {
        val selected = local
        val account = selected.parentFile!!.parentFile!!.name
        val file = cache(account)
        require(file.isFile && file.length() <= 262_144) { "Open Steam and sign in, then refresh your library." }
        val licenses = JSONObject(file.readText())
        require(licenses.getString("account") == account) { "Refresh the library for the selected Steam account." }
        val ids = licenses.getJSONArray("available")
        require(ids.length() <= 10_000)
        val available = (0 until ids.length()).map { ids.getInt(it).also { id -> require(id > 0) } }.toSet()
        val metadata = SteamAppInfo.games(File(root, "appcache/appinfo.vdf"))
        val history = SteamSettingsText(SteamSettingsText.read(selected))
        val hidden = hiddenGames(File(selected.parentFile, "cloudstorage"))
        val games = available.mapNotNull { id ->
            val game = metadata[id] ?: return@mapNotNull null
            if (id in hidden) return@mapNotNull null
            val manifest = File(root, "steamapps/appmanifest_$id.acf").takeIf { it.isFile && it.length() <= 65_536 }
                ?.let { SteamSettingsText(SteamSettingsText.read(it)) }
            fun number(key: String) = manifest?.get(listOf("AppState", key))?.toLongOrNull()?.coerceAtLeast(0) ?: 0
            val flags = number("StateFlags").toInt()
            val installed = flags and 4 != 0
            if (game.visibleOnlyWhenInstalled && !installed) return@mapNotNull null
            val path = listOf("UserLocalConfigStore", "Software", "Valve", "Steam", "apps", id.toString())
            LibraryGame(game, installed, number("SizeOnDisk"), flags, number("BytesDownloaded"), number("BytesToDownload"),
                history.get(path + "LastPlayed")?.toLongOrNull()?.takeIf { it > 0 },
                history.get(path + "Playtime")?.toLongOrNull()?.takeIf { it >= 0 },
                game.artworkPath?.let { File(root, "appcache/librarycache/$id/$it") }
                    ?.takeIf { it.isFile && it.length() <= 4_194_304 })
        }.sortedBy { it.name.lowercase() }
        return LibrarySnapshot(account, licenses.getLong("checked"), games)
    }

    fun refresh(): LibrarySnapshot {
        check((context.applicationContext as SteamApplication).session.state == SessionController.State.Running) {
            "Open Steam and sign in before refreshing the library."
        }
        val account = local.parentFile!!.parentFile!!.name
        val ids = SteamAppInfo.games(File(root, "appcache/appinfo.vdf")).keys
        val directory = File(context.cacheDir, "library").apply { check(isDirectory || mkdirs()) }
        context.assets.open("steam/library.py").use { input -> File(directory, "library.py").outputStream().use { input.copyTo(it) } }
        val components = File(context.filesDir, "session-components")
        val steam = "/root/.local/share/Steam/steamrtarm64"
        val process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/usr/bin/python3", "/run/androidsteam-library/library.py"),
            listOf("${directory.path}:/run/androidsteam-library", "${components.path}:/opt/androidsteam/session",
                "${File(context.cacheDir, "session").path}:/run/androidsteam"),
            mapOf("LD_LIBRARY_PATH" to "$steam:$steam/libs:/opt/androidsteam/session/usr/lib",
                "LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/libdeck-ports.so:/opt/androidsteam/session/usr/lib/libdeck-robust.so"))
        val result = AtomicReference<String?>()
        val readFailure = AtomicReference<Exception?>()
        val reader = Thread({
            try {
                val output = ByteArrayOutputStream()
                process.inputStream.use { input ->
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        check(output.size() + count <= 1_048_576) { "Steam's library query exceeded its output limit." }
                        output.write(buffer, 0, count)
                    }
                }
                val snapshots = output.toString(Charsets.UTF_8).lineSequence().filter { it.startsWith("ANDROIDSTEAM_LIBRARY=") }.toList()
                if (snapshots.size == 1 && snapshots.single().length <= 262_144) result.set(snapshots.single().substringAfter('='))
            } catch (failure: Exception) { readFailure.set(failure) }
        }, "Steam library query").apply { start() }
        try {
            process.outputStream.use { it.write(JSONArray(ids.toList()).toString().toByteArray()) }
            check(process.waitFor(20, TimeUnit.SECONDS)) { "Steam's library query timed out. Reopen Steam, then refresh." }
            reader.join(1_000)
            check(!reader.isAlive && readFailure.get() == null && process.exitValue() == 0 && result.get() != null) {
                "Steam's license query failed. Reconnect in Steam, then refresh the library."
            }
            val text = result.get()!!
            require(JSONObject(text).getString("account") == account) { "The Steam account changed. Reopen the native library and refresh." }
            val file = cache(account).apply { check(parentFile!!.isDirectory || parentFile!!.mkdirs()) }
            val atomic = AtomicFile(file)
            val output = atomic.startWrite()
            try { output.write(text.toByteArray()); atomic.finishWrite(output) }
            catch (failure: Exception) { atomic.failWrite(output); throw failure }
            return read()
        } finally {
            process.destroy()
            try {
                if (!process.waitFor(1, TimeUnit.SECONDS)) { process.destroyForcibly(); process.waitFor(1, TimeUnit.SECONDS) }
                process.inputStream.close()
                reader.join(1_000)
            } catch (_: InterruptedException) {
                process.destroyForcibly()
                Thread.currentThread().interrupt()
            }
        }
    }

    private fun hiddenGames(directory: File): Set<Int> {
        val hidden = mutableSetOf<Int>()
        for (name in listOf("cloud-storage-namespace-1.json", "cloud-storage-namespace-1.modified.json")) {
            val file = File(directory, name)
            if (!file.isFile) continue
            require(file.length() <= 4_194_304) { "Steam's library collections are too large for this app version." }
            val entries = JSONArray(file.readText())
            for (index in 0 until entries.length()) {
                val pair = entries.getJSONArray(index)
                if (pair.getString(0) != "user-collections.hidden") continue
                val entry = pair.getJSONObject(1)
                if (entry.optBoolean("is_deleted")) { hidden.clear(); continue }
                val value = JSONObject(entry.getString("value"))
                for ((key, add) in listOf("added" to true, "removed" to false)) {
                    val ids = value.optJSONArray(key) ?: continue
                    for (position in 0 until ids.length()) {
                        val id = ids.getInt(position)
                        if (add) hidden += id else hidden -= id
                    }
                }
            }
        }
        return hidden
    }
}
