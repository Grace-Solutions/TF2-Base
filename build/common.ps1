# Shared paths and helpers for the TF2-Base build pipeline.
# Dot-source from other scripts: . "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'

$RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SrcDir        = Join-Path $RepoRoot 'src'
$GameDir       = Join-Path $RepoRoot 'game'
$ToolsDir      = Join-Path $RepoRoot 'tools'
$DistDir       = Join-Path $RepoRoot 'dist'
$DistClientDir = Join-Path $DistDir 'client'
$DistServerDir = Join-Path $DistDir 'server'
$SteamCmdDir   = Join-Path $ToolsDir 'steamcmd'
$SteamCmdExe   = Join-Path $SteamCmdDir 'steamcmd.exe'
$BuildCacheDir = Join-Path $PSScriptRoot '.cache'

# Local prebuilt asset/binary archives shipped by upstream releases.
$ClientZip = 'C:\Users\Support\Downloads\TF2\tf_port_client.zip'
$ServerZip = 'C:\Users\Support\Downloads\TF2\tf_port_server.zip'

# Source SDK Base 2013 Steam app IDs.
$AppIdSdkBaseMP = 243750  # Source SDK Base 2013 Multiplayer (client engine)
$AppIdSdkBaseDS = 244310  # Source SDK Base 2013 Dedicated Server

# Mod folder name as used by the prebuilt zips.
$ModName = 'tf_port'

function Write-Section([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host (" {0}" -f $Text) -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

function New-DirectoryIfMissing([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function Test-FileNonEmpty([string]$Path) {
    return (Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).Length -gt 0)
}

function Find-VsInstallPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    $path = & $vswhere -latest -products '*' `
        -requires Microsoft.Component.MSBuild `
        -property installationPath 2>$null
    if (-not $path) { return $null }
    return ($path | Select-Object -First 1)
}

function Find-MsBuild {
    $vs = Find-VsInstallPath
    if (-not $vs) { return $null }
    $candidates = @(
        (Join-Path $vs 'MSBuild\Current\Bin\amd64\MSBuild.exe'),
        (Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}

function Find-DevEnv {
    $vs = Find-VsInstallPath
    if (-not $vs) { return $null }
    $devenv = Join-Path $vs 'Common7\IDE\devenv.com'
    if (Test-Path -LiteralPath $devenv) { return $devenv }
    return $null
}

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory=$true)] [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = $null
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $FilePath
    $psi.UseShellExecute = $false
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    foreach ($a in $ArgumentList) { [void]$psi.ArgumentList.Add($a) }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        throw "Process '$FilePath' exited with code $($p.ExitCode)."
    }
}
