package com.sanogueralorenzo.overlay

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "black_overlay_prefs")

object OverlayPrefs {
    private val keyAutoLockMinutes = intPreferencesKey("auto_lock_minutes")
    private val keyTileAdded = booleanPreferencesKey("tile_added")
    private val keyAutoTimeoutTileAdded = booleanPreferencesKey("auto_timeout_tile_added")
    private val keyLongPressDismissEnabled = booleanPreferencesKey("long_press_dismiss_enabled")

    private fun prefsFlow(context: Context) = context.dataStore.data.catch {
        emit(emptyPreferences())
    }

    fun autoLockMinutesFlow(context: Context): Flow<Int> {
        return prefsFlow(context).map { prefs ->
            prefs[keyAutoLockMinutes] ?: 0
        }.distinctUntilChanged()
    }

    fun tileAddedFlow(context: Context): Flow<Boolean> {
        return prefsFlow(context).map { prefs ->
            prefs[keyTileAdded] ?: false
        }.distinctUntilChanged()
    }

    fun autoTimeoutTileAddedFlow(context: Context): Flow<Boolean> {
        return prefsFlow(context).map { prefs ->
            prefs[keyAutoTimeoutTileAdded] ?: false
        }.distinctUntilChanged()
    }

    fun longPressDismissEnabledFlow(context: Context): Flow<Boolean> {
        return prefsFlow(context).map { prefs ->
            prefs[keyLongPressDismissEnabled] ?: false
        }.distinctUntilChanged()
    }

    suspend fun readAutoLockMinutes(context: Context): Int {
        return autoLockMinutesFlow(context).first()
    }

    suspend fun setAutoLockMinutes(context: Context, minutes: Int) {
        context.dataStore.edit { prefs ->
            prefs[keyAutoLockMinutes] = minutes.coerceAtLeast(0)
        }
    }

    suspend fun setTileAdded(context: Context, added: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[keyTileAdded] = added
        }
    }

    suspend fun setAutoTimeoutTileAdded(context: Context, added: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[keyAutoTimeoutTileAdded] = added
        }
    }

    suspend fun setLongPressDismissEnabled(context: Context, enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[keyLongPressDismissEnabled] = enabled
        }
    }
}
