#!/usr/bin/env bash
# Dangerous and Hidden 2 – Werkzeuge für Spieler (Linux, bash)
# Gegenstück zu tools/user/hd2_menu.ps1: erzeugt aus der EIGENEN Installation von Hidden & Dangerous 2 die Spieldaten
# (orig_cache), konvertiert die Filme und skaliert Texturen hoch. Die Original-Installation wird nur gelesen.
# Alles Benötigte landet im Ordner 'werkzeuge/' neben dem Spiel (Python-venv); Systempakete (python3, ffmpeg) installiert
# das Skript nie selbst, es nennt nur den passenden Befehl der Distribution.
# Tools for players (Linux): export game data from your OWN Hidden & Dangerous 2 installation (read-only), convert
# movies, upscale textures. Language: --sprache de|en (alias --language), otherwise saved setting, otherwise $LANG.
#
# Interaktiv / interactive:      bash tools/user/hd2_menu.sh
# Nicht-interaktiv / scripted:   bash tools/user/hd2_menu.sh --aktion <Aktion> [Optionen]
#   Aktionen: Suchen, Pruefen, Einrichten, Export, Filme, Hochskalieren, Installieren, Wiederherstellen, Status, Starten
#   --sprache de|en        Sprache der Ausgaben (wird im Menü gespeichert)            (--language)
#   --orig <Ordner>        Original-Installation (Ordner mit hd2.exe)                  (--source)
#   --ziel <Ordner>        Ausgabe orig_cache (Standard: orig_cache neben dem Spiel)    (--target)
#   --werkzeuge <Ordner>   Werkzeugordner (Standard: werkzeuge/ neben dem Spiel)        (--tools)
#   --python <python>      vorhandenes Python mit installierten Paketen verwenden
#   --missionen A,B        nur diese Missionen/Kartenordner exportieren (Export)       (--missions)
#   --schritte A,B         nur Tabellen, Missionen, Mehrspieler, Allgemein (Export)    (--steps)
#   --neu                  erledigte Schritte erneut ausführen (Export, Filme)          (--redo)
#   --probelauf            Export: nur offene Schritte auflisten                        (--dry-run)
#   --stufe hd|4k          Hochskalieren: Stufe (Standard hd)                           (--level)
#   --geraet cpu|cuda      Hochskalieren: Rechengerät (Standard cpu)                    (--device)
#   --ordner <Ordner>      Hochskalieren/Installieren: nur diesen Texturordner          (--folder)
#   --threads <n>          Hochskalieren: CPU-Threads begrenzen
#   --ja                   alle Rückfragen mit Ja beantworten (Downloads!)              (--yes)
# Optionen auch in PowerShell-Schreibweise (-Aktion Export, -Orig ...). Export-Status je Schritt in <Ziel>/.dh2_export_status.txt
# (gleiches Format wie unter Windows; fehlgeschlagene Schritte wiederholt der nächste Lauf).

# ---------------------------------------------------------------------------------------------------------------------
# Parameter
# ---------------------------------------------------------------------------------------------------------------------
AKTION=""; ORIG=""; ZIEL=""; WERKZEUGE=""; PYTHON_ARG=""; MISSIONEN=""; SCHRITTE=""; NEU=0; PROBELAUF=0
STUFE="hd"; GERAET="cpu"; GERAET_SET=0; ORDNER=""; THREADS=0; JA=0; SPRACHE=""

usage() { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  key=$(printf '%s' "$1" | sed 's/^-*//' | tr 'A-Z' 'a-z')
  val="${2-}"
  case "$key" in
    aktion|action) AKTION="$val"; shift ;;
    orig|source) ORIG="$val"; shift ;;
    ziel|target) ZIEL="$val"; shift ;;
    werkzeuge|tools) WERKZEUGE="$val"; shift ;;
    python) PYTHON_ARG="$val"; shift ;;
    missionen|missions) MISSIONEN="$MISSIONEN $val"; shift ;;
    schritte|steps) SCHRITTE="$SCHRITTE $val"; shift ;;
    neu|redo) NEU=1 ;;
    probelauf|dryrun|dry-run) PROBELAUF=1 ;;
    stufe|level) STUFE=$(printf '%s' "$val" | tr 'A-Z' 'a-z'); shift ;;
    geraet|device) GERAET=$(printf '%s' "$val" | tr 'A-Z' 'a-z'); GERAET_SET=1; shift ;;
    ordner|folder) ORDNER="$val"; shift ;;
    threads) THREADS="$val"; shift ;;
    ja|yes|y) JA=1 ;;
    sprache|language) SPRACHE=$(printf '%s' "$val" | tr 'A-Z' 'a-z'); shift ;;
    h|help|hilfe) usage; exit 0 ;;
    *) echo "Unbekannte Option / unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
# Aktionsname ohne Groß-/Kleinschreibung auf die kanonische Schreibweise abbilden
canon_action() {
  local a; a=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  for n in Menue Suchen Pruefen Einrichten Export Filme Hochskalieren Installieren Wiederherstellen Status Starten; do
    if [ "$(printf '%s' "$n" | tr 'A-Z' 'a-z')" = "$a" ]; then printf '%s' "$n"; return 0; fi
  done
  return 1
}
if [ -n "$AKTION" ]; then
  AKTION=$(canon_action "$AKTION") || { echo "Unbekannte Aktion / unknown action: $AKTION" >&2; exit 2; }
fi
case "$STUFE" in hd|4k) ;; *) echo "--stufe hd|4k" >&2; exit 2 ;; esac
case "$GERAET" in cpu|cuda) ;; *) echo "--geraet cpu|cuda" >&2; exit 2 ;; esac
case "$SPRACHE" in ""|de|en) ;; *) echo "--sprache de|en" >&2; exit 2 ;; esac
split_list() { printf '%s' "$1" | tr ',; ' '\n\n\n' | sed '/^$/d'; }
MISSIONEN=$(split_list "$MISSIONEN"); SCHRITTE=$(split_list "$SCHRITTE")

