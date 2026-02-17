package com.sanogueralorenzo.voice.setup.benchmark

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class PromptBenchmarkAdbReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != PromptBenchmarkAdbContracts.ACTION_RUN) return
        val serviceIntent = Intent(context, PromptBenchmarkAdbService::class.java).apply {
            action = PromptBenchmarkAdbContracts.ACTION_RUN
            putExtra(
                PromptBenchmarkAdbContracts.EXTRA_RUN_ID,
                intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_RUN_ID)
            )
            putExtra(
                PromptBenchmarkAdbContracts.EXTRA_PROMPT_REL_PATH,
                intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_PROMPT_REL_PATH)
            )
            putExtra(
                PromptBenchmarkAdbContracts.EXTRA_DATASET_REL_PATH,
                intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_DATASET_REL_PATH)
            )
            putExtra(
                PromptBenchmarkAdbContracts.EXTRA_OUTPUT_REL_PATH,
                intent.getStringExtra(PromptBenchmarkAdbContracts.EXTRA_OUTPUT_REL_PATH)
            )
        }
        runCatching {
            context.startService(serviceIntent)
        }.onFailure { error ->
            Log.e(TAG, "Failed to start PromptBenchmarkAdbService", error)
        }
    }

    private companion object {
        private const val TAG = "PromptBenchmarkAdbReceiver"
    }
}
