package com.sanogueralorenzo.androidsteam.login

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.Button
import com.sanogueralorenzo.androidsteam.DebugSteamApplication
import com.sanogueralorenzo.androidsteam.R
import com.sanogueralorenzo.androidsteam.session.SessionActivity
import com.sanogueralorenzo.androidsteam.session.SessionController
import java.io.File
import java.util.concurrent.Executors

/** Device proof uses the shipping sign-in UI and a separate home; no authentication is copied. */
class SteamQrProofActivity : SessionActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var isolated: Context
    private val app get() = application as DebugSteamApplication
    private val poll = object : Runnable {
        override fun run() {
            if (isFinishing) return
            if (findViewById<Button>(R.id.sign_in_steam).isEnabled && findViewById<View>(R.id.steam_sign_in).visibility == View.VISIBLE)
                mark("QR_READY")
            else if (app.session.state == SessionController.State.Running) worker.submit {
                try { if (app.session.clientBridge?.hasOnlineUser() == true) mark("LINUX_AUTHENTICATED") }
                catch (_: Exception) { }
            }
            main.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        isolated = proofContext(this)
        check(File(isolated.filesDir, "proof-prepared").isFile)
        app.openProof(isolated)
        super.onCreate(savedInstanceState)
        mark("PREPARING")
    }
    override fun onStart() { super.onStart(); main.post(poll) }
    override fun onStop() { main.removeCallbacks(poll); super.onStop() }
    override fun onDestroy() {
        super.onDestroy()
        app.session.stop()
        worker.shutdownNow()
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