# ---------------------------------------------------------------------------------------------------------------------
# Sprache: Parameter > gespeicherte Einstellung > $LANG
# ---------------------------------------------------------------------------------------------------------------------
LANGSEL="en"
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in de*) LANGSEL="de" ;; esac
L() { if [ "$LANGSEL" = "de" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

# ---------------------------------------------------------------------------------------------------------------------
# Pfade
# ---------------------------------------------------------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)                      # Spiel- bzw. Projektordner
PIPELINE="${DH2_PIPELINE:-$ROOT/pipeline}"
[ -n "$WERKZEUGE" ] || WERKZEUGE="$ROOT/werkzeuge"
CONFIG_FILE="$WERKZEUGE/einstellungen.json"
LOG_DIR="$WERKZEUGE/protokolle"
INTERAKTIV=0; { [ -z "$AKTION" ] || [ "$AKTION" = "Menue" ]; } && INTERAKTIV=1

CAMPAIGN="ARCTIC1 ARCTIC2 ARCTIC3 ARCTIC4 AFRICA1 AFRICA2 AFRICA3 AFRICA4 AFRICA5 AFRICA6 NORWAY BURMA1 BURMA2 ALPS1 ALPS2
NORMANDY NORMANDY2 CZECH1 CZECH2 CZECH3 CZECH4 CZECH5 CZECH6 TUTORIAL"
MULTI="ARCTIC1_MP ARCTIC1_OBJ ARCTIC2_MP ARCTIC3_OBJ ARCTIC4_MP_ZONE AFRICA1_MP AFRICA1_OBJ AFRICA2_MP_ZONE AFRICA3_MP
AFRICA3_OBJ AFRICA4_OBJ AFRICA5_MP AFRICA5_MP_ZONE AFRIKA5_MP ALPS1_MP_ZONE ARDENS1_OBJ BURMA1_MP BURMA1_MP_ZONE BURMA1_OBJ
BURMA2_OBJ CZECH1_OBJ CZECH2_MP_ZONE CZECH2_OBJ CZECH3_MP CZECH3_OBJ CZECH4_MP_ZONE CZECH5_MP_ZONE CZECH6_MP_ZONE LONDON_MP
NORMANDY_MP NORMANDY2_MP_ZONE NORMANDY2B_MP_ZONE NORMANDY3_MP NORMANDY3_MP_ZONE"
REQUIRED="hd2.exe rw_data.dll Maps.dta Missions.dta MODELS.DTA Sounds.dta Scripts.dta others.DTA"
OPTIONAL="patch.dta mpmaplist.txt Maps_C.dta Gamemovie PlayersProfiles"
DEV_EXE_SIZE=6889472
# KI-Modelle (Real-ESRGAN, BSD-3-Clause): Name|MB|SHA256|URL
MODELS="RealESRGAN_x4plus.pth|64|4FA0D38905F75AC06EB49A7951B426670021BE3018265FD191D2125DF9D682F1|https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth
realesr-general-x4v3.pth|5|8DC7EDB9AC80CCDC30C3A5DCA6616509367F05FBC184AD95B731F05BECE96292|https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth"
PY_MODS="numpy, PIL, pefile, capstone"

# ---------------------------------------------------------------------------------------------------------------------
# Ausgabe-Helfer
# ---------------------------------------------------------------------------------------------------------------------
if [ -t 1 ]; then C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_C=$'\e[36m'; C_D=$'\e[90m'; C_0=$'\e[0m'
else C_G=""; C_Y=""; C_R=""; C_C=""; C_D=""; C_0=""; fi
Say() { printf '%s%s%s\n' "${2:-}" "$1" "${2:+$C_0}"; }
Ok() { Say "  [OK]     $1" "$C_G"; }
Warn() { Say "$(L "  [HINWEIS] $1" "  [NOTE]   $1")" "$C_Y"; }
Err() { Say "$(L "  [FEHLER] $1" "  [ERROR]  $1")" "$C_R"; }
Title() { Say ""; Say "== $1 ==" "$C_C"; }
Log() { mkdir -p "$LOG_DIR" && printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_DIR/werkzeuge.log"; }
Ask() {  # Ask "Frage" [1 = Standard ja]
  local frage="$1" std="${2:-0}" s a
  if [ "$JA" = 1 ]; then Say "$(L "  $frage -> Ja (--ja)" "  $frage -> Yes (--ja)")"; return 0; fi
  if [ "$INTERAKTIV" != 1 ]; then Say "$(L "  $frage -> Nein (nicht-interaktiv, --ja zum Bestätigen)" "  $frage -> No (non-interactive, use --ja to confirm)")"; return 1; fi
  if [ "$std" = 1 ]; then s=$(L "[J/n]" "[Y/n]"); else s=$(L "[j/N]" "[y/N]"); fi
  read -r -p "  $frage $s " a
  [ -z "$a" ] && { [ "$std" = 1 ]; return; }
  case "$(printf '%s' "$a" | tr 'A-Z' 'a-z')" in j*|y*) return 0 ;; *) return 1 ;; esac
}
Pause_Menu() { [ "$INTERAKTIV" = 1 ] && read -r -p "$(printf '\n  %s ' "$(L "Weiter mit Eingabetaste" "Press Enter to continue")")" _; }
Fmt_Size() { awk -v b="$1" 'BEGIN { if (b >= 1073741824) printf "%.1f GB", b/1073741824; else if (b >= 1048576) printf "%.0f MB", b/1048576; else printf "%.0f KB", b/1024 }'; }
Dir_Stats() {  # Dir_Stats ordner [muster] -> "N B"
  [ -d "$1" ] || { echo "0 0"; return; }
  find "$1" -type f -iname "${2:-*}" -printf '%s\n' 2>/dev/null | awk '{ n++; s += $1 } END { printf "%d %d\n", n, s }'
}
# Datei/Ordner ohne Beachtung der Groß-/Kleinschreibung finden (Windows-Installationen auf ext4: MODELS.DTA vs. Models.dta)
ci_path() {
  local d="$1" n="$2" hit
  [ -e "$d/$n" ] && { printf '%s' "$d/$n"; return 0; }
  hit=$(find "$d" -mindepth 1 -maxdepth 1 -iname "$n" -print -quit 2>/dev/null)
  [ -n "$hit" ] && { printf '%s' "$hit"; return 0; }
  return 1
}
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
upper() { printf '%s' "$1" | tr 'a-z' 'A-Z'; }

# ---------------------------------------------------------------------------------------------------------------------
# Einstellungen (einstellungen.json, gleiches Format wie unter Windows: Orig, Python, Sprache, Ziel)
# ---------------------------------------------------------------------------------------------------------------------
json_get() {  # json_get datei schluessel
  [ -f "$1" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8-sig"))
    v = d.get(sys.argv[2]) or ""
    print(v if isinstance(v, str) else "")
except Exception:
    pass' "$1" "$2" 2>/dev/null
  else
    sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$1" | head -n 1
  fi
}
CFG_ORIG=$(json_get "$CONFIG_FILE" Orig); CFG_ZIEL=$(json_get "$CONFIG_FILE" Ziel)
CFG_PYTHON=$(json_get "$CONFIG_FILE" Python); CFG_SPRACHE=$(json_get "$CONFIG_FILE" Sprache)
Save_Config() {
  mkdir -p "$WERKZEUGE" || return 1
  local ziel=""; [ "$CFG_ZIEL" != "$ROOT/orig_cache" ] && ziel="$CFG_ZIEL"   # Standardziel nicht festschreiben
  if command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json,sys
o = {"Orig": sys.argv[2], "Python": sys.argv[3]}
if sys.argv[4]: o["Sprache"] = sys.argv[4]
if sys.argv[5]: o["Ziel"] = sys.argv[5]
json.dump(o, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False, indent=4)' \
      "$CONFIG_FILE" "$CFG_ORIG" "$CFG_PYTHON" "$CFG_SPRACHE" "$ziel"
  else
    Warn "$(L "python3 fehlt – Einstellungen werden nicht gespeichert." "python3 missing – settings are not saved.")"
  fi
}
SAVE_LANG=0
case "$CFG_SPRACHE" in de|en) LANGSEL="$CFG_SPRACHE" ;; esac
if [ -n "$SPRACHE" ]; then LANGSEL="$SPRACHE"; [ "$CFG_SPRACHE" != "$SPRACHE" ] && { CFG_SPRACHE="$SPRACHE"; SAVE_LANG=1; }; fi
[ -n "$ORIG" ] && CFG_ORIG="$ORIG"
[ -n "$ZIEL" ] && CFG_ZIEL="$ZIEL"
[ -n "$PYTHON_ARG" ] && CFG_PYTHON="$PYTHON_ARG"
# Windows-Pfade aus einer mitkopierten Einstellungsdatei unter Linux nicht verwenden
case "$CFG_ORIG" in [A-Za-z]:\\*|[A-Za-z]:/*) CFG_ORIG="" ;; esac
case "$CFG_ZIEL" in [A-Za-z]:\\*|[A-Za-z]:/*) CFG_ZIEL="" ;; esac
case "$CFG_PYTHON" in *.exe|*.EXE|[A-Za-z]:\\*) CFG_PYTHON="" ;; esac
[ -n "$CFG_ZIEL" ] || CFG_ZIEL="$ROOT/orig_cache"
[ "$SAVE_LANG" = 1 ] && [ "$INTERAKTIV" = 1 ] && Save_Config 2>/dev/null

# =====================================================================================================================
# 1) Original-Installation suchen / prüfen
# =====================================================================================================================
FOUND_PATHS=(); FOUND_SRC=()
add_cand() {
  local p="${1%/}" src="$2" i
  [ -n "$p" ] && [ -d "$p" ] || return 0
  ci_path "$p" "hd2.exe" >/dev/null || return 0
  p=$(cd "$p" && pwd)
  for i in "${FOUND_PATHS[@]}"; do [ "$i" = "$p" ] && return 0; done
  FOUND_PATHS+=("$p"); FOUND_SRC+=("$src")
}
scan_hd2() {  # scan_hd2 basisordner tiefe quelle: sucht hd2.exe (Groß-/Kleinschreibung egal) bis zur angegebenen Tiefe
  local base="$1" depth="$2" src="$3" f
  [ -d "$base" ] || return 0
  while IFS= read -r f; do
    add_cand "$(dirname "$f")" "$src"
  done < <(find "$base" -maxdepth "$depth" -type f -iname 'hd2.exe' 2>/dev/null)
}
Find_Installations() {
  FOUND_PATHS=(); FOUND_SRC=()
  local h="$HOME" lib vdf
  # Steam (nativ, Flatpak, Snap) inkl. weiterer Bibliotheken aus libraryfolders.vdf
  for lib in "$h/.steam/steam" "$h/.steam/root" "$h/.local/share/Steam" "$h/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
             "$h/snap/steam/common/.local/share/Steam"; do
    [ -d "$lib/steamapps" ] || continue
    scan_hd2 "$lib/steamapps/common" 3 "Steam"
    vdf="$lib/steamapps/libraryfolders.vdf"
    if [ -f "$vdf" ]; then
      while IFS= read -r p; do scan_hd2 "$p/steamapps/common" 3 "Steam"; done \
        < <(sed -n 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$vdf")
    fi
  done
  # Heroic (GOG), Lutris, eigene Spieleordner
  scan_hd2 "$h/Games" 5 "$(L "Spieleordner/Heroic/Lutris" "games folder/Heroic/Lutris")"
  scan_hd2 "$h/GOG Games" 3 "GOG"
  scan_hd2 "$h/.config/heroic" 6 "Heroic"
  scan_hd2 "$h/.var/app/com.heroicgameslauncher.hgl" 8 "Heroic (Flatpak)"
  scan_hd2 "$h/.local/share/lutris" 6 "Lutris"
  scan_hd2 "$h/.var/app/net.lutris.Lutris/data/lutris" 6 "Lutris (Flatpak)"
  # Wine-Präfixe (Standard + weitere ~/.wine*, ~/.local/share/wineprefixes, Bottles)
  for lib in "$h"/.wine* "$h/.local/share/wineprefixes"/* "$h/.var/app/com.usebottles.bottles/data/bottles/bottles"/* \
             "$h/.local/share/bottles/bottles"/*; do
    [ -d "$lib/drive_c" ] && scan_hd2 "$lib/drive_c" 5 "Wine ($lib)"
  done
  # Proton-Präfixe enthalten bei Nicht-Steam-Spielen gelegentlich eine Kopie
  for lib in "$h/.steam/steam/steamapps/compatdata"/* "$h/.local/share/Steam/steamapps/compatdata"/*; do
    [ -d "$lib/pfx/drive_c" ] && scan_hd2 "$lib/pfx/drive_c" 5 "Proton"
  done
  # Eingehängte Windows-Laufwerke
  for lib in /mnt/* /media/"$USER"/* /run/media/"$USER"/*; do
    [ -d "$lib" ] || continue
    for sub in "Program Files (x86)" "Program Files" "GOG Games" "Games" "Spiele"; do scan_hd2 "$lib/$sub" 3 "$(L "Laufwerk" "drive") $lib"; done
  done
  add_cand "$(dirname "$ROOT")/HD2_orig" "$(L "Arbeitsordner" "work folder")"
}

Get_Py() {
  local c
  for c in "$CFG_PYTHON" "$WERKZEUGE/pyenv/bin/python"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
    [ -n "$c" ] && command -v "$c" >/dev/null 2>&1 && [ "${c#/}" = "$c" ] && { command -v "$c"; return 0; }
  done
  return 1
}
Test_PyModules() { "$1" -I -c "import $2" >/dev/null 2>&1; }

EDITION=""; EDITION_EXTRA=""
Get_Edition() {  # liest nur die Archivverzeichnisse; ohne Python/Skript keine Aussage
  EDITION=""; EDITION_EXTRA=""
  local py sp out; py=$(Get_Py) || return 0
  sp="$PIPELINE/hd2_edition.py"; [ -f "$sp" ] || return 0
  out=$(PYTHONIOENCODING=utf-8 "$py" -I "$sp" "$1" 2>/dev/null | tail -n 1) || return 0
  [ -n "$out" ] || return 0
  EDITION=$(printf '%s' "$out" | "$py" -I -c 'import json,sys; print(json.load(sys.stdin).get("edition",""))' 2>/dev/null)
  EDITION_EXTRA=$(printf '%s' "$out" | "$py" -I -c 'import json,sys; print(", ".join(json.load(sys.stdin).get("extra_missions",[])))' 2>/dev/null)
}

TI_OK=0; TI_FEHLT=""
Test_Installation() {  # Test_Installation ordner [quiet]
  local p="$1" quiet="${2:-0}" f exe len version="" warns=()
  TI_OK=0; TI_FEHLT=""
  if [ -z "$p" ] || [ ! -d "$p" ]; then
    TI_FEHLT=$(L "Ordner" "folder"); [ "$quiet" = 1 ] || Err "$(L "Ordner nicht gefunden: $p" "Folder not found: $p")"; return 1
  fi
  for f in $REQUIRED; do ci_path "$p" "$f" >/dev/null || TI_FEHLT="${TI_FEHLT:+$TI_FEHLT, }$f"; done
  for f in $OPTIONAL; do ci_path "$p" "$f" >/dev/null || warns+=("$(L "optional fehlt: $f" "optional, missing: $f")"); done
  if exe=$(ci_path "$p" "hd2.exe"); then
    len=$(stat -c %s "$exe" 2>/dev/null || wc -c < "$exe")
    if [ "$len" = "$DEV_EXE_SIZE" ]; then version=$(L "Original-CD-Version mit Patch (wie Entwicklungsstand)" "original CD version with patch (as used for development)")
    else
      version=$(L "abweichende hd2.exe ($len Byte)" "different hd2.exe ($len bytes)")
      warns+=("$(L "Andere hd2.exe als beim Entwickeln (z. B. Steam/GOG oder anderer Patch) – einzelne Daten können abweichen." "Different hd2.exe than used for development (e.g. Steam/GOG or another patch) – some data may differ.")")
    fi
  fi
  Get_Edition "$p"
  if [ "$EDITION" = "cuf" ]; then
    warns+=("$(L "Erweiterung erkannt ('Courage Under Fire' / 'Sabre Squadron', zusätzliche Missionen: $EDITION_EXTRA). Entwickelt wurde mit dem Grundspiel – der Export übernimmt dessen Missionen, Abweichungen sind möglich." "Expansion detected ('Courage Under Fire' / 'Sabre Squadron', additional missions: $EDITION_EXTRA). Development used the base game – the export takes its missions, differences are possible.")")
  fi
  ci_path "$p" "patch.dta" >/dev/null || warns+=("$(L "patch.dta fehlt – ohne offiziellen Patch fehlen Mehrspielerkarten/neuere Daten." "patch.dta missing – without the official patch multiplayer maps/newer data are missing.")")
  [ -z "$TI_FEHLT" ] && TI_OK=1
  if [ "$quiet" != 1 ]; then
    Say "$(L "  Ordner:  $p" "  Folder:  $p")"
    [ -n "$version" ] && Say "  Version: $version"
    if [ "$TI_OK" = 1 ]; then Ok "$(L "Alle benötigten Dateien vorhanden." "All required files present.")"; else Err "$(L "Es fehlen: $TI_FEHLT" "Missing: $TI_FEHLT")"; fi
    for f in "${warns[@]}"; do Warn "$f"; done
  fi
  [ "$TI_OK" = 1 ]
}

Action_Suchen() {
  Title "$(L "Original-Installation suchen" "Find original installation")"
  Say "$(L "  Suche in Steam, Heroic/GOG, Lutris, Wine-Präfixen und üblichen Ordnern …" "  Searching Steam, Heroic/GOG, Lutris, Wine prefixes and common folders …")"
  Find_Installations
  if [ -n "$ORIG" ]; then FOUND_PATHS=("$ORIG" "${FOUND_PATHS[@]}"); FOUND_SRC=("Parameter" "${FOUND_SRC[@]}"); fi
  local i n=${#FOUND_PATHS[@]} wahl="" a
  for ((i = 0; i < n; i++)); do Say "  $((i + 1))) ${FOUND_PATHS[$i]}   (${FOUND_SRC[$i]})"; done
  [ "$n" = 0 ] && Warn "$(L "Keine Installation automatisch gefunden." "No installation found automatically.")"
  if [ "$INTERAKTIV" = 1 ]; then
    read -r -p "$(L "  Nummer wählen oder Pfad eingeben (Ordner mit hd2.exe), leer = abbrechen: " "  Choose a number or enter a path (folder containing hd2.exe), empty = cancel: ")" a
    [ -z "$a" ] && return 0
    if [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le "$n" ]; then wahl="${FOUND_PATHS[$((a - 1))]}"
    else wahl=$(printf '%s' "$a" | sed "s/^[\"' ]*//; s/[\"' ]*\$//"); wahl="${wahl/#\~/$HOME}"; fi
  elif [ "$n" -gt 0 ]; then wahl="${FOUND_PATHS[0]}"; fi
  [ -n "$wahl" ] || { Err "$(L "Keine Installation angegeben (--orig <Ordner>)." "No installation given (--orig <folder>).")"; return 1; }
  if Test_Installation "$wahl"; then CFG_ORIG="$wahl"; Save_Config; Ok "$(L "Gespeichert als Original-Installation." "Saved as original installation.")"; fi
}

