package com.sanogueralorenzo.overlay.permissions

enum class DesktopOsOption {
    Mac,
    Windows,
    Linux
}

data class SecureSettingsCommands(
    val mac: String,
    val windows: String,
    val linux: String
) {
    fun forOption(option: DesktopOsOption): String {
        return when (option) {
            DesktopOsOption.Mac -> mac
            DesktopOsOption.Windows -> windows
            DesktopOsOption.Linux -> linux
        }
    }
}
