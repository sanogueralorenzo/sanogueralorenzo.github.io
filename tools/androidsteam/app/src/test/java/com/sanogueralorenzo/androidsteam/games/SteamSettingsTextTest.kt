package com.sanogueralorenzo.androidsteam.games

import org.junit.Assert.*
import org.junit.Test

class SteamSettingsTextTest {
    @Test fun selectedEditPreservesUnrelatedOpaqueFieldsExactly() {
        val before = "// Steam's file\n\"root\" { \"opaque\" \"unusual\\q\nraw text\" \"apps\" { \"100\" { \"LaunchOptions\" \"old\" } } }"
        val path = listOf("ROOT", "apps", "100", "LaunchOptions")
        val value = "--name \"two words\" C:\\Games\\test"
        val after = SteamSettingsText(before).put(path, value)
        assertEquals(before.substringBefore("\"old\"") + "\"--name \\\"two words\\\" C:\\\\Games\\\\test\"" + before.substringAfter("\"old\""), after)
        assertEquals(value, SteamSettingsText(after).get(path))
    }

    @Test fun missingNestedFieldsAreInsertedAndOverrideRemovalPreservesOtherGames() {
        var text = "\"root\" { \"apps\" { \"100\" { \"name\" \"existing\" } } }"
        val path = listOf("root", "apps", "200", "name")
        text = SteamSettingsText(text).put(path, "tool")
        text = SteamSettingsText(text).put(listOf("root", "apps", "200", "priority"), "250")
        assertEquals("tool", SteamSettingsText(text).get(path))
        assertEquals("250", SteamSettingsText(text).get(listOf("root", "apps", "200", "priority")))
        text = SteamSettingsText(text).put(listOf("root", "apps", "200"), null)
        assertNull(SteamSettingsText(text).get(path))
        assertEquals("existing", SteamSettingsText(text).get(listOf("root", "apps", "100", "name")))
    }

    @Test fun incompleteSettingsFailWithoutReturningAPartialEdit() {
        assertThrows(IllegalArgumentException::class.java) { SteamSettingsText("\"root\" { \"a\" \"value\"") }
        assertThrows(IllegalStateException::class.java) { SteamSettingsText("\"root\" { \"a\" \"unfinished") }
    }
}
