extends "res://tests/test_gameplay.gd"
## Eigene Karten (.pck): Vorlage tools/map_template packen und laden, Paket-/Manifest-Fehlerfälle, Menüeintrag
## (Einzelmission + MP-Liste), Prüfsummen-Abgleich Server/Client, Kartenstart mit Spawn-Markern.
##   tools\godot.cmd --headless -- --autoplay=test_custom_maps --custom_maps_dir=user://test_custom_maps --profiles_dir=user://test_custom_maps_p --noimport

const CM := preload("res://src/mission/custom_maps.gd")
const PACKER := preload("res://src/mission/custom_map_packer.gd")
const ID := "tmpl_test"


func _dir() -> String:
	return CM.search_dirs()[0]


func _raw_pck(name: String, files: Dictionary) -> String:
	var tmp := ProjectSettings.globalize_path("user://test_custom_maps_src")
	DirAccess.make_dir_recursive_absolute(tmp)
	var pk := PCKPacker.new()
	var out := _dir().path_join(name)
	pk.pck_start(out)
	var i := 0
	for target in files:
		var src := tmp.path_join("r%d.txt" % i)
		i += 1
		var f := FileAccess.open(src, FileAccess.WRITE)
		f.store_string(String(files[target]))
		f.close()
		pk.add_file(target, src)
	pk.flush()
	return out


