package com.sanogueralorenzo.voice.di

import android.content.Context
import com.sanogueralorenzo.voice.VoiceApp

fun Context.appGraph(): AppGraph {
    return (applicationContext as VoiceApp).appGraph
}
