# Stage the tf_port mod content (from the upstream prebuilt zips) into
# dist/client/<ModName>/ and dist/server/<ModName>/.

[CmdletBinding()]
param(
    [string]$ClientArchive = $null,
    [string]$ServerArchive = $null,
    [switch]$Force
)

. "$PSScriptRoot\common.ps1"

if (-not $ClientArchive) { $ClientArchive = $ClientZip }
if (-not $ServerArchive) { $ServerArchive = $ServerZip }

function Expand-ModArchive {
    param(
        [Parameter(Mandatory=$true)] [string]$Archive,
        [Parameter(Mandatory=$true)] [string]$DestRoot,
        [Parameter(Mandatory=$true)] [string]$Label
    )
    Write-Section "Stage $Label"
    if (-not (Test-FileNonEmpty $Archive)) {
        throw "Archive not found: $Archive"
    }
    $modDir = Join-Path $DestRoot $ModName
    if ((Test-Path -LiteralPath $modDir) -and -not $Force) {
        $marker = Join-Path $modDir 'gameinfo.txt'
        if (Test-FileNonEmpty $marker) {
            Write-Host "Mod already staged at $modDir (use -Force to re-extract)."
            return
        }
    }
    if ($Force -and (Test-Path -LiteralPath $modDir)) {
        Write-Host "Removing existing $modDir (-Force)"
        Remove-Item -LiteralPath $modDir -Recurse -Force
    }
    New-DirectoryIfMissing $DestRoot
    Write-Host "Extracting $Archive -> $DestRoot"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Archive, $DestRoot)
    if (-not (Test-FileNonEmpty (Join-Path $modDir 'gameinfo.txt'))) {
        throw "Extraction completed but gameinfo.txt missing in $modDir"
    }
    Write-Host "Staged at $modDir"
}

Expand-ModArchive -Archive $ClientArchive -DestRoot $DistClientDir -Label 'client'
Expand-ModArchive -Archive $ServerArchive -DestRoot $DistServerDir -Label 'server'

Write-Section "Asset staging complete"
Write-Host "Client mod:  $(Join-Path $DistClientDir $ModName)"
Write-Host "Server mod:  $(Join-Path $DistServerDir $ModName)"
