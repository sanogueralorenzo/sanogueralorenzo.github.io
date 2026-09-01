$ErrorActionPreference = "Stop"

$PaletteRoot = Split-Path -Parent $PSScriptRoot
$NodeVersion = if ($env:PALETTE_NODE_VERSION) { $env:PALETTE_NODE_VERSION } else { "22.18.0" }
$RuntimeName = "node-v$NodeVersion-win-x64"
$RuntimeCache = Join-Path $PaletteRoot ".cache\$RuntimeName"
$NodeRuntime = Join-Path $RuntimeCache "node.exe"

if (-not (Test-Path $NodeRuntime)) {
    $DownloadDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("palette-node-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $DownloadDirectory | Out-Null
    try {
        $ArchiveName = "$RuntimeName.zip"
        $BaseUrl = "https://nodejs.org/dist/v$NodeVersion"
        $Archive = Join-Path $DownloadDirectory $ArchiveName
        $Checksums = Join-Path $DownloadDirectory "SHASUMS256.txt"
        Invoke-WebRequest "$BaseUrl/$ArchiveName" -OutFile $Archive
        Invoke-WebRequest "$BaseUrl/SHASUMS256.txt" -OutFile $Checksums
        $ChecksumLine = Get-Content $Checksums | Where-Object { $_ -match "\s$([regex]::Escape($ArchiveName))$" } | Select-Object -First 1
        if (-not $ChecksumLine) { throw "Node runtime checksum was not published" }
        $Expected = ($ChecksumLine -split "\s+")[0].ToLowerInvariant()
        $Actual = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
        if ($Expected -ne $Actual) { throw "Node runtime checksum verification failed" }
        Expand-Archive $Archive -DestinationPath $DownloadDirectory
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RuntimeCache) | Out-Null
        if (Test-Path $RuntimeCache) { Remove-Item -Recurse -Force $RuntimeCache }
        Move-Item (Join-Path $DownloadDirectory $RuntimeName) $RuntimeCache
    }
    finally {
        if (Test-Path $DownloadDirectory) { Remove-Item -Recurse -Force $DownloadDirectory }
    }
}

Push-Location $PaletteRoot
try {
    npm run build
    npm run build:daemon
    cargo build --release --manifest-path native/rust-indexer/Cargo.toml
    $Output = Join-Path $PaletteRoot "build\windows"
    if (Test-Path $Output) { Remove-Item -Recurse -Force $Output }
    dotnet publish native/windows/PaletteHost.csproj -c Release -r win-x64 --self-contained false -o $Output
    $Helpers = Join-Path $Output "Helpers"
    New-Item -ItemType Directory -Path $Helpers | Out-Null
    Copy-Item $NodeRuntime (Join-Path $Helpers "node.exe")
    Copy-Item "native/rust-indexer/target/release/palette-indexer.exe" (Join-Path $Helpers "palette-indexer.exe")
    Write-Output $Output
}
finally {
    Pop-Location
}
