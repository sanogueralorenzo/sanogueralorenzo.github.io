package com.sanogueralorenzo.androidsteam.runtime

import android.content.Context
import java.io.File

internal class LinuxRuntime(context: Context, private val root: File) {
    private val files = context.filesDir
    private val native = context.applicationInfo.nativeLibraryDir
    private val temporary = File(context.cacheDir, "proot").apply { mkdirs() }
    private val home = File(files, "home").apply { mkdirs() }

    fun startCheck(): Process = start(listOf("/usr/bin/dash", "-c",
        "printf 'Linux runtime ready\\n'; /usr/bin/ldd --version; /usr/bin/uname -m"))

    fun start(command: List<String>, bindings: List<String> = emptyList(), environment: Map<String, String> = emptyMap()): Process {
        val arguments = mutableListOf(
            "$native/libproot.so", "--kill-on-exit", "--sysvipc", "-0", "-r", root.path,
            "-b", "/dev", "-b", "/proc", "-b", "/sys", "-b", "${home.path}:/root",
            "-w", "/root"
        )
        bindings.forEach { arguments += listOf("-b", it) }
        // Linux library settings must reach the guest, not Android's PRoot linker.
        if (environment.isNotEmpty()) {
            arguments += "/usr/bin/env"
            arguments += environment.map { (key, value) -> "$key=$value" }
        }
        val builder = ProcessBuilder(arguments + command).redirectErrorStream(true)
        builder.environment().apply {
            clear()
            put("PROOT_LOADER", "$native/libproot-loader.so")
            put("PROOT_TMP_DIR", temporary.path)
            put("HOME", "/root")
            put("PATH", "/usr/bin:/bin")
            put("LANG", "C.UTF-8")
        }
        return builder.start()
    }
}
