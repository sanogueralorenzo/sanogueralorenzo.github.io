package com.sanogueralorenzo.androidsteam.login

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.widget.Button
import android.widget.TextView
import com.sanogueralorenzo.androidsteam.R
import com.sanogueralorenzo.androidsteam.SteamApplication
import com.sanogueralorenzo.androidsteam.session.SessionController
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** Native approval UI over the existing Linux session. Steam owns the actual login and its storage. */
internal class SteamSignIn(private val activity: Activity, private val session: SessionController) {
    private val panel = activity.findViewById<View>(R.id.steam_sign_in)
    private val status = activity.findViewById<TextView>(R.id.sign_in_status)
    private val button = activity.findViewById<Button>(R.id.sign_in_steam)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var job: Future<*>? = null
    private var generation = 0
    private var deadline = 0L
    private var awaitingApproval = false
    private var online = false
    private val poll = Runnable { checkSession() }

    init { button.setOnClickListener { openSteam() } }

    fun start() {
        deadline = SystemClock.elapsedRealtime() + 600_000
        generation++
        checkSession()
    }
    fun stop() {
        generation++; main.removeCallbacks(poll); job?.cancel(true)
    }
    fun close() { stop(); worker.shutdownNow() }

    private fun checkSession() {
        val token = generation
        if (session.gameAppId != null || session.state != SessionController.State.Running) {
            panel.visibility = View.GONE
            main.postDelayed(poll, 1000)
            return
        }
        job = worker.submit {
            var authenticated = false
            var challengePresent = false
            try {
                session.clientBridge?.let { bridge ->
                    authenticated = bridge.hasCurrentUser()
                    if (!authenticated) challengePresent = bridge.qrChallenge() != null
                }
            } catch (_: Exception) { /* Steam can recreate CEF while starting or updating. */ }
            main.post {
                if (token != generation || activity.isFinishing) return@post
                panel.visibility = if (authenticated) View.GONE else View.VISIBLE
                button.isEnabled = challengePresent
                status.setText(when {
                    awaitingApproval && challengePresent -> R.string.steam_approve
                    challengePresent -> R.string.steam_sign_in_hint
                    SystemClock.elapsedRealtime() < deadline -> R.string.steam_preparing_sign_in
                    else -> R.string.steam_sign_in_unavailable
                })
                if (authenticated && !online) (activity.application as SteamApplication).library.load(refresh = true)
                online = authenticated
                if (authenticated) awaitingApproval = false
                main.postDelayed(poll, if (authenticated) 5000 else 1000)
            }
        }
    }

    private fun openSteam() {
        // Fetch again on tap: the QR displayed by Steam may have rotated since the last poll.
        button.isEnabled = false
        main.removeCallbacks(poll)
        val token = ++generation
        job = worker.submit {
            val url = try { session.clientBridge?.qrChallenge() } catch (_: Exception) { null }
            main.post {
                if (token != generation || activity.isFinishing) return@post
                if (url == null) {
                    status.setText(R.string.steam_preparing_sign_in)
                    main.postDelayed(poll, 1000)
                    return@post
                }
                try {
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(SteamSignInLink.PACKAGE))
                    awaitingApproval = true
                    status.setText(R.string.steam_approve)
                } catch (_: ActivityNotFoundException) {
                    status.setText(R.string.steam_app_required)
                    // Keep the actionable message until the user retries or leaves this screen.
                    button.isEnabled = true
                }
            }
        }
    }
}
