# Linux-Beilagen fuer build_public.ps1 -Platform Linux (0.11.5). Reines ASCII (PowerShell 5.1).
# Write-LinuxExtras: Startskripte (.sh, LF), LIESMICH_LINUX.txt / README_LINUX_EN.txt.
# New-LinuxTarball:  tar.gz per bsdtar (Windows tar.exe) mit mtree-Liste -> Ausfuehrungsrechte 0755 fuer Programm/Skripte.

function Write-TextLF([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
}

function Write-LinuxExtras([string]$Out, [string]$Version) {
  Write-TextLF "$Out\DangerousHidden2.sh" @'
#!/bin/sh
# Dangerous and Hidden 2 - Start (Linux x86_64). Arbeitsordner = Programmordner (orig_cache/, config/, version.txt).
cd "$(dirname "$0")" || exit 1
[ -x ./DangerousHidden2.x86_64 ] || chmod +x ./DangerousHidden2.x86_64 2>/dev/null
if [ ! -f ./DangerousHidden2.pck ]; then echo "DangerousHidden2.pck fehlt / missing"; exit 1; fi
exec ./DangerousHidden2.x86_64 "$@"
'@
  Write-TextLF "$Out\DedicatedServer.sh" @'
#!/bin/sh
# Dedizierter Server: Konfigurationsmenue (ServerConfigs/*.cfg). Ohne Menue direkt:
#   ./DangerousHidden2.x86_64 --headless -- --dedicated=ServerConfigs/Default.cfg
# Ports: UDP 11001 (Spiel), 11002 (Abfrage), 27101 (LAN-Suche) in der Firewall freigeben.
cd "$(dirname "$0")" || exit 1
[ -x ./DangerousHidden2.x86_64 ] || chmod +x ./DangerousHidden2.x86_64 2>/dev/null
exec ./DangerousHidden2.x86_64 -- --server_config "$@"
'@
  $de = @"
DANGEROUS AND HIDDEN 2 (inoffizieller Nachbau) - Linux-Build v$Version (x86_64)

INHALT
  DangerousHidden2.x86_64  Programm (Linux, 64 Bit)
  DangerousHidden2.pck     Spieldaten des Nachbaus (gehoert zum Programm - beide immer aus demselben Paket)
  version.txt              Versionsmarke; beim Start wird geprueft, ob .pck und Programm zusammenpassen
  DangerousHidden2.sh      Start (./DangerousHidden2.sh)
  DedicatedServer.sh       Konfigurationsmenue des dedizierten Servers

START
  tar xzf DangerousHidden2_v${Version}_linux_public.tar.gz
  cd DangerousHidden2_v${Version}_linux_public && ./DangerousHidden2.sh
  Falls "Permission denied": chmod +x DangerousHidden2.x86_64 *.sh
  Voraussetzung: 64-Bit-Linux mit Vulkan-faehigem Grafiktreiber (Mesa/NVIDIA), glibc wie aktuelle Distributionen.

ORIGINALDATEN (eigene Installation von Hidden & Dangerous 2 noetig)
  Werkzeugmenue fuer Linux (im Paketordner):  bash tools/user/hd2_menu.sh
  1) Suchen (Steam, Heroic/GOG, Lutris, Wine-Praefixe), 2) Einrichten (python3-venv in werkzeuge/,
  ffmpeg aus der Distribution), 3) Spieldaten exportieren -> orig_cache/ neben DangerousHidden2.x86_64.
  Voraussetzung: python3 (3.10-3.14) mit venv/pip, fuer Filme ffmpeg (z. B. sudo apt install python3-venv ffmpeg).
  Ohne Menue: bash tools/user/hd2_menu.sh --aktion Export --orig "<Ordner mit hd2.exe>"  (--help fuer alle Optionen)
  Alternativ: orig_cache\ aus einem Windows-Export komplett hierher kopieren (Ordnername klein, Dateien nicht umbenennen).
  Die Originalinstallation wird nur gelesen; das Spiel selbst liest nur orig_cache.
  Die erzeugten Daten stammen aus dem eigenen Spiel - nicht weitergeben.

UPDATE
  Neue Version: Programm, .pck und version.txt gemeinsam ersetzen; orig_cache/ bleibt.
  Meldung "Versionskonflikt" beim Start = Programm und .pck stammen aus verschiedenen Paketen.

