package com.sanogueralorenzo.voice.models

import com.sanogueralorenzo.voice.BuildConfig

/**
 * Resolves candidate download URLs for a model.
 *
 * Strategy:
 * 1) Optional public mirror base URL (non-gated path).
 * 2) Canonical URL from [ModelSpec] as fallback.
 */
object ModelUrlResolver {
    fun candidateUrls(spec: ModelSpec): List<String> {
        val ordered = LinkedHashSet<String>()
        val mirrorConfig = BuildConfig.MODEL_MIRROR_BASE_URL.trim()
        if (mirrorConfig.isNotBlank() && shouldUseMirror(spec)) {
            if (mirrorConfig.endsWith(".litertlm", ignoreCase = true)) {
                // Treat mirror config as a direct file URL.
                ordered += mirrorConfig
            } else {
                val mirrorBase = mirrorConfig.trimEnd('/')
                ordered += "$mirrorBase/${spec.subdir}/${spec.fileName}"
            }
        }
        if (spec.url.isNotBlank()) {
            ordered += spec.url
        }
        return ordered.toList()
    }

    private fun shouldUseMirror(spec: ModelSpec): Boolean {
        return spec.fileName.endsWith(".litertlm", ignoreCase = true) ||
            spec.subdir.contains("litertlm", ignoreCase = true)
    }
}
