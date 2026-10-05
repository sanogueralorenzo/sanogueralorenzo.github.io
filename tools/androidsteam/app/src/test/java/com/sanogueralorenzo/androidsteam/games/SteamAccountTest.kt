package com.sanogueralorenzo.androidsteam.games

import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SteamAccountTest {
    @get:Rule val temporary = TemporaryFolder()
    private fun users(text: String): File {
        val root = temporary.newFolder()
        File(root, "config").mkdir()
        File(root, "config/loginusers.vdf").writeText(text)
        return root
    }
    @Test fun soleAndExplicitRecentAccountsUseTheirOwnUserdata() {
        val sole = users("\"users\" { \"76561197960265729\" { \"PersonaName\" \"Account A\" } }")
        assertEquals(File(sole, "userdata/1/config/localconfig.vdf"), SteamAccount(sole).localConfig())
        val recent = users("\"users\" { \"76561197960265729\" {} \"76561197960265730\" { \"MostRecent\" \"1\" } }")
        assertEquals(File(recent, "userdata/2/config/localconfig.vdf"), SteamAccount(recent).localConfig())
    }
    @Test fun ambiguousAccountsAreRejectedInsteadOfLeakingAnotherLibrary() {
        for (flags in listOf("", "\"MostRecent\" \"1\"")) {
            val root = users("\"users\" { \"76561197960265729\" { $flags } \"76561197960265730\" { $flags } }")
            assertThrows(IllegalArgumentException::class.java) { SteamAccount(root).localConfig() }
        }
    }
}
