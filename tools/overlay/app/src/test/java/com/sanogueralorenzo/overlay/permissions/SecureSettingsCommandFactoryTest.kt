package com.sanogueralorenzo.overlay.permissions

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SecureSettingsCommandFactoryTest {
    private val packageName = "com.example.overlay"
    private val commands = SecureSettingsCommandFactory.create(packageName)

    @Test
    fun macCommandDownloadsDarwinToolsAndGrantsPermission() {
        assertTrue(commands.mac.contains("platform-tools-latest-darwin.zip"))
        assertTrue(commands.mac.contains("platform-tools/adb"))
        assertGrantCommand(commands.mac)
        assertFalse(commands.mac.contains("platform-tools-latest-linux.zip"))
        assertFalse(commands.mac.contains("platform-tools-latest-windows.zip"))
    }

    @Test
    fun linuxCommandDownloadsLinuxToolsAndGrantsPermission() {
        assertTrue(commands.linux.contains("platform-tools-latest-linux.zip"))
        assertTrue(commands.linux.contains("platform-tools/adb"))
        assertGrantCommand(commands.linux)
        assertFalse(commands.linux.contains("platform-tools-latest-darwin.zip"))
        assertFalse(commands.linux.contains("platform-tools-latest-windows.zip"))
    }

    @Test
    fun windowsCommandDownloadsWindowsToolsAndGrantsPermission() {
        assertTrue(commands.windows.contains("platform-tools-latest-windows.zip"))
        assertTrue(commands.windows.contains("platform-tools\\adb.exe"))
        assertGrantCommand(commands.windows)
        assertFalse(commands.windows.contains("platform-tools-latest-darwin.zip"))
        assertFalse(commands.windows.contains("platform-tools-latest-linux.zip"))
    }

    private fun assertGrantCommand(command: String) {
        assertTrue(
            command.contains(
                "shell pm grant $packageName android.permission.WRITE_SECURE_SETTINGS"
            )
        )
    }
}
