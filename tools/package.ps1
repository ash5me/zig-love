param(
    [string]$LoveExe = $env:LOVE_EXE,
    [string]$Output = "dist"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($LoveExe)) {
    throw "Pass -LoveExe C:\\path\\to\\love.exe or set LOVE_EXE."
}
if (-not (Test-Path $LoveExe)) { throw "LÖVE executable not found: $LoveExe" }

& (Join-Path $PSScriptRoot "generate_bindings.ps1")
zig build -Dproduction=true
New-Item -ItemType Directory -Force $Output | Out-Null
$archive = Join-Path $Output "game.love"
$bundle = Join-Path $Output "game.exe"
$staging = Join-Path $Output ".game-staging"
$zip = Join-Path $Output "game.zip"
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $staging | Out-Null
Copy-Item main.lua, game_logic.lua, ffi_bindings.lua -Destination $staging
Copy-Item zig-out/bin/game_systems.dll -Destination $staging
if (Test-Path $archive) { Remove-Item $archive -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zip
Move-Item $zip $archive
if (Test-Path $bundle) { Remove-Item $bundle -Force }
Copy-Item $LoveExe $bundle
$loveBytes = [System.IO.File]::ReadAllBytes($archive)
$file = [System.IO.File]::Open($bundle, [System.IO.FileMode]::Append)
try { $file.Write($loveBytes, 0, $loveBytes.Length) } finally { $file.Dispose() }
Remove-Item $staging -Recurse -Force
Write-Host "Created $archive and fused executable $bundle"
