package com.example.super_overlay.overlay.moonshine

object MoonshineModelCatalog {
    private const val MODEL_SUBDIR = "moonshine/medium-streaming-en"

    val mediumStreamingSpecs = listOf(
        MoonshineModelSpec(
            id = "moonshine-medium-streaming-en-adapter",
            fileName = "adapter.ort",
            url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/adapter.ort",
            sizeBytes = 3_647_712L,
            subdir = MODEL_SUBDIR
        ),
        MoonshineModelSpec(
            id = "moonshine-medium-streaming-en-cross-kv",
            fileName = "cross_kv.ort",
            url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/cross_kv.ort",
            sizeBytes = 11_544_952L,
            subdir = MODEL_SUBDIR
        ),
        MoonshineModelSpec(
            id = "moonshine-medium-streaming-en-decoder-kv",
            fileName = "decoder_kv.ort",
            url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/decoder_kv.ort",
            sizeBytes = 146_216_448L,
            subdir = MODEL_SUBDIR
        ),
        MoonshineModelSpec(
            id = "moonshine-medium-streaming-en-encoder",
            fileName = "encoder.ort",
            url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/encoder.ort",
            sizeBytes = 94_202_872L,
            subdir = MODEL_SUBDIR
        ),
        MoonshineModelSpec(
            id = "moonshine-medium-streaming-en-frontend",
            fileName = "frontend.ort",
            url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/frontend.ort",
            sizeBytes = 47_467_256L,
            subdir = MODEL_SUBDIR
        ),
        MoonshineModelSpec(
            id = "moonshine-medium-streaming-en-config",
            fileName = "streaming_config.json",
            url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/streaming_config.json",
            sizeBytes = 513L,
            subdir = MODEL_SUBDIR
        ),
        MoonshineModelSpec(
            id = "moonshine-medium-streaming-en-tokenizer",
            fileName = "tokenizer.bin",
            url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/tokenizer.bin",
            sizeBytes = 249_974L,
            subdir = MODEL_SUBDIR
        )
    )
}
