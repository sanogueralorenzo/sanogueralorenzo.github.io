package com.sanogueralorenzo.androidsteam.session

import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SteamGameLogTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun oldGamesAreIgnoredAndEachTrackedProcessMustExit() {
        val file = temporary.newFile("gameprocess_log.txt")
        file.writeText("AppID 100 adding PID 1 as a tracked process\n")
        val log = SteamGameLog(file)
        assertNull(log.read())
        file.appendText("AppID 200 adding PID 2 as a tracked process\nAppID 200 adding PID 3 as a tracked process\n")
        assertEquals(200, log.read())
        file.appendText("AppID 200 no longer tracking PID 3, exit code -1\n")
        assertEquals(200, log.read())
        file.appendText("AppID 200 no longer tracking PID 2, exit code 0\n")
        assertNull(log.read())
    }

    @Test fun partialLinesWaitAndTruncatedLogClearsStaleGames() {
        val file = temporary.newFile("gameprocess_log.txt")
        val log = SteamGameLog(file)
        file.appendText("AppID 200 adding PID 2 as a tracked process")
        assertNull(log.read())
        file.appendText("\r\n")
        assertEquals(200, log.read())
        file.writeText("new session\n")
        assertNull(log.read())
        file.appendText("AppID 300 adding PID 3 as a tracked process\nRemove 300 from running list\n")
        assertNull(log.read())
    }

    @Test fun onlyTheNewClientsModeEventAllowsColdLaunchDelivery() {
        val file = temporary.newFile("gameprocess_log.txt")
        file.writeText("SSGL: UI mode (0->4)\n")
        val log = SteamGameLog(file)
        log.read()
        assertFalse(log.clientReady)
        file.appendText("SSGL: UI mode (0->4)\n")
        log.read()
        assertTrue(log.clientReady)
        file.writeText("new log\n")
        log.read()
        assertFalse(log.clientReady)
    }
}
