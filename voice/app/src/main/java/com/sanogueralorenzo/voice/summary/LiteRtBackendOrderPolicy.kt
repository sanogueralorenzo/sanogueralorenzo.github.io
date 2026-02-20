package com.sanogueralorenzo.voice.summary

import android.os.Build
import com.google.ai.edge.litertlm.Backend

/**
 * Chooses backend order for LiteRT engine initialization.
 *
 * Possible outcomes:
 * - Emulator-like device: `[CPU, GPU]`.
 * - Physical device: `[GPU, CPU]`.
 */
class LiteRtBackendOrderPolicy {
    private val isEmulatorDevice: Boolean = isEmulator()

    fun preferredBackends(): List<Backend> {
        return if (isEmulatorDevice) {
            listOf(Backend.CPU, Backend.GPU)
        } else {
            listOf(Backend.GPU, Backend.CPU)
        }
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
