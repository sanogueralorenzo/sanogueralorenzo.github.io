package com.sanogueralorenzo.androidsteam.games

import android.content.Context
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** Saved projections into Steam's own settings, applied before the client starts. */
internal class GameProfiles(context: Context) {
    private val root = File(context.filesDir, "home/.local/share/Steam")
    private val preferences = context.getSharedPreferences("launch_profiles", Context.MODE_PRIVATE)
    private val client = File(root, "config/config.vdf")

    fun load(appId: Int): GameLaunchProfile {
        require(appId > 0)
        val local = localConfig()
        return preferences.getString(key(local, appId), null)?.let(::decode) ?: GameLaunchProfile.fromSteam(
            SteamSettingsText(read(client)).get(compatPath(appId) + "name"),
            SteamSettingsText(read(local)).get(optionsPath(appId)).orEmpty())
    }

    fun save(appId: Int, profile: GameLaunchProfile) {
        require(appId > 0)
        val data = JSONObject().put("tool", profile.tool ?: JSONObject.NULL)
            .put("arguments", JSONArray(profile.arguments)).put("environment", JSONObject(profile.environment))
        check(preferences.edit().putString(key(localConfig(), appId), data.toString()).commit()) { "Cannot save game settings." }
    }

    fun apply() {
        if (preferences.all.isEmpty()) return
        val local = selectedLocalConfig()
        val prefix = local.parentFile!!.parentFile!!.name + ":"
        val saved = preferences.all.filterKeys { it.startsWith(prefix) }
        if (saved.isEmpty()) return
        var clientText = read(client)
        var localText = read(local)
        saved.forEach { (key, value) ->
            val appId = key.removePrefix(prefix).toInt()
            val profile = decode(value as String)
            if (profile.tool == null) clientText = SteamSettingsText(clientText).put(compatPath(appId), null)
            else for ((name, setting) in listOf("name" to profile.tool, "config" to "", "priority" to "250"))
                clientText = SteamSettingsText(clientText).put(compatPath(appId) + name, setting)
            localText = SteamSettingsText(localText).put(optionsPath(appId), profile.launchOptions())
        }
        // Saved profiles remain authoritative if startup is interrupted between
        // these atomic file replacements; the next attempt reapplies both.
        write(client, clientText)
        write(local, localText)
    }

    private fun localConfig(): File {
        val file = selectedLocalConfig()
        require(file.isFile) { "Sign in to Steam before editing game settings." }
        return file
    }

    private fun selectedLocalConfig(): File {
        val users = File(root, "config/loginusers.vdf")
        if (users.isFile) {
            val settings = SteamSettingsText(read(users))
            val accounts = settings.keys(listOf("users"))
            val recent = accounts.filter { settings.get(listOf("users", it, "MostRecent")) == "1" }
            // This ARM64 client omits MostRecent when only one account is saved.
            val selected = if (recent.isEmpty()) accounts.singleOrNull() else recent.singleOrNull()
            require(selected != null) { "Open Steam and select an account before editing game settings." }
            val steamId = selected.toLongOrNull()
            require(steamId != null && steamId > 0) { "Steam's selected account is invalid. Sign in again." }
            return File(root, "userdata/${steamId and 0xffff_ffffL}/config/localconfig.vdf")
        }
        val files = File(root, "userdata").listFiles().orEmpty().filter { it.name.all(Char::isDigit) }
            .map { File(it, "config/localconfig.vdf") }.filter(File::isFile)
        require(files.size == 1) { "Sign in to Steam before editing game settings." }
        return files.single()
    }

    private fun key(local: File, appId: Int) = local.parentFile!!.parentFile!!.name + ":" + appId
    private fun compatPath(appId: Int) = listOf("InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping", appId.toString())
    private fun optionsPath(appId: Int) = listOf("UserLocalConfigStore", "Software", "Valve", "Steam", "apps", appId.toString(), "LaunchOptions")
    private fun read(file: File): String {
        require(file.isFile && file.length() <= 4 * 1024 * 1024) { "Open Steam to prepare its game settings, then retry." }
        return Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(file.readBytes())).toString()
    }

    private fun write(file: File, text: String) {
        if (file.readText() == text) return
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(text.toByteArray()); atomic.finishWrite(stream) }
        catch (failure: Exception) { atomic.failWrite(stream); throw failure }
    }

    private fun decode(text: String): GameLaunchProfile {
        val data = JSONObject(text)
        val arguments = data.getJSONArray("arguments")
        val environment = data.getJSONObject("environment")
        return GameLaunchProfile(if (data.isNull("tool")) null else data.getString("tool"),
            List(arguments.length()) { arguments.getString(it) }, environment.keys().asSequence().associateWith(environment::getString))
    }
}
