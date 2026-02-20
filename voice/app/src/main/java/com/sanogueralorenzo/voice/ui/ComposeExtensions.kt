package com.sanogueralorenzo.voice.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

@Composable
private fun OnLifecycleEvents(
    events: Set<Lifecycle.Event>,
    onEvent: () -> Unit
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestOnEvent by rememberUpdatedState(onEvent)

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event in events) {
                latestOnEvent()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
}

@Composable
fun OnResume(onResume: () -> Unit) {
    OnLifecycleEvents(
        events = setOf(Lifecycle.Event.ON_RESUME),
        onEvent = onResume
    )
}

@Composable
fun OnStartOrResume(onStartOrResume: () -> Unit) {
    OnLifecycleEvents(
        events = setOf(Lifecycle.Event.ON_START, Lifecycle.Event.ON_RESUME),
        onEvent = onStartOrResume
    )
}
