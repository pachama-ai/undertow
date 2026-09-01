# Vorbereitung für den Testlauf: Simulator-Prozesse beenden + altes Ergebnis löschen.
Get-Process | Where-Object { $_.Name -match 'Playdate' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
Remove-Item -Force (Join-Path $sdk 'Disk\Data\com.selina.ringe.test\test_results.txt') -ErrorAction SilentlyContinue
Write-Output 'BEREIT'
