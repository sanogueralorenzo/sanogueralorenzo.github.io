package com.sanogueralorenzo.voice.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

@Composable
fun OnLifecycle(
    vararg events: Lifecycle.Event,
    onEvent: () -> Unit
) {
    require(events.isNotEmpty()) { "OnLifecycle requires at least one event" }

    val lifecycleOwner = LocalLifecycleOwner.current
    val latestOnEvent by rememberUpdatedState(onEvent)
    val eventSet = remember(*events) { events.toSet() }

    DisposableEffect(lifecycleOwner, eventSet) {
        val observer = LifecycleEventObserver { _, event ->
            if (event in eventSet) {
                latestOnEvent()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
}
