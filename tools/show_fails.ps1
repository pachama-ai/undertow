# Zeigt die FAIL-Zeilen des letzten Testlaufs.
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
$rf = Join-Path $sdk 'Disk\Data\com.selina.ringe.test\test_results.txt'
if (Test-Path $rf) {
    Get-Content $rf | Where-Object { $_ -match 'FAIL' } | ForEach-Object { Write-Output $_ }
} else {
    Write-Output 'KEIN ERGEBNIS'
}
