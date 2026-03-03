package com.sanogueralorenzo.overlay.permissions

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.sanogueralorenzo.overlay.SettingsRepository
import com.sanogueralorenzo.overlay.ui.components.SecureSettingsCommands
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.flow.Flow

@Inject
@SingleIn(AppScope::class)
class PermissionsRepository(
    context: Context,
    private val settingsRepository: SettingsRepository
) {
    private val appContext = context.applicationContext
    private val packageName = appContext.packageName

    fun tileAddedFlow(): Flow<Boolean> = settingsRepository.tileAddedFlow()

    suspend fun setTileAdded(added: Boolean) {
        settingsRepository.setTileAdded(added)
    }

    fun isOverlayPermissionGranted(): Boolean {
        return Settings.canDrawOverlays(appContext)
    }

    fun isNotificationPermissionGranted(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun isWriteSecureSettingsPermissionGranted(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.WRITE_SECURE_SETTINGS
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun secureSettingsCommands(): SecureSettingsCommands {
        return SecureSettingsCommands(
            mac = buildMacCommand(packageName),
            windows = buildWindowsCommand(packageName),
            linux = buildLinuxCommand(packageName)
        )
    }

    private fun buildMacCommand(packageName: String): String {
        return buildUnixCommand(
            packageName = packageName,
            zipUrl = "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
        )
    }

    private fun buildLinuxCommand(packageName: String): String {
        return buildUnixCommand(
            packageName = packageName,
            zipUrl = "https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
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
