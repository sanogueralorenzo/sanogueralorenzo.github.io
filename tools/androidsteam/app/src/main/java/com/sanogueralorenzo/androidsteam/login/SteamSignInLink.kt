package com.sanogueralorenzo.androidsteam.login

/** Only current Steam QR challenge links may be sent to Valve's Android app. */
internal object SteamSignInLink {
    const val PACKAGE = "com.valvesoftware.android.steam.community"
    private val challenge = Regex("https://s\\.team/q/[0-9]{1,3}/[0-9]{1,20}")
    fun valid(value: String) = challenge.matches(value)
}
