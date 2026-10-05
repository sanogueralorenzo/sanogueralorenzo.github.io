package com.sanogueralorenzo.androidsteam.games

import java.io.File

/** Select the same private Steam account for profiles and the native library. */
internal class SteamAccount(private val root: File) {
    fun localConfig(): File {
        val users = File(root, "config/loginusers.vdf")
        if (users.isFile) {
            val settings = SteamSettingsText(SteamSettingsText.read(users))
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

}
