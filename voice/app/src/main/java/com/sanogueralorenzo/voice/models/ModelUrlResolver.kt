package com.sanogueralorenzo.voice.models

/**
 * Resolves candidate download URLs for a model.
 *
 * Strategy:
 * 1) Canonical URL from [ModelSpec].
 */
object ModelUrlResolver {
    fun candidateUrls(spec: ModelSpec): List<String> {
        if (spec.url.isBlank()) return emptyList()
        return listOf(spec.url)
    }
}
