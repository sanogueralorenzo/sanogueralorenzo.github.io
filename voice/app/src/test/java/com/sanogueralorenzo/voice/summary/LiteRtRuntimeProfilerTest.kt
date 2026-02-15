package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtRuntimeProfilerTest {
    @Test
    fun classifyTier_returnsLowForLowRamDevices() {
        val tier = LiteRtRuntimeProfiler.classifyTier(
            memoryClassMb = 512,
            isLowRamDevice = true,
            availMemBytes = 1_200L * 1024L * 1024L
        )
        assertEquals(LiteRtRuntimeTier.LOW, tier)
    }

    @Test
    fun classifyTier_returnsLowForSmallMemoryClass() {
        val tier = LiteRtRuntimeProfiler.classifyTier(
            memoryClassMb = 256,
            isLowRamDevice = false,
            availMemBytes = 1_200L * 1024L * 1024L
        )
        assertEquals(LiteRtRuntimeTier.MEDIUM, tier)
    }

    @Test
    fun classifyTier_returnsLowForVerySmallMemoryClassWhenAvailMemIsNotHigh() {
        val tier = LiteRtRuntimeProfiler.classifyTier(
            memoryClassMb = 192,
            isLowRamDevice = false,
            availMemBytes = 700L * 1024L * 1024L
        )
        assertEquals(LiteRtRuntimeTier.LOW, tier)
    }

    @Test
    fun classifyTier_returnsMediumForMidMemoryClass() {
        val tier = LiteRtRuntimeProfiler.classifyTier(
            memoryClassMb = 320,
            isLowRamDevice = false,
            availMemBytes = 1_200L * 1024L * 1024L
        )
        assertEquals(LiteRtRuntimeTier.MEDIUM, tier)
    }

    @Test
    fun classifyTier_returnsHighWhenMemoryIsHealthy() {
        val tier = LiteRtRuntimeProfiler.classifyTier(
            memoryClassMb = 512,
            isLowRamDevice = false,
            availMemBytes = 1_800L * 1024L * 1024L
        )
        assertEquals(LiteRtRuntimeTier.HIGH, tier)
    }

    @Test
    fun memoryGuard_triggersWhenLowMemoryFlagIsSet() {
        val profile = LiteRtRuntimeProfile(
            tier = LiteRtRuntimeTier.MEDIUM,
            limits = LiteRtRuntimeProfiler.limitsForTier(LiteRtRuntimeTier.MEDIUM),
            memoryClassMb = 384,
            isLowRamDevice = false,
            availMemBytes = 800L * 1024L * 1024L,
            lowMemory = true
        )
        assertTrue(profile.shouldBypassForMemoryPressure())
    }

    @Test
    fun limits_matchExpectedLowTierValues() {
        val limits = LiteRtRuntimeProfiler.limitsForTier(LiteRtRuntimeTier.LOW)
        assertEquals(160, limits.engineMaxTokens)
        assertEquals(640, limits.rewriteInputMaxChars)
        assertEquals(115, limits.rewriteInputMaxWords)
        assertEquals(96, limits.rewriteOutputMaxTokens)
        assertEquals(900, limits.editInputMaxChars)
        assertEquals(160, limits.editInputMaxWords)
    }
}
