package com.sanogueralorenzo.voice.benchmark

object BenchmarkSuite {
    const val SUITE_VERSION = "v1"

    fun defaultCases(): List<BenchmarkCase> {
        return listOf(
            BenchmarkCase(
                id = "C01_disfluency_text",
                title = "Disfluency + chat text",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "uh hey can you text sara that i'll be like ten minutes late"
            ),
            BenchmarkCase(
                id = "C02_restart_correction",
                title = "Restart and correction",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "book a table for two tomorrow no sorry for four at seven"
            ),
            BenchmarkCase(
                id = "C03_punctuation_runon",
                title = "Run-on punctuation",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "hey mom landed safe call you later love you"
            ),
            BenchmarkCase(
                id = "C04_time_and_date",
                title = "Date and time",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "remind me next friday at three thirty to pay the electricity bill"
            ),
            BenchmarkCase(
                id = "C05_names_and_numbers",
                title = "Names and identifiers",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "send to jon perez order id a9k-44 is confirmed"
            ),
            BenchmarkCase(
                id = "C06_shopping_list_with_correction",
                title = "List with correction",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "buy apples eggs avocado actually no eggs make it milk"
            ),
            BenchmarkCase(
                id = "C07_work_message_constraints",
                title = "Work constraints",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "tell the team i can join at 2pm but i need the deck before noon"
            ),
            BenchmarkCase(
                id = "C08_location_and_negation",
                title = "Location and negation",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "i'm not at the office i'm at the downtown clinic"
            ),
            BenchmarkCase(
                id = "C09_short_casual",
                title = "Short casual",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "on my way five mins"
            ),
            BenchmarkCase(
                id = "C10_multi_clause_personal",
                title = "Multi-clause personal",
                category = "compose",
                type = BenchmarkCaseType.COMPOSE,
                composeInput = "hey mia can you grab the package and leave it by the back door thanks"
            ),
            BenchmarkCase(
                id = "E01_replace_list_item",
                title = "Replace list item",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "Hey Mia, can you go to the supermarket and buy:\n- apple\n- eggs\n- avocado",
                editInstruction = "actually i already have eggs and i'm missing milk"
            ),
            BenchmarkCase(
                id = "E02_remove_phrase",
                title = "Remove phrase",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "I can do 5pm tomorrow at the office.",
                editInstruction = "remove at the office"
            ),
            BenchmarkCase(
                id = "E03_change_time",
                title = "Change time",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "Let's meet at 5:00 PM.",
                editInstruction = "actually make it 6:30"
            ),
            BenchmarkCase(
                id = "E04_change_name",
                title = "Change recipient",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "Text Jon: I'm outside.",
                editInstruction = "no send it to johnny"
            ),
            BenchmarkCase(
                id = "E05_add_missing_item",
                title = "Add missing item",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "Buy rice and chicken.",
                editInstruction = "add yogurt"
            ),
            BenchmarkCase(
                id = "E06_tone_shorten",
                title = "Shorten tone",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "Hello team, I wanted to kindly check if we could maybe move this meeting to later this afternoon.",
                editInstruction = "make it shorter"
            ),
            BenchmarkCase(
                id = "E07_tone_warm",
                title = "Warm tone",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "I can't make it.",
                editInstruction = "make this warmer"
            ),
            BenchmarkCase(
                id = "E08_tone_work",
                title = "Professional tone",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "hey can't talk now",
                editInstruction = "make this professional"
            ),
            BenchmarkCase(
                id = "E09_final_correction_turn",
                title = "Final correction turn",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "Pickup is at gate B12.",
                editInstruction = "change to gate c3 no sorry gate c4"
            ),
            BenchmarkCase(
                id = "E10_delete_all",
                title = "Delete all",
                category = "edit",
                type = BenchmarkCaseType.EDIT,
                editOriginal = "Draft note to delete.",
                editInstruction = "delete all"
            )
        )
    }
}
