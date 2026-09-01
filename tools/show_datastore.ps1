# Zeigt den aktuellen Fortschritt (data.json + save.json) des Spiels.
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
$dir = Join-Path $sdk 'Disk\Data\com.selina.ringe'
foreach ($f in @('data.json', 'save.json')) {
    $p = Join-Path $dir $f
    if (Test-Path $p) {
        Write-Output ("=== " + $f + " ===")
        Get-Content $p -Raw
    } else {
        Write-Output ("=== " + $f + " FEHLT ===")
    }
}