Require_Orig() {
  if [ -z "$CFG_ORIG" ]; then
    Find_Installations
    if [ ${#FOUND_PATHS[@]} -gt 0 ]; then CFG_ORIG="${FOUND_PATHS[0]}"; Say "$(L "  Original-Installation gefunden: $CFG_ORIG" "  Original installation found: $CFG_ORIG")"; fi
  fi
  [ -n "$CFG_ORIG" ] || { Err "$(L "Keine Original-Installation gewählt – Menüpunkt 1 (oder --orig <Ordner>)." "No original installation selected – menu item 1 (or --orig <folder>).")"; return 1; }
  Test_Installation "$CFG_ORIG" 1 || { Err "$(L "Installation unvollständig ($CFG_ORIG): es fehlen $TI_FEHLT" "Installation incomplete ($CFG_ORIG): missing $TI_FEHLT")"; return 1; }
}

# =====================================================================================================================
# 2) Werkzeuge einrichten (Python-venv, Pakete, ffmpeg)
# =====================================================================================================================
distro_hint() {  # distro_hint python|ffmpeg
  local id=""; [ -f /etc/os-release ] && id=$(. /etc/os-release; printf '%s %s' "${ID:-}" "${ID_LIKE:-}")
  case "$1:$id" in
    python:*debian*|python:*ubuntu*) local pv; pv=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)
      echo "sudo apt install python3 python3-venv python3-pip${pv:+ python$pv-venv}" ;;
    python:*fedora*|python:*rhel*) echo "sudo dnf install python3 python3-pip" ;;
    python:*arch*) echo "sudo pacman -S python python-pip" ;;
    python:*suse*) echo "sudo zypper install python3 python3-pip" ;;
    ffmpeg:*debian*|ffmpeg:*ubuntu*) echo "sudo apt install ffmpeg" ;;
    ffmpeg:*fedora*|ffmpeg:*rhel*) echo "sudo dnf install ffmpeg   (RPM Fusion)" ;;
    ffmpeg:*arch*) echo "sudo pacman -S ffmpeg" ;;
    ffmpeg:*suse*) echo "sudo zypper install ffmpeg   (Packman)" ;;
    python:*) echo "python3 (3.10–3.14) + venv/pip über die Paketverwaltung / via your package manager" ;;
    *) echo "ffmpeg über die Paketverwaltung / via your package manager" ;;
  esac
}
Find_SystemPython() {
  local c v
  for c in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
    command -v "$c" >/dev/null 2>&1 || continue
    v=$("$c" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null) || continue
    case "$v" in 3.10|3.11|3.12|3.13|3.14) printf '%s|%s' "$(command -v "$c")" "$v"; return 0 ;; esac
  done
  return 1
}
Install_Requirements() {  # py datei [extra …]
  local py="$1" file="$2"; shift 2
  Say "$(L "  Installiere Pakete aus $(basename "$file") (nur in $WERKZEUGE) …" "  Installing packages from $(basename "$file") (only into $WERKZEUGE) …")"
  "$py" -m pip install --disable-pip-version-check --no-warn-script-location -r "$file" "$@" ||
    { Err "$(L "pip-Installation fehlgeschlagen ($file). Internetverbindung prüfen und erneut versuchen." "pip installation failed ($file). Check the internet connection and try again.")"; return 1; }
}
Setup_Python() {  # Ergebnis in SETUP_PY (Pfad des eingerichteten Pythons)
  local py sys exe v venv="$WERKZEUGE/pyenv"
  py=$(Get_Py)
  if [ -n "$py" ] && Test_PyModules "$py" "$PY_MODS"; then Ok "$(L "Python-Umgebung bereit: $py" "Python environment ready: $py")"; SETUP_PY="$py"; return 0; fi
  if [ -z "$py" ]; then
    Say "$(L "  Für den Export wird Python 3.10–3.14 benötigt. Es wird eine eigene Umgebung (venv) in $WERKZEUGE angelegt." "  The export needs Python 3.10–3.14. A separate environment (venv) will be created in $WERKZEUGE.")"
    if ! sys=$(Find_SystemPython); then
      Err "$(L "Kein passendes python3 (3.10–3.14) gefunden. Bitte installieren:" "No suitable python3 (3.10–3.14) found. Please install:")"
      Say "    $(distro_hint python)"; return 1
    fi
    exe="${sys%|*}"; v="${sys#*|}"
    Say "$(L "  Gefunden: Python $v ($exe)." "  Found: Python $v ($exe).")"
    Ask "$(L "Damit eine isolierte Umgebung (venv) in werkzeuge/pyenv anlegen?" "Create an isolated environment (venv) in werkzeuge/pyenv with it?")" 1 ||
      { Warn "$(L "Abgebrochen – ohne Python ist kein Export möglich." "Cancelled – no export possible without Python.")"; return 1; }
    mkdir -p "$WERKZEUGE"
    if ! "$exe" -m venv "$venv"; then
      rm -rf "$venv"
      Err "$(L "venv konnte nicht angelegt werden (Paket python3-venv fehlt?):" "venv could not be created (package python3-venv missing?):")"
      Say "    $(distro_hint python)"; return 1
    fi
    py="$venv/bin/python"
    "$py" -m pip --version >/dev/null 2>&1 || "$py" -m ensurepip --upgrade >/dev/null 2>&1
  fi
  Install_Requirements "$py" "$SCRIPT_DIR/requirements.txt" || return 1
  Test_PyModules "$py" "$PY_MODS" || { Err "$(L "Pakete fehlen nach der Installation." "Packages missing after installation.")"; return 1; }
  CFG_PYTHON="$py"; Save_Config
  Ok "$(L "Python-Umgebung bereit: $py" "Python environment ready: $py")"
  SETUP_PY="$py"
}
Find_Ffmpeg() {
  local c
  for c in "$WERKZEUGE/ffmpeg/bin/ffmpeg" "$WERKZEUGE/ffmpeg"; do [ -f "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }; done
  command -v ffmpeg 2>/dev/null
}
Setup_Ffmpeg() {
  local f; f=$(Find_Ffmpeg)
  if [ -n "$f" ]; then Ok "ffmpeg: $f"; return 0; fi
  Say "$(L "  ffmpeg (für die Filme) fehlt. Bitte über die Paketverwaltung installieren:" "  ffmpeg (for the movies) is missing. Please install it via your package manager:")"
  Say "    $(distro_hint ffmpeg)"
  Say "$(L "  (oder eine eigene ffmpeg-Datei nach $WERKZEUGE/ffmpeg/bin/ kopieren)." "  (or copy your own ffmpeg binary to $WERKZEUGE/ffmpeg/bin/).")"
  return 1
}
Action_Einrichten() {
  Title "$(L "Werkzeuge einrichten" "Set up tools")"
  Say "$(L "  Zielordner: $WERKZEUGE" "  Target folder: $WERKZEUGE")"
  mkdir -p "$WERKZEUGE"
  [ -f "$PIPELINE/convert_mission.py" ] || { Err "$(L "Konverter fehlen ($PIPELINE). Das Paket ist unvollständig." "Converters missing ($PIPELINE). The package is incomplete.")"; return 1; }
  Ok "$(L "Konverter: $PIPELINE" "Converters: $PIPELINE")"
  local rc=0
  Setup_Python || { Log "Einrichten Python fehlgeschlagen"; rc=1; }
  Setup_Ffmpeg
  return $rc
}

# =====================================================================================================================
# 3) Spieldaten exportieren
# =====================================================================================================================
STATE_FILE=""; EXPORT_LOG=""; declare -A STATE=()
State_Has() { [ -n "${STATE[$1]+x}" ]; }
State_Add() { STATE["$1"]=1; printf '%s\n' "$1" >> "$STATE_FILE"; }

Run_Py() {  # Run_Py label skript [argumente …]
  local label="$1" script="$2" sp code; shift 2
  sp="$PIPELINE/$script"
  [ -f "$sp" ] || { printf '!! %s fehlt\n' "$script" >> "$EXPORT_LOG"; return 1; }
  printf -- '---- %s :: %s %s  %s\n' "$label" "$script" "$*" "$(date +%H:%M:%S)" >> "$EXPORT_LOG"
  ( cd "$PIPELINE" && exec nice -n 10 "$PY" -I "$sp" "$@" ) >> "$EXPORT_LOG" 2>&1
  code=$?
  [ "$code" -ne 0 ] && printf '!! Exit %s\n' "$code" >> "$EXPORT_LOG"
  return "$code"
}
# Schrittlisten: je Zeile "skript<TAB>arg1<TAB>arg2…" (identisch mit hd2_menu.ps1)
Mission_Steps() {
  local m="$1" l c="$CFG_ZIEL"; l=$(lower "$m")
  printf '%s\t%s\n' convert_mission.py "$m"
  printf '%s\t%s\t%s\n' fmt_mission_extra.py "$m" "$c/$l/extra.json"
  printf '%s\t%s\n' extract_mission_audio.py "$m"
  printf '%s\t%s\n' export_characters.py "$m"
  printf '%s\t%s\t%s\n' fmt_actors_items.py "$m" "$c/$l/actor_params.json"
  printf '%s\t%s\n' fmt_interactive.py "$m"
  printf '%s\t%s\n' fmt_drive.py "$m"
  printf '%s\t%s\n' fmt_vehicles.py "$m"
  printf '%s\t%s\n' fmt_vehicle_dm.py "$m"
  printf '%s\t%s\n' fmt_klz.py "$m"
  printf '%s\t%s\n' fmt_meshplayer.py "$m"
  printf '%s\t%s\n' fmt_mp_screens.py "$m"
  [ "$m" = "AFRICA6" ] && printf '%s\n' fmt_ju88.py
  return 0
}
# Allgemeine Schritte: je Zeile "schluessel<TAB>titel<TAB>skript<TAB>args…"
General_Steps() {
  local c="$CFG_ZIEL" o="$CFG_ORIG" pp
  printf '%s\t%s\t%s\n' mp "$(L "Mehrspielerkarten (Regeln/Zonen)" "Multiplayer maps (rules/zones)")" fmt_mp.py
  printf '%s\t%s\t%s\t%s\n' vehicle_dm "$(L "Fahrzeug-Schadensmodelle" "Vehicle damage models")" fmt_vehicle_dm.py --all
  printf '%s\t%s\t%s\n' weapons "$(L "Waffen" "Weapons")" export_weapons.py
  printf '%s\t%s\t%s\t%s\n' hands "$(L "Ego-Hände" "First-person hands")" export_weapons.py --hands
  printf '%s\t%s\t%s\n' anims "$(L "Skriptanimationen" "Script animations")" fmt_i3d.py
  printf '%s\t%s\t%s\n' dmodels "$(L "Zerstörbare Objekte" "Destructible objects")" fmt_dmodels.py
  printf '%s\t%s\t%s\n' commands "$(L "Befehlsmenü + Sprachausgabe" "Command menu + speech")" fmt_commands.py
  printf '%s\t%s\t%s\n' sounds "$(L "Klänge und Musik" "Sounds and music")" fmt_sounds.py
  printf '%s\t%s\t%s\n' dabing "$(L "Gesichtsdaten der Sprache" "Lip-sync face data")" fmt_dabing.py
  printf '%s\t%s\t%s\t%s\n' characters_morph "$(L "Alle Figuren mit Gesichtsanimation" "All characters with facial animation")" export_characters.py --all
  printf '%s\t%s\t%s\t%s\t%s\n' blood "$(L "Bluttexturen" "Blood textures")" fmt_blood.py "$o" "$c"
  printf '%s\t%s\t%s\n' humanzones "$(L "Trefferzonen" "Hit zones")" fmt_humanzones.py
  printf '%s\t%s\t%s\n' gamedata "$(L "Missionsdatenbank" "Mission database")" fmt_gamedata.py
  printf '%s\t%s\t%s\n' roster "$(L "Soldaten und Ausrüstung" "Soldiers and equipment")" fmt_roster.py
  printf '%s\t%s\t%s\n' hud "HUD" export_hud.py
  printf '%s\t%s\t%s\n' menu "$(L "Menüs" "Menus")" _menu_export.py
  printf '%s\t%s\t%s\n' menu_inv "$(L "Inventar-Bildschirm" "Inventory screen")" _menu_export_ingame_inv.py
  printf '%s\t%s\t%s\n' menu_spec "$(L "Menü-Texte/Ablauf" "Menu texts/flow")" _menu_spec.py
  printf '%s\t%s\t%s\t%s\t%s\n' fonts "$(L "Originalschriften" "Original fonts")" fmt_fonts.py "$o" "$c/ui/fonts"
  if pp=$(ci_path "$o" "PlayersProfiles"); then
    printf '%s\t%s\t%s\t%s\t%s\n' profiles "$(L "Spielerprofile (Übernahme)" "Player profiles (import)")" fmt_profile.py "$pp" "$c/profiles_import.json"
  fi
}

Action_Export() {
  Title "$(L "Spieldaten exportieren" "Export game data")"
  Require_Orig || return 1
  PY=$(Get_Py)
  if [ -z "$PY" ] || ! Test_PyModules "$PY" "$PY_MODS"; then
    Warn "$(L "Python-Umgebung fehlt oder ist unvollständig." "Python environment missing or incomplete.")"
    if Ask "$(L "Jetzt einrichten (Menüpunkt 2)?" "Set it up now (menu item 2)?")" 1; then SETUP_PY=""; Setup_Python; PY="$SETUP_PY"; else PY=""; fi
    [ -n "$PY" ] || return 1
  fi
  # Die Original-Installation wird nie beschrieben: Ziel darf nicht in ihr liegen
  local oFull zFull
  oFull="$(realpath -m "$CFG_ORIG")/"; zFull="$(realpath -m "$CFG_ZIEL")/"
  case "$zFull" in "$oFull"*) Err "$(L "Ziel liegt in der Original-Installation ($CFG_ZIEL) – bitte einen anderen Ordner wählen (--ziel)." "Target is inside the original installation ($CFG_ZIEL) – please choose another folder (--ziel).")"; return 1 ;; esac
  mkdir -p "$CFG_ZIEL" "$LOG_DIR"
  EXPORT_LOG="$LOG_DIR/export_$(date +%Y%m%d_%H%M%S).log"; : > "$EXPORT_LOG"
  STATE_FILE="$CFG_ZIEL/.dh2_export_status.txt"; STATE=()
  if [ "$NEU" = 1 ]; then rm -f "$STATE_FILE"
  elif [ -f "$STATE_FILE" ]; then
    # Datei kann unter Windows entstanden sein (BOM, CRLF)
    while IFS= read -r line; do line="${line//$'\r'/}"; line="${line#$'\xEF\xBB\xBF'}"; [ -n "$line" ] && STATE["$line"]=1; done < "$STATE_FILE"
  fi
  # Letzte Zeile ohne Zeilenende abschließen, damit angehängte Einträge nicht verschmelzen
  [ -s "$STATE_FILE" ] && [ -n "$(tail -c 1 "$STATE_FILE")" ] && printf '\n' >> "$STATE_FILE"
  export DH2_ORIG="$CFG_ORIG" DH2_CACHE="$CFG_ZIEL" DH2_WAV_TABLES="$WERKZEUGE/wav_tables.json" PYTHONIOENCODING=utf-8 PYTHONUTF8=1
  Say "$(L "  Quelle (nur lesen): $CFG_ORIG" "  Source (read-only): $CFG_ORIG")"
  Say "$(L "  Ziel:               $CFG_ZIEL" "  Target:             $CFG_ZIEL")"
  Say "$(L "  Protokoll:          $EXPORT_LOG" "  Log:                $EXPORT_LOG")"
  Say "$(L "  Bereits erledigte Schritte werden übersprungen (--neu bzw. Menü: n = alles wiederholen). Abbruch jederzeit mit Strg+C." "  Steps already done are skipped (--neu or menu: n = redo everything). Cancel any time with Ctrl+C.")"
  Log "Export gestartet: $CFG_ORIG -> $CFG_ZIEL"

  local gruppen="${SCHRITTE:-$(printf 'Tabellen\nMissionen\nMehrspieler\nAllgemein')}" miss="" mp="" m u
  if [ -n "$MISSIONEN" ]; then
    for m in $MISSIONEN; do u=$(upper "$m"); if printf '%s\n' $MULTI | grep -qx "$u"; then mp="$mp $u"; else miss="$miss $u"; fi; done
  else miss="$CAMPAIGN"; mp="$MULTI"; fi
  printf '%s\n' "$gruppen" | grep -qix Missionen || miss=""
  printf '%s\n' "$gruppen" | grep -qix Mehrspieler || mp=""
  # Jobs: JOB_K[i], JOB_T[i], JOB_M[i], JOB_S[i] (Schrittzeilen, durch Zeilenumbruch getrennt)
  local -a JOB_K=() JOB_T=() JOB_M=() JOB_S=()
  if printf '%s\n' "$gruppen" | grep -qix Tabellen; then JOB_K+=(wavtables); JOB_T+=("$(L "Audiotabellen" "Audio tables")"); JOB_M+=(""); JOB_S+=("read_wav_tables.py"); fi
  for m in $miss $mp; do JOB_K+=("mission:$m"); JOB_T+=("Mission $m"); JOB_M+=("$m"); JOB_S+=("$(Mission_Steps "$m")"); done
  if printf '%s\n' "$gruppen" | grep -qix Allgemein; then
    local k t rest
    while IFS=$'\t' read -r k t rest; do JOB_K+=("global:$k"); JOB_T+=("$t"); JOB_M+=(""); JOB_S+=("$rest"); done < <(General_Steps)
  fi
  local total=${#JOB_K[@]} i n st sk scr fehlt="" bad ok dt ts t0 fehler=() okLevel
  # O-023: fehlende Konverter vorab melden
  for scr in $(printf '%s\n' "${JOB_S[@]}" | cut -f1 | sort -u); do [ -f "$PIPELINE/$scr" ] || fehlt="${fehlt:+$fehlt, }$scr"; done
  [ -n "$fehlt" ] && Warn "$(L "Konverter fehlen in $PIPELINE: $fehlt – diese Schritte scheitern und werden beim nächsten Lauf wiederholt." "Converters missing in $PIPELINE: $fehlt – these steps fail and are retried on the next run.")"
  if [ "$PROBELAUF" = 1 ]; then
    Say "$(L "  PROBELAUF – es wird nichts ausgeführt. Offene Schritte:" "  DRY RUN – nothing is executed. Open steps:")"
    for ((i = 0; i < total; i++)); do
      State_Has "${JOB_K[$i]}" && continue
      n=0
      while IFS= read -r st; do
        n=$((n + 1)); scr="${st%%$'\t'*}"
        State_Has "${JOB_K[$i]}#$n:$scr" || Say "$(printf '    %-28s %s %s' "${JOB_T[$i]}" "$scr" "$(printf '%s' "$st" | cut -s -f2- | sed 's/\t/" "/g; s/^/"/; s/$/"/; s/^""$//')")" "$C_D"
      done <<< "${JOB_S[$i]}"
    done
    return 0
  fi
  t0=$(date +%s)
  for ((i = 0; i < total; i++)); do
    if State_Has "${JOB_K[$i]}"; then Say "$(printf '  [%3d/%d] %-34s %s' $((i + 1)) "$total" "${JOB_T[$i]}" "$(L "bereits erledigt" "already done")")" "$C_D"; continue; fi
    printf '  [%3d/%d] %-34s …\r' $((i + 1)) "$total" "${JOB_T[$i]}"
    ts=$(date +%s); ok=1; bad=""; n=0
    while IFS= read -r st; do
      # B-024/O-001: Status je Schritt ("<job>#<nr>:<skript>"); Job erledigt erst, wenn ALLE Schritte liefen
      n=$((n + 1)); scr="${st%%$'\t'*}"; sk="${JOB_K[$i]}#$n:$scr"
      State_Has "$sk" && continue
      local -a argv=(); IFS=$'\t' read -r -a argv <<< "$st"
      if Run_Py "${JOB_T[$i]}" "${argv[@]}" < /dev/null; then State_Add "$sk"; else ok=0; bad="${bad:+$bad, }$scr"; fi
    done <<< "${JOB_S[$i]}"
    if [ -n "${JOB_M[$i]}" ]; then [ -f "$CFG_ZIEL/$(lower "${JOB_M[$i]}")/scene.glb" ] && okLevel=1 || okLevel=0; else okLevel=$ok; fi
    dt=$(( $(date +%s) - ts ))
    if [ "$ok" = 1 ]; then Say "$(printf '  [%3d/%d] %-34s OK (%d s)' $((i + 1)) "$total" "${JOB_T[$i]}" "$dt")" "$C_G"; State_Add "${JOB_K[$i]}"
    elif [ "$okLevel" = 1 ]; then Say "$(printf '  [%3d/%d] %-34s %s (%s)' $((i + 1)) "$total" "${JOB_T[$i]}" "$(L "teilweise" "partial")" "$bad")" "$C_Y"; fehler+=("${JOB_T[$i]}: $bad")
    else Say "$(printf '  [%3d/%d] %-34s %s (%s)' $((i + 1)) "$total" "${JOB_T[$i]}" "$(L "FEHLER" "ERROR")" "$bad")" "$C_R"; fehler+=("${JOB_T[$i]}: $bad"); fi
  done
  local dauer=$(( ($(date +%s) - t0) / 60 ))
  Say ""
  if [ ${#fehler[@]} -gt 0 ]; then
    Warn "$(L "${#fehler[@]} Schritt(e) mit Fehlern (Einzelheiten im Protokoll $EXPORT_LOG):" "${#fehler[@]} step(s) with errors (details in log $EXPORT_LOG):")"
    for t in "${fehler[@]}"; do Say "     - $t" "$C_Y"; done
    Say "$(L "  Ein erneuter Start wiederholt nur die fehlgeschlagenen Schritte." "  Running again repeats only the failed steps.")"
  else Ok "$(L "Export abgeschlossen ($dauer min)." "Export finished ($dauer min).")"; fi
  Log "Export beendet, Fehler: ${#fehler[@]}"
  return 0
}

# =====================================================================================================================
# 4) Filme
# =====================================================================================================================
Action_Filme() {
  Title "$(L "Filme konvertieren (Bink -> Ogg Theora)" "Convert movies (Bink -> Ogg Theora)")"
  Require_Orig || return 1
  local src ff out log f base dst tmp n=0 i=0 err=0 cnt
  src=$(ci_path "$CFG_ORIG" "Gamemovie") || { Err "$(L "Kein Ordner Gamemovie in der Installation." "No Gamemovie folder in the installation.")"; return 1; }
  ff=$(Find_Ffmpeg); [ -n "$ff" ] || { Setup_Ffmpeg; Err "$(L "ffmpeg fehlt – Menüpunkt 2." "ffmpeg missing – menu item 2.")"; return 1; }
  out="$CFG_ZIEL/movies"; mkdir -p "$out" "$LOG_DIR"; log="$LOG_DIR/filme.log"
  cnt=$(find "$src" -maxdepth 1 -type f -iname '*.bik' | wc -l)
  Say "$(L "  $cnt Filme, Ziel $out (fertige werden übersprungen)." "  $cnt movies, target $out (finished ones are skipped).")"
  while IFS= read -r f; do
    i=$((i + 1)); base=$(basename "$f"); dst="$out/${base%.*}.ogv"
    [ -f "$dst" ] && [ "$NEU" != 1 ] && continue
    printf '  [%d/%d] %s\r' "$i" "$cnt" "$base"
    tmp="$dst.tmp.ogv"
    if "$ff" -nostdin -hide_banner -loglevel error -y -i "$f" -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 "$tmp" 2>> "$log"; then
      mv -f "$tmp" "$dst"; n=$((n + 1)); Say "  OK      $base" "$C_G"
    else rm -f "$tmp"; err=$((err + 1)); Say "$(L "  FEHLER  $base (siehe $log)" "  ERROR   $base (see $log)")" "$C_R"; fi
  done < <(find "$src" -maxdepth 1 -type f -iname '*.bik' | sort)
  Ok "$(L "$n Filme konvertiert, $err Fehler." "$n movies converted, $err errors.")"
}

# =====================================================================================================================
# 5) Texturen hochskalieren
# =====================================================================================================================
Texture_Folders() {
  if [ -n "$ORDNER" ]; then printf '%s\n' "$ORDNER"; return; fi
  local s; for s in textures ui/menu/textures ui/menu/backgrounds ui/hud/textures; do [ -d "$CFG_ZIEL/$s" ] && printf '%s\n' "$CFG_ZIEL/$s"; done
}
Setup_Upscale() {
  local py="$1" idx
  if Test_PyModules "$py" "torch, spandrel"; then
    if [ "$GERAET" = "cuda" ] && ! "$py" -I -c "import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)" >/dev/null 2>&1; then
      Warn "$(L "torch ist installiert, aber ohne nutzbare CUDA-GPU – es wird die CPU verwendet." "torch is installed but no usable CUDA GPU – using the CPU.")"; GERAET="cpu"
    fi
    return 0
  fi
  Say "$(L "  Für das Hochskalieren werden PyTorch und spandrel benötigt (nur in $WERKZEUGE):" "  Upscaling needs PyTorch and spandrel (only in $WERKZEUGE):")"
  Say "$(L "    CPU-Fassung ca. 250 MB Download – läuft auf jedem PC." "    CPU version approx. 250 MB download – runs on every PC.")"
  Say "$(L "    GPU-Fassung (NVIDIA/CUDA) ca. 3 GB Download – vielfach schneller." "    GPU version (NVIDIA/CUDA) approx. 3 GB download – many times faster.")"
  idx="https://download.pytorch.org/whl/cpu"; [ "$GERAET" = "cuda" ] && idx="https://download.pytorch.org/whl/cu128"
  Ask "$(L "PyTorch ($GERAET) jetzt installieren?" "Install PyTorch ($GERAET) now?")" || return 1
  "$py" -m pip install --disable-pip-version-check --no-warn-script-location torch torchvision --index-url "$idx" ||
    { Err "$(L "PyTorch-Installation fehlgeschlagen." "PyTorch installation failed.")"; return 1; }
  Install_Requirements "$py" "$SCRIPT_DIR/requirements-upscale.txt" || return 1
  Test_PyModules "$py" "torch, spandrel"
}
download() {  # download url ziel
  Say "$(L "  Lade $1 …" "  Downloading $1 …")"
  if command -v curl >/dev/null 2>&1; then curl -fL --retry 2 -o "$2.part" "$1" || return 1
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2.part" "$1" || return 1
  else Err "$(L "Weder curl noch wget gefunden." "Neither curl nor wget found.")"; return 1; fi
  mv -f "$2.part" "$2"
}
Setup_Models() {
  local dir="$WERKZEUGE/sr_models" line name mb sha url missing="" mbsum=0 h
  mkdir -p "$dir"
  while IFS='|' read -r name mb sha url; do [ -f "$dir/$name" ] || { missing="${missing:+$missing, }$name"; mbsum=$((mbsum + mb)); }; done <<< "$MODELS"
  if [ -n "$missing" ]; then
    Say "$(L "  KI-Modelle (Real-ESRGAN, BSD-3-Lizenz) fehlen: $missing – zusammen ca. $mbsum MB von github.com." "  AI models (Real-ESRGAN, BSD-3 licence) missing: $missing – together approx. $mbsum MB from github.com.")"
    Ask "$(L "Herunterladen?" "Download?")" || return 1
    while IFS='|' read -r name mb sha url; do
      [ -f "$dir/$name" ] && continue
      download "$url" "$dir/$name" || { rm -f "$dir/$name.part"; Err "$(L "Download fehlgeschlagen: $name" "Download failed: $name")"; return 1; }
      h=$(sha256sum "$dir/$name" | cut -d' ' -f1 | tr 'a-f' 'A-F')
      if [ "$h" != "$sha" ]; then rm -f "$dir/$name"; Err "$(L "Prüfsumme von $name stimmt nicht – Datei verworfen." "Checksum of $name does not match – file discarded.")"; return 1; fi
      Ok "$(L "$name geprüft." "$name verified.")"
    done <<< "$MODELS"
  fi
  export DH2_SR_MODELS="$dir"
}
Action_Hochskalieren() {
  Title "$(L "Texturen hochskalieren ($(upper "$STUFE"), $GERAET)" "Upscale textures ($(upper "$STUFE"), $GERAET)")"
  local py f nn d done total=0 open=0 sek min std gb g sp log pass line
  py=$(Get_Py) || { Err "$(L "Python fehlt – zuerst Menüpunkt 2." "Python missing – run menu item 2 first.")"; return 1; }
  local -a folders=(); mapfile -t folders < <(Texture_Folders)
  [ ${#folders[@]} -gt 0 ] || { Err "$(L "Keine exportierten Texturen gefunden – zuerst Menüpunkt 3." "No exported textures found – run menu item 3 first.")"; return 1; }
  for f in "${folders[@]}"; do
    nn=$(find "$f" -maxdepth 1 -type f -iname '*.png' 2>/dev/null | wc -l)
    d="${f%/}_$STUFE"; done=0; [ -d "$d" ] && done=$(find "$d" -maxdepth 1 -type f -iname '*.png' | wc -l)
    total=$((total + nn)); [ "$nn" -gt "$done" ] && open=$((open + nn - done))
    Say "$(printf '  %-60s %5d %s, %5d %s' "$f" "$nn" "$(L "Texturen" "textures")" "$done" "$(L "fertig" "done")")"
  done
  if [ "$GERAET" = "cuda" ]; then sek=1.5; elif [ "$STUFE" = "hd" ]; then sek=15; else sek=12; fi
  min=$(awk -v o="$open" -v s="$sek" 'BEGIN { m = o * s / 60; printf "%d", (m == int(m)) ? m : int(m) + 1 }')
  if [ "$min" -lt 120 ]; then std=$(L "$min Minuten" "$min minutes"); else std=$(awk -v m="$min" 'BEGIN { printf "%.1f", m / 60 }'); std=$(L "$std Stunden" "$std hours"); fi
  if [ "$STUFE" = "hd" ]; then gb=$(awk -v t="$total" 'BEGIN { printf "%.2f", t * 0.6 / 1000 }'); else gb=$(awk -v t="$total" 'BEGIN { printf "%.2f", t * 1.8 / 1000 }'); fi
  Say "$(L "  Offen: $open Texturen. Geschätzte Dauer ca. $std ($GERAET), Platzbedarf ca. $gb GB." "  Open: $open textures. Estimated time approx. $std ($GERAET), disk space approx. $gb GB.")"
  [ "$STUFE" = "4k" ] && Say "$(L "  Hinweis: 4K baut auf HD auf (fehlende HD-Texturen werden dabei mit erzeugt)." "  Note: 4K builds on HD (missing HD textures are created as well).")"
  Say "$(L "  Der Lauf ist jederzeit abbrechbar (Strg+C) und setzt beim nächsten Start fort." "  The run can be cancelled any time (Ctrl+C) and resumes on the next start.")"
  [ "$open" = 0 ] && { Ok "$(L "Nichts zu tun." "Nothing to do.")"; return 0; }
  Ask "$(L "Starten?" "Start?")" 1 || return 0
  if [ "$INTERAKTIV" = 1 ] && [ "$GERAET_SET" = 0 ]; then
    read -r -p "$(L "  Rechengerät: 1 = CPU (Standard), 2 = NVIDIA-GPU (CUDA): " "  Device: 1 = CPU (default), 2 = NVIDIA GPU (CUDA): ")" g
    [ "$g" = "2" ] && GERAET="cuda"
  fi
  Setup_Upscale "$py" || return 1
  Setup_Models || return 1
  export DH2_SR_DEVICE="$GERAET"; [ "$THREADS" -gt 0 ] 2>/dev/null && export DH2_SR_THREADS="$THREADS"
  mkdir -p "$LOG_DIR"; log="$LOG_DIR/hochskalieren.log"; sp="$PIPELINE/upscale_textures.py"
  for f in "${folders[@]}"; do
    for pass in hd $([ "$STUFE" = "4k" ] && echo --4k); do
      local -a extra=(); [ "$pass" != "hd" ] && extra=("$pass")
      Say "  -> $f ${extra[*]}"
      printf '== %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$f" "${extra[*]}" >> "$log"
      PYTHONUNBUFFERED=1 "$py" -I "$sp" "$f" "${extra[@]}" 2>&1 | while IFS= read -r line; do
        printf '%s\n' "$line" >> "$log"
        if [[ "$line" =~ ^\[([0-9]+)/([0-9]+)\] ]]; then printf '     %s\r' "$line"
        elif [[ "$line" =~ FERTIG|Texturen|offen ]]; then Say "     $line"; fi
      done
      [ "${PIPESTATUS[0]}" -eq 0 ] || { Err "$(L "Abbruch bei $f (siehe $log)" "Aborted at $f (see $log)")"; return 1; }
    done
  done
  Ok "$(L "Fertig. Das Spiel verwendet automatisch die beste vorhandene Stufe (textures_4k vor textures_hd)." "Done. The game automatically uses the best available level (textures_4k before textures_hd).")"
}
Action_Installieren() {  # Action_Installieren [zurueck]
  local py base sp rc
  py=$(Get_Py) || { Err "$(L "Python fehlt – zuerst Menüpunkt 2." "Python missing – run menu item 2 first.")"; return 1; }
  base="${ORDNER:-$CFG_ZIEL/textures}"; base="${base%/}"; sp="$PIPELINE/upscale_textures.py"
  if [ "${1:-}" = "zurueck" ]; then
    Title "$(L "Original-Texturen wiederherstellen" "Restore original textures")"
    [ -d "${base}_sd" ] || { Warn "$(L "Keine Sicherung (${base}_sd) vorhanden – es ist nichts installiert." "No backup (${base}_sd) present – nothing is installed.")"; return 0; }
    "$py" -I "$sp" "$base" --restore; rc=$?
  else
    Title "$(L "HD-Texturen fest installieren" "Install HD textures permanently")"
    Say "$(L "  Normalerweise nicht nötig: das Spiel nutzt textures_hd/textures_4k automatisch." "  Usually not needed: the game uses textures_hd/textures_4k automatically.")"
    Say "$(L "  Installieren kopiert die HD-Fassung über $base (Originale werden vorher nach ${base}_sd gesichert)." "  Installing copies the HD version over $base (originals are backed up to ${base}_sd first).")"
    [ -d "${base}_hd" ] || { Err "$(L "Keine HD-Texturen vorhanden – zuerst hochskalieren." "No HD textures present – upscale first.")"; return 1; }
    Ask "$(L "Fortfahren?" "Continue?")" || return 0
    "$py" -I "$sp" "$base" --install; rc=$?
  fi
  if [ "$rc" = 0 ]; then Ok "$(L "Erledigt." "Done.")"; else Err "$(L "Fehlgeschlagen." "Failed.")"; return 1; fi
}

# =====================================================================================================================
# 6) Status (nur lesen)
# =====================================================================================================================
st_line() {  # st_line name ok(1/0) info
  local s; s=$(printf '%-22s %s' "$1" "$3")
  if [ "$2" = 1 ]; then Ok "$s"; else Warn "$s"; fi
}
Action_Status() {
  Title "Status"
  if [ -n "$CFG_ORIG" ]; then Test_Installation "$CFG_ORIG"; else Warn "$(L "Keine Original-Installation gewählt (Menüpunkt 1)." "No original installation selected (menu item 1).")"; fi
  Say ""
  if [ -f "$PIPELINE/convert_mission.py" ]; then
    Ok "$(L "Konverter: $PIPELINE ($(find "$PIPELINE" -maxdepth 1 -name '*.py' | wc -l) Skripte)" "Converters: $PIPELINE ($(find "$PIPELINE" -maxdepth 1 -name '*.py' | wc -l) scripts)")"
  else Err "$(L "Konverter fehlen: $PIPELINE" "Converters missing: $PIPELINE")"; fi
  local py ff md mods=0 name mb sha url c x s nb nf tx bik ogv camp=0 mpd=0 fehlen="" m
  if py=$(Get_Py); then
    if Test_PyModules "$py" "$PY_MODS"; then Ok "Python (Export): $py"; else Warn "$(L "Python vorhanden, Pakete fehlen: $py" "Python present, packages missing: $py")"; fi
    if Test_PyModules "$py" "torch, spandrel"; then Ok "$(L "Hochskalieren: PyTorch vorhanden" "Upscaling: PyTorch present")"; else Say "$(L "  [--]     Hochskalieren: PyTorch nicht installiert" "  [--]     Upscaling: PyTorch not installed")" "$C_D"; fi
  else Warn "$(L "Python-Umgebung fehlt (Menüpunkt 2)." "Python environment missing (menu item 2).")"; fi
  ff=$(Find_Ffmpeg)
  if [ -n "$ff" ]; then Ok "ffmpeg: $ff"; else Say "$(L "  [--]     ffmpeg nicht gefunden (nur für Filme)" "  [--]     ffmpeg not found (only needed for movies)")" "$C_D"; fi
  md="$WERKZEUGE/sr_models"
  while IFS='|' read -r name mb sha url; do [ -f "$md/$name" ] && mods=$((mods + 1)); done <<< "$MODELS"
  Say "$(L "  KI-Modelle: $mods/2" "  AI models: $mods/2")"
  Say ""
  c="$CFG_ZIEL"
  Say "$(L "  Spieldaten: $c" "  Game data: $c")"
  [ -d "$c" ] || { Warn "$(L "Noch nicht exportiert (Menüpunkt 3)." "Not exported yet (menu item 3).")"; return 0; }
  for m in $CAMPAIGN; do if [ -f "$c/$(lower "$m")/scene.glb" ]; then camp=$((camp + 1)); else fehlen="${fehlen:+$fehlen, }$m"; fi; done
  for m in $MULTI; do [ -f "$c/$(lower "$m")/scene.glb" ] && mpd=$((mpd + 1)); done
  local nc nm; nc=$(printf '%s\n' $CAMPAIGN | wc -l); nm=$(printf '%s\n' $MULTI | wc -l)
  st_line "$(L "Kampagnenmissionen" "Campaign missions")" "$([ "$camp" = "$nc" ] && echo 1 || echo 0)" "$camp/$nc"
  [ -n "$fehlen" ] && Say "       $(L "fehlen" "missing"): $fehlen" "$C_Y"
  st_line "$(L "Mehrspielerkarten" "Multiplayer maps")" "$([ "$mpd" = "$nm" ] && echo 1 || echo 0)" "$mpd/$nm"
  while IFS='|' read -r name x; do
    read -r nf nb <<< "$(Dir_Stats "$c/$x")"
    st_line "$name" "$([ "$nf" -gt 0 ] && echo 1 || echo 0)" "$(printf '%6d %s  %s' "$nf" "$(L "Dateien" "files")" "$(Fmt_Size "$nb")")"
  done <<EOF
$(L "Texturen" "Textures")|textures
$(L "Figuren" "Characters")|characters
$(L "Waffen" "Weapons")|weapons
$(L "Klänge" "Sounds")|sounds
$(L "Musik" "Music")|music
$(L "Menüs/HUD" "Menus/HUD")|ui
$(L "Animationen" "Animations")|anims
$(L "Filme" "Movies")|movies
$(L "HD-Texturen" "HD textures")|textures_hd
$(L "4K-Texturen" "4K textures")|textures_4k
EOF
  # B-024/O-002: jede Sprachinstallation – mindestens eine texts_<sprache>.json
  tx=$(find "$c" -maxdepth 1 -type f -name 'texts_*.json' -printf '%f\n' 2>/dev/null | sed 's/^texts_//; s/\.json$//' | sort | paste -sd, - | sed 's/,/, /g')
  st_line "$(L "Originaltexte" "Original texts")" "$([ -n "$tx" ] && echo 1 || echo 0)" "${tx:-$(L "keine texts_*.json" "no texts_*.json")}"
  st_line "$(L "Originalschriften" "Original fonts")" "$([ -f "$c/ui/fonts/fonts.json" ] && echo 1 || echo 0)" "ui/fonts/fonts.json"
  for x in items.json sounds.json commands.json mp_maps.json missions_db.json roster.json; do st_line "$x" "$([ -f "$c/$x" ] && echo 1 || echo 0)" ""; done
  if [ -n "$CFG_ORIG" ] && s=$(ci_path "$CFG_ORIG" "Gamemovie"); then
    bik=$(find "$s" -maxdepth 1 -type f -iname '*.bik' | wc -l)
    read -r ogv _ <<< "$(Dir_Stats "$c/movies" '*.ogv')"
    Say "$(L "  Filme: $ogv von $bik konvertiert" "  Movies: $ogv of $bik converted")"
  fi
  read -r nf nb <<< "$(Dir_Stats "$c")"
  Say "$(L "  Gesamt: $nf Dateien, $(Fmt_Size "$nb")" "  Total: $nf files, $(Fmt_Size "$nb")")"
}

# =====================================================================================================================
# 7) Spiel starten (Linux-Programm DangerousHidden2.x86_64 + DangerousHidden2.pck)
# =====================================================================================================================
Action_Starten() {
  local exe="" c dir pck ver v
  for c in "$ROOT/DangerousHidden2.x86_64" "$ROOT/build/DangerousHidden2.x86_64" "$ROOT/build/linux_public/DangerousHidden2.x86_64"; do
    [ -f "$c" ] && { exe="$c"; break; }
  done
  [ -n "$exe" ] || { Err "$(L "DangerousHidden2.x86_64 nicht gefunden (erwartet in $ROOT)." "DangerousHidden2.x86_64 not found (expected in $ROOT).")"; return 1; }
  [ -x "$exe" ] || chmod +x "$exe" 2>/dev/null || { Err "$(L "Keine Ausführungsrechte: chmod +x \"$exe\"" "Not executable: chmod +x \"$exe\"")"; return 1; }
  dir=$(dirname "$exe"); pck="$dir/DangerousHidden2.pck"; ver="$dir/version.txt"
  if [ ! -f "$pck" ]; then
    [ -f "$ver" ] && { Err "$(L "DangerousHidden2.pck fehlt neben dem Programm ($dir) – Programm und .pck aus demselben Paket kopieren." "DangerousHidden2.pck missing next to the program ($dir) – copy program and .pck from the same package.")"; return 1; }
    Warn "$(L "Keine DangerousHidden2.pck gefunden – nur ältere Pakete mit eingebetteten Spieldaten starten so." "No DangerousHidden2.pck found – only older packages with embedded game data start this way.")"
  elif [ -f "$ver" ]; then
    v=$(head -n 1 "$ver" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    Say "$(L "  Version $v (Programm + .pck; das Spiel prüft beim Start, ob beide zusammenpassen)." "  Version $v (program + .pck; the game checks at start-up that both match).")"
  fi
  [ -d "$CFG_ZIEL/textures" ] || Warn "$(L "Es wurden noch keine Spieldaten exportiert – Originalinhalte fehlen dann." "No game data has been exported yet – original content will be missing.")"
  Say "$(L "  Starte $exe …" "  Starting $exe …")"
  ( cd "$dir" && nohup "$exe" > /dev/null 2>&1 & )
}

# =====================================================================================================================
# Menü
# =====================================================================================================================
Run_Action() {
  case "$1" in
    Suchen) Action_Suchen ;;
    Pruefen) Title "$(L "Installation prüfen" "Check installation")"; if [ -n "$CFG_ORIG" ]; then Test_Installation "$CFG_ORIG"; else Action_Suchen; fi ;;
    Einrichten) Action_Einrichten ;;
    Export) Action_Export ;;
    Filme) Action_Filme ;;
    Hochskalieren) Action_Hochskalieren ;;
    Installieren) Action_Installieren ;;
    Wiederherstellen) Action_Installieren zurueck ;;
    Status) Action_Status ;;
    Starten) Action_Starten ;;
  esac
  local rc=$?
  [ "$rc" -ne 0 ] && Log "$1 fehlgeschlagen (Exit $rc)"
  return "$rc"
}

