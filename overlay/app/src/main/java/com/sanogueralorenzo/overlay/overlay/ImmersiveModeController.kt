package com.sanogueralorenzo.overlay.overlay

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.core.content.ContextCompat

private const val POLICY_CONTROL_KEY = "policy_control"
private const val IMMERSIVE_STATUS_POLICY = "immersive.status=*"

class ImmersiveModeController(
    private val context: Context
) {
    fun enableStatusBarImmersiveMode() {
        updatePolicyControl { policies ->
            if (IMMERSIVE_STATUS_POLICY in policies) {
                policies
            } else {
                policies + IMMERSIVE_STATUS_POLICY
            }
        }
    }

    fun disableStatusBarImmersiveMode() {
        updatePolicyControl { policies ->
            policies.filterNot { policy -> policy == IMMERSIVE_STATUS_POLICY }
        }
    }

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

    private fun hasWriteSecureSettingsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_SECURE_SETTINGS
        ) == PackageManager.PERMISSION_GRANTED
    }
}

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
