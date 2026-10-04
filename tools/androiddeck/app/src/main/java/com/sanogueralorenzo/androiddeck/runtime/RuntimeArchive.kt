package com.sanogueralorenzo.androiddeck.runtime

import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.FileVisitResult
import java.nio.file.attribute.BasicFileAttributes
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.archivers.tar.TarConstants

/** Extract into a new private staging directory; publish only after verification. */
internal object RuntimeArchive {
    fun extract(input: InputStream, directory: File, checkCancelled: () -> Unit = {}) {
        val root = directory.canonicalFile.toPath()
        require(Files.isDirectory(root) && directory.list().orEmpty().isEmpty()) { "Extraction needs an empty directory" }
        val links = mutableListOf<Triple<Path, Path, Boolean>>()
        val seen = mutableSetOf<Path>()
        var expanded = 0L
        TarArchiveInputStream(input).use { tar ->
            var count = 0
            while (true) {
                checkCancelled()
                val entry = tar.nextEntry ?: break
                require(++count <= 100_000) { "Runtime contains too many files" }
                val path = resolve(root, entry.name)
                require(seen.add(path)) { "Duplicate runtime entry: ${entry.name}" }
                require(tar.canReadEntryData(entry)) { "Unsupported runtime entry: ${entry.name}" }
                when {
                    entry.isDirectory -> Files.createDirectories(path)
                    entry.linkFlag == TarConstants.LF_NORMAL || entry.linkFlag == TarConstants.LF_OLDNORM -> {
                        expanded = Math.addExact(expanded, entry.size)
                        require(entry.size >= 0 && expanded <= 1_000_000_000L) { "Runtime exceeds extraction limit" }
                        Files.createDirectories(path.parent)
                        Files.newOutputStream(path).use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                checkCancelled()
                                val read = tar.read(buffer)
                                if (read < 0) break
                                output.write(buffer, 0, read)
                            }
                        }
                        require(path.toFile().setExecutable(entry.mode and 0b001001001 != 0, true)) { "Cannot set runtime file permissions" }
                    }
                    entry.isSymbolicLink || entry.isLink -> {
                        val target = if (entry.isLink || entry.linkName.startsWith('/')) {
                            resolve(root, entry.linkName.removePrefix("/"))
                        } else {
                            path.parent.resolve(entry.linkName).normalize().also {
                                require(it.startsWith(root)) { "Runtime link escapes installation" }
                            }
                        }
                        links += Triple(path, target, entry.isLink)
                    }
                    // Linux /dev is bound to Android /dev; creating device nodes would require root.
                    entry.isCharacterDevice && path.parent == root.resolve("dev") -> Unit
                    else -> error("Unsupported runtime file: ${entry.name}")
                }
            }
        }
        // No archive writes can follow a symlink: all links are created after regular files.
        for ((path, target, hard) in links.sortedBy { !it.third }) {
            checkCancelled()
            var parent = path.parent
            while (parent != root) {
                require(!Files.isSymbolicLink(parent)) { "Runtime link has a symbolic parent" }
                parent = parent.parent
            }
            Files.createDirectories(path.parent)
            if (hard) {
                require(Files.isRegularFile(target, NOFOLLOW_LINKS)) { "Invalid runtime hard link" }
            }
            // Android app storage forbids hard links. A contained symbolic alias
            // preserves shared content without copying each multicall executable.
            val relative = path.parent.relativize(target)
            Files.createSymbolicLink(path, if (relative.toString().isEmpty()) Path.of(".") else relative)
        }
        for ((_, target, _) in links) {
            require(target.toFile().canonicalFile.toPath().startsWith(root)) { "Runtime link chain escapes installation: ${root.relativize(target)}" }
        }
    }

    fun delete(directory: File) {
        if (!Files.exists(directory.toPath(), NOFOLLOW_LINKS)) return
        Files.walkFileTree(directory.toPath(), object : SimpleFileVisitor<Path>() {
            override fun visitFile(file: Path, attributes: BasicFileAttributes): FileVisitResult {
                Files.delete(file)
                return FileVisitResult.CONTINUE
            }
            override fun postVisitDirectory(dir: Path, error: java.io.IOException?): FileVisitResult {
                if (error != null) throw error
                Files.delete(dir)
                return FileVisitResult.CONTINUE
            }
        })
    }

    private fun resolve(root: Path, name: String): Path {
        require(!name.startsWith('/') && name.split('/').none { it == ".." }) { "Unsafe runtime path: $name" }
        return root.resolve(name).normalize().also { require(it.startsWith(root)) { "Runtime path escapes installation" } }
    }
}
