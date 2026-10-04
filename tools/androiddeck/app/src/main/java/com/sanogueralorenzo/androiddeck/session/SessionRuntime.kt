package com.sanogueralorenzo.androiddeck.session

import android.content.Context
import android.net.ConnectivityManager
import com.sanogueralorenzo.androiddeck.display.GraphicsInstaller
import com.sanogueralorenzo.androiddeck.runtime.LinuxRuntime
import com.sanogueralorenzo.androiddeck.runtime.RuntimeInstaller
import java.io.File

/** The fixed Linux environment shared by the real Steam session and its rendering check. */
internal class SessionRuntime(private val context: Context, val directory: File) {
    val socket = File(directory, "wayland-0")
    private val components = SessionComponents(context)
    private val graphics = GraphicsInstaller(context)

    private fun bindings(): List<String> {
        check(directory.isDirectory || directory.mkdirs()) { "Cannot prepare the Steam session directory." }
        val sharedMemory = File(directory, "shm").apply { mkdirs() }
        return listOf("${components.root.path}:/opt/androiddeck/session", "${graphics.root.path}:/opt/androiddeck/graphics",
            "${context.applicationInfo.nativeLibraryDir}:/opt/androiddeck/app", "${directory.path}:/run/androiddeck",
            "${sharedMemory.path}:/dev/shm", "${components.root.path}/usr/bin/xkbcomp:/usr/bin/xkbcomp",
            "${components.root.path}/usr/share/gamescope:/usr/share/gamescope",
            "${components.root.path}/usr/share/fonts:/usr/share/fonts",
            "${components.root.path}/usr/share/fontconfig:/usr/share/fontconfig",
            "${components.root.path}/etc/fonts:/etc/fonts") + GpuDevice.bindings(File(directory, "gpu"))
    }

    fun start(command: List<String>, width: Int, height: Int): Process =
        LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/opt/androiddeck/session/usr/games/gamescope", "--backend", "sdl", "--expose-wayland",
                "-W", width.toString(), "-H", height.toString(), "--") + command, bindings(), environment)

    fun steamCommand(): List<String> {
        val network = context.getSystemService(ConnectivityManager::class.java)
        val servers = network.activeNetwork?.let { network.getLinkProperties(it)?.dnsServers }.orEmpty()
        check(servers.isNotEmpty()) { "Connect to a network with DNS, then start Steam again." }
        // Ubuntu's resolver points at an absent systemd stub. Replace only this
        // runtime configuration, preserving the separately stored user home.
        val resolver = File(RuntimeInstaller(context).root, "etc/resolv.conf")
        java.nio.file.Files.deleteIfExists(resolver.toPath())
        resolver.writeText(servers.joinToString("") { "nameserver ${it.hostAddress}\n" } + "options timeout:2 attempts:2\n")
        context.assets.open("steam/launch.sh").use { input ->
            File(directory, "steam-launch.sh").outputStream().use { input.copyTo(it) }
        }
        return listOf("/usr/bin/env", "STEAM_RUNTIME=1",
            "SDL_VIDEODRIVER=x11",
            "LD_PRELOAD=/opt/androiddeck/session/usr/lib/aarch64-linux-gnu/libdeck-robust.so:${environment.getValue("LD_PRELOAD")}",
            "LD_LIBRARY_PATH=$STEAM/steamrtarm64:$STEAM/steamrtarm64/libs:${environment.getValue("LD_LIBRARY_PATH")}",
            "/bin/sh", "/run/androiddeck/steam-launch.sh", "$STEAM/steamrtarm64/steam", "-gamepadui", "-steamdeck", "-steamos3",
            "-overridepackageurl", "https://client-update.akamai.steamstatic.com")
    }

    private val environment = mapOf(
        "XDG_RUNTIME_DIR" to "/run/androiddeck", "WAYLAND_DISPLAY" to "wayland-0", "SDL_VIDEODRIVER" to "wayland",
        "WLR_XWAYLAND" to "/opt/androiddeck/session/usr/bin/Xwayland",
        "LD_PRELOAD" to "/opt/androiddeck/session/usr/lib/aarch64-linux-gnu/libdeck-drm.so",
        "PATH" to "/opt/androiddeck/session/usr/games:/opt/androiddeck/session/usr/bin:/usr/bin:/bin",
        "__EGL_VENDOR_LIBRARY_FILENAMES" to "/opt/androiddeck/session/usr/share/glvnd/egl_vendor.d/50_mesa.json",
        "LIBGL_DRIVERS_PATH" to "/opt/androiddeck/session/usr/lib/aarch64-linux-gnu/dri",
        "GBM_BACKENDS_PATH" to "/opt/androiddeck/session/usr/lib/aarch64-linux-gnu/gbm",
        "MESA_LOADER_DRIVER_OVERRIDE" to "zink", "GALLIUM_DRIVER" to "zink",
        "LD_LIBRARY_PATH" to "/opt/androiddeck/session/usr/lib/aarch64-linux-gnu:/opt/androiddeck/session/usr/lib/aarch64-linux-gnu/pulseaudio:/opt/androiddeck/graphics/usr/lib/aarch64-linux-gnu",
        "VK_DRIVER_FILES" to "/opt/androiddeck/graphics/linux/freedreno_icd.aarch64.json")

    companion object { private const val STEAM = "/root/.local/share/Steam" }
}
