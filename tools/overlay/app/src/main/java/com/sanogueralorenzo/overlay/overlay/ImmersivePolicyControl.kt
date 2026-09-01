package com.sanogueralorenzo.overlay.overlay

private const val IMMERSIVE_STATUS_POLICY = "immersive.status=*"

internal fun enableImmersiveStatusPolicy(rawValue: String?): String {
    val policies = parsePolicies(rawValue)
    return (policies + IMMERSIVE_STATUS_POLICY).distinct().joinToString(",")
}

internal fun disableImmersiveStatusPolicy(rawValue: String?): String? {
    return parsePolicies(rawValue)
        .filterNot { policy -> policy == IMMERSIVE_STATUS_POLICY }
        .takeIf { policies -> policies.isNotEmpty() }
        ?.joinToString(",")
}

private fun parsePolicies(rawValue: String?): List<String> {
    return rawValue
        ?.split(',')
        ?.map { policy -> policy.trim() }
        ?.filter { policy -> policy.isNotEmpty() }
        ?.distinct()
        .orEmpty()
}
