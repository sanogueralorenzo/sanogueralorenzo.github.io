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

    @Synchronized fun hasClientInterface(): Boolean = evaluate(
        "typeof SteamClient !== 'undefined' && typeof SteamClient.User?.RegisterForCurrentUserChanges === 'function'") == true

    @Synchronized fun hasCurrentUser(timeoutMillis: Long = 90_000): Boolean =
        evaluate("$OBSERVER; $HAS_ACCOUNT", timeoutMillis = timeoutMillis) == true

    @Synchronized fun hasOnlineUser(): Boolean = evaluate("$OBSERVER; $HAS_ACCOUNT && globalThis.__androidSteamUser.bIsOfflineMode === false") == true

    /** Use the running client's own URI handler; it retains Steam's launch/install prompts. */
    @Synchronized fun requestGame(appId: Int, install: Boolean): Boolean {
        require(appId > 0)
        val uri = if (install) "steam://install/$appId" else "steam://rungameid/$appId"
        return evaluate("""
            typeof SteamClient.URL?.ExecuteSteamURL === 'function' && (() => {
                SteamClient.URL.ExecuteSteamURL("$uri");
                return true;
            })()
        """.trimIndent(), timeoutMillis = 10_000) == true
    }

    /** A missing initial observer callback is unknown, never proof that Steam is signed out. */
    @Synchronized fun isSignedOut(): Boolean = evaluate("""
        (async () => {
            $OBSERVER;
            for (let i = 0; i < 40 && !globalThis.__androidSteamUserObserved; i++)
                await new Promise(resolve => setTimeout(resolve, 250));
            return globalThis.__androidSteamUserObserved === true &&
                !($HAS_ACCOUNT);
        })()
    """.trimIndent(), awaitPromise = true) == true

    private fun evaluate(expression: String, awaitPromise: Boolean = false, timeoutMillis: Long = 90_000): Any? {
        val deadline = SystemClock.elapsedRealtime() + timeoutMillis
        try {
            val targets = request("Target.getTargets", deadline = deadline).getJSONArray("targetInfos")
            val candidates = (0 until targets.length()).map { targets.getJSONObject(it) }
                .sortedByDescending { it.optString("title").contains("SharedJS", ignoreCase = true) }
            for (target in candidates) {
                val session = request("Target.attachToTarget", JSONObject().put("targetId", target.getString("targetId"))
                    .put("flatten", true), deadline = deadline).getString("sessionId")
                try {
                    val capability = request("Runtime.evaluate", JSONObject().put("expression",
                        USER_INTERFACE)
                        .put("returnByValue", true), session, deadline)
                    if (capability.optJSONObject("result")?.optBoolean("value") != true) continue
                    val response = request("Runtime.evaluate", JSONObject().put("expression", expression)
                        .put("returnByValue", true).put("awaitPromise", awaitPromise), session, deadline)
                    check(!response.has("exceptionDetails"))
                    val value = response.optJSONObject("result")?.opt("value")?.takeUnless { it === JSONObject.NULL }
                    return value
                } finally { request("Target.detachFromTarget", JSONObject().put("sessionId", session), deadline = deadline) }
            }
            return null
        } catch (_: Exception) {
            error("Steam's private interface is unavailable. Restart Steam and retry.")
        }
    }

    private fun request(method: String, parameters: JSONObject = JSONObject(), session: String? = null,
        deadline: Long = SystemClock.elapsedRealtime() + 90_000): JSONObject {
        try {
            check(!closed)
            val id = ++nextId
            val message = JSONObject().put("id", id).put("method", method).put("params", parameters)
            if (session != null) message.put("sessionId", session)
            val bytes = (message.toString() + '\u0000').toByteArray(Charsets.UTF_8)
            var offset = 0
            while (offset < bytes.size) offset += Os.write(output, bytes, offset, bytes.size - offset)
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
        private const val USER_INTERFACE = "typeof SteamClient !== 'undefined' && typeof SteamClient.User?.RegisterForCurrentUserChanges === 'function'"
        // Signed-out Steam may return the individual-account namespace with account number zero.
        private const val HAS_ACCOUNT = "!!globalThis.__androidSteamUser?.strSteamID && (BigInt(globalThis.__androidSteamUser.strSteamID) & 0xffffffffn) !== 0n"
        private const val OBSERVER = """
            if (!globalThis.__androidSteamWatchingUser) {
                globalThis.__androidSteamWatchingUser = true;
                SteamClient.User.RegisterForCurrentUserChanges(user => { globalThis.__androidSteamUser = user; globalThis.__androidSteamUserObserved = true; });
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
