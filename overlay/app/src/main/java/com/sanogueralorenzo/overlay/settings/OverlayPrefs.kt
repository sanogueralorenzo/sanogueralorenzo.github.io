package com.sanogueralorenzo.overlay.settings

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStore
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "overlay_prefs")

@Inject
@SingleIn(AppScope::class)
class OverlayPrefs(context: Context) {
    private val appContext = context.applicationContext
    private val keyTileAdded = booleanPreferencesKey("tile_added")

    private fun prefsFlow() = appContext.dataStore.data.catch {
        emit(emptyPreferences())
    }

    fun tileAddedFlow(): Flow<Boolean> {
        return prefsFlow().map { prefs ->
            prefs[keyTileAdded] ?: false
        }.distinctUntilChanged()
    }

    suspend fun setTileAdded(added: Boolean) {
        appContext.dataStore.edit { prefs ->
            prefs[keyTileAdded] = added
        }
    }
}
