# Copy locally-built client.dll / server.dll into the staged dist/ directories,
# overlaying the prebuilt DLLs that came from the upstream asset zips.

[CmdletBinding()]
param()

. "$PSScriptRoot\common.ps1"

$builtBin    = Join-Path $GameDir 'tf_mod\bin'
$clientBuilt = Join-Path $builtBin 'client.dll'
$serverBuilt = Join-Path $builtBin 'server.dll'

$clientModBin = Join-Path $DistClientDir (Join-Path $ModName 'bin')
$serverModBin = Join-Path $DistServerDir (Join-Path $ModName 'bin')

function Copy-IfPresent {
    param([string]$Source, [string]$DestDir, [string]$Label)
    if (-not (Test-FileNonEmpty $Source)) {
        Write-Warning "$Label not found at $Source (skipping)."
        return
    }
    New-DirectoryIfMissing $DestDir
    $dest = Join-Path $DestDir (Split-Path -Leaf $Source)
    Copy-Item -LiteralPath $Source -Destination $dest -Force
    Write-Host "Deployed $Label -> $dest"
}

Write-Section "Deploy built binaries"
Copy-IfPresent -Source $clientBuilt -DestDir $clientModBin -Label 'client.dll'
Copy-IfPresent -Source $serverBuilt -DestDir $serverModBin -Label 'server.dll'
# Server distribution also carries a server.dll for the game logic.
Copy-IfPresent -Source $serverBuilt -DestDir $clientModBin -Label 'server.dll (client-side)'

Write-Section "Deploy complete"
