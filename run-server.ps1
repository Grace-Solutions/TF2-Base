# Top-level entry: run the dedicated server from dist/server.
[CmdletBinding()]
param(
    [string]$Map = 'ctf_2fort',
    [int]$MaxPlayers = 16,
    [int]$Port = 27015,
    [string]$Hostname = 'TF2-Base Dev Server',
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot\build\run-server.ps1" `
    -Map $Map `
    -MaxPlayers $MaxPlayers `
    -Port $Port `
    -Hostname $Hostname `
    -ExtraArgs $ExtraArgs
