package com.sanogueralorenzo.amarchy.session

import android.content.Context
import android.net.ConnectivityManager
import com.sanogueralorenzo.amarchy.runtime.EnvironmentInstaller
import com.sanogueralorenzo.amarchy.runtime.LinuxRuntime
import com.sanogueralorenzo.amarchy.runtime.RuntimeArchive
import com.sanogueralorenzo.amarchy.runtime.ProcessOutput
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.json.JSONArray

/** The one pinned Linux session; Android owns display, lifetime and hardware. */
internal class DesktopSession(private val context: Context) {
    val directory = File(context.cacheDir, "s")
    val socket get() = File(directory, "wayland-0")
    private val linux get() = LinuxRuntime(context, EnvironmentInstaller(context).root, 1000)
    private val bindings get() = listOf("${directory.path}:/run/user/1000", "${directory.path}/shm:/dev/shm", "${context.applicationInfo.nativeLibraryDir}:/opt/amarchy")
    private val environment = mapOf(
        "XDG_RUNTIME_DIR" to "/run/user/1000", "XDG_CURRENT_DESKTOP" to "Hyprland", "XDG_SESSION_TYPE" to "wayland",
        "WAYLAND_DISPLAY" to "wayland-0", "OMARCHY_PATH" to "/usr/share/omarchy", "PATH" to "/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin",
        "TZ" to java.util.TimeZone.getDefault().id,
        "LD_PRELOAD" to "/opt/amarchy/libamarchy-aquamarine.so:/opt/amarchy/libamarchy-software-drm.so",
        "LIBGL_ALWAYS_SOFTWARE" to "1", "MESA_LOADER_DRIVER_OVERRIDE" to "kms_swrast", "GALLIUM_DRIVER" to "llvmpipe",
        "GDK_BACKEND" to "wayland", "QT_QPA_PLATFORM" to "wayland", "QSG_RHI_BACKEND" to "opengl")
    private var process: Process? = null
    private var drain: Thread? = null
    private val commandGate = Object()
    private var commandProcess: Process? = null
    private var closing = false

    fun prepare() {
        RuntimeArchive.delete(directory)
        check(directory.mkdirs()) { "Could not create the desktop session. Try again." }
        File(directory, "shm").mkdirs()
        for (name in listOf("hyprland.lua", "start.sh", "prepare.sh", "platform.py")) context.assets.open("desktop/$name").use { input -> File(directory, name).outputStream().use { input.copyTo(it) } }
        prepareHome()
        updateResolver()
    }

    fun start() {
        process = linux.start(listOf("/usr/bin/dbus-run-session", "--", "/bin/bash", "/run/user/1000/start.sh"), bindings, environment)
        val running = process!!
        // Do not retain arbitrary application output or surface it in UI errors.
        drain = Thread({ try { running.inputStream.use { input ->
            val bytes = ByteArray(8192)
            while (input.read(bytes) >= 0) { }
        } } catch (_: java.io.IOException) { } }, "amarchy-desktop-output").apply { start() }
    }

    fun ready(): Boolean = try {
        val clients = JSONArray(command(listOf("/usr/bin/hyprctl", "-j", "clients")))
        (0 until clients.length()).any { clients.getJSONObject(it).optString("class") == "foot" } &&
            command(listOf("/usr/share/omarchy/bin/omarchy-shell", "shell", "ping")).trim() == "ok"
    } catch (_: Exception) { false }
    val alive get() = process?.isAlive == true
    fun waitForExit(): Int = process!!.waitFor()

    fun command(arguments: List<String>, timeoutSeconds: Long = 5): String {
        val signature = File(directory, "hypr").listFiles()?.singleOrNull { it.isDirectory }?.name
            ?: error("The desktop is still starting.")
        val display = directory.listFiles()?.firstOrNull { it.name.startsWith("wayland-") && it.name != "wayland-0" && !it.name.endsWith(".lock") }?.name
            ?: error("The desktop is still starting.")
        val child = synchronized(commandGate) {
            check(!closing) { "The desktop is closing." }
            linux.start(arguments, bindings, environment + mapOf("HYPRLAND_INSTANCE_SIGNATURE" to signature, "WAYLAND_DISPLAY" to display)).also { commandProcess = it }
        }
        val output = ProcessOutput(child, 2_000_000)
        try {
            check(child.waitFor(timeoutSeconds, TimeUnit.SECONDS)) { "The desktop took too long to respond." }
            val text = output.text()
            check(child.exitValue() == 0) { "The desktop could not complete that action." }
            return text
        } finally {
            if (child.isAlive) { child.destroyForcibly(); child.waitFor(5, TimeUnit.SECONDS) }
            synchronized(commandGate) { if (commandProcess === child) commandProcess = null }
        }
    }

    fun close() {
        val command = synchronized(commandGate) { closing = true; commandProcess }
        if (command?.isAlive == true) { command.destroyForcibly(); command.waitFor(5, TimeUnit.SECONDS) }
        val running = process
        if (running?.isAlive == true) { running.destroy(); if (!running.waitFor(3, TimeUnit.SECONDS)) { running.destroyForcibly(); running.waitFor(5, TimeUnit.SECONDS) } }
        drain?.join(1000); process = null; drain = null
    }

    private fun updateResolver() {
        val network = context.getSystemService(ConnectivityManager::class.java)
        val servers = network.activeNetwork?.let { network.getLinkProperties(it)?.dnsServers }.orEmpty()
        if (servers.isEmpty()) return
        val resolver = File(EnvironmentInstaller(context).root, "etc/resolv.conf")
        Files.deleteIfExists(resolver.toPath())
        resolver.writeText(servers.joinToString("") { "nameserver ${it.hostAddress}\n" } + "options timeout:2 attempts:2\n")
    }

    private fun prepareHome() {
        val root = EnvironmentInstaller(context).root
        val passwd = File(root, "etc/passwd")
        if (!passwd.readText().lineSequence().any { it.startsWith("amarchy:") }) passwd.appendText("amarchy:x:1000:1000:Amarchy:/root:/bin/bash\n")
        val group = File(root, "etc/group")
        if (!group.readText().lineSequence().any { it.startsWith("amarchy:") }) group.appendText("amarchy:x:1000:\n")
    }
}
