# Launch the dedicated server from dist/server with sane defaults.

[CmdletBinding()]
param(
    [string]$Map = 'ctf_2fort',
    [int]$MaxPlayers = 16,
    [int]$Port = 27015,
    [string]$Hostname = 'TF2-Base Dev Server',
    [string[]]$ExtraArgs = @()
)

. "$PSScriptRoot\common.ps1"

$srcds = Join-Path $DistServerDir 'srcds.exe'
if (-not (Test-FileNonEmpty $srcds)) {
    throw "srcds.exe not found at $srcds. Run build\setup.ps1 first."
}

$modDir = Join-Path $DistServerDir $ModName
if (-not (Test-FileNonEmpty (Join-Path $modDir 'gameinfo.txt'))) {
    throw "Mod directory '$modDir' not staged. Run build\assets.ps1 first."
}

$args = @(
    '-game', $ModName,
    '-console',
    '-port', "$Port",
    '+maxplayers', "$MaxPlayers",
    '+hostname', $Hostname,
    '+map', $Map
) + $ExtraArgs

Write-Host "Launching: $srcds $($args -join ' ')"
Push-Location $DistServerDir
try {
    & $srcds @args
} finally {
    Pop-Location
}
