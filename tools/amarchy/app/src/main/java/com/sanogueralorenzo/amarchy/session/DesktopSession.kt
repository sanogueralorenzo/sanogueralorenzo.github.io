package com.sanogueralorenzo.amarchy.session

import android.content.Context
import android.net.ConnectivityManager
import com.sanogueralorenzo.amarchy.runtime.EnvironmentInstaller
import com.sanogueralorenzo.amarchy.runtime.LinuxRuntime
import com.sanogueralorenzo.amarchy.runtime.RuntimeArchive
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
        "WAYLAND_DISPLAY" to "wayland-0", "OMARCHY_PATH" to "/usr/share/omarchy", "PATH" to "/usr/share/omarchy/bin:/usr/bin:/bin",
        "LD_PRELOAD" to "/opt/amarchy/libamarchy-aquamarine.so:/opt/amarchy/libamarchy-software-drm.so",
        "LIBGL_ALWAYS_SOFTWARE" to "1", "MESA_LOADER_DRIVER_OVERRIDE" to "kms_swrast", "GALLIUM_DRIVER" to "llvmpipe",
        "GDK_BACKEND" to "wayland", "QT_QPA_PLATFORM" to "wayland", "GTK_THEME" to "Adwaita:dark")
    private var process: Process? = null
    private var drain: Thread? = null
    private val commandGate = Object()
    private var commandProcess: Process? = null
    private var closing = false

    fun prepare() {
        RuntimeArchive.delete(directory)
        check(directory.mkdirs()) { "Could not create the desktop session. Try again." }
        File(directory, "shm").mkdirs()
        context.assets.open("desktop/hyprland.lua").use { input -> File(directory, "hyprland.lua").outputStream().use { input.copyTo(it) } }
        prepareHome()
        updateResolver()
    }

    fun start() {
        process = linux.start(listOf("/usr/bin/dbus-run-session", "--", "/usr/bin/start-hyprland", "--", "--config", "/run/user/1000/hyprland.lua"), bindings, environment)
        val running = process!!
        // Do not retain arbitrary application output or surface it in UI errors.
        drain = Thread({ try { running.inputStream.use { input ->
            val bytes = ByteArray(8192)
            while (input.read(bytes) >= 0) { }
        } } catch (_: java.io.IOException) { } }, "amarchy-desktop-output").apply { start() }
    }

    fun terminalMapped(): Boolean = try {
        val clients = JSONArray(command(listOf("/usr/bin/hyprctl", "-j", "clients")))
        (0 until clients.length()).any { clients.getJSONObject(it).optString("class") == "foot" }
    } catch (_: Exception) { false }
    val alive get() = process?.isAlive == true
    fun waitForExit(): Int = process!!.waitFor()

    fun command(arguments: List<String>): String {
        val signature = File(directory, "hypr").listFiles()?.singleOrNull { it.isDirectory }?.name
            ?: error("The desktop is still starting.")
        val display = directory.listFiles()?.firstOrNull { it.name.startsWith("wayland-") && it.name != "wayland-0" && !it.name.endsWith(".lock") }?.name
            ?: error("The desktop is still starting.")
        val child = synchronized(commandGate) {
            check(!closing) { "The desktop is closing." }
            linux.start(arguments, bindings, environment + mapOf("HYPRLAND_INSTANCE_SIGNATURE" to signature, "WAYLAND_DISPLAY" to display)).also { commandProcess = it }
        }
        try {
            check(child.waitFor(5, TimeUnit.SECONDS)) { "The desktop took too long to respond." }
            val output = child.inputStream.bufferedReader().readText()
            check(child.exitValue() == 0) { "The desktop could not complete that action." }
            return output
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
        val home = File(context.filesDir, "home")
        val foot = File(home, ".config/foot/foot.ini")
        if (!foot.exists()) {
            foot.parentFile!!.mkdirs()
            foot.writeText("[main]\nfont=JetBrainsMono Nerd Font:size=14\npad=12x12\nterm=xterm-256color\n[colors-dark]\nbackground=2d353b\nforeground=d3c6aa\nregular0=4f585e\nregular1=e67e80\nregular2=a7c080\nregular3=dbbc7f\nregular4=7fbbb3\nregular5=d699b6\nregular6=83c092\nregular7=d3c6aa\n")
        }
        val bashrc = File(home, ".bashrc")
        if (!bashrc.exists()) bashrc.writeText("export PS1='\\[\\e[38;5;108m\\]amarchy\\[\\e[0m\\] \\w \\$ '\nexport EDITOR=nvim\nalias ls='ls --color=auto'\n")
        for (name in listOf("Projects", "Documents", "Downloads")) File(home, name).mkdirs()
    }
}
