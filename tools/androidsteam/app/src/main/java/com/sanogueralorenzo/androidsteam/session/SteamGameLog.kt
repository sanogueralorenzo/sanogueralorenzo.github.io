package com.sanogueralorenzo.androidsteam.session

import java.io.File
import java.io.FileNotFoundException
import java.io.RandomAccessFile

/** Only new Steam process events matter; old games are never restored as active. */
internal class SteamGameLog(private val file: File) {
    private var position = file.length()
    private val processes = linkedMapOf<Int, MutableSet<Int>>()
    val activeAppId: Int? get() = processes.keys.lastOrNull()

    fun read(): Int? {
        val stream = try { RandomAccessFile(file, "r") } catch (_: FileNotFoundException) {
            // Steam can remove/replace its log between sessions.
            position = 0; processes.clear(); return null
        }
        stream.use { input ->
            if (input.length() < position) { position = 0; processes.clear() }
            input.seek(position)
            // Consume bounded chunks; a partial line is retried on the next read.
            val end = minOf(input.length(), position + 65_536)
            while (input.filePointer < end) {
                val start = input.filePointer
                val line = input.readLine() ?: break
                input.seek(input.filePointer - 1)
                if (input.read() != '\n'.code) { position = start; break }
                accept(line)
                position = input.filePointer
            }
        }
        return activeAppId
    }

    internal fun accept(line: String) {
        added.find(line)?.let { match ->
            val appId = match.groupValues[1].toIntOrNull() ?: return
            val pid = match.groupValues[2].toIntOrNull() ?: return
            processes.getOrPut(appId) { mutableSetOf() }.add(pid)
        }
        removed.find(line)?.let { match ->
            val appId = match.groupValues[1].toIntOrNull() ?: return
            processes[appId]?.remove(match.groupValues[2].toIntOrNull())
            if (processes[appId]?.isEmpty() == true) processes.remove(appId)
        }
        finished.find(line)?.let { processes.remove(it.groupValues[1].toIntOrNull()) }
    }

    companion object {
        private val added = Regex("AppID (\\d+) adding PID (\\d+) as a tracked process")
        private val removed = Regex("AppID (\\d+) no longer tracking PID (\\d+), exit code")
        private val finished = Regex("Remove (\\d+) from running list")
    }
}
