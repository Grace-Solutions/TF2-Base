# Bootstrap the local environment: SteamCMD + Source SDK Base 2013 (MP and DS).
# Idempotent. Re-running only refreshes anything missing or out-of-date.

[CmdletBinding()]
param(
    [switch]$SkipClientSdk,
    [switch]$SkipServerSdk,
    [string]$SteamUser = $null,
    [string]$SteamPassword = $null
)

. "$PSScriptRoot\common.ps1"

function Install-SteamCmd {
    Write-Section "SteamCMD"
    New-DirectoryIfMissing $SteamCmdDir
    if (Test-FileNonEmpty $SteamCmdExe) {
        Write-Host "SteamCMD already present at $SteamCmdExe"
        return
    }
    $url = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
    $zip = Join-Path $SteamCmdDir 'steamcmd.zip'
    Write-Host "Downloading SteamCMD from $url"
    $progressBefore = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    } finally {
        $ProgressPreference = $progressBefore
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $SteamCmdDir -Force
    Remove-Item -LiteralPath $zip -Force
    if (-not (Test-FileNonEmpty $SteamCmdExe)) {
        throw "SteamCMD bootstrap failed: $SteamCmdExe is missing."
    }
    Write-Host "First-run bootstrap (SteamCMD will self-update)..."
    & $SteamCmdExe +quit | Out-Host
}

function Invoke-SteamCmd-AppDownload {
    param(
        [Parameter(Mandatory=$true)] [int]$AppId,
        [Parameter(Mandatory=$true)] [string]$InstallDir,
        [string]$Login = 'anonymous',
        [string]$Password = $null
    )
    New-DirectoryIfMissing $InstallDir
    # SteamCMD requires force_install_dir to come before login.
    $args = @('+force_install_dir', $InstallDir)
    if ($Login -eq 'anonymous') {
        $args += @('+login', 'anonymous')
    } else {
        if ([string]::IsNullOrWhiteSpace($Password)) {
            $args += @('+login', $Login)
        } else {
            $args += @('+login', $Login, $Password)
        }
    }
    $args += @('+app_update', "$AppId", 'validate', '+quit')
    Write-Host ("steamcmd " + ($args -join ' ')) -ForegroundColor DarkGray
    & $SteamCmdExe @args 2>&1 | Out-Host
    return $LASTEXITCODE
}

function Get-SdkBase {
    param(
        [Parameter(Mandatory=$true)] [int]$AppId,
        [Parameter(Mandatory=$true)] [string]$InstallDir,
        [Parameter(Mandatory=$true)] [string]$Label,
        [bool]$AllowAnonymous = $true,
        [int]$MaxAttempts = 3
    )
    Write-Section "$Label (app $AppId)"
    if ($AllowAnonymous) {
        for ($i = 1; $i -le $MaxAttempts; $i++) {
            Write-Host ("Anonymous fetch attempt {0}/{1}" -f $i, $MaxAttempts)
            $rc = Invoke-SteamCmd-AppDownload -AppId $AppId -InstallDir $InstallDir -Login 'anonymous'
            if ($rc -eq 0) { return }
            Write-Warning "Anonymous fetch returned exit code $rc for app $AppId."
            Start-Sleep -Seconds 2
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($SteamUser)) {
        Write-Host "Retrying with Steam account '$SteamUser'..."
        $rc = Invoke-SteamCmd-AppDownload -AppId $AppId -InstallDir $InstallDir -Login $SteamUser -Password $SteamPassword
        if ($rc -eq 0) { return }
        throw "SteamCMD failed for app $AppId with user '$SteamUser' (exit $rc)."
    }
    Write-Warning ("App $AppId could not be fetched anonymously after $MaxAttempts attempts. " +
                  "Re-run setup with -SteamUser <name> [-SteamPassword <pw>] to provide credentials, " +
                  "or install via the Steam client and copy the install into '$InstallDir'.")
}

Install-SteamCmd

New-DirectoryIfMissing $DistClientDir
New-DirectoryIfMissing $DistServerDir

if (-not $SkipServerSdk) {
    Get-SdkBase -AppId $AppIdSdkBaseDS -InstallDir $DistServerDir `
                -Label 'Source SDK Base 2013 Dedicated Server' -AllowAnonymous $true
} else {
    Write-Host "Skipping server SDK fetch (-SkipServerSdk)."
}

if (-not $SkipClientSdk) {
    Get-SdkBase -AppId $AppIdSdkBaseMP -InstallDir $DistClientDir `
                -Label 'Source SDK Base 2013 Multiplayer' -AllowAnonymous $true
} else {
    Write-Host "Skipping client SDK fetch (-SkipClientSdk)."
}

Write-Section "Setup complete"
Write-Host "Server SDK location:  $DistServerDir"
Write-Host "Client SDK location:  $DistClientDir"
Write-Host ""
Write-Host "Next: run build\assets.ps1 to stage the tf_port mod content,"
Write-Host "      then build\build.ps1 to compile client.dll and server.dll."
