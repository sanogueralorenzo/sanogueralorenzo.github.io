package com.sanogueralorenzo.voice.summary

import com.sanogueralorenzo.voice.engine.VoiceEngine
import org.junit.Assert.assertEquals
import org.junit.Test

class VoiceEnginePostprocessTest {
    @Test
    fun cleanModelOutput_capitalizesStartAndAfterConfiguredPunctuation() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "hey mia, can you buy apples. actually get milk? thanks",
            bulletMode = false
        )

        assertEquals("Hey mia, can you buy apples. Actually get milk? Thanks", cleaned)
    }

    @Test
    fun cleanModelOutput_appliesCapitalizationAfterLabelCleanup() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "cleaned: hello, this is fine. maybe? yes",
            bulletMode = false
        )

        assertEquals("Hello, this is fine. Maybe? Yes", cleaned)
    }

    @Test
    fun cleanModelOutput_flattensBulletsAndCapitalizesResult() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "- apple\n- milk\n- avocado",
            bulletMode = false
        )

        assertEquals("Apple milk avocado", cleaned)
    }

    @Test
    fun cleanModelOutput_convertsSpokenDigitSequenceWithCommasToNumber() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "the code is one, two, three",
            bulletMode = false
        )

        assertEquals("The code is 123", cleaned)
    }

    @Test
    fun cleanModelOutput_convertsSpokenDigitSequenceWithoutCommasToNumber() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "call one two three four five",
            bulletMode = false
        )

        assertEquals("Call 12345", cleaned)
    }

    @Test
    fun cleanModelOutput_convertsSpokenCardinalNumberToNumber() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "set it to three hundred twenty one",
            bulletMode = false
        )

        assertEquals("Set it to 321", cleaned)
    }

    @Test
    fun cleanModelOutput_convertsSpokenCardinalNumberWithAndToNumber() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "set it to one hundred and five",
            bulletMode = false
        )

        assertEquals("Set it to 105", cleaned)
    }

    @Test
    fun cleanModelOutput_convertsTwoWordCardinalNumberToNumber() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "set it to twenty one",
            bulletMode = false
        )

        assertEquals("Set it to 21", cleaned)
    }

    @Test
    fun cleanModelOutput_doesNotConvertSingleNumberWordInProse() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "one more thing",
            bulletMode = false
        )

        assertEquals("One more thing", cleaned)
    }

    @Test
    fun cleanModelOutput_doesNotConvertAmbiguousMixedSpokenNumberPhrase() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "the code is one twenty three",
            bulletMode = false
        )

        assertEquals("The code is one twenty three", cleaned)
    }

    @Test
    fun cleanModelOutput_doesNotConvertTrailingDigitAfterCardinalPhrase() {
        val cleaned = VoiceEngine.cleanModelOutput(
            text = "the code is twenty one five",
            bulletMode = false
        )

        assertEquals("The code is twenty one five", cleaned)
    }
}
