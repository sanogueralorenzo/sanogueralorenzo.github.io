package com.sanogueralorenzo.androidsteam.games

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

internal data class SteamGameMetadata(
    val appId: Int, val name: String, val platforms: Set<String>,
    val visibleOnlyWhenInstalled: Boolean = false, val controllerSupport: String? = null,
    val artworkPath: String? = null,
)

/** Steam appinfo v41; cached product metadata is not an ownership source. */
internal object SteamAppInfo {
    fun games(file: File): Map<Int, SteamGameMetadata> {
        require(file.isFile && file.length() in 16..33_554_432) { "Open Steam to prepare its game metadata, then retry." }
        val data = ByteBuffer.wrap(file.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
        require(data.int == 0x07564429) { "Steam's metadata format is unsupported by this app version." }
        data.int
        val offset = data.long
        require(offset in 16 until data.capacity().toLong()) { "Steam game metadata is incomplete. Open Steam, then retry." }
        data.position(offset.toInt())
        val count = data.int
        require(count in 0..100_000)
        val strings = List(count) { string(data) }
        data.position(16)
        data.limit(offset.toInt())
        val games = mutableMapOf<Int, SteamGameMetadata>()
        while (true) {
            val appId = data.int
            if (appId == 0) break
            val size = data.int
            require(appId > 0 && size >= 60 && size <= data.remaining()) { "Steam game metadata is incomplete." }
            val end = data.position() + size
            data.position(data.position() + 60)
            val limit = data.limit()
            data.limit(end)
            val record = objectValue(data, strings, 0)
            val info = record["appinfo"] as? Map<*, *> ?: record
            val common = info["common"] as? Map<*, *> ?: emptyMap<Any, Any>()
            val extended = info["extended"] as? Map<*, *> ?: emptyMap<Any, Any>()
            val assets = common["library_assets_full"] as? Map<*, *>
            val header = assets?.get("library_header") as? Map<*, *>
            val image = header?.get("image") as? Map<*, *>
            val storeHeader = common["header_image"] as? Map<*, *>
            val artwork = (image?.get("english") ?: storeHeader?.get("english")) as? String
            if (common["type"]?.toString().equals("game", true)) {
                val name = common["name"] as? String
                if (!name.isNullOrBlank()) games[appId] = SteamGameMetadata(appId, name,
                    (common["oslist"] as? String).orEmpty().lowercase().split(',').filter(String::isNotBlank).toSet(),
                    extended.entries.any { (key, value) -> key.toString().equals("VisibleOnlyWhenInstalled", true) && value.toString() == "1" },
                    common["controller_support"] as? String,
                    artwork?.takeIf { it.matches(Regex("(?:[a-f0-9]{40}/)?[A-Za-z0-9_]+\\.(?:jpg|png|webp)")) })
            }
            data.limit(limit); data.position(end)
        }
        return games
    }

    private fun objectValue(data: ByteBuffer, strings: List<String>, depth: Int): Map<String, Any> {
        require(depth <= 64)
        val result = mutableMapOf<String, Any>()
        while (data.hasRemaining()) {
            val type = data.get().toInt() and 255
            if (type == 8 || type == 11) return result
            val key = data.int
            require(key in strings.indices)
            val value: Any = when (type) {
                0 -> objectValue(data, strings, depth + 1)
                1 -> string(data)
                2, 3, 4, 6 -> data.int
                7 -> data.long
                else -> error("Steam game metadata contains an unsupported value.")
            }
            result[strings[key]] = value
        }
        error("Steam game metadata is incomplete.")
    }

    private fun string(data: ByteBuffer): String {
        val start = data.position()
        while (data.hasRemaining()) if (data.get() == 0.toByte())
            return String(data.array(), start, data.position() - start - 1, Charsets.UTF_8)
        error("Steam game metadata string is incomplete.")
    }
}