if [ "$INTERAKTIV" != 1 ]; then
  Run_Action "$AKTION"; exit $?
fi

while true; do
  clear 2>/dev/null || printf '\n\n'
  Say "=================================================================" "$C_C"
  Say "$(L "   DANGEROUS AND HIDDEN 2  –  Werkzeuge (inoffizielles Fanprojekt)" "   DANGEROUS AND HIDDEN 2  –  Tools (unofficial fan project)")" "$C_C"
  Say "=================================================================" "$C_C"
  Say "$(L "   Original-Installation: ${CFG_ORIG:-(noch nicht gewählt)}" "   Original installation: ${CFG_ORIG:-(not selected yet)}")"
  Say "$(L "   Spieldaten-Ziel:       $CFG_ZIEL" "   Game data target:      $CFG_ZIEL")"
  Say ""
  Say "$(L "   1) Original-Installation suchen / wählen / prüfen" "   1) Find / select / check original installation")"
  Say "$(L "   2) Werkzeuge einrichten (Python, Pakete, ffmpeg)" "   2) Set up tools (Python, packages, ffmpeg)")"
  Say "$(L "   3) Spieldaten exportieren (fortsetzbar)" "   3) Export game data (resumable)")"
  Say "$(L "   4) Filme konvertieren" "   4) Convert movies")"
  Say "$(L "   5) Texturen hochskalieren / installieren" "   5) Upscale / install textures")"
  Say "$(L "   6) Prüfen / Status" "   6) Check / status")"
  Say "$(L "   7) Spiel starten" "   7) Start game")"
  Say "   8) Sprache / Language ($LANGSEL)"
  Say "$(L "   0) Beenden" "   0) Exit")"
  Say ""
  read -r -p "$(L "   Auswahl: " "   Choice: ")" w || exit 0
  case "$w" in
    1) Run_Action Suchen ;;
    2) Run_Action Einrichten ;;
    3)
      NEU=0
      read -r -p "$(L "  a) alles exportieren (Standard)  b) nur bestimmte Missionen  n) alles neu: " "  a) export everything (default)  b) only certain missions  n) redo everything: ")" a
      if [ "$a" = "b" ]; then
        read -r -p "$(L "  Missionen (z. B. ARCTIC1,TUTORIAL): " "  Missions (e.g. ARCTIC1,TUTORIAL): ")" mm
        MISSIONEN=$(split_list "$mm"); SCHRITTE=$(printf 'Tabellen\nMissionen\nMehrspieler')
      elif [ "$a" = "n" ]; then NEU=1; MISSIONEN=""; SCHRITTE=""
      else MISSIONEN=""; SCHRITTE=""; fi
      Run_Action Export
      NEU=0 ;;
    4) Run_Action Filme ;;
    5)
      Say "$(L "   a) HD (4-fach, max. 2048 px) erzeugen" "   a) create HD (4x, max. 2048 px)")"
      Say "$(L "   b) 4K (zusätzlich, max. 4096 px) erzeugen" "   b) create 4K (additionally, max. 4096 px)")"
      Say "$(L "   c) HD fest installieren   d) Originale wiederherstellen" "   c) install HD permanently   d) restore originals")"
      read -r -p "$(L "   Auswahl: " "   Choice: ")" a
      case "$a" in
        a) STUFE=hd; Run_Action Hochskalieren ;;
        b) STUFE=4k; Run_Action Hochskalieren ;;
        c) Run_Action Installieren ;;
        d) Run_Action Wiederherstellen ;;
      esac ;;
    6) Run_Action Status ;;
    7) Run_Action Starten ;;
    8)
      if [ "$LANGSEL" = "de" ]; then LANGSEL=en; else LANGSEL=de; fi
      CFG_SPRACHE="$LANGSEL"; Save_Config 2>/dev/null
      continue ;;
    0) exit 0 ;;
    *) continue ;;
  esac
  Pause_Menu
done
