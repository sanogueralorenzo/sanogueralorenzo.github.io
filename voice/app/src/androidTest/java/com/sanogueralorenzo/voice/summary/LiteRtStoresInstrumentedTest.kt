package com.sanogueralorenzo.voice.summary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiteRtStoresInstrumentedTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun backendPolicy_staysAutoEvenAfterGpuFailures() {
        val store = LiteRtBackendPolicyStore(context)
        val modelSha = "demo-model-sha"

        store.clearPolicy(modelSha)
        assertEquals(LiteRtBackendPolicy.AUTO, store.currentPolicy(modelSha))

        store.markGpuFailed(modelSha)
        assertEquals(LiteRtBackendPolicy.AUTO, store.currentPolicy(modelSha))
        assertEquals(listOf(com.google.ai.edge.litertlm.Backend.GPU, com.google.ai.edge.litertlm.Backend.CPU), store.preferredBackends(modelSha))

        store.clearPolicy(modelSha)
    }

    @Test
    fun compatibilityChecker_disablesAfterTwoFailures() {
        val checker = LiteRtCompatibilityChecker(context)
        val modelSha = "probe-model-sha"
        val appVersion = 1L
        val backend = "CPU"

        checker.clearForModel(modelSha)

        val first = checker.recordFailure(modelSha, appVersion, backend, "first")
        assertFalse(first.disabled)
        assertEquals(1, first.failureCount)

        val second = checker.recordFailure(modelSha, appVersion, backend, "second")
        assertTrue(second.disabled)
        assertEquals(2, second.failureCount)

        val recovered = checker.recordSuccess(modelSha, appVersion, backend)
        assertTrue(recovered.healthy)
        assertFalse(recovered.disabled)
        assertEquals(0, recovered.failureCount)

        checker.clearForModel(modelSha)
    }
}
