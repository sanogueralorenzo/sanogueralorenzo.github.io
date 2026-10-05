package com.sanogueralorenzo.androidsteam.login

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.*
import com.sanogueralorenzo.androidsteam.DebugSteamApplication
import com.sanogueralorenzo.androidsteam.games.GameProfiles
import com.sanogueralorenzo.androidsteam.games.GameLaunchProfile
import com.sanogueralorenzo.androidsteam.library.SteamLibrary
import com.sanogueralorenzo.androidsteam.session.SessionActivity
import com.sanogueralorenzo.androidsteam.session.SessionController
import com.sanogueralorenzo.androidsteam.session.SessionService
import java.io.File
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** Temporary device-only proof. Preserve the real home and keep the canonical session owner. */
class NativeLoginProofActivity : Activity(), SurfaceHolder.Callback {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val app get() = application as DebugSteamApplication
    private val session get() = app.session
    private lateinit var isolated: Context
    private lateinit var surface: SurfaceView
    private lateinit var status: TextView
    private lateinit var account: EditText
    private lateinit var password: EditText
    private lateinit var code: EditText
    private lateinit var signIn: Button
    private lateinit var submitCode: Button
    private lateinit var play: Button
    private lateinit var restart: Button
    private var guard: CompletableFuture<String>? = null
    private var job: Future<*>? = null
    private var started = false
    private var closed = false
    @Volatile private var nativeTokens: SteamTokens? = null
    private val gameObserver: (Int?) -> Unit = { if (it == 732430) mark("GAME_LAUNCHED", "Owned Superflight is running.") }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        isolated = proofContext(this)
        check(File(isolated.filesDir, "proof-prepared").isFile) { "Prepare the isolated proof first." }
        check(session.state == SessionController.State.Idle)
        app.openProof(isolated)
        session.observeGame(gameObserver)
        val frame = FrameLayout(this)
        surface = SurfaceView(this).apply { holder.setFixedSize(1280, 720); holder.addCallback(this@NativeLoginProofActivity) }
        frame.addView(surface, FrameLayout.LayoutParams(-1, -1))
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 60, 32, 40); setBackgroundColor(0xff14191f.toInt())
        }
        fun label(text: String) = TextView(this).apply { this.text = text; textSize = 20f; panel.addView(this) }
        label("Native Steam sign-in test")
        status = label("Preparing the private Linux client…")
        account = input(panel, "Steam account name", InputType.TYPE_CLASS_TEXT)
        password = input(panel, "Password", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        signIn = button(panel, "Sign in") { authenticate() }.apply { isEnabled = false }
        code = input(panel, "Steam Guard code", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD).apply { visibility = View.GONE }
        submitCode = button(panel, "Send code") {
            val response = guard ?: return@button
            val value = code.text.toString().trim()
            code.text.clear(); guard = null; code.visibility = View.GONE; submitCode.visibility = View.GONE
            response.complete(value)
        }.apply { visibility = View.GONE }
        play = button(panel, "Play Superflight") {
            session.requestGame(732430, false)
            startActivity(Intent(this, SessionActivity::class.java).putExtra("appId", 732430))
        }.apply { isEnabled = false }
        restart = button(panel, "Verify session after restart") { verifyRestart() }.apply { isEnabled = false }
        button(panel, "Close test") { closeProof() }
        val scroll = ScrollView(this).apply { addView(panel) }
        frame.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        setContentView(frame)
        onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT) { closeProof() }
    }

    private fun input(panel: LinearLayout, hint: String, type: Int) = EditText(this).apply {
        this.hint = hint; inputType = type; isSingleLine = true; isSaveEnabled = false
        importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
        imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        panel.addView(this, LinearLayout.LayoutParams(-1, -2))
    }
    private fun button(panel: LinearLayout, text: String, action: () -> Unit) = Button(this).apply {
        this.text = text; setOnClickListener { action() }; panel.addView(this, LinearLayout.LayoutParams(-1, -2))
    }

    override fun surfaceCreated(holder: SurfaceHolder) = Unit
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (started) { session.attach(holder.surface); return }
        started = true
        mark("PREPARING", "Preparing the private Linux client. Steam may update itself first…")
        startRuntime()
        job = worker.submit {
            try {
                val bridge = awaitBridge()
                check(bridge.isSignedOut())
                mark("READY", "Enter your Steam account and password. Your existing login is preserved.")
                nativeTokens = TokenVault(isolated).read()
                main.post {
                    signIn.text = if (nativeTokens == null) "Sign in" else "Retry Linux sign-in"
                    signIn.isEnabled = true
                    if (nativeTokens != null) { account.visibility = View.GONE; password.visibility = View.GONE }
                }
            } catch (_: Exception) { mark("FAILED_PREPARATION", "Private Steam startup failed. Close the test and retry.") }
        }
    }
    override fun surfaceDestroyed(holder: SurfaceHolder) { session.detach(holder.surface) }
    private fun startRuntime() {
        session.start(surface.holder.surface, 1280, 720, 60_000)
        startForegroundService(Intent(this, SessionService::class.java))
    }

    private fun authenticate() {
        nativeTokens?.let { tokens ->
            signIn.isEnabled = false
            job = worker.submit { completeHandoff(tokens) }
            return
        }
        val name = account.text.toString().trim()
        val secret = CharArray(password.length()) { password.text[it] }
        password.text.clear()
        if (name.isEmpty() || secret.isEmpty()) { secret.fill('\u0000'); status.text = "Enter your account name and password."; return }
        signIn.isEnabled = false
        account.visibility = View.GONE; password.visibility = View.GONE
        job = worker.submit {
            var phase = "FAILED_NATIVE"
            try {
                val tokens = NativeSteamAuth().authenticate(name, secret, { type, incorrect ->
                    val response = CompletableFuture<String>()
                    main.post {
                        if (closed || response.isDone) return@post
                        guard = response
                        status.text = if (type == NativeSteamAuth.Guard.APPROVAL) "Approve Android Steam in the Steam app, or enter an authenticator code below."
                            else if (incorrect) "That code was rejected. Enter a new Steam Guard code."
                            else "Enter the Steam Guard ${if (type == NativeSteamAuth.Guard.EMAIL_CODE) "email" else "authenticator"} code."
                        code.visibility = View.VISIBLE; submitCode.visibility = View.VISIBLE
                    }
                    response
                }, { message -> main.post { status.text = message } })
                phase = "FAILED_STORAGE"
                TokenVault(isolated).save(tokens)
                nativeTokens = tokens
                main.post { clearGuard() }
                completeHandoff(tokens)
            } catch (_: Exception) {
                mark(phase, if (phase == "FAILED_STORAGE") "Native authentication succeeded, but its token could not be saved securely."
                    else "Native Steam sign-in did not complete. Enter your password and retry.")
            } finally {
                secret.fill('\u0000')
                main.post {
                    clearGuard()
                    if (nativeTokens == null && !closed) {
                        account.visibility = View.VISIBLE; password.visibility = View.VISIBLE; signIn.isEnabled = true
                    }
                }
            }
        }
    }

    private fun clearGuard() {
        guard?.cancel(true); guard = null; code.text.clear()
        code.visibility = View.GONE; submitCode.visibility = View.GONE
        code.clearFocus()
        getSystemService(android.view.inputmethod.InputMethodManager::class.java)
            .hideSoftInputFromWindow(code.windowToken, 0)
    }

    private fun completeHandoff(tokens: SteamTokens) {
        var phase = "FAILED_HANDOFF_INTERFACE"
        try {
            mark("NATIVE_AUTHENTICATED", "Native Android authentication succeeded. Signing the Linux client in…")
            val bridge = awaitBridge()
            // Retry may already have authenticated the expected account. Never accept a different account.
            if (!bridge.isAuthenticated(tokens.steamId)) {
                phase = "FAILED_HANDOFF_PRECONDITION"
                check(bridge.isSignedOut())
                phase = "FAILED_HANDOFF_REQUEST"
                check(bridge.signIn(tokens))
            }
            mark("HANDOFF_ACCEPTED", "Linux accepted the sign-in request. Verifying the online session…")
            phase = "FAILED_LINUX_ONLINE"
            awaitAuthenticated(bridge, tokens.steamId)
            phase = "FAILED_LICENSES"
            verifyOwnership(tokens)
            GameProfiles(isolated).save(732430, GameLaunchProfile("androidsteam-proton",
                listOf("-force-d3d11", "-screen-width", "1280", "-screen-height", "720", "-screen-fullscreen", "1"), emptyMap()))
            mark("LINUX_AUTHENTICATED", "Linux is online and Superflight ownership is verified. Play, then verify restart.")
            main.post { play.isEnabled = true; restart.isEnabled = true }
        } catch (_: Exception) {
            mark(phase, "Native authentication succeeded. Linux sign-in is not verified ($phase). Retry Linux sign-in or close the test.")
            main.post { if (!closed) { signIn.text = "Retry Linux sign-in"; signIn.isEnabled = true } }
        }
    }

    private fun verifyRestart() {
        if (session.gameAppId != null) { status.text = "Close the game before verifying restart."; return }
        play.isEnabled = false; restart.isEnabled = false
        mark("RESTARTING", "Restarting Linux Steam without another login…")
        session.stop()
        job = worker.submit {
            try {
                awaitIdle()
                main.post { startRuntime() }
                val tokens = checkNotNull(TokenVault(isolated).read())
                awaitAuthenticated(awaitBridge(), tokens.steamId)
                verifyOwnership(tokens)
                mark("RESTART_AUTHENTICATED", "The restarted Linux client is online and owns Superflight without another login.")
                main.post { play.isEnabled = true; restart.isEnabled = true }
            } catch (_: Exception) { mark("FAILED_RESTART", "Linux did not restore the authenticated session after restart.") }
        }
    }

    private fun verifyOwnership(tokens: SteamTokens) {
        val snapshot = SteamLibrary(isolated).refresh()
        check(snapshot.account == (tokens.steamId.toLong() and 0xffffffffL).toString())
        check(snapshot.games.any { it.appId == 732430 })
    }

    private fun awaitBridge(): SteamClientBridge {
        val deadline = System.currentTimeMillis() + 600_000
        while (System.currentTimeMillis() < deadline) {
            check(!closed && session.state !is SessionController.State.Failed)
            session.clientBridge?.let {
                try { if (it.hasAuthenticationInterface() && session.state == SessionController.State.Running) return it }
                catch (_: IllegalStateException) {
                    // Fresh Steam can update before CEF exists; retry while the owned client is alive.
                    check(!closed && session.state !is SessionController.State.Failed && session.state != SessionController.State.Idle)
                }
            }
            Thread.sleep(250)
        }
        error("Private client interface timed out")
    }
    private fun awaitAuthenticated(bridge: SteamClientBridge, id: String) {
        val deadline = System.currentTimeMillis() + 90_000
        while (System.currentTimeMillis() < deadline) {
            if (bridge.isAuthenticated(id)) return
            Thread.sleep(500)
        }
        error("Linux authentication was not established")
    }
    private fun awaitIdle() {
        val deadline = System.currentTimeMillis() + 20_000
        while (session.state != SessionController.State.Idle && System.currentTimeMillis() < deadline) Thread.sleep(50)
        check(session.state == SessionController.State.Idle)
    }
    private fun mark(stage: String, message: String) {
        File(isolated.cacheDir, "proof-status").writeText(stage)
        main.post { if (!closed) status.text = message }
    }
    internal fun closeProof() {
        if (closed) return
        closed = true; guard?.cancel(true); job?.cancel(true); password.text.clear(); code.text.clear()
        session.stop()
        worker.execute {
            try { awaitIdle() } finally { main.post {
                session.removeGameObserver(gameObserver)
                app.closeProof()
                finish(); worker.shutdown()
            } }
        }
    }

    companion object {
        internal fun proofContext(context: Context): Context {
            val root = File(context.filesDir, "native-auth-proof")
            return object : ContextWrapper(context) {
                override fun getFilesDir() = File(root, "files").apply { mkdirs() }
                override fun getCacheDir() = File(root, "cache").apply { mkdirs() }
                override fun getNoBackupFilesDir() = File(context.noBackupFilesDir, "native-auth-proof").apply { mkdirs() }
                override fun getSharedPreferences(name: String, mode: Int): SharedPreferences = context.getSharedPreferences("native-auth-proof-$name", mode)
            }
        }
    }
}
