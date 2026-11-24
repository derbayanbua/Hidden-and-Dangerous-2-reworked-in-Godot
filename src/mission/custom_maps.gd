extends RefCounted
## Eigene Karten ohne neuen Spiel-Build.
## Custom maps without a new game build.
##
## Beim Start werden alle `<id>.pck` aus genau zwei Ordnern geladen (nicht rekursiv):
##   1. `maps/` neben der EXE (im Editor-Binary: `maps/` im Projektordner)
##   2. `user://maps/`
## Jede Datei muss ihr Manifest unter `res://custom_maps/<id>/map.json` enthalten und darf nur Dateien unter
## `res://custom_maps/<id>/` (plus importierte Daten unter `res://.godot/imported/`) mitbringen. Das Inhaltsverzeichnis
## der .pck wird VOR dem Einbinden gelesen und geprüft; eingebunden wird mit replace_files = false (eine Karte kann keine
## Spieldateien ersetzen). Fehlerhafte Pakete/Manifeste werden mit Logzeile übersprungen.
## Registriert wird über `Game._register_mp_maps` (Missionsregister, Übungseinsätze, MP-Kartenliste) mit Kennzeichnung
## „[Eigene Karte]“ / „[Custom map]“. MP-Abgleich: `annotate_settings` (Server) / `check_remote` (Client), SHA-256 der .pck.

const MANIFEST_ROOT := "res://custom_maps"
const MISSION_PREFIX := "custom_"
const GENERIC_SCRIPT := "res://src/mission/custom_map_mission.gd"
const MAX_PACK_BYTES := 2147483648          ## 2 GiB
const MAX_PACK_FILES := 20000
const MODES := ["singleplayer", "deathmatch", "teamdeathmatch", "occupation"]
const MP_MODE := {"deathmatch": 0, "teamdeathmatch": 1, "occupation": 2}
const MODE_SUFFIX := {"deathmatch": "", "teamdeathmatch": "_tdm", "occupation": "_occ"}
const MODE_TITLE := {"teamdeathmatch": "Team-DM", "occupation": "Eroberung / Occupation"}
const PCK_MAGIC := 0x43504447               ## "GDPC"

## Basis-ID (aus dem Dateinamen) -> {id, file, sha256, version, name_de, name_en, briefing_de, briefing_en, scene, script, modes}
static var maps := {}
## Protokoll der Ladevorgänge (Tests/Fehlersuche)
static var log_lines: Array[String] = []
static var _scanned := false


static func _log(s: String) -> void:
	log_lines.append(s)
	print("CUSTOM_MAPS: ", s)


static func valid_id(id: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z0-9_]{1,40}$")
	return re.search(id) != null


## Die zwei erlaubten Suchordner (absolute Pfade). Tests (--autoplay) dürfen mit --custom_maps_dir=user://test… einen
## einzigen Testordner statt der beiden Ordner setzen.
static func search_dirs() -> Array[String]:
	var out: Array[String] = []
	var cli: Dictionary = Game.cli
	if cli.has("autoplay") and String(cli.get("custom_maps_dir", "")).begins_with("user://test"):
		out.append(ProjectSettings.globalize_path(String(cli["custom_maps_dir"])).simplify_path())
		return out
	var base := OS.get_executable_path().get_base_dir()
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	out.append(base.path_join("maps").simplify_path())
	out.append(ProjectSettings.globalize_path("user://maps").simplify_path())
	return out


static func in_allowed_dir(path: String) -> bool:
	var dir := path.get_base_dir().simplify_path().replace("\\", "/").to_lower()
	for d in search_dirs():
		if d.replace("\\", "/").to_lower() == dir:
			return true
	return false


## Alle Suchordner einmal laden (Game._ready). Mehrfachaufrufe sind wirkungslos.
static func scan() -> void:
	if _scanned:
		return
	_scanned = true
	for dir in search_dirs():
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var files := d.get_files()
		files.sort()
		for f in files:
			if f.get_extension().to_lower() != "pck":
				continue
			if d.is_link(f):
				_log("übersprungen (Verknüpfung) / skipped (link): " + f)
				continue
			load_pack(dir.path_join(f))


