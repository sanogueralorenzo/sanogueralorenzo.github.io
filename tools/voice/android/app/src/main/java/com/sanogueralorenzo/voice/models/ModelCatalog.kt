package com.sanogueralorenzo.voice.models

import com.sanogueralorenzo.voice.audio.DictationLanguage

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

    private const val SPANISH_SMALL_BASE_URL =
        "https://download.moonshine.ai/model/small-streaming-es/quantized_26_08_24"
    private const val SPANISH_SMALL_SUBDIR = "moonshine/small-streaming-es"

    val moonshineSmallStreamingSpanishSpecs = listOf(
        ModelSpec(
            id = "moonshine-small-streaming-es-adapter",
            fileName = "adapter.ort",
            url = "$SPANISH_SMALL_BASE_URL/adapter.ort",
            sizeBytes = 2_869_296L,
            subdir = SPANISH_SMALL_SUBDIR
        ),
        ModelSpec(
            id = "moonshine-small-streaming-es-cross-kv",
            fileName = "cross_kv.ort",
            url = "$SPANISH_SMALL_BASE_URL/cross_kv.ort",
            sizeBytes = 5_358_752L,
            subdir = SPANISH_SMALL_SUBDIR
        ),
        ModelSpec(
            id = "moonshine-small-streaming-es-decoder-kv",
            fileName = "decoder_kv.ort",
            url = "$SPANISH_SMALL_BASE_URL/decoder_kv.ort",
            sizeBytes = 61_314_512L,
            subdir = SPANISH_SMALL_SUBDIR
        ),
        ModelSpec(
            id = "moonshine-small-streaming-es-encoder",
            fileName = "encoder.ort",
            url = "$SPANISH_SMALL_BASE_URL/encoder.ort",
            sizeBytes = 44_358_376L,
            subdir = SPANISH_SMALL_SUBDIR
        ),
        ModelSpec(
            id = "moonshine-small-streaming-es-frontend-model",
            fileName = "frontend.model.ort",
            url = "$SPANISH_SMALL_BASE_URL/frontend.model.ort",
            sizeBytes = 26_776L,
            subdir = SPANISH_SMALL_SUBDIR
        ),
        ModelSpec(
            id = "moonshine-small-streaming-es-frontend-weights",
            fileName = "frontend.weights.ort",
            url = "$SPANISH_SMALL_BASE_URL/frontend.weights.ort",
            sizeBytes = 7_769_280L,
            subdir = SPANISH_SMALL_SUBDIR
        ),
        ModelSpec(
            id = "moonshine-small-streaming-es-config",
            fileName = "streaming_config.json",
            url = "$SPANISH_SMALL_BASE_URL/streaming_config.json",
            sizeBytes = 512L,
            subdir = SPANISH_SMALL_SUBDIR
        ),
        ModelSpec(
            id = "moonshine-small-streaming-es-tokenizer",
            fileName = "tokenizer.bin",
            url = "$SPANISH_SMALL_BASE_URL/tokenizer.bin",
            sizeBytes = 102_888L,
            subdir = SPANISH_SMALL_SUBDIR
        )
    )

    fun moonshineStreamingSpecsFor(language: DictationLanguage): List<ModelSpec> {
        return when (language) {
            DictationLanguage.ENGLISH -> moonshineMediumStreamingSpecs
            DictationLanguage.SPANISH -> moonshineSmallStreamingSpanishSpecs
        }
    }
}
