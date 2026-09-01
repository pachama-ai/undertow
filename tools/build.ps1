# Baut das Spiel (Ringe.pdx) — pdc direkt.
$ErrorActionPreference = 'Stop'
$root = 'C:\Users\User\Downloads\undertow-master\undertow-master'
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
Set-Location $root
& (Join-Path $sdk 'bin\pdc.exe') .\source .\Ringe.pdx
Write-Output "PDC_EXIT=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { exit 1 }
