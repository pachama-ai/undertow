# Setzt einen FRISCHEN ROOM-1-Zustand: highestRoom=1 in beiden Dateien und
# leere Tutorial-Flags in data.json (damit die Player-Vorstellung in ROOM 1
# gezeigt wird — Flag "move" nicht gesehen). Mit Backup des aktuellen Stands.
$sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
$dir = Join-Path $sdk 'Disk\Data\com.selina.ringe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
foreach ($f in @('data.json', 'save.json')) {
    $p = Join-Path $dir $f
    if (Test-Path $p) {
        Copy-Item $p (Join-Path $dir ($f -replace '\.json$', "_room1fresh_$stamp.json")) -Force
    }
}
# data.json: tutorial-Flags LEER + highestRoom=1
$data = Join-Path $dir 'data.json'
$json = Get-Content $data -Raw | ConvertFrom-Json
$json.highestRoom = 1
$json.tutorial = @{}
$json | ConvertTo-Json -Compress | Set-Content $data -Encoding utf8 -NoNewline
Write-Output ('data.json -> highestRoom=1, tutorial leer (Backup _room1fresh_' + $stamp + '.json)')
# save.json: highestRoom=1
$save = Join-Path $dir 'save.json'
$sj = Get-Content $save -Raw | ConvertFrom-Json
$sj.highestRoom = 1
$sj | ConvertTo-Json -Compress | Set-Content $save -Encoding utf8 -NoNewline
Write-Output ('save.json -> highestRoom=1 (Backup _room1fresh_' + $stamp + '.json)')
