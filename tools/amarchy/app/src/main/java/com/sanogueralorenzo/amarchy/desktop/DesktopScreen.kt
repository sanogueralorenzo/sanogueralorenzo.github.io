package com.sanogueralorenzo.amarchy.desktop

import android.content.Context
import android.content.ClipboardManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.RippleDrawable
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
import android.widget.Toast
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
    private var keyboardVisible = false
    private var lastDetail = ""
    private val keyboardButton = action("Keyboard") {
        if (keyboardVisible) hideKeyboard() else {
            surface.requestFocus()
            context.getSystemService(InputMethodManager::class.java).showSoftInput(surface, InputMethodManager.SHOW_IMPLICIT)
        }
    }
    init {
        orientation = VERTICAL; setBackgroundColor(Color.BLACK)
        val frame = FrameLayout(context)
        frame.addView(surface, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
        frame.addView(loading, FrameLayout.LayoutParams(-1, -1))
        addView(frame, LayoutParams(-1, 0, 1f)); addView(toolbar, LayoutParams(-1, dp(52)))
        toolbar.addView(action("Home") { hideKeyboard(); home() })
        toolbar.addView(action("Apps") { workspace.launch("omarchy-menu toggle apps"); surface.requestFocus() })
        toolbar.addView(action("Omarchy") { workspace.launch("omarchy-menu"); surface.requestFocus() }, LayoutParams(0, -1, 1f))
        toolbar.addView(keyboardButton)
        toolbar.addView(action("Keys") { anchor -> shortcuts(anchor) })
        surface.holder.addCallback(this)
        setOnApplyWindowInsetsListener { _, insets ->
            val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            val keyboard = insets.getInsets(WindowInsets.Type.ime())
            keyboardVisible = insets.isVisible(WindowInsets.Type.ime())
            keyboardButton.text = if (keyboardVisible) "Hide keyboard" else "Keyboard"
            keyboardButton.contentDescription = keyboardButton.text
            setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, keyboard.bottom)); insets
        }
    }
    fun render(state: WorkspaceState) {
        if (state.phase == Phase.RUNNING && state.detail != lastDetail && state.detail != "Your desktop is open") {
            Toast.makeText(context, state.detail, Toast.LENGTH_SHORT).show()
            announceForAccessibility(state.detail)
        }
        lastDetail = state.detail
        loading.visibility = if (state.phase == Phase.RUNNING) GONE else VISIBLE
        for (index in 0 until toolbar.childCount) {
            val child = toolbar.getChildAt(index)
            child.isEnabled = state.phase == Phase.RUNNING
            child.alpha = if (state.phase == Phase.RUNNING) 1f else 0.5f
        }
    }
    fun hideKeyboard() { context.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(surface.windowToken, 0) }
    override fun surfaceCreated(holder: SurfaceHolder) = Unit
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        workspace.attach(holder.surface, surface.bufferWidth, surface.bufferHeight)
    }
    override fun surfaceDestroyed(holder: SurfaceHolder) { workspace.attach(null) }
    private fun action(label: String, click: (Button) -> Unit) = Button(context).apply {
        text = label; isAllCaps = false; textSize = 13f; setTextColor(Color.rgb(210, 223, 204))
        background = RippleDrawable(ColorStateList.valueOf(Color.rgb(57, 73, 52)), null, null)
        minHeight = dp(48); minimumWidth = dp(56); setPadding(dp(12), 0, dp(12), 0); setOnClickListener { click(this) }
        contentDescription = label
    }
    private fun shortcuts(anchor: Button) {
        val entries = linkedMapOf("Escape" to intArrayOf(1), "Tab" to intArrayOf(15), "Ctrl+C" to intArrayOf(29, 46),
            "Enter" to intArrayOf(28), "Arrow up" to intArrayOf(103), "Arrow down" to intArrayOf(108),
            "Next window" to intArrayOf(56, 15), "Full screen / tiled" to intArrayOf(125, 33),
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
