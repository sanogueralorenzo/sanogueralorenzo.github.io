package com.sanogueralorenzo.androidsteam.input

import android.content.Context

internal enum class TouchKey(val label: String, val code: Int) {
    P("P", 25), R("R", 19), CTRL("Ctrl", 29), SHIFT("Shift", 42), C("C", 46), X("X", 45);
    companion object {
        fun load(context: Context, appId: Int): List<TouchKey> = context.getSharedPreferences("controls", Context.MODE_PRIVATE)
            .getString("keys:$appId", "").orEmpty().split(',').mapNotNull { name -> entries.find { it.name == name } }.distinct().take(4)
        fun save(context: Context, appId: Int, keys: List<TouchKey>) {
            require(appId > 0 && keys.size <= 4 && keys.distinct().size == keys.size)
            context.getSharedPreferences("controls", Context.MODE_PRIVATE).edit().putString("keys:$appId", keys.joinToString(",") { it.name }).apply()
        }
    }
}

internal enum class ControlProfile(val label: String, private val directions: IntArray) {
    XBOX("Xbox controller", intArrayOf()),
    TOUCH("Direct touch", intArrayOf(105, 106, 103, 108)),
    ARROWS("Arrow keys", intArrayOf(105, 106, 103, 108)),
    WASD("WASD", intArrayOf(30, 32, 17, 31));

    fun movement(x: Float, y: Float): Set<Int> = buildSet {
        if (directions.isEmpty()) return@buildSet
        if (x < -.35f) add(directions[0])
        if (x > .35f) add(directions[1])
        if (y < -.35f) add(directions[2])
        if (y > .35f) add(directions[3])
    }

    companion object {
        fun load(context: Context, appId: Int): ControlProfile =
            entries.firstOrNull { it.name == context.getSharedPreferences("controls", Context.MODE_PRIVATE).getString(appId.toString(), null) } ?: XBOX

        fun save(context: Context, appId: Int, profile: ControlProfile) {
            require(appId > 0)
            context.getSharedPreferences("controls", Context.MODE_PRIVATE).edit().putString(appId.toString(), profile.name).apply()
        }
    }
}
