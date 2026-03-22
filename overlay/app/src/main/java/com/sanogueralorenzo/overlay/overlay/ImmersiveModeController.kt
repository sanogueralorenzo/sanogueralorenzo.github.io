package com.sanogueralorenzo.overlay.overlay

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.core.content.ContextCompat

private const val POLICY_CONTROL_KEY = "policy_control"
private const val IMMERSIVE_STATUS_POLICY = "immersive.status=*"

/**
 * Thin controller around `Settings.Global.policy_control` for toggling status-bar immersive policy.
 *
 * Behavior contract:
 * - Writes only to `Settings.Global[policy_control]`.
 * - Mutates only the `immersive.status=*` token and preserves any unrelated policy tokens.
 * - Performs no writes when `android.permission.WRITE_SECURE_SETTINGS` is not granted.
 * - All public operations are idempotent.
 *
 * Runtime expectations:
 * - Caller is responsible for lifecycle timing (typically enable on overlay start, disable on stop).
 * - Permission is commonly granted via ADB (`pm grant ... WRITE_SECURE_SETTINGS`).
 *
 * Failure model:
 * - Missing permission is treated as a no-op.
 * - Invalid/blank `policy_control` input is normalized to an empty token list.
 */
class ImmersiveModeController(
    private val context: Context
) {
    /**
     * Ensures `immersive.status=*` is present in the policy token set.
     *
     * Side effects:
     * - May write a comma-separated token string back to `Settings.Global[policy_control]`.
     * - Does nothing when write-secure-settings permission is absent.
     */
    fun enableStatusBarImmersiveMode() {
        updatePolicyControl { policies ->
            if (IMMERSIVE_STATUS_POLICY in policies) {
                policies
            } else {
                policies + IMMERSIVE_STATUS_POLICY
            }
        }
    }

    /**
     * Ensures `immersive.status=*` is removed from the policy token set.
     *
     * Side effects:
     * - May clear `Settings.Global[policy_control]` by writing `null` when no tokens remain.
     * - Does nothing when write-secure-settings permission is absent.
     */
    fun disableStatusBarImmersiveMode() {
        updatePolicyControl { policies ->
            policies.filterNot { policy -> policy == IMMERSIVE_STATUS_POLICY }
        }
    }

    /**
     * Canonical read-transform-write path for policy token updates.
     *
     * Algorithm:
     * 1. Gate on permission.
     * 2. Read and parse current token set.
     * 3. Apply caller transform.
     * 4. Serialize to comma-separated string or `null` when empty.
     * 5. Persist via `Settings.Global.putString`.
     */
    private fun updatePolicyControl(transform: (List<String>) -> List<String>) {
        if (!hasWriteSecureSettingsPermission()) {
            return
        }
        val resolver = context.contentResolver
        val currentPolicies = readPolicies(resolver)
        val updatedPolicies = transform(currentPolicies)
        val updatedValue = updatedPolicies.takeIf { it.isNotEmpty() }?.joinToString(",")
        Settings.Global.putString(resolver, POLICY_CONTROL_KEY, updatedValue)
    }

    /**
     * Returns true when process has `android.permission.WRITE_SECURE_SETTINGS`.
     */
    private fun hasWriteSecureSettingsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_SECURE_SETTINGS
        ) == PackageManager.PERMISSION_GRANTED
    }
}

/**
 * Parses `Settings.Global[policy_control]` into normalized non-empty trimmed tokens.
 */
private fun readPolicies(contentResolver: ContentResolver): List<String> {
    val rawValue = Settings.Global.getString(contentResolver, POLICY_CONTROL_KEY)
    if (rawValue.isNullOrBlank()) {
        return emptyList()
    }
    return rawValue
        .split(',')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
}