## Eine .pck prüfen, einbinden und ihr Manifest übernehmen. Rückgabe "" = geladen, sonst Grund (auch geloggt).
static func load_pack(path: String) -> String:
	var err := _load_pack(path)
	if err != "":
		_log("übersprungen / skipped %s: %s" % [path.get_file(), err])
	return err


static func _load_pack(path: String) -> String:
	path = path.simplify_path()
	if not in_allowed_dir(path):
		return "nicht in maps/ bzw. user://maps/ / not in an allowed folder"
	var id := path.get_file().get_basename().to_lower()
	if path.get_extension().to_lower() != "pck" or not valid_id(id):
		return "Dateiname muss <id>.pck mit a-z, 0-9, _ sein / file name must be <id>.pck (a-z, 0-9, _)"
	if maps.has(id):
		return "Karten-ID bereits geladen / map id already loaded"
	if not FileAccess.file_exists(path):
		return "Datei fehlt / file missing"
	var listing := read_pck_listing(path)
	if listing.has("error"):
		return String(listing["error"])
	var bad := check_listing(listing["files"], id)
	if bad != "":
		return bad
	var sha := FileAccess.get_sha256(path)
	if sha == "":
		return "Prüfsumme nicht lesbar / checksum unreadable"
	if not ProjectSettings.load_resource_pack(path, false):
		return "load_resource_pack fehlgeschlagen / failed"
	var mpath := "%s/%s/map.json" % [MANIFEST_ROOT, id]
	if not FileAccess.file_exists(mpath):
		return "map.json fehlt / missing (%s)" % mpath
	var data = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	var info := validate_manifest(data, id)
	if info.has("error"):
		return "Manifest: " + String(info["error"])
	if info["script"] != GENERIC_SCRIPT and not _is_mission_script(String(info["script"])):
		return "Manifest: script muss von Mission erben / script must extend Mission"
	if not ResourceLoader.exists(String(info["scene"])):
		return "Manifest: Szene fehlt im Paket / scene missing in pack"
	info["file"] = path
	info["sha256"] = sha
	maps[id] = info
	_log("geladen / loaded %s (v%s, sha256 %s…)" % [id, info["version"], sha.substr(0, 12)])
	return ""


## Inhaltsverzeichnis einer .pck lesen (Godot-PCK-Format 2/3, unverschlüsselt). {"files": [res-Pfade]} oder {"error"}.
static func read_pck_listing(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "nicht lesbar / unreadable"}
	var size := f.get_length()
	if size > MAX_PACK_BYTES:
		return {"error": "zu groß / too large"}
	if size < 32 or f.get_32() != PCK_MAGIC:
		return {"error": "keine Godot-.pck / not a Godot .pck"}
	var version := f.get_32()
	f.get_32()
	f.get_32()
	f.get_32()                                   # Engine-Version
	if version < 2 or version > 4:                # 4 = Godot 4.7 (Kopf wie 3: Dateibasis + Verzeichnis-Offset)
		return {"error": "PCK-Formatversion %d nicht unterstützt / unsupported" % version}
	var flags := f.get_32()
	if flags & 1:
		return {"error": "verschlüsseltes Verzeichnis / encrypted directory"}
	f.get_64()                                   # Dateibasis
	if version >= 3:
		var dir_ofs := f.get_64()
		if dir_ofs <= 0 or dir_ofs >= size:
			return {"error": "Verzeichnis außerhalb der Datei / directory out of range"}
		f.seek(dir_ofs)
	else:
		for i in 16:
			f.get_32()
	var count := f.get_32()
	if count > MAX_PACK_FILES:
		return {"error": "zu viele Dateien / too many files"}
	var files: Array[String] = []
	for i in count:
		var sl := f.get_32()
		if sl == 0 or sl > 4096 or f.get_position() + sl > size:
			return {"error": "Verzeichnis beschädigt / directory corrupt"}
		var p := f.get_buffer(sl).get_string_from_utf8()
		f.get_64()
		f.get_64()
		f.get_buffer(16)
		f.get_32()
		if f.eof_reached():
			return {"error": "Verzeichnis abgeschnitten / directory truncated"}
		if not p.begins_with("res://"):
			p = "res://" + p
		files.append(p)
	return {"files": files}


