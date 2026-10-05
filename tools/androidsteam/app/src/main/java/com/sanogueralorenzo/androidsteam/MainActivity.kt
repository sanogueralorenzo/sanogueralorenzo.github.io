package com.sanogueralorenzo.androidsteam

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.text.format.DateUtils
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.BaseAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.ListView
import android.widget.PopupMenu
import android.widget.TextView
import com.sanogueralorenzo.androidsteam.library.GameActivity
import com.sanogueralorenzo.androidsteam.library.LibraryController
import com.sanogueralorenzo.androidsteam.library.LibraryGame
import com.sanogueralorenzo.androidsteam.session.SessionActivity

class MainActivity : Activity() {
    private enum class Tab { LIBRARY, SEARCH, DOWNLOADS }
    private val app get() = application as SteamApplication
    private val observer: (LibraryController.State) -> Unit = { render() }
    private var tab = Tab.LIBRARY
    private var filter = 0
    private var typingLandscape = false
    private val rows = Games()
    private val query get() = findViewById<EditText>(R.id.library_search)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        tab = Tab.entries.getOrElse(savedInstanceState?.getInt("tab") ?: 0) { Tab.LIBRARY }
        filter = (savedInstanceState?.getInt("filter") ?: 0).coerceIn(0, 2)
        findViewById<View>(R.id.library_content).setOnApplyWindowInsetsListener { view, insets ->
            val bars = insets.getInsets(WindowInsets.Type.systemBars())
            val keyboard = insets.getInsets(WindowInsets.Type.ime())
            view.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, keyboard.bottom))
            val compact = keyboard.bottom > 0 && resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
            if (typingLandscape != compact) { typingLandscape = compact; render() }
            insets
        }
        query.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = render()
            override fun afterTextChanged(s: Editable?) = Unit
        })
        query.setOnEditorActionListener { _, _, _ -> hideKeyboard(); true }
        findViewById<ListView>(R.id.library_games).apply {
            adapter = rows
            setOnItemClickListener { _, _, position, _ ->
                hideKeyboard()
                startActivity(Intent(this@MainActivity, GameActivity::class.java).putExtra("appId", rows.games[position].appId))
            }
        }
        listOf(R.id.filter_all, R.id.filter_installed, R.id.filter_recent).forEachIndexed { index, id ->
            findViewById<View>(id).setOnClickListener { filter = index; render() }
        }
        listOf(R.id.tab_library, R.id.tab_search, R.id.tab_downloads).forEachIndexed { index, id ->
            findViewById<View>(id).setOnClickListener { tab = Tab.entries[index]; hideKeyboard(); render() }
        }
        findViewById<View>(R.id.library_refresh).setOnClickListener { app.library.load(refresh = true) }
        findViewById<View>(R.id.open_steam).setOnClickListener { openSteam() }
        findViewById<View>(R.id.profile).setOnClickListener { anchor ->
            PopupMenu(this, anchor).apply {
                menu.add(R.string.open_steam).setOnMenuItemClickListener { openSteam(); true }
                menu.add(R.string.refresh_library).setOnMenuItemClickListener { app.library.load(refresh = true); true }
                menu.add(R.string.setup).setOnMenuItemClickListener { startActivity(Intent(this@MainActivity, SetupActivity::class.java)); true }
                show()
            }
        }
    }
    override fun onStart() { super.onStart(); app.library.observe(observer) }
    override fun onStop() { app.library.removeObserver(observer); super.onStop() }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        tab = Tab.entries.getOrElse(intent.getIntExtra("tab", 0)) { Tab.LIBRARY }
        render()
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("tab", tab.ordinal); outState.putInt("filter", filter)
        super.onSaveInstanceState(outState)
    }
    private fun openSteam() {
        startActivity(SessionActivity.intent(this))
    }
    private fun hideKeyboard() {
        getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(query.windowToken, 0)
        query.clearFocus()
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun render() {
        val state = app.library.state
        val search = tab == Tab.SEARCH
        val compact = search && typingLandscape
        findViewById<View>(R.id.library_header).visibility = if (compact) View.GONE else View.VISIBLE
        findViewById<View>(R.id.library_status).visibility = if (compact) View.GONE else View.VISIBLE
        query.visibility = if (search) View.VISIBLE else View.GONE
        val spacing = dp(if (compact) 0 else 12)
        (query.layoutParams as ViewGroup.MarginLayoutParams).let { params ->
            if (params.bottomMargin != spacing) { params.bottomMargin = spacing; query.layoutParams = params }
        }
        findViewById<View>(R.id.library_navigation).let { navigation ->
            val height = dp(if (compact) 48 else 72)
            if (navigation.layoutParams.height != height) navigation.layoutParams = navigation.layoutParams.apply { this.height = height }
        }
        findViewById<View>(R.id.library_filters).visibility = if (tab == Tab.DOWNLOADS || compact) View.GONE else View.VISIBLE
        findViewById<TextView>(R.id.library_heading).setText(when (tab) { Tab.LIBRARY -> R.string.library; Tab.SEARCH -> R.string.search; Tab.DOWNLOADS -> R.string.downloads })
        listOf(R.id.filter_all, R.id.filter_installed, R.id.filter_recent).forEachIndexed { index, id -> findViewById<View>(id).isSelected = index == filter }
        val icons = intArrayOf(R.drawable.ic_library, R.drawable.ic_search, R.drawable.ic_download)
        listOf(R.id.tab_library, R.id.tab_search, R.id.tab_downloads).forEachIndexed { index, id ->
            val color = getColor(if (index == tab.ordinal) R.color.accent else R.color.secondary)
            findViewById<Button>(id).apply {
                setCompoundDrawablesWithIntrinsicBounds(0, if (compact) 0 else icons[index], 0, 0)
                setTextColor(color); compoundDrawableTintList = ColorStateList.valueOf(color)
            }
        }
        val games = state.snapshot?.games.orEmpty().filter { game ->
            (when { tab == Tab.DOWNLOADS -> game.pending; filter == 1 -> game.installed; filter == 2 -> game.lastPlayed != null; else -> true }) &&
                (!search || game.name.contains(query.text.toString().trim(), ignoreCase = true))
        }.let { if (filter == 2 && tab != Tab.DOWNLOADS) it.sortedByDescending(LibraryGame::lastPlayed) else it }
        rows.games = games
        rows.notifyDataSetChanged()
        findViewById<View>(R.id.library_refresh).isEnabled = !state.loading
        findViewById<TextView>(R.id.library_status).text = when {
            state.loading -> "Reading Steam library…"
            state.error != null -> state.error + (state.snapshot?.let { "\nShowing cached licenses checked ${DateUtils.getRelativeTimeSpanString(it.checked * 1000)}." } ?: "")
            state.snapshot != null -> "${resources.getQuantityString(R.plurals.game_count, games.size, games.size)} · Licenses checked ${DateUtils.getRelativeTimeSpanString(state.snapshot.checked * 1000)}"
            else -> ""
        }
        findViewById<TextView>(R.id.library_message).text = when {
            state.snapshot == null -> state.error ?: "Open Steam to sign in and connect your account."
            tab == Tab.DOWNLOADS -> "No pending game downloads. Steam manages downloads and updates."
            search -> "No matching games in your available library."
            else -> "No games in this view."
        }
        findViewById<View>(R.id.library_empty).visibility = if (games.isEmpty()) View.VISIBLE else View.GONE
        findViewById<View>(R.id.library_games).visibility = if (games.isEmpty()) View.GONE else View.VISIBLE
    }
    private inner class Games : BaseAdapter() {
        var games: List<LibraryGame> = emptyList()
        override fun getCount() = games.size
        override fun getItem(position: Int) = games[position]
        override fun getItemId(position: Int) = games[position].appId.toLong()
        override fun hasStableIds() = true
        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val view = convertView ?: layoutInflater.inflate(R.layout.library_row, parent, false)
            val game = games[position]
            val compact = tab == Tab.SEARCH && typingLandscape
            view.minimumHeight = dp(if (compact) 48 else 88)
            val padding = dp(if (compact) 8 else 12)
            view.setPadding(0, padding, 0, padding)
            view.findViewById<TextView>(R.id.game_name).text = game.name
            view.findViewById<View>(R.id.game_state).visibility = if (compact) View.GONE else View.VISIBLE
            view.findViewById<TextView>(R.id.game_state).text = when {
                game.pending -> if (game.downloadTotal > 0) "Download · ${android.text.format.Formatter.formatShortFileSize(this@MainActivity, game.downloaded)} / ${android.text.format.Formatter.formatShortFileSize(this@MainActivity, game.downloadTotal)}" else "Update pending in Steam"
                game.installed -> "Installed · Launch settings"
                else -> "Available · Not installed"
            }
            view.findViewById<ImageView>(R.id.game_art).let { art ->
                art.visibility = if (compact) View.GONE else View.VISIBLE
                if (!compact) app.artwork.show(art, game)
            }
            return view
        }
    }
}
