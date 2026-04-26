# Top-level entry: bootstrap SteamCMD, fetch SDK bases, stage mod assets.
# Forwards all arguments to build\setup.ps1 then build\assets.ps1.

[CmdletBinding()]
param(
    [switch]$SkipClientSdk,
    [switch]$SkipServerSdk,
    [string]$SteamUser = $null,
    [string]$SteamPassword = $null,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot\build\setup.ps1" `
    -SkipClientSdk:$SkipClientSdk `
    -SkipServerSdk:$SkipServerSdk `
    -SteamUser $SteamUser `
    -SteamPassword $SteamPassword

& "$PSScriptRoot\build\assets.ps1" -Force:$Force
