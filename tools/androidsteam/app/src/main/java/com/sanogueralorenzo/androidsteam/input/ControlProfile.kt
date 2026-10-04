package com.sanogueralorenzo.androidsteam.input

import android.content.Context

internal enum class ControlProfile(val label: String, private val directions: IntArray) {
    TOUCH("Direct touch", intArrayOf(105, 106, 103, 108)),
    ARROWS("Arrow keys", intArrayOf(105, 106, 103, 108)),
    WASD("WASD", intArrayOf(30, 32, 17, 31));

    fun movement(x: Float, y: Float): Set<Int> = buildSet {
        if (x < -.35f) add(directions[0])
        if (x > .35f) add(directions[1])
        if (y < -.35f) add(directions[2])
        if (y > .35f) add(directions[3])
    }

    companion object {
        fun load(context: Context, appId: Int): ControlProfile =
            entries.firstOrNull { it.name == context.getSharedPreferences("controls", Context.MODE_PRIVATE).getString(appId.toString(), null) } ?: TOUCH

        fun save(context: Context, appId: Int, profile: ControlProfile) {
            require(appId > 0)
            context.getSharedPreferences("controls", Context.MODE_PRIVATE).edit().putString(appId.toString(), profile.name).apply()
        }
    }
}
