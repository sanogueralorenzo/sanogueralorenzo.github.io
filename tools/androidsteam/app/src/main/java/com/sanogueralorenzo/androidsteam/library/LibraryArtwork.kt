package com.sanogueralorenzo.androidsteam.library

import android.graphics.Bitmap
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.widget.ImageView
import java.io.File
import java.util.concurrent.Executors
import java.net.URL
import java.net.HttpURLConnection

/** Decode official phone-cache artwork off the UI thread, with bounded retained pixels. */
internal class LibraryArtwork(context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newFixedThreadPool(2)
    private val directory = File(context.cacheDir, "library-art")
    private val retryAfter = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private val images = object : LruCache<String, Bitmap>(8 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }
    fun show(view: ImageView, game: LibraryGame) {
        val path = game.metadata.artworkPath
        val file = game.artwork ?: path?.let { File(directory, "${game.appId}_${it.replace('/', '_')}") }
        val key = file?.path
        if (view.tag == key && view.drawable != null) return
        view.tag = key
        view.clipToOutline = true
        view.setImageDrawable(null)
        if (file == null || key == null) return
        images[key]?.let { view.setImageBitmap(it); return }
        worker.execute {
            if (!file.isFile) {
                if (path == null || (retryAfter[key] ?: 0) > android.os.SystemClock.elapsedRealtime()) return@execute
                val fetched = runCatching { download(game.appId, path, file) }.isSuccess
                if (!fetched) { retryAfter[key] = android.os.SystemClock.elapsedRealtime() + 60_000; return@execute }
            }
            val bitmap = images[key] ?: run {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.path, options)
                if (options.outWidth !in 1..8192 || options.outHeight !in 1..8192) return@execute
                options.inSampleSize = 1
                while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > 768) options.inSampleSize *= 2
                options.inJustDecodeBounds = false
                BitmapFactory.decodeFile(file.path, options)?.also { images.put(key, it) }
            }
            main.post { if (view.tag == key) view.setImageBitmap(bitmap) }
        }
    }

    private fun download(appId: Int, path: String, file: File) {
        check(directory.isDirectory || directory.mkdirs())
        val connection = URL("https://shared.steamstatic.com/store_item_assets/steam/apps/$appId/$path").openConnection() as HttpURLConnection
        connection.connectTimeout = 5_000; connection.readTimeout = 5_000
        connection.instanceFollowRedirects = false
        val temporary = File.createTempFile("header-", ".jpg", directory)
        try {
            check(connection.responseCode == 200 && connection.contentType.orEmpty().startsWith("image/"))
            connection.inputStream.use { input -> temporary.outputStream().use { output ->
                val buffer = ByteArray(4096)
                var size = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    size += count
                    check(size <= 4_194_304)
                    output.write(buffer, 0, count)
                }
            } }
            check(temporary.renameTo(file))
        } finally { connection.disconnect(); temporary.delete() }
    }
}
