package com.sanogueralorenzo.androidsteam.input

import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteOrder
import java.nio.channels.FileChannel

/** One Xbox slot using DroidDeck's version-2 evdev ring/snapshot ABI (GPL-3.0).
 * Delta events avoid repeated input; the absolute snapshot repairs late opens and overflow.
 * Lifetime and synchronization belong to PadBridge, alongside the Steam session.
 */
internal class PadRing(directory: File) : AutoCloseable {
    private val file = RandomAccessFile(File(directory, "ring0"), "rw")
    private val data = file.apply { setLength(SIZE.toLong()) }.channel
        .map(FileChannel.MapMode.READ_WRITE, 0, SIZE.toLong()).order(ByteOrder.LITTLE_ENDIAN)
    private var writeSequence = 0L
    private var snapshotSequence = 0L
    private var previousButtons = 0
    private val previousAxes = IntArray(8)

    init {
        data.putInt(0, 0x46494252)
        data.putInt(4, 2)
        data.putInt(8, 24)
        data.putInt(12, CAPACITY)
        data.putLong(16, 0)
        data.putLong(24, 0)
        data.putLong(32, 0)
        data.putInt(40, 0)
        repeat(8) { data.putShort(44 + it * 2, 0) }
        data.putInt(60, 0)
        NativeDisplay.storeFence()
    }

    fun write(state: PadState) {
        val buttons = (0..9).fold(0) { bits, i -> if (state.isDown(i)) bits or (1 shl i) else bits } or
            (if (state.isDown(PadState.GUIDE)) 1 shl 10 else 0)
        val axes = intArrayOf(
            (state.leftX.coerceIn(-1f, 1f) * 32767).toInt(), (state.leftY.coerceIn(-1f, 1f) * 32767).toInt(),
            (state.rightX.coerceIn(-1f, 1f) * 32767).toInt(), (state.rightY.coerceIn(-1f, 1f) * 32767).toInt(),
            (state.rightTrigger.coerceIn(0f, 1f) * 255).toInt(), (state.leftTrigger.coerceIn(0f, 1f) * 255).toInt(),
            state.hatX(), state.hatY())
        if (buttons == previousButtons && axes.contentEquals(previousAxes)) return
        BUTTONS.forEachIndexed { i, code ->
            if ((buttons xor previousButtons) and (1 shl i) != 0) {
                event(4, 4, code) // MSC_SCAN before the key, matching a real Xbox evdev node.
                event(1, code, if (buttons and (1 shl i) != 0) 1 else 0)
            }
        }
        AXES.forEachIndexed { i, code -> if (axes[i] != previousAxes[i]) event(3, code, axes[i]) }
        event(0, 0, 0)
        data.putLong(32, ++snapshotSequence) // odd: snapshot write in progress
        NativeDisplay.storeFence()
        data.putInt(40, buttons)
        axes.forEachIndexed { i, value -> data.putShort(44 + i * 2, value.toShort()) }
        NativeDisplay.storeFence()
        data.putLong(32, ++snapshotSequence)
        NativeDisplay.storeFence()
        data.putLong(16, writeSequence)
        previousButtons = buttons
        axes.copyInto(previousAxes)
    }

    private fun event(type: Int, code: Int, value: Int) {
        val offset = 64 + (writeSequence++ % CAPACITY).toInt() * 24
        val time = android.os.SystemClock.elapsedRealtimeNanos()
        data.putLong(offset, time / 1_000_000_000)
        data.putLong(offset + 8, time % 1_000_000_000 / 1_000)
        data.putShort(offset + 16, type.toShort())
        data.putShort(offset + 18, code.toShort())
        data.putInt(offset + 20, value)
    }

    override fun close() { file.close() }

    companion object {
        private const val CAPACITY = 4096
        private const val SIZE = 64 + CAPACITY * 24
        private val BUTTONS = intArrayOf(0x130, 0x131, 0x133, 0x134, 0x136, 0x137, 0x13a, 0x13b, 0x13d, 0x13e, 0x13c)
        private val AXES = intArrayOf(0, 1, 3, 4, 9, 10, 16, 17)
    }
}
