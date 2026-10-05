package com.sanogueralorenzo.androidsteam

import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.login.NativeLoginProofActivity
import com.sanogueralorenzo.androidsteam.session.SteamInstaller
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class NativeLoginProofPreparationTest {
    @Test fun preparesFreshSteamWithoutCopyingAuthentication() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("prepareNativeLoginProof") == "true")
        val original = InstrumentationRegistry.getInstrumentation().targetContext
        val isolated = NativeLoginProofActivity.proofContext(original)
        assertTrue((original.applicationContext as SteamApplication).preparation.installed)
        for (name in listOf("runtime", "graphics", "session-components")) {
            val target = File(isolated.filesDir, name).toPath()
            if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) Files.createSymbolicLink(target, File(original.filesDir, name).toPath())
        }
        val installer = SteamInstaller(isolated)
        installer.install { }
        val source = SteamInstaller(original).root
        val root = installer.root
        assertFalse(File(root, "config/loginusers.vdf").exists())
        assertFalse(File(root, "userdata").exists())
        val common = File(root, "steamapps/common").apply { mkdirs() }
        for (name in listOf("SuperFlight", "Proton Experimental (ARM64)")) {
            val target = File(common, name)
            if (!target.exists()) {
                val copy = ProcessBuilder("/system/bin/cp", "-a", File(source, "steamapps/common/$name").path, target.path).redirectErrorStream(true).start()
                val drain = Thread { copy.inputStream.use { it.copyTo(java.io.OutputStream.nullOutputStream()) } }.apply { start() }
                try { assertTrue("Public game/tool copy timed out", copy.waitFor(180, TimeUnit.SECONDS)); drain.join(1000); assertEquals(0, copy.exitValue()) }
                finally { copy.destroyForcibly() }
            }
        }
        for (id in listOf(732430, 4427310)) File(source, "steamapps/appmanifest_$id.acf").copyTo(File(root, "steamapps/appmanifest_$id.acf"), overwrite = true)
        File(root, "appcache").mkdirs()
        File(source, "appcache/appinfo.vdf").copyTo(File(root, "appcache/appinfo.vdf"), overwrite = true)
        assertTrue(installer.installed && installer.protonInstalled)
        assertFalse(File(root, "config/loginusers.vdf").exists())
        assertFalse(File(root, "userdata").exists())
        File(isolated.filesDir, "proof-prepared").writeText("fresh-client")
        println("Fresh private Steam prepared; only public game/tool payloads and metadata copied.")
    }
}
