package com.sanogueralorenzo.voice.summary

import android.os.Build
import com.google.ai.edge.litertlm.Backend

enum class LiteRtBackendPolicy {
    AUTO
}

/**
 * Backend policy holder.
 *
 * Current behavior is fixed to AUTO as requested.
 */
class LiteRtBackendPolicyStore {
    private val isEmulatorDevice: Boolean = isEmulator()

    fun currentPolicy(modelSha: String): LiteRtBackendPolicy {
        return LiteRtBackendPolicy.AUTO
    }

    fun preferredBackends(modelSha: String): List<Backend> {
        return if (isEmulatorDevice) {
            listOf(Backend.CPU, Backend.GPU)
        } else {
            listOf(Backend.GPU, Backend.CPU)
        }
    }

    fun markGpuFailed(modelSha: String) {
        // Intentionally no-op while policy is fixed to AUTO.
    }

    fun clearPolicy(modelSha: String) {
        // Intentionally no-op while policy is fixed to AUTO.
    }

    private fun isEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.orEmpty()
        val model = Build.MODEL.orEmpty()
        val hardware = Build.HARDWARE.orEmpty()
        val product = Build.PRODUCT.orEmpty()
        val manufacturer = Build.MANUFACTURER.orEmpty()
        return fingerprint.startsWith("generic", ignoreCase = true) ||
            fingerprint.contains("emulator", ignoreCase = true) ||
            model.contains("sdk_gphone", ignoreCase = true) ||
            model.contains("emulator", ignoreCase = true) ||
            hardware.contains("goldfish", ignoreCase = true) ||
            hardware.contains("ranchu", ignoreCase = true) ||
            product.contains("sdk", ignoreCase = true) ||
            manufacturer.contains("genymotion", ignoreCase = true)
    }
}
