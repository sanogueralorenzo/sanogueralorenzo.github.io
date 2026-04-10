package com.example.super_overlay.overlay

import android.content.Context

object BubbleOverlayPreferences {
    private const val PREFS_NAME = "bubble_overlay_prefs"
    private const val KEY_ENABLED = "bubble_enabled"
    private const val KEY_X = "bubble_x"
    private const val KEY_Y = "bubble_y"

    private const val DEFAULT_ENABLED = false
    private const val DEFAULT_X = 48
    private const val DEFAULT_Y = 520

    fun isEnabled(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_ENABLED, DEFAULT_ENABLED)
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun getPosition(context: Context): Pair<Int, Int> {
        val prefs = prefs(context)
        return prefs.getInt(KEY_X, DEFAULT_X) to prefs.getInt(KEY_Y, DEFAULT_Y)
    }

    fun setPosition(context: Context, x: Int, y: Int) {
        prefs(context).edit()
            .putInt(KEY_X, x.coerceAtLeast(0))
            .putInt(KEY_Y, y.coerceAtLeast(0))
            .apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
