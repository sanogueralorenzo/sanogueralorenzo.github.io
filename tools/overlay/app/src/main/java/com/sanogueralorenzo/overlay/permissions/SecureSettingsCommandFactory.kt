package com.sanogueralorenzo.overlay.permissions

internal object SecureSettingsCommandFactory {
    fun create(packageName: String): SecureSettingsCommands {
        return SecureSettingsCommands(
            mac = buildUnixCommand(
                packageName = packageName,
                zipUrl = "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
            ),
            windows = buildWindowsCommand(packageName),
            linux = buildUnixCommand(
                packageName = packageName,
                zipUrl = "https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
            )
        )
    }

    private fun buildUnixCommand(
        packageName: String,
        zipUrl: String
    ): String {
        return """
tmp_dir="$(mktemp -d)"; trap 'rm -rf "${'$'}tmp_dir"' EXIT; echo "1/3 Downloading Android platform-tools"; curl -fL --progress-bar $zipUrl -o "${'$'}tmp_dir/platform-tools.zip" && echo "2/3 Extracting" && unzip -q "${'$'}tmp_dir/platform-tools.zip" -d "${'$'}tmp_dir" && echo "3/3 Granting permission on phone" && "${'$'}tmp_dir/platform-tools/adb" shell pm grant $packageName android.permission.WRITE_SECURE_SETTINGS && echo "Done: permission granted"
""".trimIndent()
    }

    private fun buildWindowsCommand(packageName: String): String {
        return """
${'$'}tmp = Join-Path ${'$'}env:TEMP ("adb-" + [guid]::NewGuid()); ${'$'}exit_code = 1; New-Item -ItemType Directory -Path ${'$'}tmp | Out-Null; try { Write-Host "1/3 Downloading Android platform-tools"; ${'$'}zip = Join-Path ${'$'}tmp "platform-tools.zip"; Invoke-WebRequest -UseBasicParsing https://dl.google.com/android/repository/platform-tools-latest-windows.zip -OutFile ${'$'}zip; Write-Host "2/3 Extracting"; Expand-Archive -Path ${'$'}zip -DestinationPath ${'$'}tmp -Force; Write-Host "3/3 Granting permission on phone"; ${'$'}adb = Join-Path ${'$'}tmp "platform-tools\adb.exe"; & ${'$'}adb shell pm grant $packageName android.permission.WRITE_SECURE_SETTINGS; ${'$'}exit_code = ${'$'}LASTEXITCODE; if (${'$'}exit_code -eq 0) { Write-Host "Done: permission granted" } } finally { Remove-Item -Recurse -Force ${'$'}tmp }; exit ${'$'}exit_code
""".trimIndent()
    }
}
