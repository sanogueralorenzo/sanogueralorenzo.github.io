package com.sanogueralorenzo.androidsteam.input

import android.view.KeyEvent

// US evdev codes matching the bundled XKB map. ADB events have no scan code;
// physical keyboards supply the kernel code.
internal object SteamKeys {
    private val letters = intArrayOf(30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44)
    fun code(event: KeyEvent): Int? {
        if (event.scanCode in 1..255) return event.scanCode
        return when (val code = event.keyCode) {
            in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z -> letters[code - KeyEvent.KEYCODE_A]
            in KeyEvent.KEYCODE_1..KeyEvent.KEYCODE_9 -> code - KeyEvent.KEYCODE_1 + 2
            KeyEvent.KEYCODE_0 -> 11
            in KeyEvent.KEYCODE_F1..KeyEvent.KEYCODE_F10 -> code - KeyEvent.KEYCODE_F1 + 59
            KeyEvent.KEYCODE_F11 -> 87
            KeyEvent.KEYCODE_F12 -> 88
            KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BUTTON_B -> 1
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_BUTTON_A -> 28
            KeyEvent.KEYCODE_DEL -> 14
            KeyEvent.KEYCODE_TAB -> 15
            KeyEvent.KEYCODE_SPACE -> 57
            KeyEvent.KEYCODE_SHIFT_LEFT -> 42
            KeyEvent.KEYCODE_SHIFT_RIGHT -> 54
            KeyEvent.KEYCODE_CTRL_LEFT -> 29
            KeyEvent.KEYCODE_CTRL_RIGHT -> 97
            KeyEvent.KEYCODE_ALT_LEFT -> 56
            KeyEvent.KEYCODE_ALT_RIGHT -> 100
            KeyEvent.KEYCODE_META_LEFT -> 125
            KeyEvent.KEYCODE_META_RIGHT -> 126
            KeyEvent.KEYCODE_CAPS_LOCK -> 58
            KeyEvent.KEYCODE_NUM_LOCK -> 69
            KeyEvent.KEYCODE_DPAD_UP -> 103
            KeyEvent.KEYCODE_DPAD_DOWN -> 108
            KeyEvent.KEYCODE_DPAD_LEFT -> 105
            KeyEvent.KEYCODE_DPAD_RIGHT -> 106
            KeyEvent.KEYCODE_MOVE_HOME -> 102
            KeyEvent.KEYCODE_MOVE_END -> 107
            KeyEvent.KEYCODE_PAGE_UP -> 104
            KeyEvent.KEYCODE_PAGE_DOWN -> 109
            KeyEvent.KEYCODE_INSERT -> 110
            KeyEvent.KEYCODE_FORWARD_DEL -> 111
            KeyEvent.KEYCODE_MINUS -> 12
            KeyEvent.KEYCODE_EQUALS -> 13
            KeyEvent.KEYCODE_LEFT_BRACKET -> 26
            KeyEvent.KEYCODE_RIGHT_BRACKET -> 27
            KeyEvent.KEYCODE_BACKSLASH -> 43
            KeyEvent.KEYCODE_SEMICOLON -> 39
            KeyEvent.KEYCODE_APOSTROPHE -> 40
            KeyEvent.KEYCODE_GRAVE -> 41
            KeyEvent.KEYCODE_COMMA -> 51
            KeyEvent.KEYCODE_PERIOD -> 52
            KeyEvent.KEYCODE_SLASH -> 53
            else -> null
        }
    }
}
