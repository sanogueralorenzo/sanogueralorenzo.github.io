package com.sanogueralorenzo.androidsteam.games

import org.junit.Assert.*
import org.junit.Test

class GameLaunchProfileTest {
    @Test fun quotedArgumentsAndEnvironmentRoundTripWithoutEvaluatingCommands() {
        val args = listOf("-screen-width", "1280", "two words", "O'Brien", "", "$(echo x)", "`literal`")
        val environment = mapOf("PROFILE_TEST" to "some='quoted'\nvalue=$" + "(echo x)")
        val profile = GameLaunchProfile("androidsteam-proton", args, environment)
        assertEquals(args, GameLaunchProfile.words(GameLaunchProfile.argumentText(args)))
        assertEquals(profile, GameLaunchProfile.fromSteam(profile.tool, profile.launchOptions()))
        assertEquals(listOf("C:\\Games\\Folder"), GameLaunchProfile.words("\"C:\\Games\\Folder\""))
    }

    @Test fun malformedAndBackendOverridesFailExplicitly() {
        assertThrows(IllegalArgumentException::class.java) { GameLaunchProfile.words("'unfinished") }
        assertThrows(IllegalArgumentException::class.java) { GameLaunchProfile(null, listOf("%command%"), emptyMap()) }
        assertThrows(IllegalArgumentException::class.java) { GameLaunchProfile(null, emptyList(), mapOf("LD_PRELOAD" to "other")) }
        assertThrows(IllegalArgumentException::class.java) { GameLaunchProfile.environment("KEY=value\nKEY=other") }
        assertThrows(IllegalArgumentException::class.java) { GameLaunchProfile.fromSteam(null, "custom-wrapper %command%") }
    }
}
