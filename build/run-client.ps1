# Launch the client (hl2.exe) from dist/client with sane defaults.

[CmdletBinding()]
param(
    [switch]$Windowed,
    [int]$Width = 1280,
    [int]$Height = 720,
    [switch]$Insecure,
    [string[]]$ExtraArgs = @()
)

. "$PSScriptRoot\common.ps1"

$hl2 = Join-Path $DistClientDir 'hl2.exe'
if (-not (Test-FileNonEmpty $hl2)) {
    throw "hl2.exe not found at $hl2. Run build\setup.ps1 first (Source SDK Base 2013 Multiplayer required)."
}

$modDir = Join-Path $DistClientDir $ModName
if (-not (Test-FileNonEmpty (Join-Path $modDir 'gameinfo.txt'))) {
    throw "Mod directory '$modDir' not staged. Run build\assets.ps1 first."
}

$args = @(
    '-game', $ModName,
    '-w', "$Width",
    '-h', "$Height"
)
if ($Windowed) { $args += '-windowed' } else { $args += '-fullscreen' }
if ($Insecure) { $args += '-insecure' }
$args += $ExtraArgs

Write-Host "Launching: $hl2 $($args -join ' ')"
Push-Location $DistClientDir
try {
    & $hl2 @args
} finally {
    Pop-Location
}
