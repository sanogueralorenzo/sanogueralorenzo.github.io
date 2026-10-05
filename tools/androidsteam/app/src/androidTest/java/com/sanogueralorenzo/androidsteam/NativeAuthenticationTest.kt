package com.sanogueralorenzo.androidsteam

import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.login.NativeSteamAuth
import com.sanogueralorenzo.androidsteam.login.SteamTokens
import com.sanogueralorenzo.androidsteam.login.TokenVault
import `in`.dragonbra.javasteam.steam.steamclient.SteamClient
import `in`.dragonbra.javasteam.util.crypto.CryptoHelper
import `in`.dragonbra.javasteam.util.log.LogManager
import java.io.File
import java.security.KeyPairGenerator
import java.util.Base64
import javax.crypto.Cipher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.cancel
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class NativeAuthenticationTest {
    @Test fun androidCryptoSupportsTheSteamHandshake() {
        NativeSteamAuth.prepareCrypto()
        assertTrue(LogManager.LOG_LISTENERS.isEmpty())
        val key = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val cipher = Cipher.getInstance("RSA/None/PKCS1Padding", CryptoHelper.SEC_PROV)
        cipher.init(Cipher.ENCRYPT_MODE, key.public)
        val encrypted = cipher.doFinal(byteArrayOf(1, 2, 3))
        cipher.init(Cipher.DECRYPT_MODE, key.private)
        assertArrayEquals(byteArrayOf(1, 2, 3), cipher.doFinal(encrypted))
        assertEquals(20, CryptoHelper.shaHash(byteArrayOf(1)).size)
    }

    @Test fun tokenStorageIsEncryptedAndRejectsTampering() {
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(target.noBackupFilesDir, "auth-vault-test").apply { mkdirs() }
        val isolated = object : ContextWrapper(target) { override fun getNoBackupFilesDir() = directory }
        val refresh = token("client")
        val vault = TokenVault(isolated)
        try {
            vault.save(SteamTokens.fromNative("test-account", refresh, "test-guard"))
            assertEquals(refresh, vault.read()?.refresh)
            val storage = File(directory, "steam-auth")
            val bytes = storage.readBytes()
            val encoded = String(bytes, Charsets.ISO_8859_1)
            assertFalse(encoded.contains(refresh))
            assertFalse(encoded.contains("test-account"))
            assertFalse(encoded.contains("test-guard"))
            bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
            storage.writeBytes(bytes)
            try { vault.read(); fail("Tampered sign-in must be rejected") }
            catch (failure: IllegalStateException) { assertNull(failure.cause) }
            try { SteamTokens.fromNative("test-account", token("web"), null); fail("Web token must be rejected") }
            catch (failure: IllegalStateException) { assertNull(failure.cause) }
        } finally { vault.clear(); directory.deleteRecursively() }
    }

    @Test fun nativeAndroidConnectsToSteamWithoutCredentials() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyNativeConnection") == "true")
        NativeSteamAuth.prepareCrypto()
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob() + CoroutineExceptionHandler { _, _ -> })
        val client = SteamClient(defaultScope = scope)
        try {
            NativeSteamAuth().connect(client)
            assertTrue(client.isConnected)
            assertNull(client.steamID)
            assertTrue(LogManager.LOG_LISTENERS.isEmpty())
        } finally { try { client.disconnect() } finally { scope.cancel() } }
    }

    private fun token(audience: String): String {
        val claims = """{"aud":["derive","$audience"],"sub":"76561198000000000","exp":${System.currentTimeMillis() / 1000 + 3600}}"""
        return "test." + Base64.getUrlEncoder().withoutPadding().encodeToString(claims.toByteArray()) + ".signature"
    }
}