## Erlaubt: res://custom_maps/<id>/… und res://.godot/imported/… ; nie „..“, Backslash, Laufwerk oder Steuerzeichen.
static func check_listing(files: Array, id: String) -> String:
	if files.is_empty():
		return "leeres Paket / empty pack"
	var own := "%s/%s/" % [MANIFEST_ROOT, id]
	for p in files:
		var s := String(p)
		if not _safe_path_chars(s) or s.simplify_path() != s:
			return "unzulässiger Pfad / illegal path: " + s.substr(0, 120)
		if not (s.begins_with(own) or s.begins_with("res://.godot/imported/")):
			return "Datei außerhalb von %s / file outside: %s" % [own, s.substr(0, 120)]
	return ""


static func _safe_path_chars(s: String) -> bool:
	if not s.begins_with("res://") or s.contains("..") or s.contains("\\") or s.substr(6).contains(":") \
			or s.find("//", 6) >= 0:
		return false
	for i in s.length():
		if s.unicode_at(i) < 32:
			return false
	return true


## Pfad aus dem Manifest: muss unter res://custom_maps/<id>/ liegen und eine der Endungen haben
static func safe_res_path(p: Variant, id: String, exts: Array) -> bool:
	if typeof(p) != TYPE_STRING:
		return false
	var s := String(p)
	return s.begins_with("%s/%s/" % [MANIFEST_ROOT, id]) and _safe_path_chars(s) and s.simplify_path() == s \
		and exts.has(s.get_extension().to_lower())


static func _clean_text(v: Variant, max_len: int) -> String:
	if typeof(v) != TYPE_STRING:
		return ""
	var out := ""
	for ch in String(v).strip_edges():
		if ch.unicode_at(0) >= 32 or ch == "\n":
			out += ch
	return out.substr(0, max_len)


## Manifest prüfen und normalisieren. Rückgabe {"error": …} oder die normalisierten Felder.
## Felder: id (= Dateiname), name {de,en} oder Text, scene, script (optional), modes (optional), version, briefing {de,en}
static func validate_manifest(d: Variant, id: String) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return {"error": "kein JSON-Objekt / not a JSON object"}
	if String(d.get("id", "")) != id:
		return {"error": "id muss dem Dateinamen entsprechen / id must match the file name"}
	var nm = d.get("name", "")
	var de := _clean_text(nm.get("de", "") if nm is Dictionary else nm, 60)
	var en := _clean_text(nm.get("en", "") if nm is Dictionary else nm, 60)
	if de == "" and en == "":
		return {"error": "name fehlt / name missing"}
	if not safe_res_path(d.get("scene"), id, ["tscn", "scn"]):
		return {"error": "scene muss res://custom_maps/%s/….tscn sein / scene path invalid" % id}
	var script := GENERIC_SCRIPT
	if d.has("script"):
		if not safe_res_path(d.get("script"), id, ["gd", "gdc"]):
			return {"error": "script muss res://custom_maps/%s/….gd sein / script path invalid" % id}
		script = String(d["script"])
	var modes: Array = []
	var mv = d.get("modes", ["singleplayer", "deathmatch"])
	if not mv is Array or (mv as Array).is_empty():
		return {"error": "modes muss eine Liste sein / modes must be a list"}
	for m in mv:
		if not MODES.has(String(m)):
			return {"error": "unbekannter Modus / unknown mode: " + _clean_text(m, 30)}
		if not modes.has(String(m)):
			modes.append(String(m))
	if modes.has("occupation") and script == GENERIC_SCRIPT:
		return {"error": "occupation braucht ein Missionsskript mit mp_zones() / needs a script with mp_zones()"}
	var ver := _clean_text(str(d.get("version", "")), 20) if d.has("version") else ""
	if ver == "":
		return {"error": "version fehlt / version missing"}
	var br = d.get("briefing", {})
	return {"id": id, "name_de": de if de != "" else en, "name_en": en if en != "" else de,
		"briefing_de": _clean_text(br.get("de", "") if br is Dictionary else br, 2000),
		"briefing_en": _clean_text(br.get("en", "") if br is Dictionary else br, 2000),
		"scene": String(d["scene"]), "script": script, "modes": modes, "version": ver}


