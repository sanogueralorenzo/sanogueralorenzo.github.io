package com.sanogueralorenzo.voice.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class ImeAppendFormatterTest {
    @Test
    fun append_blankChunk_keepsSource() {
        assertEquals(
            "Hello there",
            ImeAppendFormatter.append("Hello there", "   ")
        )
    }

    @Test
    fun append_blankSource_returnsChunk() {
        assertEquals(
            "hello there",
            ImeAppendFormatter.append("", " hello there ")
        )
    }

    @Test
    fun append_plainText_usesSpaceSeparator() {
        assertEquals(
            "Hello there world",
            ImeAppendFormatter.append("Hello there", "world")
        )
    }

    @Test
    fun append_listLike_usesNewlineSeparator() {
        val source = "Buy:\n- apples\n- eggs"
        val chunk = "milk"
        assertEquals(
            "Buy:\n- apples\n- eggs\nmilk",
            ImeAppendFormatter.append(source, chunk)
        )
    }
}
