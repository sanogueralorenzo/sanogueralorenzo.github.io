package com.sanogueralorenzo.amarchy.desktop

import android.content.Context
import android.content.ClipboardManager
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ProgressBar
import android.widget.TextView
import com.sanogueralorenzo.amarchy.session.Phase
import com.sanogueralorenzo.amarchy.session.WorkspaceController
import com.sanogueralorenzo.amarchy.session.WorkspaceState

internal class DesktopScreen(context: Context, private val workspace: WorkspaceController, home: () -> Unit) : LinearLayout(context), SurfaceHolder.Callback {
    val surface = DesktopSurface(context, workspace)
    private val loading = LinearLayout(context).apply {
        orientation = VERTICAL; gravity = Gravity.CENTER; setBackgroundColor(Color.rgb(16, 20, 17))
        addView(ProgressBar(context), LayoutParams(dp(40), dp(40)))
        addView(TextView(context).apply { text = "Opening your desktop…"; textSize = 16f; gravity = Gravity.CENTER; setTextColor(Color.rgb(184, 238, 162)); setPadding(0, dp(18), 0, 0) })
    }
    private val toolbar = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; setBackgroundColor(Color.rgb(20, 27, 21)); setPadding(dp(8), 0, dp(8), 0) }
    init {
        orientation = VERTICAL; setBackgroundColor(Color.BLACK)
        val frame = FrameLayout(context)
        frame.addView(surface, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
        frame.addView(loading, FrameLayout.LayoutParams(-1, -1))
        addView(frame, LayoutParams(-1, 0, 1f)); addView(toolbar, LayoutParams(-1, dp(52)))
        toolbar.addView(action("Home") { hideKeyboard(); home() })
        toolbar.addView(action("Apps") { anchor -> apps(anchor) })
        toolbar.addView(TextView(context).apply {
            text = "amarchy"; setTextColor(Color.rgb(184, 238, 162)); textSize = 15f; gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        }, LayoutParams(0, -1, 1f))
        toolbar.addView(action("Keyboard") { surface.requestFocus(); context.getSystemService(InputMethodManager::class.java).showSoftInput(surface, InputMethodManager.SHOW_IMPLICIT) })
        toolbar.addView(action("Keys") { anchor -> shortcuts(anchor) })
        surface.holder.addCallback(this)
        setOnApplyWindowInsetsListener { _, insets ->
            val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            val keyboard = insets.getInsets(WindowInsets.Type.ime())
            setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, keyboard.bottom)); insets
        }
    }
    fun render(state: WorkspaceState) {
        loading.visibility = if (state.phase == Phase.RUNNING) GONE else VISIBLE
        for (index in 0 until toolbar.childCount) {
            val child = toolbar.getChildAt(index)
            child.isEnabled = state.phase == Phase.RUNNING
            child.alpha = if (state.phase == Phase.RUNNING) 1f else 0.5f
        }
    }
    fun hideKeyboard() { context.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(surface.windowToken, 0) }
    override fun surfaceCreated(holder: SurfaceHolder) = Unit
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { workspace.attach(holder.surface) }
    override fun surfaceDestroyed(holder: SurfaceHolder) { workspace.attach(null) }
    private fun action(label: String, click: (Button) -> Unit) = Button(context).apply {
        text = label; isAllCaps = false; textSize = 13f; setTextColor(Color.rgb(210, 223, 204)); setBackgroundColor(Color.TRANSPARENT)
        minHeight = dp(48); minimumWidth = dp(56); setPadding(dp(12), 0, dp(12), 0); setOnClickListener { click(this) }
        contentDescription = label
    }
    private fun apps(anchor: Button) {
        val entries = linkedMapOf("Terminal" to "foot", "Files" to "nautilus --new-window /root", "Editor" to "foot --app-id=amarchy-editor --title=Neovim nvim", "Browser" to "chromium --ozone-platform=wayland --no-sandbox --disable-gpu --no-first-run --no-default-browser-check")
        PopupMenu(context, anchor).apply {
            entries.keys.forEachIndexed { index, name -> menu.add(0, index, index, name) }
            setOnMenuItemClickListener { item -> workspace.launch(entries.values.elementAt(item.itemId)); surface.requestFocus(); true }
            show()
        }
    }
    private fun shortcuts(anchor: Button) {
        val entries = linkedMapOf("Escape" to intArrayOf(1), "Tab" to intArrayOf(15), "Ctrl+C" to intArrayOf(29, 46),
            "New terminal" to intArrayOf(125, 28), "Close window" to intArrayOf(125, 16),
            "Workspace 1" to intArrayOf(125, 2), "Workspace 2" to intArrayOf(125, 3))
        PopupMenu(context, anchor).apply {
            entries.keys.forEachIndexed { index, name -> menu.add(0, index, index, name) }
            menu.add(0, 99, 99, "Paste from Android")
            menu.add(0, 100, 100, "Close desktop")
            setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    100 -> workspace.stop()
                    99 -> workspace.type(context.getSystemService(ClipboardManager::class.java).primaryClip?.getItemAt(0)?.text?.toString().orEmpty())
                    else -> workspace.shortcut(*entries.values.elementAt(item.itemId))
                }
                surface.requestFocus(); true
            }
            show()
        }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()
}
