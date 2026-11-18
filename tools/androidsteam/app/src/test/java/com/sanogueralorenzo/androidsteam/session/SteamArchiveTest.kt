package com.sanogueralorenzo.androidsteam.session

import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import java.nio.file.Files
import java.io.File
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream
import org.junit.Assert.*
import org.junit.Test

class SteamArchiveTest {
    @Test fun mergesComponentsAndNormalizesWindowsSeparators() = withDirectory { directory ->
        val root = File(directory, "root").apply { mkdir() }
        val extractor = SteamArchive(root)
        extractor.extract(archive(directory, "one.zip", "steamrtarm64\\steam", 493))
        extractor.extract(archive(directory, "two.zip", "resource/label", 420))
        assertEquals("content", File(root, "steamrtarm64/steam").readText())
        assertTrue(File(root, "steamrtarm64/steam").canExecute())
        assertFalse(File(root, "resource/label").canExecute())
    }

    @Test fun rejectsBothTraversalSeparatorsAndAbsolutePaths() = withDirectory { directory ->
        for (name in listOf("../escape", "..\\escape", "/absolute", "C:\\absolute")) {
            val root = Files.createTempDirectory(directory.toPath(), "root").toFile()
            assertThrows(IllegalArgumentException::class.java) { SteamArchive(root).extract(archive(directory, "bad.zip", name, 420)) }
        }
        assertFalse(File(directory, "escape").exists())
    }

    @Test fun defersLinksAndRejectsEscapingTargets() = withDirectory { directory ->
        val root = File(directory, "root").apply { mkdir() }
        val extractor = SteamArchive(root)
        extractor.extract(archive(directory, "link.zip", "alias", 40960 + 511))
        assertFalse(File(root, "alias").exists())
        extractor.extract(archive(directory, "file.zip", "content", 420))
        extractor.finish()
        assertEquals("content", File(root, "alias").readText())
        assertThrows(IllegalArgumentException::class.java) {
            SteamArchive(root).extract(archive(directory, "escape.zip", "escape", 40960 + 511, "../../outside"))
        }
    }

    @Test fun rejectsCollidingComponentFiles() = withDirectory { directory ->
        val root = File(directory, "root").apply { mkdir() }
        val extractor = SteamArchive(root)
        extractor.extract(archive(directory, "one.zip", "folder\\same", 420))
        assertThrows(IllegalArgumentException::class.java) { extractor.extract(archive(directory, "two.zip", "folder/same", 420)) }
        assertEquals("content", File(root, "folder/same").readText())
    }

    private fun archive(directory: File, filename: String, name: String, mode: Int, content: String = "content"): File = File(directory, filename).also { file ->
        ZipArchiveOutputStream(file).use { zip ->
            zip.putArchiveEntry(ZipArchiveEntry(name).apply { unixMode = mode })
            zip.write(content.toByteArray())
            zip.closeArchiveEntry()
        }
    }

    private fun withDirectory(test: (File) -> Unit) {
        val directory = Files.createTempDirectory("androidsteam-steam").toFile()
        try { test(directory) } finally { RuntimeArchive.delete(directory) }
    }
}
