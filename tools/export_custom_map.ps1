# Eigene Karte anlegen bzw. als .pck exportieren.
# Create a custom map or export it as .pck.
#
#   powershell -File tools\export_custom_map.ps1 -Id meine_karte -New          # Vorlage -> custom_maps\meine_karte\
#   powershell -File tools\export_custom_map.ps1 -Id meine_karte               # -> maps\meine_karte.pck (Projektordner)
#   powershell -File tools\export_custom_map.ps1 -Id meine_karte -Out D:\Spiel\maps\meine_karte.pck
#   powershell -File tools\export_custom_map.ps1 -Id meine_karte -User         # zusaetzlich nach user://maps/
#
# Ablauf Export: Godot --headless --import (importierte Texturen/Modelle aktuell), dann tools\pack_custom_map.gd
# (PCKPacker, prueft Manifest und Paketinhalt). Nutzt die Test-Sperre test_output\.godot_lock/.godot_lock2.
param([Parameter(Mandatory = $true)][string]$Id, [switch]$New, [string]$Out = "", [switch]$User, [switch]$NoImport,
  [int]$TimeoutSec = 900)
$ErrorActionPreference = "Stop"
$proj = Split-Path $PSScriptRoot -Parent
if ($Id -cnotmatch '^[a-z0-9_]{1,40}$') { Write-Error "Id: nur a-z, 0-9, _ (max. 40) / only a-z, 0-9, _"; exit 2 }
$mapDir = Join-Path $proj "custom_maps\$Id"

if ($New) {
  if (Test-Path $mapDir) { Write-Error "$mapDir existiert bereits / already exists"; exit 2 }
  New-Item -ItemType Directory -Force $mapDir | Out-Null
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot "map_template") -File -Force) {
    if ($f.Name -eq ".gdignore") { continue }
    $dst = Join-Path $mapDir $f.Name
    if ($f.Extension -in @(".json", ".tscn", ".gd", ".md", ".tres")) {
      $txt = [System.IO.File]::ReadAllText($f.FullName, $utf8).Replace("__MAP_ID__", $Id)
      [System.IO.File]::WriteAllText($dst, $txt, $utf8)
    } else { Copy-Item $f.FullName $dst }
  }
  "NEU / NEW: $mapDir  (im Editor bearbeiten, dann ohne -New exportieren / edit in the editor, then export without -New)"
  exit 0
}

if (-not (Test-Path (Join-Path $mapDir "map.json"))) { Write-Error "$mapDir\map.json fehlt / missing (zuerst -New)"; exit 2 }
if ($Out -eq "") { $Out = Join-Path $proj "maps\$Id.pck" }
$Out = [System.IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force (Split-Path $Out -Parent) | Out-Null
New-Item -ItemType Directory -Force "$proj\test_output" | Out-Null

. "$PSScriptRoot\test_lock.ps1"
$lockName = "export_custom_map_$Id"
$slots = Get-TestSlots -Proj $proj -Name $lockName -Count 1
try {
  if (-not $NoImport) {
    $r = Invoke-GodotSuite -Proj $proj -GodotArgs "--headless --import" -Log "$proj\test_output\custom_map_import.log" `
      -TimeoutSec $TimeoutSec -Slots $slots
    if ($r.code -ne 0) { Write-Error "Import fehlgeschlagen / failed (test_output\custom_map_import.log)"; exit 1 }
  }
  $extra = if ($User) { " --install_user=1" } else { "" }
  $log = "$proj\test_output\custom_map_pack.log"
  $r = Invoke-GodotSuite -Proj $proj -GodotArgs "--headless -s res://tools/pack_custom_map.gd -- --map=$Id `"--out=$Out`"$extra" `
    -Log $log -TimeoutSec $TimeoutSec -Slots $slots
  Get-Content $log -Encoding UTF8 | Where-Object { $_ -match 'PACK_' }
  if ($r.code -ne 0) { Write-Error "Export fehlgeschlagen / failed ($log)"; exit 1 }
  $sha = (Get-FileHash -Algorithm SHA256 $Out).Hash.ToLower()
  "OK $Out"
  "SHA-256 $sha"
} finally { Release-TestSlots -Slots $slots -Name $lockName }
