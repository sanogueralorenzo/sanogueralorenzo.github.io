package com.sanogueralorenzo.overlay

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "black_overlay_prefs")

object OverlayPrefs {
    private val keyTileAdded = booleanPreferencesKey("tile_added")

    private fun prefsFlow(context: Context) = context.dataStore.data.catch {
        emit(emptyPreferences())
    }

    fun tileAddedFlow(context: Context): Flow<Boolean> {
        return prefsFlow(context).map { prefs ->
            prefs[keyTileAdded] ?: false
        }.distinctUntilChanged()
    }

    suspend fun setTileAdded(context: Context, added: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[keyTileAdded] = added
        }
    }
}
