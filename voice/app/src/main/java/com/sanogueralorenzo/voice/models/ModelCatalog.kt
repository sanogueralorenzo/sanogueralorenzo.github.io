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
        id = "qwen3-0.6b-litertlm",
        fileName = "Qwen3-0.6B.litertlm",
        url = "https://huggingface.co/litert-community/Qwen3-0.6B/resolve/4c0f158768e8ed6b3cebc54e617732e9b1d819ae/Qwen3-0.6B.litertlm",
        sha256 = "555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4",
        sizeBytes = 614_236_160L,
        subdir = "litertlm",
        notes = "Primary LiteRT summarizer (non-gated)"
    )

    val moonshineTinyStreamingAdapter = ModelSpec(
        id = "moonshine-tiny-streaming-en-adapter",
        fileName = "adapter.ort",
        url = "https://download.moonshine.ai/model/tiny-streaming-en/quantized/adapter.ort",
        sizeBytes = 1_319_440L,
        subdir = "moonshine/tiny-streaming-en"
    )

    val moonshineTinyStreamingCrossKv = ModelSpec(
        id = "moonshine-tiny-streaming-en-cross-kv",
        fileName = "cross_kv.ort",
        url = "https://download.moonshine.ai/model/tiny-streaming-en/quantized/cross_kv.ort",
        sizeBytes = 1_264_384L,
        subdir = "moonshine/tiny-streaming-en"
    )

    val moonshineTinyStreamingDecoderKv = ModelSpec(
        id = "moonshine-tiny-streaming-en-decoder-kv",
        fileName = "decoder_kv.ort",
        url = "https://download.moonshine.ai/model/tiny-streaming-en/quantized/decoder_kv.ort",
        sizeBytes = 32_403_688L,
        subdir = "moonshine/tiny-streaming-en"
    )

    val moonshineTinyStreamingEncoder = ModelSpec(
        id = "moonshine-tiny-streaming-en-encoder",
        fileName = "encoder.ort",
        url = "https://download.moonshine.ai/model/tiny-streaming-en/quantized/encoder.ort",
        sizeBytes = 7_569_200L,
        subdir = "moonshine/tiny-streaming-en"
    )

    val moonshineTinyStreamingFrontend = ModelSpec(
        id = "moonshine-tiny-streaming-en-frontend",
        fileName = "frontend.ort",
        url = "https://download.moonshine.ai/model/tiny-streaming-en/quantized/frontend.ort",
        sizeBytes = 8_324_600L,
        subdir = "moonshine/tiny-streaming-en"
    )

    val moonshineTinyStreamingConfig = ModelSpec(
        id = "moonshine-tiny-streaming-en-config",
        fileName = "streaming_config.json",
        url = "https://download.moonshine.ai/model/tiny-streaming-en/quantized/streaming_config.json",
        sizeBytes = 509L,
        subdir = "moonshine/tiny-streaming-en"
    )

    val moonshineTinyStreamingTokenizer = ModelSpec(
        id = "moonshine-tiny-streaming-en-tokenizer",
        fileName = "tokenizer.bin",
        url = "https://download.moonshine.ai/model/tiny-streaming-en/quantized/tokenizer.bin",
        sizeBytes = 249_974L,
        subdir = "moonshine/tiny-streaming-en"
    )

    val moonshineTinyStreamingSpecs = listOf(
        moonshineTinyStreamingAdapter,
        moonshineTinyStreamingCrossKv,
        moonshineTinyStreamingDecoderKv,
        moonshineTinyStreamingEncoder,
        moonshineTinyStreamingFrontend,
        moonshineTinyStreamingConfig,
        moonshineTinyStreamingTokenizer
    )

    val moonshineTinyStreamingTotalBytes: Long =
        moonshineTinyStreamingSpecs.sumOf { it.sizeBytes.coerceAtLeast(0L) }
}
