package com.sanogueralorenzo.overlay.tiles

import android.app.StatusBarManager
import android.content.ComponentName
import android.graphics.drawable.Icon
import androidx.activity.ComponentActivity

fun ComponentActivity.requestQuickSettingsTile(
    component: ComponentName,
    label: String,
    iconRes: Int,
    onAdded: () -> Unit
) {
    val statusBarManager = getSystemService(StatusBarManager::class.java) ?: return
    val icon = Icon.createWithResource(this, iconRes)
    statusBarManager.requestAddTileService(
        component,
        label,
        icon,
        mainExecutor
    ) { result ->
        if (isTileAddedResult(result)) {
            onAdded()
        }
    }
}

private fun isTileAddedResult(result: Int): Boolean {
    return result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
        result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
}