func _run() -> void:
	await frames(5)
	var dirs := CM.search_dirs()
	check(dirs.size() == 1 and dirs[0].contains("test_custom_maps"), "Testordner statt maps/ + user://maps/", str(dirs))
	DirAccess.make_dir_recursive_absolute(_dir())
	for f in DirAccess.get_files_at(_dir()):
		DirAccess.remove_absolute(_dir().path_join(f))
	CM.maps.clear()                  # Reste eines Vorlaufs (beim Start schon gescannt) vergessen
	# --- 1. Vorlage packen ---------------------------------------------------------------------------------------
	var tpl := "res://tools/map_template"
	if not FileAccess.file_exists(tpl + "/map.json"):
		check(true, "Vorlage nicht im Paket (exportierter Build) – Teil übersprungen")
		_finish()
		return
	var out := _dir().path_join(ID + ".pck")
	var err := PACKER.pack(tpl, ID, out)
	check(err == "" and FileAccess.file_exists(out), "Vorlage → %s.pck gepackt" % ID, err)
	var listing := CM.read_pck_listing(out)
	check(not listing.has("error") and (listing["files"] as Array).has("res://custom_maps/%s/map.json" % ID),
		"PCK-Verzeichnis lesbar, Manifest am Konventionspfad", str(listing).substr(0, 300))
	check(CM.check_listing(listing.get("files", []), ID) == "", "Paketinhalt nur unter res://custom_maps/<id>/")
	check(PACKER.pack(tpl, "Bad-Id", out + ".x") != "", "Packer lehnt ungültige ID ab")
	# --- 2. Manifest-Fehlerfälle (ohne Laden) --------------------------------------------------------------------
	var good := {"id": "m1", "name": {"de": "A", "en": "B"}, "scene": "res://custom_maps/m1/main.tscn", "version": "1"}
	check(not CM.validate_manifest(good, "m1").has("error"), "gültiges Minimal-Manifest")
	var cases := {
		"kein Objekt": [1, "m1"],
		"id ≠ Dateiname": [_with(good, "id", "m2"), "m1"],
		"name fehlt": [_with(good, "name", ""), "m1"],
		"scene mit ..": [_with(good, "scene", "res://custom_maps/m1/../../src/x.tscn"), "m1"],
		"scene fremde Karte": [_with(good, "scene", "res://custom_maps/m2/main.tscn"), "m1"],
		"scene außerhalb": [_with(good, "scene", "res://scenes/main.tscn"), "m1"],
		"scene Endung": [_with(good, "scene", "res://custom_maps/m1/main.gd"), "m1"],
		"script außerhalb": [_with(good, "script", "res://src/autoload/game.gd"), "m1"],
		"script Backslash": [_with(good, "script", "res://custom_maps/m1\\x.gd"), "m1"],
		"Modus unbekannt": [_with(good, "modes", ["coop"]), "m1"],
		"Modi leer": [_with(good, "modes", []), "m1"],
		"Eroberung ohne Skript": [_with(good, "modes", ["occupation"]), "m1"],
		"version fehlt": [_without(good, "version"), "m1"],
	}
	for k in cases:
		var r := CM.validate_manifest(cases[k][0], cases[k][1])
		check(r.has("error"), "Manifest abgelehnt: " + k, String(r.get("error", "angenommen!")))
	# --- 3. Pakete: Fehlerfälle werden übersprungen, kein Absturz ------------------------------------------------
	var g := FileAccess.open(_dir().path_join("garbage.pck"), FileAccess.WRITE)
	g.store_string("das ist keine pck-datei")
	g.close()
	check(CM.load_pack(_dir().path_join("garbage.pck")) != "", "Müll-Datei übersprungen")
	_raw_pck("Bad-Name.pck", {"res://custom_maps/bad/map.json": "{}"})
	check(CM.load_pack(_dir().path_join("Bad-Name.pck")) != "", "ungültiger Dateiname übersprungen")
	_raw_pck("evil.pck", {"res://custom_maps/evil/map.json": "{}", "res://src/autoload/game.gd": "extends Node"})
	var e_evil := CM.load_pack(_dir().path_join("evil.pck"))
	check(e_evil.contains("außerhalb") or e_evil.contains("outside"), "Datei außerhalb des Kartenordners → abgelehnt", e_evil)
	check(Game.has_method("_register_mp_maps"), "Spieldatei nicht ersetzt (game.gd intakt)")
	_raw_pck("nomani.pck", {"res://custom_maps/nomani/readme.txt": "x"})
	check(CM.load_pack(_dir().path_join("nomani.pck")).contains("map.json"), "Paket ohne map.json übersprungen")
	_raw_pck("brokenjs.pck", {"res://custom_maps/brokenjs/map.json": "{ kaputt"})
	check(CM.load_pack(_dir().path_join("brokenjs.pck")).begins_with("Manifest"), "kaputtes JSON übersprungen")
	_raw_pck("noscene.pck", {"res://custom_maps/noscene/map.json": JSON.stringify(
		{"id": "noscene", "name": "X", "scene": "res://custom_maps/noscene/main.tscn", "version": "1"})})
	check(CM.load_pack(_dir().path_join("noscene.pck")).contains("Szene"), "Manifest ohne Szene im Paket übersprungen")
	var outside := ProjectSettings.globalize_path("user://test_custom_maps_other")
	DirAccess.make_dir_recursive_absolute(outside)
	DirAccess.copy_absolute(out, outside.path_join(ID + ".pck"))
	check(CM.load_pack(outside.path_join(ID + ".pck")) != "", "Paket außerhalb der erlaubten Ordner abgelehnt")
	check(not CM.maps.has(ID), "fremder Ordner hat nichts registriert")
	# --- 4. Vorlage laden und registrieren -----------------------------------------------------------------------
	var e_ok := CM.load_pack(out)
	check(e_ok == "" and CM.maps.has(ID), "Vorlage geladen", e_ok)
	check(CM.load_pack(out) != "", "doppeltes Laden abgewiesen")
	Game._register_orig_missions()
	var mid := CM.mission_id(ID)
	var title := String(Game.MISSIONS.get(mid, {}).get("title", ""))
	check(title.contains("[Eigene Karte]") or title.contains("[Custom map]"), "Titel mit Kennzeichnung", title)
	check(Game.PRACTICE_MISSIONS.has(mid), "Einzelspieler: als Übungseinsatz gelistet")
	check(Game.MP_MAPS.has(mid) and Game.MP_MAPS.has(mid + "_tdm"), "MP-Liste: DM- und Team-DM-Eintrag", str(Game.MP_MAPS.slice(-3)))
	check(int(Game.MISSIONS.get(mid, {}).get("mp_mode", -1)) == 0 and int(Game.MISSIONS.get(mid + "_tdm", {}).get("mp_mode", -1)) == 1,
		"feste Spielstile je Eintrag")
	check(Net.resolve_map(mid) == mid, "Net.resolve_map kennt die Karte")
	check(not Net.coop_map_ok(mid, Net.Mode.COOP), "kein Coop auf eigenen Karten")
	for bi in ["a1_blizzard", "m01_funkfeuer", "bavaria"]:
		check(not Game.MISSIONS.get(bi, {}).has("custom_map"), "eingebaute Karte unverändert: " + bi)
	# Menüeintrag Einzelmission
	var menu := get_tree().current_scene
	if menu and menu.has_method("show_menu"):
		Game.create_profile("CustomMaps", 2)
		Game.set_game_mode(Game.MODE_CAMPAIGN, true)
		menu.show_menu("single_mission")
		await frames(3)
		var btn: Button = null
		for b in menu.mission_buttons():
			if String(b.get_meta("mission")) == mid:
				btn = b
		check(btn != null and not btn.disabled and (btn.text.contains("Eigene Karte") or btn.text.contains("Custom map")),
			"Menü EINZELMISSION: Eintrag mit Kennzeichnung", btn.text if btn else "fehlt")
		Game.end_single_mission()
	else:
		check(false, "Hauptmenü nicht gefunden")
	# --- 5. Prüfsummen-Abgleich ----------------------------------------------------------------------------------
	var srv := {"map": mid}
	CM.annotate_settings(srv)
	var info: Dictionary = srv.get("custom_map", {})
	check(String(info.get("sha256", "")) == FileAccess.get_sha256(out) and info.get("id") == ID, "Server: id + SHA-256 der .pck im Kartenwechsel-Dictionary")
	var plain := {"map": "m01_funkfeuer"}
	CM.annotate_settings(plain)
	check(not plain.has("custom_map"), "eingebaute Karte ohne Zusatzschlüssel")
	check(CM.check_remote(srv) == "", "Client mit gleicher Datei: Beitritt erlaubt")
	check(CM.check_remote(plain) == "", "eingebaute Karte: keine Prüfung")
	var bad := srv.duplicate(true)
	bad["custom_map"]["sha256"] = "00" + String(info.get("sha256", "")).substr(2)
	var e_sha := CM.check_remote(bad)
	check(e_sha.contains("SHA-256") and e_sha.contains("Custom map"), "abweichende Prüfsumme: Meldung DE+EN", e_sha)
	var missing := {"map": "custom_gibtsnicht", "custom_map": {"id": "gibtsnicht", "sha256": "ab", "version": "1"}}
	check(CM.check_remote(missing).contains("nicht installiert"), "fehlende Karte: Meldung")
	check(CM.check_remote({"map": "custom_gibtsnicht"}) != "", "unbekannte custom_-Karte ohne Prüfangabe: Meldung")
	check(CM.check_remote({"map": mid, "custom_map": {"id": "../x", "sha256": "", "version": ""}}) != "", "manipulierte id abgewiesen")
	# echter Client-Pfad: _enter_match mit falscher Prüfsumme lädt nichts und meldet
	Net.last_error = ""
	var before := Game.current_mission_id
	Net._enter_match(bad, [0.0, 0.0])
	await frames(5)
	check(Net.last_error == e_sha and Game.current_mission() == null and Game.current_mission_id == before,
		"Net._enter_match: kein Laden, Meldung im Menü", Net.last_error.substr(0, 80))
	# --- 6. Karte starten ----------------------------------------------------------------------------------------
	Game.start_mission(mid)
	var t := 0
	while (mission() == null or mission().squad == null or mission().squad.members.is_empty()) and t < 60 * 120:
		await frames(10)
		t += 10
	var m := mission()
	check(m != null and m.get_script().resource_path.ends_with("custom_maps/%s/mission.gd" % ID), "Missionsskript aus dem Paket läuft",
		m.get_script().resource_path if m else "keine Mission")
	if m:
		check(m.get("map_scene") != null and (m.map_scene as Node).get_node_or_null("Ground") != null, "Szene aus dem Paket geladen")
		var sp: Array = m.mp_spawns()
		var axis := sp.filter(func(p): return int(p["team"]) == Soldier.TEAM_AXIS).size()
		check(sp.size() == 4 and axis == 2, "Spawn-Marker: 2 Alliierte + 2 Achse", str(sp.size()))
		if m.squad and not m.squad.members.is_empty():
			var p0: Vector3 = m.squad.members[0].global_position
			check(Vector2(p0.x, p0.z).distance_to(Vector2(-3, 16)) < 3.0, "Trupp startet am Spawn_Allied_1", str(p0))
			await seconds(2.0)
			check(m.squad.members[0].alive and m.squad.members[0].global_position.y > -2.0, "steht auf der Kollision (2 s)",
				str(m.squad.members[0].global_position))
	_finish()


func _with(d: Dictionary, k: String, v: Variant) -> Dictionary:
	var c := d.duplicate(true)
	c[k] = v
	return c


func _without(d: Dictionary, k: String) -> Dictionary:
	var c := d.duplicate(true)
	c.erase(k)
	return c
