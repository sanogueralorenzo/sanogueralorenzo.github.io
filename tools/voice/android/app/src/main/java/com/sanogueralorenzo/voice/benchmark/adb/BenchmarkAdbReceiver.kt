package com.sanogueralorenzo.voice.benchmark.adb

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

class BenchmarkAdbReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != BenchmarkAdbContracts.ACTION_RUN) return
        val serviceIntent = Intent(context, BenchmarkAdbService::class.java).apply {
            action = BenchmarkAdbContracts.ACTION_RUN
            putExtra(
                BenchmarkAdbContracts.EXTRA_RUN_ID,
                intent.getStringExtra(BenchmarkAdbContracts.EXTRA_RUN_ID)
            )
            putExtra(
                BenchmarkAdbContracts.EXTRA_PROMPT_REL_PATH,
                intent.getStringExtra(BenchmarkAdbContracts.EXTRA_PROMPT_REL_PATH)
            )
            putExtra(
                BenchmarkAdbContracts.EXTRA_DATASET_REL_PATH,
                intent.getStringExtra(BenchmarkAdbContracts.EXTRA_DATASET_REL_PATH)
            )
            putExtra(
                BenchmarkAdbContracts.EXTRA_OUTPUT_REL_PATH,
                intent.getStringExtra(BenchmarkAdbContracts.EXTRA_OUTPUT_REL_PATH)
            )
        }
        runCatching {
            ContextCompat.startForegroundService(context, serviceIntent)
        }.onFailure { error ->
            Log.e(TAG, "Failed to start BenchmarkAdbService", error)
        }
    }

    private companion object {
        private const val TAG = "BenchmarkAdbReceiver"
    }
}
