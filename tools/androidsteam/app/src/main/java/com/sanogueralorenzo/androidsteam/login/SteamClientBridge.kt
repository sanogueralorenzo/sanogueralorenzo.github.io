package com.sanogueralorenzo.androidsteam.login

import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.io.FileDescriptor
import org.json.JSONObject

/** CEF's private pipe protocol. Request contents and remote errors are never logged. */
internal class SteamClientBridge(directory: File) : Closeable {
    private val input: FileDescriptor
    private val output: FileDescriptor
    private val pending = ByteArrayOutputStream()
    private val packets = ArrayDeque<JSONObject>()
    private var nextId = 0
    @Volatile private var closed = false

    init {
        prepare(directory)
        input = open(File(directory, "ui-response"))
        output = try { open(File(directory, "ui-command")) } catch (_: Exception) {
            Os.close(input); error("Cannot open Steam's private command channel.")
        }
    }

    @Synchronized fun hasAuthenticationInterface(): Boolean = evaluate(
        "typeof SteamClient !== 'undefined' && typeof SteamClient.Auth.SetLoginToken === 'function' && typeof SteamClient.Auth.StartSignInFromCache === 'function'")

    @Synchronized fun hasOnlineUser(): Boolean = evaluate("$OBSERVER; !!globalThis.__androidSteamUser?.strSteamID && globalThis.__androidSteamUser.strSteamID !== '0' && globalThis.__androidSteamUser.bIsOfflineMode === false")

    @Synchronized fun isAuthenticated(steamId: String): Boolean = evaluate(
        "$OBSERVER; globalThis.__androidSteamUser?.strSteamID === ${JSONObject.quote(steamId)} && globalThis.__androidSteamUser.bIsOfflineMode === false")

    /** Only operation success leaves CEF; tokens never enter argv or returned diagnostics. */
    @Synchronized fun signIn(tokens: SteamTokens): Boolean = evaluate("""
        (async () => {
            $OBSERVER;
            if (globalThis.__androidSteamUser?.strSteamID && globalThis.__androidSteamUser.strSteamID !== '0')
                return globalThis.__androidSteamUser.strSteamID === ${JSONObject.quote(tokens.steamId)} && globalThis.__androidSteamUser.bIsOfflineMode === false;
            const result = await SteamClient.Auth.SetLoginToken(${JSONObject.quote(tokens.refresh)}, ${JSONObject.quote(tokens.account)});
            if (result?.result !== 1) return false;
            ${tokens.guard?.let { "SteamClient.Auth.SetSteamGuardData(${JSONObject.quote(tokens.account)}, ${JSONObject.quote(it)});" }.orEmpty()}
            const login = await SteamClient.Auth.StartSignInFromCache(${JSONObject.quote(tokens.account)}, false);
            return !login || login.result === 1;
        })()
    """.trimIndent(), awaitPromise = true)

    private fun evaluate(expression: String, awaitPromise: Boolean = false): Boolean {
        try {
            val targets = request("Target.getTargets").getJSONArray("targetInfos")
            for (i in 0 until targets.length()) {
                val target = targets.getJSONObject(i)
                if (!target.optString("title").contains("SharedJS", ignoreCase = true)) continue
                val session = request("Target.attachToTarget", JSONObject().put("targetId", target.getString("targetId"))
                    .put("flatten", true)).getString("sessionId")
                try {
                    val response = request("Runtime.evaluate", JSONObject().put("expression", expression)
                        .put("returnByValue", true).put("awaitPromise", awaitPromise), session)
                    check(!response.has("exceptionDetails"))
                    return response.optJSONObject("result")?.optBoolean("value") == true
                } finally { request("Target.detachFromTarget", JSONObject().put("sessionId", session)) }
            }
            return false
        } catch (_: Exception) {
            error("Steam's private interface is unavailable. Restart Steam and retry.")
        }
    }

    private fun request(method: String, parameters: JSONObject = JSONObject(), session: String? = null): JSONObject {
        try {
            check(!closed)
            val id = ++nextId
            val message = JSONObject().put("id", id).put("method", method).put("params", parameters)
            if (session != null) message.put("sessionId", session)
            val bytes = (message.toString() + '\u0000').toByteArray(Charsets.UTF_8)
            var offset = 0
            while (offset < bytes.size) offset += Os.write(output, bytes, offset, bytes.size - offset)
            val deadline = SystemClock.elapsedRealtime() + 90_000
            val poll = StructPollfd().apply { fd = input; events = OsConstants.POLLIN.toShort() }
            val buffer = ByteArray(4096)
            while (!closed && !Thread.currentThread().isInterrupted && SystemClock.elapsedRealtime() < deadline) {
                while (packets.isNotEmpty()) {
                    val packet = packets.removeFirst()
                    if (packet.optInt("id") == id) {
                        check(!packet.has("error"))
                        return packet.getJSONObject("result")
                    }
                }
                if (Os.poll(arrayOf(poll), 250) == 0) continue
                check(!closed)
                val count = Os.read(input, buffer, 0, buffer.size)
                for (i in 0 until count) {
                    if (buffer[i].toInt() == 0) {
                        packets.addLast(JSONObject(pending.toString(Charsets.UTF_8.name())))
                        pending.reset()
                    } else {
                        pending.write(buffer[i].toInt())
                        check(pending.size() <= 1_048_576)
                    }
                }
            }
            error("Private Steam request did not complete")
        } catch (_: Exception) {
            // Avoid carrying remote values, expressions or sensitive parser exceptions into callers.
            error("Steam's private interface is unavailable. Restart Steam and retry.")
        }
    }

    override fun close() {
        closed = true
        try { Os.close(input) } finally { Os.close(output) }
    }

    companion object {
        private const val OBSERVER = """
            if (!globalThis.__androidSteamWatchingUser) {
                globalThis.__androidSteamWatchingUser = true;
                SteamClient.User.RegisterForCurrentUserChanges(user => { globalThis.__androidSteamUser = user; });
            }
        """

        fun prepare(directory: File) {
            for (name in listOf("ui-command", "ui-response")) {
                val path = File(directory, name).path
                try { Os.mkfifo(path, 0x180) } catch (failure: android.system.ErrnoException) {
                    if (failure.errno != OsConstants.EEXIST) error("Cannot prepare Steam's private interface.")
                }
                val info = Os.lstat(path)
                check(OsConstants.S_ISFIFO(info.st_mode) && info.st_uid == Os.getuid() && info.st_mode and 0x1ff == 0x180) {
                    "Steam's private interface has invalid permissions. Restart Steam."
                }
            }
        }

        private fun open(file: File) = Os.open(file.path,
            OsConstants.O_RDWR or OsConstants.O_NONBLOCK or OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW, 0)
    }
}