MEHRSPIELER
  Firewall: UDP 11001, 11002, 27101 erlauben (z. B. ufw allow 11001:11002/udp; ufw allow 27101/udp).
  Server-Konfigurationen liegen in config/ bzw. ServerConfigs/ neben dem Programm.
  Profile und Einstellungen: ~/.local/share/godot/app_userdata/<Projektname>/ (Godot user://).
"@
  Write-TextLF "$Out\LIESMICH_LINUX.txt" $de
  $en = @"
DANGEROUS AND HIDDEN 2 (unofficial remake) - Linux build v$Version (x86_64)

CONTENTS
  DangerousHidden2.x86_64  Program (Linux, 64-bit)
  DangerousHidden2.pck     Game data of the remake (always use program and .pck from the same package)
  version.txt              Version marker; checked at start-up
  DangerousHidden2.sh      Start script (./DangerousHidden2.sh)
  DedicatedServer.sh       Dedicated server configuration menu

START
  tar xzf DangerousHidden2_v${Version}_linux_public.tar.gz
  cd DangerousHidden2_v${Version}_linux_public && ./DangerousHidden2.sh
  On "Permission denied": chmod +x DangerousHidden2.x86_64 *.sh
  Requirements: 64-bit Linux with a Vulkan-capable graphics driver (Mesa/NVIDIA).

ORIGINAL GAME DATA (requires your own installation of Hidden & Dangerous 2)
  Linux tools menu (inside the package folder):  bash tools/user/hd2_menu.sh
  1) find (Steam, Heroic/GOG, Lutris, Wine prefixes), 2) set up (python3 venv in werkzeuge/,
  ffmpeg from your distribution), 3) export game data -> orig_cache/ next to DangerousHidden2.x86_64.
  Requirements: python3 (3.10-3.14) with venv/pip, ffmpeg for movies (e.g. sudo apt install python3-venv ffmpeg).
  Without menu: bash tools/user/hd2_menu.sh --action Export --source "<folder containing hd2.exe>"  (--help lists all options)
  Alternatively copy orig_cache\ from a Windows export here (lower-case folder name, do not rename files).
  The original installation is only read; the game itself reads only orig_cache.
  The generated data comes from your own game - do not distribute it.

UPDATE
  Replace program, .pck and version.txt together; orig_cache/ stays.
  "version conflict" at start-up = program and .pck come from different packages.

MULTIPLAYER
  Firewall: allow UDP 11001, 11002, 27101.
  Profiles/settings: ~/.local/share/godot/app_userdata/<project name>/ (Godot user://).
"@
  Write-TextLF "$Out\README_LINUX_EN.txt" $en
}

function ConvertTo-MtreePath([string]$p) {
  $sb = New-Object Text.StringBuilder
  foreach ($ch in $p.ToCharArray()) {
    $c = [int]$ch
    if ($c -le 32 -or $c -ge 127 -or $ch -eq '\' -or $ch -eq '#') {
      foreach ($b in [Text.Encoding]::UTF8.GetBytes([string]$ch)) { [void]$sb.Append('\' + [Convert]::ToString($b, 8).PadLeft(3, '0')) }
    } else { [void]$sb.Append($ch) }
  }
  $sb.ToString()
}

function New-LinuxTarball([string]$Dir, [string]$Archive, [string[]]$ExecNames) {
  $dir = (Resolve-Path $Dir).Path.TrimEnd('\')
  $top = Split-Path $dir -Leaf
  $parent = Split-Path $dir -Parent
  $lines = New-Object Collections.Generic.List[string]
  $lines.Add("#mtree")
  $lines.Add("./" + (ConvertTo-MtreePath $top) + " type=dir mode=0755")
  Get-ChildItem $dir -Recurse | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($dir.Length + 1).Replace('\', '/')
    $name = "./" + (ConvertTo-MtreePath "$top/$rel")
    if ($_.PSIsContainer) { $lines.Add("$name type=dir mode=0755") }
    else {
      $mode = if ($ExecNames -contains $_.Name -and $rel -notmatch '/') { "0755" } else { "0644" }
      $lines.Add("$name type=file mode=$mode contents=" + (ConvertTo-MtreePath $_.FullName.Replace('\', '/')))
    }
  }
  $spec = Join-Path $env:TEMP ("dh2_mtree_" + [guid]::NewGuid().ToString("N") + ".txt")
  [IO.File]::WriteAllText($spec, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
  try {
    Push-Location $parent
    & tar.exe --format=pax -czf $Archive "@$spec"
    if ($LASTEXITCODE -ne 0) { throw "tar fehlgeschlagen ($LASTEXITCODE)." }
  } finally { Pop-Location; Remove-Item $spec -ErrorAction SilentlyContinue }
}