static func _is_mission_script(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var s = load(path)
	var mission_base := load("res://src/mission/mission.gd")
	while s is Script:
		if s == mission_base:
			return true
		s = (s as Script).get_base_script()
	return false


static func english() -> bool:
	return String(Settings.get("language")).begins_with("english")


static func tag() -> String:
	return "[Custom map]" if english() else "[Eigene Karte]"


## Missions-ID des Basiseintrags
static func mission_id(id: String) -> String:
	return MISSION_PREFIX + id


## Alle geladenen Karten in das Register eintragen (aus Game._register_mp_maps, auch nach Sprachwechsel).
static func register(game: Node) -> void:
	var en := english()
	var ids := maps.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = maps[id]
		var base := mission_id(id)
		var title := "%s %s" % [info["name_en"] if en else info["name_de"], tag()]
		var entry := {"title": title, "script": info["script"], "custom_scene": info["scene"], "custom_map": id,
			"briefing": info["briefing_en"] if en and info["briefing_en"] != "" else info["briefing_de"]}
		var modes: Array = info["modes"]
		var first_mp := true
		for m in modes:
			if not MP_MODE.has(m):
				continue
			var mid := base if first_mp else base + String(MODE_SUFFIX[m])
			if game.MISSIONS.has(mid) and not game.MISSIONS[mid].has("custom_map"):
				_log("ID-Konflikt / id clash: " + mid)
				continue
			var e := entry.duplicate()
			e["mp_mode"] = int(MP_MODE[m])
			if not first_mp:
				e["title"] = "%s (%s) %s" % [info["name_en"] if en else info["name_de"], MODE_TITLE.get(m, m), tag()]
			game.MISSIONS[mid] = e
			if not game.MP_MAPS.has(mid):
				game.MP_MAPS.append(mid)
			first_mp = false
		if first_mp:                                  # nur Einzelspieler
			if game.MISSIONS.has(base) and not game.MISSIONS[base].has("custom_map"):
				_log("ID-Konflikt / id clash: " + base)
				continue
			game.MISSIONS[base] = entry
		if modes.has("singleplayer") and not game.PRACTICE_MISSIONS.has(base):
			game.PRACTICE_MISSIONS.append(base)


## Basis-ID einer Missions-ID ("" = keine eigene Karte)
static func base_of(mission: String) -> String:
	return String(Game.MISSIONS.get(mission, {}).get("custom_map", ""))


## Server: Prüfangaben der laufenden Karte in die öffentlichen Einstellungen (vorhandenes _enter_match-Dictionary;
## alte Clients ignorieren den Zusatzschlüssel, Protokoll bleibt DH2-LAN-6).
static func annotate_settings(s: Dictionary) -> void:
	s.erase("custom_map")
	var id := base_of(String(s.get("map", "")))
	if id != "" and maps.has(id):
		s["custom_map"] = {"id": id, "sha256": String(maps[id]["sha256"]), "version": String(maps[id]["version"])}


## Client: passt die Karte des Servers zur lokalen Datei? "" = ja, sonst Meldung DE/EN.
static func check_remote(cfg: Dictionary) -> String:
	var map := String(cfg.get("map", ""))
	var cm = cfg.get("custom_map")
	if not cm is Dictionary:
		if map.begins_with(MISSION_PREFIX) and not Game.MISSIONS.has(map):
			return remote_error("missing", map.trim_prefix(MISSION_PREFIX))
		return ""
	var id := String(cm.get("id", ""))
	if not valid_id(id):
		return remote_error("missing", "?")
	if not maps.has(id) or base_of(map) != id:
		return remote_error("missing", id)
	if String(maps[id]["sha256"]).to_lower() != String(cm.get("sha256", "")).to_lower():
		return remote_error("checksum", id)
	return ""


static func remote_error(kind: String, id: String) -> String:
	if kind == "checksum":
		return ("Eigene Karte „%s“ weicht von der Datei des Servers ab (SHA-256). Gleiche .pck in maps/ ablegen.\n" +
			"Custom map \"%s\" differs from the server's file (SHA-256). Install the same .pck in maps/.") % [id, id]
	return ("Eigene Karte „%s“ ist nicht installiert. %s.pck in maps/ neben der EXE oder in user://maps/ ablegen.\n" +
		"Custom map \"%s\" is not installed. Put %s.pck into maps/ next to the EXE or into user://maps/.") % [id, id, id, id]
