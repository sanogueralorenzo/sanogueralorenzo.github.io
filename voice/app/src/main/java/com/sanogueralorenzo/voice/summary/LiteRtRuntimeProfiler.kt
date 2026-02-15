package com.sanogueralorenzo.voice.summary

import android.app.ActivityManager
import android.content.Context

enum class LiteRtRuntimeTier {
    LOW,
    MEDIUM,
    HIGH
}

data class LiteRtRuntimeLimits(
    val engineMaxTokens: Int,
    val rewriteInputMaxChars: Int,
    val rewriteInputMaxWords: Int,
    val rewriteOutputMaxTokens: Int,
    val editInputMaxChars: Int,
    val editInputMaxWords: Int
) {
    fun compactLabel(): String {
        return "engine=$engineMaxTokens rewriteIn=${rewriteInputMaxChars}/${rewriteInputMaxWords} " +
            "rewriteOut=$rewriteOutputMaxTokens editIn=${editInputMaxChars}/${editInputMaxWords}"
    }
}

data class LiteRtRuntimeProfile(
    val tier: LiteRtRuntimeTier,
    val limits: LiteRtRuntimeLimits,
    val memoryClassMb: Int,
    val isLowRamDevice: Boolean,
    val availMemBytes: Long,
    val lowMemory: Boolean
) {
    val availMemMb: Long
        get() = (availMemBytes.coerceAtLeast(0L) / MB_BYTES)

    fun shouldBypassForMemoryPressure(): Boolean {
        return lowMemory || (availMemBytes in 1 until MEMORY_GUARD_BYTES)
    }

    companion object {
        private const val MB_BYTES = 1024L * 1024L
        private const val MEMORY_GUARD_BYTES = 300L * MB_BYTES
    }
}

object LiteRtRuntimeProfiler {
    private const val MB_BYTES = 1024L * 1024L
    private const val LOW_TIER_AVAIL_BYTES = 450L * MB_BYTES
    private const val MEDIUM_TIER_AVAIL_BYTES = 900L * MB_BYTES

    fun snapshot(context: Context): LiteRtRuntimeProfile {
        val appContext = context.applicationContext
        val am = appContext.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        if (am != null) {
            am.getMemoryInfo(memoryInfo)
        }
        val memoryClass = am?.memoryClass ?: 256
        val isLowRamDevice = am?.isLowRamDevice ?: false
        val availMemBytes = memoryInfo.availMem
        val lowMemory = memoryInfo.lowMemory
        val tier = classifyTier(
            memoryClassMb = memoryClass,
            isLowRamDevice = isLowRamDevice,
            availMemBytes = availMemBytes
        )
        return LiteRtRuntimeProfile(
            tier = tier,
            limits = limitsForTier(tier),
            memoryClassMb = memoryClass,
            isLowRamDevice = isLowRamDevice,
            availMemBytes = availMemBytes,
            lowMemory = lowMemory
        )
    }

    internal fun classifyTier(
        memoryClassMb: Int,
        isLowRamDevice: Boolean,
        availMemBytes: Long
    ): LiteRtRuntimeTier {
        if (isLowRamDevice || (availMemBytes in 1 until LOW_TIER_AVAIL_BYTES)) {
            return LiteRtRuntimeTier.LOW
        }
        if ((memoryClassMb <= 192 && (availMemBytes in 1 until MEDIUM_TIER_AVAIL_BYTES))) {
            return LiteRtRuntimeTier.LOW
        }
        if (memoryClassMb <= 320 || (availMemBytes in 1 until MEDIUM_TIER_AVAIL_BYTES)) {
            return LiteRtRuntimeTier.MEDIUM
        }
        return LiteRtRuntimeTier.HIGH
    }

    internal fun limitsForTier(tier: LiteRtRuntimeTier): LiteRtRuntimeLimits {
        return when (tier) {
            LiteRtRuntimeTier.LOW -> LiteRtRuntimeLimits(
                engineMaxTokens = 160,
                rewriteInputMaxChars = 640,
                rewriteInputMaxWords = 115,
                rewriteOutputMaxTokens = 96,
                editInputMaxChars = 900,
                editInputMaxWords = 160
            )

            LiteRtRuntimeTier.MEDIUM -> LiteRtRuntimeLimits(
                engineMaxTokens = 192,
                rewriteInputMaxChars = 800,
                rewriteInputMaxWords = 145,
                rewriteOutputMaxTokens = 128,
                editInputMaxChars = 1_150,
                editInputMaxWords = 200
            )

            LiteRtRuntimeTier.HIGH -> LiteRtRuntimeLimits(
                engineMaxTokens = 224,
                rewriteInputMaxChars = 960,
                rewriteInputMaxWords = 175,
                rewriteOutputMaxTokens = 160,
                editInputMaxChars = 1_400,
                editInputMaxWords = 245
            )
        }
    }
}
