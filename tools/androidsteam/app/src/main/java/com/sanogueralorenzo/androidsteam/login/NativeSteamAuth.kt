package com.sanogueralorenzo.androidsteam.login

import `in`.dragonbra.javasteam.enums.EOSType
import `in`.dragonbra.javasteam.enums.EResult
import `in`.dragonbra.javasteam.steam.authentication.AuthSessionDetails
import `in`.dragonbra.javasteam.steam.authentication.AuthenticationException
import `in`.dragonbra.javasteam.steam.authentication.CredentialsAuthSession
import `in`.dragonbra.javasteam.protobufs.steamclient.SteammessagesAuthSteamclient.EAuthSessionGuardType
import `in`.dragonbra.javasteam.protobufs.steamclient.SteammessagesAuthSteamclient.EAuthTokenPlatformType
import `in`.dragonbra.javasteam.steam.handlers.steamuser.LogOnDetails
import `in`.dragonbra.javasteam.steam.handlers.steamuser.SteamUser
import `in`.dragonbra.javasteam.steam.handlers.steamuser.callback.LoggedOnCallback
import `in`.dragonbra.javasteam.steam.steamclient.SteamClient
import `in`.dragonbra.javasteam.steam.steamclient.callbacks.ConnectedCallback
import `in`.dragonbra.javasteam.steam.steamclient.callbacks.DisconnectedCallback
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.security.Security
import java.security.SecureRandom
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit

/** Runs on the login worker; no SDK log listener or packet/debug output is installed. */
internal class NativeSteamAuth {
    enum class Guard { APPROVAL, APP_CODE, EMAIL_CODE }

    fun authenticate(account: String, password: CharArray,
        ask: (Guard, Boolean) -> CompletableFuture<String>, progress: (String) -> Unit): SteamTokens {
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob() + CoroutineExceptionHandler { _, _ -> })
        var client: SteamClient? = null
        try {
            prepareCrypto()
            client = SteamClient(defaultScope = scope)
            progress("Connecting to Steam…")
            connect(client)
            val details = AuthSessionDetails().apply {
                username = account
                this.password = String(password)
                deviceFriendlyName = "Android Steam"
                platformType = EAuthTokenPlatformType.k_EAuthTokenPlatformType_SteamClient
                clientOSType = EOSType.LinuxUnknown
                persistentSession = true
            }
            password.fill('\u0000')
            progress("Signing in…")
            val session = try { client.authentication.beginAuthSessionViaCredentials(details).get(60, TimeUnit.SECONDS) }
                finally { details.password = null }
            val result = authorize(session, ask)
            val tokens = SteamTokens.fromNative(result.accountName, result.refreshToken, result.newGuardData)
            progress("Verifying Steam authentication…")
            val user = checkNotNull(client.getHandler(SteamUser::class.java))
            user.logOn(LogOnDetails().apply {
                username = tokens.account
                accessToken = tokens.refresh
                loginID = SecureRandom().nextInt(Int.MAX_VALUE - 1) + 1
                shouldRememberPassword = true
                clientOSType = EOSType.LinuxUnknown
                machineName = "Android Steam"
            })
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45)
            while (System.nanoTime() < deadline) {
                checkInterrupted()
                when (val callback = client.waitForCallback(250)) {
                    is DisconnectedCallback -> error("Disconnected")
                    is LoggedOnCallback -> {
                        check(callback.result == EResult.OK)
                        check(client.steamID?.convertToUInt64()?.toString() == tokens.steamId)
                        return tokens
                    }
                }
            }
            error("Timed out")
        } catch (failure: Exception) {
            val underlying = if (failure is ExecutionException) failure.cause else failure
            val message = when ((underlying as? AuthenticationException)?.result) {
                EResult.InvalidPassword -> "Check your account name and password, then try again."
                EResult.RateLimitExceeded -> "Steam is limiting sign-in attempts. Wait before trying again."
                else -> "Steam sign-in did not complete. Check your connection and try again."
            }
            // Never propagate a remote exception, cause, account, password, code or token.
            error(message)
        } finally {
            password.fill('\u0000')
            try { client?.disconnect() } catch (_: Exception) { /* No remote cleanup errors. */ } finally { scope.cancel() }
        }
    }

    internal fun connect(client: SteamClient) {
        client.connect()
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
        while (System.nanoTime() < deadline) {
            checkInterrupted()
            when (client.waitForCallback(250)) {
                is ConnectedCallback -> return
                is DisconnectedCallback -> error("Steam connection did not complete.")
            }
        }
        error("Steam connection did not complete.")
    }

    private fun authorize(session: CredentialsAuthSession, ask: (Guard, Boolean) -> CompletableFuture<String>): `in`.dragonbra.javasteam.steam.authentication.AuthPollResult {
        val methods = session.allowedConfirmations.map { it.confirmationType }
        val none = EAuthSessionGuardType.k_EAuthSessionGuardType_None
        val approval = EAuthSessionGuardType.k_EAuthSessionGuardType_DeviceConfirmation
        val app = EAuthSessionGuardType.k_EAuthSessionGuardType_DeviceCode
        val email = EAuthSessionGuardType.k_EAuthSessionGuardType_EmailCode
        val method = listOf(none, approval, app, email).firstOrNull { it in methods } ?: error("Unsupported Guard")
        var code: CompletableFuture<String>? = when (method) {
            approval -> ask(Guard.APPROVAL, false)
            app -> ask(Guard.APP_CODE, false)
            email -> ask(Guard.EMAIL_CODE, false)
            else -> null
        }
        val deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(10)
        try {
            while (System.nanoTime() < deadline) {
                checkInterrupted()
                if (code != null && code.isDone) {
                    val type = if (method == email) email else app
                    check(type in methods)
                    try { session.sendSteamGuardCode(code.get(), type).get(30, TimeUnit.SECONDS); code = null }
                    catch (failure: ExecutionException) {
                        val result = (failure.cause as? AuthenticationException)?.result
                        check(result == EResult.InvalidLoginAuthCode || result == EResult.TwoFactorCodeMismatch)
                        code = ask(if (type == email) Guard.EMAIL_CODE else Guard.APP_CODE, true)
                    }
                }
                session.pollAuthSessionStatus().get(30, TimeUnit.SECONDS)?.let { return it }
                // Valve's advertised interval is seconds. Avoid a busy authentication poll loop.
                Thread.sleep((session.pollingInterval * 1000).toLong().coerceIn(1000, 10_000))
            }
            error("Guard timed out")
        } finally { code?.cancel(true) }
    }

    companion object {
        @Synchronized internal fun prepareCrypto() {
            if (Security.getProvider("BC") is BouncyCastleProvider) return
            // Android's built-in BC omits algorithms JavaSteam requests explicitly.
            Security.removeProvider("BC")
            check(Security.insertProviderAt(BouncyCastleProvider(), 1) > 0)
        }
        private fun checkInterrupted() { if (Thread.currentThread().isInterrupted) throw InterruptedException() }
    }
}
