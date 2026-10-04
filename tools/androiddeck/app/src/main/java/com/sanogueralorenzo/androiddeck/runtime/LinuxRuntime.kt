package com.sanogueralorenzo.androiddeck.runtime

import android.content.Context
import java.io.File

internal class LinuxRuntime(context: Context, private val root: File) {
    private val files = context.filesDir
    private val native = context.applicationInfo.nativeLibraryDir
    private val temporary = File(context.cacheDir, "proot").apply { mkdirs() }
    private val home = File(files, "home").apply { mkdirs() }

    fun startCheck(): Process {
        val builder = ProcessBuilder(
            "$native/libproot.so", "--kill-on-exit", "-0", "-r", root.path,
            "-b", "/dev", "-b", "/proc", "-b", "/sys", "-b", "${home.path}:/root",
            "-w", "/root", "/usr/bin/dash", "-c",
            "printf 'Linux runtime ready\\n'; /usr/bin/ldd --version; /usr/bin/uname -m"
        ).redirectErrorStream(true)
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
