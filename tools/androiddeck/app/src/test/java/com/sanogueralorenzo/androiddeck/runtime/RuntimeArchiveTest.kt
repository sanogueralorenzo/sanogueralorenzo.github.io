package com.sanogueralorenzo.androiddeck.runtime

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream
import org.apache.commons.compress.archivers.tar.TarConstants
import org.junit.Assert.*
import org.junit.Test

class RuntimeArchiveTest {
    @Test fun extractsFilesAndGuestAbsoluteLinks() = withDirectory { root ->
        RuntimeArchive.extract(archive(
            entry("usr/bin/program", "hello".toByteArray()).also { it.first.mode = 493 },
            link("bin", "/usr/bin")
        ), root)
        assertEquals("hello", root.resolve("bin/program").readText())
        assertTrue(root.resolve("bin/program").canExecute())
        assertEquals("usr/bin", Files.readSymbolicLink(root.resolve("bin").toPath()).toString())
    }

    @Test fun rejectsTraversalBeforeWritingOutside() = withDirectory { root ->
        assertThrows(IllegalArgumentException::class.java) {
            RuntimeArchive.extract(archive(entry("../escape", byteArrayOf(1))), root)
        }
        assertFalse(requireNotNull(root.parentFile).resolve("escape").exists())
    }

    @Test fun rejectsAbsoluteArchivePaths() = withDirectory { root ->
        val item = TarArchiveEntry("/absolute", true).apply { size = 0 }
        assertThrows(IllegalArgumentException::class.java) { RuntimeArchive.extract(archive(item to byteArrayOf()), root) }
    }

    @Test fun rejectsEscapingLinks() = withDirectory { root ->
        assertThrows(IllegalArgumentException::class.java) { RuntimeArchive.extract(archive(link("escape", "../../outside")), root) }
    }

    @Test fun rejectsWritingThroughArchiveLinks() = withDirectory { root ->
        assertThrows(Exception::class.java) { RuntimeArchive.extract(archive(link("alias", "folder"), link("alias/child", "../other")), root) }
    }

    @Test fun rejectsDuplicateEntries() = withDirectory { root ->
        assertThrows(IllegalArgumentException::class.java) { RuntimeArchive.extract(archive(entry("same", byteArrayOf()), entry("same", byteArrayOf())), root) }
    }

    @Test fun representsHardLinksWithoutDuplicatingContent() = withDirectory { root ->
        val hard = TarArchiveEntry("copy", TarConstants.LF_LINK).apply { linkName = "original" }
        RuntimeArchive.extract(archive(entry("original", "content".toByteArray()), hard to byteArrayOf()), root)
        assertEquals("content", root.resolve("copy").readText())
        assertTrue(Files.isSymbolicLink(root.resolve("copy").toPath()))
        assertTrue(Files.isSameFile(root.resolve("copy").toPath(), root.resolve("original").toPath()))
    }

    @Test fun cleanupNeverFollowsLinks() = withDirectory { root ->
        val outside = Files.createTempDirectory("androiddeck-preserved").toFile()
        try {
            outside.resolve("user-data").writeText("preserve")
            Files.createSymbolicLink(root.resolve("link").toPath(), outside.toPath())
            RuntimeArchive.delete(root)
            assertEquals("preserve", outside.resolve("user-data").readText())
        } finally { RuntimeArchive.delete(outside) }
    }

    private fun entry(name: String, bytes: ByteArray) = TarArchiveEntry(name).apply { size = bytes.size.toLong() } to bytes
    private fun link(name: String, target: String) = TarArchiveEntry(name, TarConstants.LF_SYMLINK).apply { linkName = target } to byteArrayOf()
    private fun archive(vararg entries: Pair<TarArchiveEntry, ByteArray>): ByteArrayInputStream {
        val output = ByteArrayOutputStream()
        TarArchiveOutputStream(output).use { tar ->
            for ((entry, data) in entries) { tar.putArchiveEntry(entry); tar.write(data); tar.closeArchiveEntry() }
        }
        return ByteArrayInputStream(output.toByteArray())
    }
    private fun withDirectory(test: (java.io.File) -> Unit) {
        val directory = Files.createTempDirectory("androiddeck-extraction").toFile()
        try { test(directory) } finally { RuntimeArchive.delete(directory) }
    }
}
