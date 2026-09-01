# Beendet alte Simulator-Prozesse und startet den Simulator mit Ringe.pdx.
Get-Process | Where-Object { $_.Name -match 'Playdate' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
$root = 'C:\Users\User\Downloads\undertow-master\undertow-master'
$pdx = Join-Path $root 'Ringe.pdx'
Start-Process -FilePath (Join-Path $sdk 'bin\PlaydateSimulator.exe') -ArgumentList ('"' + $pdx + '"')
Write-Output 'SIM_GESTARTET'
