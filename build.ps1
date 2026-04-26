# Top-level entry: build client.dll and server.dll and deploy them into dist/.
[CmdletBinding()]
param(
    [ValidateSet('Release','Debug')] [string]$Configuration = 'Release',
    [string]$PlatformToolset = 'v143',
    [string]$WindowsSdkVersion = '10.0',
    [switch]$Regenerate,
    [switch]$NoDeploy
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot\build\build.ps1" `
    -Configuration $Configuration `
    -PlatformToolset $PlatformToolset `
    -WindowsSdkVersion $WindowsSdkVersion `
    -Regenerate:$Regenerate `
    -NoDeploy:$NoDeploy
