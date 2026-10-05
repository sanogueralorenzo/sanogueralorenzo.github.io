package com.sanogueralorenzo.androidsteam

import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.login.SteamQrProofActivity
import com.sanogueralorenzo.androidsteam.session.SteamInstaller
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class SteamQrSignInTest {
    @Test fun privateSessionIsOwnedAndConfirmedSignedOut() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyQrLoginIsolation") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val original = instrumentation.targetContext
        val app = original.applicationContext as DebugSteamApplication
        val originalSession = app.session
        val isolated = SteamQrProofActivity.proofContext(original)
        assertEquals(com.sanogueralorenzo.androidsteam.session.SessionController.State.Idle, originalSession.state)
        val activity = instrumentation.startActivitySync(android.content.Intent(original, SteamQrProofActivity::class.java)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) as SteamQrProofActivity
        try {
            assertNotSame(originalSession, app.session)
            val marker = File(isolated.cacheDir, "proof-status")
            val deadline = android.os.SystemClock.elapsedRealtime() + 600_000
            var ready = false
            while (android.os.SystemClock.elapsedRealtime() < deadline) {
                val stage = marker.takeIf { it.isFile }?.readText()
                if (stage == "QR_READY") { ready = true; break }
                assertFalse("Private session preparation failed", app.session.state is com.sanogueralorenzo.androidsteam.session.SessionController.State.Failed)
                Thread.sleep(250)
            }
            assertTrue("Private session did not become ready", ready)
            assertTrue(File(isolated.cacheDir, "session/ui-command").exists())
            assertFalse("Original session must stay closed", File(original.cacheDir, "session/ui-command").exists())
            assertTrue("Signed-out status requires a delivered observer callback", app.session.clientBridge!!.isSignedOut())
            assertTrue("Only a valid Steam challenge should enable sign-in", app.session.clientBridge!!.qrChallenge() != null)
            val challenge = app.session.clientBridge!!.qrChallenge()!!
            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(challenge))
                .setPackage(com.sanogueralorenzo.androidsteam.login.SteamSignInLink.PACKAGE)
            assertNotNull("Official Steam app must handle the challenge", original.packageManager.resolveActivity(intent, 0))
            instrumentation.runOnMainSync {
                assertEquals("Sign in with Steam", activity.findViewById<android.widget.Button>(R.id.sign_in_steam).text.toString())
                assertTrue(activity.findViewById<android.widget.Button>(R.id.sign_in_steam).compoundDrawablesRelative[0] != null)
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
            val deadline = android.os.SystemClock.elapsedRealtime() + 25_000
            while (app.session !== originalSession && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
            assertSame(originalSession, app.session)
            assertEquals(com.sanogueralorenzo.androidsteam.session.SessionController.State.Idle, originalSession.state)
            assertFalse(File(isolated.cacheDir, "session/ui-command").exists())
        }
    }

    @Test fun preparesFreshSteamWithoutCopyingAuthentication() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("prepareQrLoginProof") == "true")
        val original = InstrumentationRegistry.getInstrumentation().targetContext
        val isolated = SteamQrProofActivity.proofContext(original)
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
