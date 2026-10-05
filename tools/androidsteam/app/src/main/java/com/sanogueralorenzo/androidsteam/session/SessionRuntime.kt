package com.sanogueralorenzo.androidsteam.session

import android.content.Context
import android.net.ConnectivityManager
import com.sanogueralorenzo.androidsteam.display.GraphicsInstaller
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import java.io.File

/** The fixed Linux environment shared by the real Steam session and its rendering check. */
internal class SessionRuntime(private val context: Context, val directory: File) {
    val socket = File(directory, "wayland-0")
    private val components = SessionComponents(context)
    private val graphics = GraphicsInstaller(context)

    private fun bindings(): List<String> {
        check(directory.isDirectory || directory.mkdirs()) { "Cannot prepare the Steam session directory." }
        check(File(directory, "ports").isDirectory || File(directory, "ports").mkdirs()) { "Cannot prepare Steam browser connections." }
        val sharedMemory = File(directory, "shm").apply { mkdirs() }
        return listOf("${components.root.path}:/opt/androidsteam/session", "${graphics.root.path}:/opt/androidsteam/graphics",
            "${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app", "${directory.path}:/run/androidsteam",
            "${sharedMemory.path}:/dev/shm",
            "${components.root.path}/usr/bin/steam-socket-peer:/usr/bin/lsof") + GpuDevice.bindings(File(directory, "gpu"))
    }

    fun start(command: List<String>, width: Int, height: Int): Process =
        LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/usr/bin/gamescope", "--backend", "sdl", "--expose-wayland",
                "-W", width.toString(), "-H", height.toString(), "--") + command, bindings(), environment)

    fun steamCommand(): List<String> {
        com.sanogueralorenzo.androidsteam.login.SteamClientBridge.prepare(directory)
        val network = context.getSystemService(ConnectivityManager::class.java)
        val servers = network.activeNetwork?.let { network.getLinkProperties(it)?.dnsServers }.orEmpty()
        check(servers.isNotEmpty()) { "Connect to a network with DNS, then start Steam again." }
        // Supply Android’s current DNS servers to the private Linux
        // runtime configuration, preserving the separately stored user home.
        val resolver = File(RuntimeInstaller(context).root, "etc/resolv.conf")
        java.nio.file.Files.deleteIfExists(resolver.toPath())
        resolver.writeText(servers.joinToString("") { "nameserver ${it.hostAddress}\n" } + "options timeout:2 attempts:2\n")
        // Steam replaces LD_LIBRARY_PATH when launching games. Register the
        // installed host libraries with glibc so its overlay can still load.
        val libraries = File(RuntimeInstaller(context).root, "etc/ld.so.conf.d/androidsteam.conf")
        val paths = "# ${SessionComponents.VERSION}\n/opt/androidsteam/session/usr/lib\n/usr/lib/pulseaudio\n"
        if (!libraries.isFile || libraries.readText() != paths) libraries.writeText(paths)
        context.assets.open("steam/launch.sh").use { input ->
            File(directory, "steam-launch.sh").outputStream().use { input.copyTo(it) }
        }
        return listOf("/usr/bin/env", "STEAM_RUNTIME=1",
            "SDL_VIDEODRIVER=x11",
            "LD_PRELOAD=/opt/androidsteam/session/usr/lib/libsteam-ui-pipe.so:/opt/androidsteam/session/usr/lib/libdeck-ports.so:/opt/androidsteam/session/usr/lib/libdeck-robust.so:${environment.getValue("LD_PRELOAD")}",
            "LD_LIBRARY_PATH=$STEAM/steamrtarm64:$STEAM/steamrtarm64/libs:${environment.getValue("LD_LIBRARY_PATH")}",
            "/bin/sh", "/run/androidsteam/steam-launch.sh", "$STEAM/steamrtarm64/steam", "-gamepadui", "-clientbeta", "steamdeck_stable",
            "-overridepackageurl", "https://client-update.akamai.steamstatic.com") +
            if (SteamInstaller(context).protonInstalled) emptyList() else listOf("steam://install/4427310")
    }

    private val environment = mapOf(
        "XDG_RUNTIME_DIR" to "/run/androidsteam", "WAYLAND_DISPLAY" to "wayland-0", "SDL_VIDEODRIVER" to "wayland",
        "PULSE_SERVER" to "unix:/run/androidsteam/pulse/native",
        "XLOCALEDIR" to "/usr/share/X11/locale",
        "WLR_XWAYLAND" to "/usr/bin/Xwayland",
        "LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/libdeck-drm.so",
        "PATH" to "/usr/bin:/bin",
        "__EGL_VENDOR_LIBRARY_FILENAMES" to "/usr/share/glvnd/egl_vendor.d/50_mesa.json",
        "LIBGL_DRIVERS_PATH" to "/usr/lib/dri",
        "GBM_BACKENDS_PATH" to "/usr/lib/gbm",
        "MESA_LOADER_DRIVER_OVERRIDE" to "zink", "GALLIUM_DRIVER" to "zink",
        "LD_LIBRARY_PATH" to "/opt/androidsteam/session/usr/lib:/usr/lib/pulseaudio",
        "VK_DRIVER_FILES" to "/opt/androidsteam/graphics/linux/freedreno_icd.aarch64.json")

    companion object { private const val STEAM = "/root/.local/share/Steam" }
}
