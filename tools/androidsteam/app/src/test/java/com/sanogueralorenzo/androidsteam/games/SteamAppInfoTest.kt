package com.sanogueralorenzo.androidsteam.games

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SteamAppInfoTest {
    @get:Rule val temporary = TemporaryFolder()
    private val keys = listOf("appinfo", "common", "type", "name", "oslist", "header_image", "english", "extended", "VisibleOnlyWhenInstalled")
    private fun integer(value: Int) = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(value).array()
    private fun text(value: String) = value.toByteArray() + byteArrayOf(0)
    private fun record(appId: Int, type: String, artwork: String = "header.jpg", visible: Boolean = false): ByteArray {
        val payload = ByteArrayOutputStream().apply {
            write(0); write(integer(0)); write(0); write(integer(1))
            for ((key, value) in listOf(2 to type, 3 to "Title $appId", 4 to "Windows,Linux")) {
                write(1); write(integer(key)); write(text(value))
            }
            write(0); write(integer(5)); write(1); write(integer(6)); write(text(artwork)); write(8)
            write(8)
            write(0); write(integer(7)); write(2); write(integer(8)); write(integer(if (visible) 1 else 0)); write(8)
            write(byteArrayOf(8, 8))
        }.toByteArray()
        return integer(appId) + integer(60 + payload.size) + ByteArray(60) + payload
    }

    @Test fun cachedProductTypesExcludeToolsAndDlcWithoutAnIdBlacklist() {
        val records = record(111, "Game", "0123456789012345678901234567890123456789/header.jpg", true) + record(222, "Tool") + record(333, "DLC") + integer(0)
        val offset = 16 + records.size
        val header = ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN).putInt(0x07564429).putInt(1).putLong(offset.toLong()).array()
        val table = integer(keys.size) + keys.fold(byteArrayOf()) { bytes, key -> bytes + text(key) }
        val file = temporary.newFile("appinfo.vdf").apply { writeBytes(header + records + table) }
        val games = SteamAppInfo.games(file)
        assertEquals(setOf(111), games.keys)
        assertEquals("Title 111", games.getValue(111).name)
        assertEquals(setOf("windows", "linux"), games.getValue(111).platforms)
        assertTrue(games.getValue(111).visibleOnlyWhenInstalled)
        assertEquals("0123456789012345678901234567890123456789/header.jpg", games.getValue(111).artworkPath)
    }

    @Test fun incompleteAndUnknownCachesFailInsteadOfInventingGames() {
        val file = temporary.newFile("appinfo.vdf").apply { writeBytes(ByteArray(16)) }
        assertThrows(IllegalArgumentException::class.java) { SteamAppInfo.games(file) }
        file.writeBytes(ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN).putInt(0x07564429).putInt(1).putLong(32).array())
        assertThrows(IllegalArgumentException::class.java) { SteamAppInfo.games(file) }
    }
}
