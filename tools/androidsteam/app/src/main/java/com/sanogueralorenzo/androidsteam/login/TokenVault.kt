package com.sanogueralorenzo.androidsteam.login

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** Only verified session tokens belong here; passwords and Guard codes are never persisted. */
internal class TokenVault(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "steam-auth"))

    @Synchronized fun save(tokens: SteamTokens) {
        try {
            val plain = JSONObject().put("account", tokens.account).put("refresh", tokens.refresh)
                .put("guard", tokens.guard).toString().toByteArray(Charsets.UTF_8)
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
                check(cipher.iv.size == 12)
                val encrypted = byteArrayOf(1) + cipher.iv + cipher.doFinal(plain)
                val stream = file.startWrite()
                try {
                    Os.fchmod(stream.fd, 0x180)
                    stream.write(encrypted)
                    file.finishWrite(stream)
                } catch (failure: Exception) { file.failWrite(stream); throw failure }
            } finally { plain.fill(0) }
        } catch (_: Exception) { error("Cannot securely save Steam sign-in. Try again.") }
    }

    @Synchronized fun read(): SteamTokens? {
        if (!file.baseFile.exists()) return null
        try {
            check(file.baseFile.length() in 30..65_536)
            val encrypted = file.readFully()
            check(encrypted[0].toInt() == 1)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, encrypted.copyOfRange(1, 13)))
            }
            val plain = cipher.doFinal(encrypted, 13, encrypted.size - 13)
            try {
                val data = JSONObject(String(plain, Charsets.UTF_8))
                return SteamTokens.fromNative(data.getString("account"), data.getString("refresh"),
                    if (data.isNull("guard")) null else data.getString("guard"))
            } finally { plain.fill(0) }
        } catch (_: Exception) { error("Saved Steam sign-in is unavailable. Sign in again.") }
    }

    @Synchronized fun clear() = file.delete()

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    companion object { private const val ALIAS = "android-steam.session-token" }
}
