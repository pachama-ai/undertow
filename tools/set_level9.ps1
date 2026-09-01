# Setzt den Fortschritt auf highestRoom=9 (mit Backup des aktuellen Stands).
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
$dir = Join-Path $sdk 'Disk\Data\com.selina.ringe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
foreach ($f in @('data.json', 'save.json')) {
    $p = Join-Path $dir $f
    if (Test-Path $p) {
        Copy-Item $p (Join-Path $dir ($f -replace '\.json$', "_backup_$stamp.json")) -Force
        $json = Get-Content $p -Raw | ConvertFrom-Json
        if ($json.highestRoom -ne 9) {
            $json.highestRoom = 9
            $json | ConvertTo-Json -Compress | Set-Content $p -Encoding utf8 -NoNewline
            Write-Output ("$f -> highestRoom=9 (Backup _backup_$stamp.json)")
        } else {
            Write-Output ("$f war bereits highestRoom=9")
        }
    } else {
        Write-Output ("$f fehlt")
    }
}
