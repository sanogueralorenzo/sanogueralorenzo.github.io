package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtSamplingProfilesTest {
    @Test
    fun consistentLevel_usesDeterministicProfile() {
        val profile = LiteRtSamplingProfiles.profileForLevel(0)

        assertEquals(LiteRtSamplingProfiles.DEFAULT_TOP_K, profile.topK)
        assertEquals(LiteRtSamplingProfiles.DEFAULT_TOP_P, profile.topP, 0.0)
        assertEquals(LiteRtSamplingProfiles.DEFAULT_TEMPERATURE, profile.temperature, 0.0)
        assertFalse(profile.useDynamicSeed)
    }

    @Test
    fun creativeLevel_usesHighVarianceProfile() {
        val profile = LiteRtSamplingProfiles.profileForLevel(5)

        assertEquals(40, profile.topK)
        assertEquals(1.0, profile.topP, 0.0)
        assertEquals(1.1, profile.temperature, 0.0)
        assertTrue(profile.useDynamicSeed)
    }

    @Test
    fun outOfRangeLevels_areNormalized() {
        val belowMin = LiteRtSamplingProfiles.profileForLevel(-99)
        val aboveMax = LiteRtSamplingProfiles.profileForLevel(999)

        assertEquals(1, belowMin.topK)
        assertFalse(belowMin.useDynamicSeed)
        assertEquals(40, aboveMax.topK)
        assertTrue(aboveMax.useDynamicSeed)
    }
}
