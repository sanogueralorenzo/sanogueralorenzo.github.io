package com.sanogueralorenzo.amarchy

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.amarchy.runtime.EnvironmentInstaller
import com.sanogueralorenzo.amarchy.runtime.LinuxRuntime
import com.sanogueralorenzo.amarchy.runtime.ProcessOutput
import com.sanogueralorenzo.amarchy.session.DesktopSession
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class UpstreamEnvironmentTest {
    @Test fun qtApplicationsCanSaveAndReplaceFilesAtomically() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = java.io.File(context.cacheDir, "qt-save-proof").apply { mkdirs() }
        java.io.File(directory, "save.cpp").writeText("""
            #include <QSaveFile>
            #include <QFile>
            int main() {
                for (const char* value : {"first", "second"}) {
                    QSaveFile file("/tmp/save-proof/settings.json");
                    if (!file.open(QIODevice::WriteOnly) || file.write(value) < 0 || !file.commit()) return 1;
                }
                QFile file("/tmp/save-proof/settings.json");
                return !file.open(QIODevice::ReadOnly) || file.readAll() != "second";
            }
        """.trimIndent())
        val process = LinuxRuntime(context, EnvironmentInstaller(context).root, 1000).start(listOf("/bin/bash", "-c",
            "set -e; c++ -fPIC -no-pie /tmp/save-proof/save.cpp \$(pkg-config --cflags --libs Qt6Core) -o /tmp/save-proof/save; /tmp/save-proof/save"),
            listOf("${directory.path}:/tmp/save-proof", "${context.applicationInfo.nativeLibraryDir}:/opt/amarchy"),
            mapOf("LD_PRELOAD" to "/opt/amarchy/libamarchy-software-drm.so"))
        val output = ProcessOutput(process, 32_768)
        try {
            assertTrue(process.waitFor(60, TimeUnit.SECONDS))
            assertEquals(output.text(), 0, process.exitValue())
            assertEquals("second", java.io.File(directory, "settings.json").readText())
        } finally {
            if (process.isAlive) process.destroyForcibly()
            com.sanogueralorenzo.amarchy.runtime.RuntimeArchive.delete(directory)
        }
    }

    @Test fun preconfiguredUserDefaultsPrepareWithoutAnInstallerOrNetworkDownloads() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val desktop = DesktopSession(context)
        desktop.prepare()
        val process = LinuxRuntime(context, EnvironmentInstaller(context).root, 1000).start(
            listOf("/usr/bin/dbus-run-session", "--", "/bin/bash", "/run/user/1000/prepare.sh"),
            listOf("${desktop.directory.path}:/run/user/1000"),
            mapOf("XDG_RUNTIME_DIR" to "/run/user/1000", "OMARCHY_PATH" to "/usr/share/omarchy", "XDG_CURRENT_DESKTOP" to "Hyprland",
                "PATH" to "/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin"))
        val output = ProcessOutput(process, 32_768)
        try {
            assertTrue(process.waitFor(60, TimeUnit.SECONDS))
            val result = output.text()
            println(result)
            assertEquals(result, 0, process.exitValue())
            assertTrue(java.io.File(context.filesDir, "home/.local/state/amarchy/provisioned").isFile)
        } finally { if (process.isAlive) process.destroyForcibly() }
    }

    @Test fun completeUpstreamBundleInstallsWithConsistentPackagesAndOfflineDefaults() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val installer = EnvironmentInstaller(context)
        var previous = ""
        installer.prepare { detail, progress ->
            val state = "$detail ${(progress * 10).toInt() * 10}%"
            if (state != previous) { println(state); previous = state }
        }
        val process = LinuxRuntime(context, installer.root, 0).start(listOf("/bin/bash", "-c", """
            set -e
            pacman -Dk
            test -f /usr/share/omarchy/shell/shell.qml
            test -f /usr/share/omarchy/themes/tokyo-night/colors.toml
            test -f /etc/skel/.bashrc
            test -f /etc/skel/.config/foot/foot.ini
            test -f /etc/skel/.local/share/nvim/lazy/LazyVim/lua/lazyvim/config/init.lua
            test -x /usr/local/bin/uwsm-app
            pacman -Q quickshell omarchy-nvim foot nautilus chromium libreoffice-fresh omawrite omacalc omasnap obsidian
            printf 'upstream-bundle-ok\n'
        """.trimIndent()))
        val output = ProcessOutput(process, 32_768)
        try {
            assertTrue(process.waitFor(30, TimeUnit.SECONDS))
            val result = output.text()
            println(result)
            assertEquals(result, 0, process.exitValue())
            assertTrue(result, result.contains("upstream-bundle-ok"))
            assertTrue(result, result.contains("quickshell 0.3.2-4"))
        } finally { if (process.isAlive) process.destroyForcibly() }
    }
}
