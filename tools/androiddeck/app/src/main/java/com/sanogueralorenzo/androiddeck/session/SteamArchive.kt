package com.sanogueralorenzo.androiddeck.session

import com.sanogueralorenzo.androiddeck.runtime.checkInstallationCancelled
import java.io.File
import java.nio.file.Files
import org.apache.commons.compress.archivers.zip.ZipFile

/** Valve components merge into a private staging directory, never the user's live Steam tree. */
internal class SteamArchive(directory: File) {
    private val root = directory.canonicalFile.toPath()
    private val files = mutableSetOf<String>()
    private val links = mutableListOf<Pair<java.nio.file.Path, java.nio.file.Path>>()
    private var expanded = 0L

    fun extract(archive: File) {
        ZipFile.builder().setFile(archive).get().use { zip ->
            val entries = zip.entries
            var count = 0
            while (entries.hasMoreElements()) {
                checkInstallationCancelled()
                val entry = entries.nextElement()
                require(entry.method == 0 || entry.method == 8) { "Unsupported Steam ZIP compression." }
                require(++count <= 100_000 && zip.canReadEntryData(entry)) { "Unsupported Steam archive entry." }
                // Valve's archives contain both POSIX and Windows separators.
                val name = entry.name.replace('\\', '/')
                require(!name.startsWith('/') && ':' !in name && name.split('/').none { it == ".." }) { "Unsafe Steam archive path: $name" }
                val path = root.resolve(name).normalize()
                require(path.startsWith(root) && path != root) { "Steam archive path escapes installation." }
                if (entry.isDirectory) { Files.createDirectories(path); continue }
                require(files.add(root.relativize(path).toString())) { "Duplicate Steam file: $name" }
                if (entry.isUnixSymlink) {
                    require(entry.size in 1..4096) { "Steam link exceeds its expected size." }
                    val name = zip.getUnixSymlink(entry).replace('\\', '/')
                    require(!name.startsWith('/') && ':' !in name) { "Unsafe Steam link." }
                    val target = path.parent.resolve(name).normalize()
                    require(target.startsWith(root)) { "Steam link escapes installation." }
                    links += path to target
                    continue
                }
                expanded = Math.addExact(expanded, entry.size)
                require(entry.size >= 0 && expanded <= 2_000_000_000L) { "Steam exceeds its extraction limit." }
                Files.createDirectories(path.parent)
                zip.getInputStream(entry).use { input ->
                    Files.newOutputStream(path).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var written = 0L
                        while (true) {
                            checkInstallationCancelled()
                            val read = input.read(buffer)
                            if (read < 0) break
                            written += read
                            require(written <= entry.size) { "Steam file exceeds its expected size." }
                            output.write(buffer, 0, read)
                        }
                        require(written == entry.size) { "Steam archive is incomplete." }
                    }
                }
                require(path.toFile().setExecutable(entry.unixMode and 0b001001001 != 0, true)) { "Cannot set Steam file permissions." }
            }
        }
    }

    fun finish() {
        // Create links only after all component writes, preventing writes through aliases.
        for ((path, target) in links) {
            checkInstallationCancelled()
            var parent = path.parent
            while (parent != root) {
                require(!Files.isSymbolicLink(parent)) { "Steam link has a symbolic parent." }
                parent = parent.parent
            }
            Files.createDirectories(path.parent)
            Files.createSymbolicLink(path, path.parent.relativize(target))
        }
        for ((_, target) in links) require(target.toFile().canonicalFile.toPath().startsWith(root)) { "Steam link chain escapes installation." }
    }
}
