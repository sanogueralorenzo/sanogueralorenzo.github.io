package com.sanogueralorenzo.androidsteam.login

import org.junit.Assert.*
import org.junit.Test

class SteamSignInLinkTest {
    @Test fun acceptsSteamChallengeAndRejectsExternalOrMalformedTargets() {
        assertTrue(SteamSignInLink.valid("https://s.team/q/1/12345678901234567890"))
        for (url in listOf("http://s.team/q/1/123", "https://s.team.evil/q/1/123", "https://s.team@evil/q/1/123",
            "https://s.team/q/1/123?next=evil", "https://s.team/q/1/123#evil", "https://s.team/a/1/123",
            "https://s.team/q/1/", "https://s.team/q/1/123456789012345678901", "https://s.team/q/1/123\n"))
            assertFalse(SteamSignInLink.valid(url))
    }
}
