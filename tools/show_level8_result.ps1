# Zeigt das Endergebnis + die Level-8-Beweiszeilen des letzten Testlaufs.
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
$rf = Join-Path $sdk 'Disk\Data\com.selina.ringe.test\test_results.txt'
if (Test-Path $rf) {
    Write-Output '--- LEVEL8 FULL SOLUTION ---'
    Get-Content $rf | Where-Object { $_ -match 'LEVEL8_FULL_SOLUTION|^STEP |^  PASS:|^  FAIL:|^  PLAYER|^  PLATTEN|^  SCHALTER|^  BRIDGES|^  SHUTTER' } | ForEach-Object { Write-Output $_ }
    Write-Output '--- RESULT ---'
    Get-Content $rf | Where-Object { $_ -match '^RESULT|level8:' } | ForEach-Object { Write-Output $_ }
} else {
    Write-Output 'KEIN ERGEBNIS'
}
