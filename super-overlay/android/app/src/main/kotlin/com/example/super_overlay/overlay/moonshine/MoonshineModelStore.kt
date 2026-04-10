package com.example.super_overlay.overlay.moonshine

import android.content.Context
import java.io.File

object MoonshineModelStore {
    fun modelDirectory(context: Context): File {
        return File(context.filesDir, "models/moonshine/medium-streaming-en")
    }

    fun modelFile(context: Context, spec: MoonshineModelSpec): File {
        return File(context.filesDir, "models/${spec.subdir}/${spec.fileName}")
    }

    fun isModelPresent(context: Context, spec: MoonshineModelSpec): Boolean {
        val file = modelFile(context, spec)
        if (!file.exists()) {
            return false
        }
        return spec.sizeBytes <= 0L || file.length() == spec.sizeBytes
    }

    fun areAllModelsPresent(context: Context): Boolean {
        return MoonshineModelCatalog.mediumStreamingSpecs.all { spec ->
            isModelPresent(context, spec)
        }
    }
}
