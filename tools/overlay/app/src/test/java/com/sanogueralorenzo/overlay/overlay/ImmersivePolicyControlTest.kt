package com.sanogueralorenzo.overlay.overlay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ImmersivePolicyControlTest {
    @Test
    fun enableAddsPolicyToEmptyValue() {
        assertEquals("immersive.status=*", enableImmersiveStatusPolicy(null))
        assertEquals("immersive.status=*", enableImmersiveStatusPolicy("  "))
    }

    @Test
    fun enablePreservesUnrelatedPolicies() {
        assertEquals(
            "immersive.navigation=apps,custom.policy=x,immersive.status=*",
            enableImmersiveStatusPolicy("immersive.navigation=apps,custom.policy=x")
        )
    }

    @Test
    fun enableNormalizesWhitespaceAndDuplicates() {
        assertEquals(
            "custom.policy=x,immersive.status=*",
            enableImmersiveStatusPolicy(
                " custom.policy=x, immersive.status=*,,custom.policy=x,immersive.status=* "
            )
        )
    }

    @Test
    fun disableRemovesOnlyOverlayPolicy() {
        assertEquals(
            "immersive.navigation=apps,custom.policy=x",
            disableImmersiveStatusPolicy(
                "immersive.navigation=apps,immersive.status=*,custom.policy=x"
            )
        )
    }

    @Test
    fun disableReturnsNullWhenNoPoliciesRemain() {
        assertNull(disableImmersiveStatusPolicy(null))
        assertNull(disableImmersiveStatusPolicy("immersive.status=*"))
        assertNull(disableImmersiveStatusPolicy(" , immersive.status=* , "))
    }

    @Test
    fun disableNormalizesWhitespaceAndDuplicates() {
        assertEquals(
            "custom.policy=x,immersive.navigation=apps",
            disableImmersiveStatusPolicy(
                " custom.policy=x,immersive.status=*,custom.policy=x, immersive.navigation=apps "
            )
        )
    }
}
