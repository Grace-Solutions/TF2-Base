# Top-level entry: run the client (hl2.exe) from dist/client.
[CmdletBinding()]
param(
    [switch]$Windowed,
    [int]$Width = 1280,
    [int]$Height = 720,
    [switch]$Insecure,
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot\build\run-client.ps1" `
    -Windowed:$Windowed `
    -Width $Width `
    -Height $Height `
    -Insecure:$Insecure `
    -ExtraArgs $ExtraArgs
