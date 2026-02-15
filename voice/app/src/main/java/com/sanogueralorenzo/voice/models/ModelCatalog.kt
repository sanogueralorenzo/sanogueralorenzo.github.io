package com.sanogueralorenzo.voice.models

data class ModelSpec(
    val id: String,
    val fileName: String,
    val url: String,
    val sha256: String = "",
    val sizeBytes: Long = -1L,
    val subdir: String,
    val notes: String = ""
)

/** Central model definitions used by both setup UI and runtime pipelines. */
object ModelCatalog {
    val liteRtLm = ModelSpec(
        id = "gemma3-1b-it-litertlm",
        fileName = "gemma3-1b-it-int4.litertlm",
        // Use the public mirror default path.
        url = "https://huggingface.co/ANISH-j/models-for-echo-application/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm",
        // Hash pin disabled by request to avoid download hash mismatch failures.
        sha256 = "",
        sizeBytes = 584_417_280L,
        subdir = "litertlm",
        notes = "Primary LiteRT rewrite model (Gemma3-1B-IT), downloaded from a public mirror without strict hash pin."
    )

    val moonshineMediumStreamingAdapter = ModelSpec(
        id = "moonshine-medium-streaming-en-adapter",
        fileName = "adapter.ort",
        url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/adapter.ort",
        sizeBytes = 3_647_712L,
        subdir = "moonshine/medium-streaming-en"
    )

    val moonshineMediumStreamingCrossKv = ModelSpec(
        id = "moonshine-medium-streaming-en-cross-kv",
        fileName = "cross_kv.ort",
        url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/cross_kv.ort",
        sizeBytes = 11_544_952L,
        subdir = "moonshine/medium-streaming-en"
    )

    val moonshineMediumStreamingDecoderKv = ModelSpec(
        id = "moonshine-medium-streaming-en-decoder-kv",
        fileName = "decoder_kv.ort",
        url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/decoder_kv.ort",
        sizeBytes = 146_216_448L,
        subdir = "moonshine/medium-streaming-en"
    )

    val moonshineMediumStreamingEncoder = ModelSpec(
        id = "moonshine-medium-streaming-en-encoder",
        fileName = "encoder.ort",
        url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/encoder.ort",
        sizeBytes = 94_202_872L,
        subdir = "moonshine/medium-streaming-en"
    )

    val moonshineMediumStreamingFrontend = ModelSpec(
        id = "moonshine-medium-streaming-en-frontend",
        fileName = "frontend.ort",
        url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/frontend.ort",
        sizeBytes = 47_467_256L,
        subdir = "moonshine/medium-streaming-en"
    )

    val moonshineMediumStreamingConfig = ModelSpec(
        id = "moonshine-medium-streaming-en-config",
        fileName = "streaming_config.json",
        url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/streaming_config.json",
        sizeBytes = 513L,
        subdir = "moonshine/medium-streaming-en"
    )

    val moonshineMediumStreamingTokenizer = ModelSpec(
        id = "moonshine-medium-streaming-en-tokenizer",
        fileName = "tokenizer.bin",
        url = "https://download.moonshine.ai/model/medium-streaming-en/quantized/tokenizer.bin",
        sizeBytes = 249_974L,
        subdir = "moonshine/medium-streaming-en"
    )

    val moonshineMediumStreamingSpecs = listOf(
        moonshineMediumStreamingAdapter,
        moonshineMediumStreamingCrossKv,
        moonshineMediumStreamingDecoderKv,
        moonshineMediumStreamingEncoder,
        moonshineMediumStreamingFrontend,
        moonshineMediumStreamingConfig,
        moonshineMediumStreamingTokenizer
    )

    val moonshineMediumStreamingTotalBytes: Long =
        moonshineMediumStreamingSpecs.sumOf { it.sizeBytes.coerceAtLeast(0L) }
}
