package com.sanogueralorenzo.androidsteam

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.games.GameLaunchProfile
import com.sanogueralorenzo.androidsteam.games.GameProfiles
import com.sanogueralorenzo.androidsteam.games.SteamAppInfo
import com.sanogueralorenzo.androidsteam.games.SteamSettingsText
import java.io.File
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GameProfileIntegrationTest {
    @Test fun savedProfileProjectsIntoSteamWithoutChangingUnrelatedClientData() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyProfiles") == "true")
        val appId = InstrumentationRegistry.getArguments().getString("profileAppId")?.toIntOrNull()
        require(appId != null && appId > 0) { "Pass the installed baseline game's profileAppId." }
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.filesDir, "home/.local/share/Steam")
        assertTrue(SteamAppInfo.games(File(root, "appcache/appinfo.vdf")).containsKey(appId))
        val client = File(root, "config/config.vdf")
        val local = File(root, "userdata").listFiles().orEmpty().map { File(it, "config/localconfig.vdf") }.filter(File::isFile).single()
        val beforeClient = client.readBytes()
        val beforeLocal = local.readBytes()
        val preferences = context.getSharedPreferences("launch_profiles", android.content.Context.MODE_PRIVATE)
        val key = local.parentFile!!.parentFile!!.name + ":" + appId
        val beforeSaved = preferences.getString(key, null)
        try {
            val original = GameProfiles(context).load(appId)
            val value = "saved profile = 'literal' $" + "(not-executed)"
            val profile = original.copy(environment = original.environment + ("ANDROID_STEAM_PROFILE_TEST" to value))
            GameProfiles(context).save(appId, profile)
            assertEquals(value, GameProfiles(context).load(appId).environment["ANDROID_STEAM_PROFILE_TEST"])
            GameProfiles(context).apply()
            // The baseline already has its explicit tool/config/priority. Its
            // complete unrelated client data must remain byte-for-byte intact.
            assertArrayEquals(beforeClient, client.readBytes())
            val options = SteamSettingsText(local.readText()).get(listOf("UserLocalConfigStore", "Software", "Valve", "Steam", "apps", appId.toString(), "LaunchOptions"))
            val actual = GameLaunchProfile.fromSteam(original.tool, requireNotNull(options))
            assertEquals(original.arguments, actual.arguments)
            assertEquals(value, actual.environment["ANDROID_STEAM_PROFILE_TEST"])
            val applied = local.readBytes()
            GameProfiles(context).apply()
            assertArrayEquals(applied, local.readBytes())
        } finally {
            client.writeBytes(beforeClient)
            local.writeBytes(beforeLocal)
            preferences.edit().putString(key, beforeSaved).commit()
        }
    }
}
