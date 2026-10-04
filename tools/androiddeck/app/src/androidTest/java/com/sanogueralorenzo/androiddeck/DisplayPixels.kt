package com.sanogueralorenzo.androiddeck

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import com.sanogueralorenzo.androiddeck.display.DisplayTestActivity
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*

internal object DisplayPixels {
    fun awaitBlue(activity: DisplayTestActivity) {
        val started = SystemClock.elapsedRealtime()
        var colors = emptyList<Int>()
        do {
            withPixels(activity) { image ->
                colors = listOf(1, 160, 318).flatMap { x -> listOf(1, 100, 198).map { y -> image.getPixel(x, y) } }
            }
            if (colors.all { it == Color.BLUE }) return
            Thread.sleep(16)
        } while (SystemClock.elapsedRealtime() - started < 2_000)
        assertEquals("The final Linux Vulkan frame never reached Android", List(9) { Color.BLUE }, colors)
    }

    fun withPixels(activity: DisplayTestActivity, check: (Bitmap) -> Unit) {
        val image = Bitmap.createBitmap(320, 200, Bitmap.Config.ARGB_8888)
        val copied = CountDownLatch(1)
        var result = -1
        try {
            PixelCopy.request(activity.surface, image, { result = it; copied.countDown() }, Handler(Looper.getMainLooper()))
            assertTrue("Pixel copy timed out", copied.await(5, TimeUnit.SECONDS))
            assertEquals("Android surface has no readable frame", PixelCopy.SUCCESS, result)
            check(image)
        } finally { image.recycle() }
    }
}
