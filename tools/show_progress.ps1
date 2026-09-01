# Zeigt den aktuellen Spielstand (höchster Raum) aus dem Datastore.
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
$base = Join-Path $sdk 'Disk\Data\com.selina.ringe'
foreach ($f in @('data.json', 'save.json')) {
    $p = Join-Path $base $f
    Write-Output "--- $f ---"
    if (Test-Path $p) { Get-Content $p } else { Write-Output 'FEHLT' }
}
