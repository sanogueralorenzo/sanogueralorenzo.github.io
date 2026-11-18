package com.sanogueralorenzo.androidsteam.session

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.sanogueralorenzo.androidsteam.DebugSteamApplication
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** The real Steam screen in the existing isolated home; diagnostics expose fixed markers only. */
class LoginProofActivity : SessionActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val checking = AtomicBoolean(false)
    private lateinit var isolated: Context
    private val app get() = application as DebugSteamApplication
    private val poll = object : Runnable {
        override fun run() {
            if (isFinishing) return
            when (app.session.state) {
                is SessionController.State.Failed -> mark("FAILED")
                SessionController.State.Running -> if (checking.compareAndSet(false, true)) worker.submit {
                    try {
                        val bridge = app.session.clientBridge
                        if (bridge?.hasOnlineUser() == true) mark("LINUX_AUTHENTICATED")
                        else if (bridge?.isSignedOut() == true) mark("SIGNED_OUT")
                    } catch (_: Exception) { } finally { checking.set(false) }
                }
                else -> Unit
            }
            main.postDelayed(this, 1000)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        isolated = proofContext(this)
        check(File(isolated.filesDir, "proof-prepared").isFile)
        if (savedInstanceState == null) app.openProof(isolated)
        super.onCreate(savedInstanceState)
        mark("PREPARING")
    }
    override fun onStart() { super.onStart(); main.post(poll) }
    override fun onStop() { main.removeCallbacks(poll); super.onStop() }
    override fun onDestroy() {
        super.onDestroy()
        worker.shutdownNow()
        if (!isFinishing) return
        app.session.stop()
        val deadline = android.os.SystemClock.elapsedRealtime() + 25_000
        main.post(object : Runnable {
            override fun run() {
                if (app.session.state == SessionController.State.Idle) app.closeProof()
                else if (android.os.SystemClock.elapsedRealtime() < deadline) main.postDelayed(this, 50)
            }
        })
    }
    private fun mark(stage: String) { File(isolated.cacheDir, "proof-status").writeText(stage) }
    companion object {
        internal fun proofContext(context: Context): Context {
            val root = File(context.filesDir, "steam-qr-proof")
            return object : ContextWrapper(context) {
                override fun getFilesDir() = File(root, "files").apply { mkdirs() }
                override fun getCacheDir() = File(root, "cache").apply { mkdirs() }
                override fun getSharedPreferences(name: String, mode: Int): SharedPreferences = context.getSharedPreferences("steam-qr-proof-$name", mode)
            }
        }
    }
}
