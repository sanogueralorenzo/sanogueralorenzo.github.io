package com.sanogueralorenzo.amarchy.runtime

/** Drain Linux output while waiting so a full pipe cannot stall its process. */
internal class ProcessOutput(process: Process, private val limit: Int) {
    private val output = StringBuilder()
    private val reader = Thread({
        try {
            process.inputStream.bufferedReader().use { input ->
                val buffer = CharArray(4096)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    synchronized(output) { output.append(buffer, 0, minOf(count, (limit - output.length).coerceAtLeast(0))) }
                }
            }
        } catch (_: java.io.IOException) { }
    }, "amarchy-linux-output").apply { start() }

    fun text(): String { reader.join(1000); return synchronized(output) { output.toString() } }
}
