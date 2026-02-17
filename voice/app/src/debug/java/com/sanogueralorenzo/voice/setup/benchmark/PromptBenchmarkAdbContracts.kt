package com.sanogueralorenzo.voice.setup.benchmark

object PromptBenchmarkAdbContracts {
    const val ACTION_RUN = "com.sanogueralorenzo.voice.DEBUG_PROMPT_BENCHMARK_RUN"

    const val EXTRA_RUN_ID = "run_id"
    const val EXTRA_PROMPT_REL_PATH = "prompt_rel_path"
    const val EXTRA_DATASET_REL_PATH = "dataset_rel_path"
    const val EXTRA_OUTPUT_REL_PATH = "output_rel_path"

    const val DEFAULT_RESULTS_DIR = "benchmark_runs"
    const val APP_DEFAULT_PROMPT_SENTINEL = "__APP_DEFAULT__"
}
