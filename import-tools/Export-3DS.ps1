# Build the 3DS SD-card folder from your ROMs.  Asks nothing.
#
#   1. finds the gen1recomp desktop app (or plain LOVE) next to this folder
#   2. imports every ROM in .\roms that it can recognise
#   3. copies every cache the app has -- including ones imported by hand in
#      the app -- into .\sd-card\3ds\save\pokemon-love2d\<version>\
#
# Then copy .\sd-card\3ds onto the root of the SD card.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$roms = Join-Path $here 'roms'
$out  = Join-Path $here 'sd-card\3ds\save\pokemon-love2d'

function Find-App {
    # The packaged game first (nothing extra to install for people who already
    # play it), then a plain LOVE.
    foreach ($dir in @((Split-Path -Parent $here), $here)) {
        $hit = Get-ChildItem -Path $dir -Filter 'gen1recomp*.exe' -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    $love = Get-Command 'love.exe' -ErrorAction SilentlyContinue
    if ($love) { return $love.Source }
    foreach ($p in @("$env:ProgramFiles\LOVE\love.exe", "${env:ProgramFiles(x86)}\LOVE\love.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$app = Find-App
if (-not $app) {
    Write-Host 'Export-3DS: no gen1recomp app found.'
    Write-Host ''
    Write-Host 'Put this folder next to the gen1recomp desktop app (the one you play on'
    Write-Host 'the PC), or install LOVE from https://love2d.org, then run this again.'
    Read-Host 'Press enter to close' | Out-Null
    exit 1
}
Write-Host "using: $app"

New-Item -ItemType Directory -Force -Path $roms | Out-Null
foreach ($rom in @(Get-ChildItem -Path $roms -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Extension -in '.gb', '.gbc' })) {
    Write-Host "importing $($rom.Name) ..."
    # POKEPORT_IMPORT_ONLY / POKEPORT_IMPORT_ROM are the game's own headless
    # import mode: it imports, writes the cache, and quits without a window.
    $env:POKEPORT_IMPORT_ONLY = '1'
    $env:POKEPORT_IMPORT_ROM  = $rom.FullName
    try { Start-Process -FilePath $app -Wait -NoNewWindow }
    catch { Write-Host '  skipped (the import failed)' }
}
Remove-Item Env:POKEPORT_IMPORT_ONLY, Env:POKEPORT_IMPORT_ROM -ErrorAction SilentlyContinue

# LOVE keeps saves under %APPDATA%\LOVE\<identity>, but a fused (packaged)
# build drops the LOVE level.  Check both.
$copied = 0
New-Item -ItemType Directory -Force -Path $out | Out-Null
foreach ($dir in @((Join-Path $env:APPDATA 'LOVE\pokemon-love2d'), (Join-Path $env:APPDATA 'pokemon-love2d'))) {
    if (-not (Test-Path $dir)) { continue }
    foreach ($marker in @(Get-ChildItem -Path $dir -Filter 'rom-cache.complete' -File -Depth 1 -Recurse -ErrorAction SilentlyContinue)) {
        $version = $marker.Directory.Name
        $dest = Join-Path $out $version
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        Copy-Item -Recurse $marker.Directory.FullName $dest
        Write-Host "  $version"
        $copied++
    }
}

Write-Host ''
if ($copied -eq 0) {
    Write-Host 'Nothing to export yet.'
    Write-Host ''
    Write-Host 'Put your own Game Boy ROM files (.gb / .gbc) in:'
    Write-Host "  $roms"
    Write-Host 'and run this again -- or import them in the desktop app first.'
    Read-Host 'Press enter to close' | Out-Null
    exit 1
}
Write-Host "Done: $copied version(s) ready in"
Write-Host "  $here\sd-card\3ds"
Write-Host ''
Write-Host "Copy that '3ds' folder onto the root of your SD card (merge with the folder"
Write-Host 'already there), put the card back in the console, and start Gen1Recomp.'
Read-Host 'Press enter to close' | Out-Null
