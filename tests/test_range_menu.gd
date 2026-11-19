extends "res://tests/test_gameplay.gd"
## 0.11.8: Schießstand als Testkarte im Einzelspieler-Menü. Hauptmenü → EINZELSPIELER → EINZELMISSION → Eintrag
## „Schießstand (Test)“ im Bildlauf finden, wählen, Briefing → „Einsatz beginnen“ → Mission test_range läuft.
## Prüft auch: Liste läuft nicht aus dem Bild (Bildlauf), Kampagnenstand unverändert, nicht in Kampagne/Blutbad.
##   tools\godot.cmd --headless -- --autoplay=test_range_menu --profiles_dir=user://test_range_menu --noimport


func _buttons_text(root: Node, t: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == t and (b as Button).is_visible_in_tree():
			return b
	return null


func _run() -> void:
	await frames(10)
	var menu := get_tree().current_scene
	Game.create_profile("RangeMenu", 3)
	Game.set_game_mode(Game.MODE_CAMPAIGN)
	var camp_before := JSON.stringify(Game.campaign)
	check(Game.MISSIONS.has("test_range") and String(Game.MISSIONS["test_range"]["title"]).ends_with("(Test)"),
		"Register: test_range mit Titel „… (Test)“", String(Game.MISSIONS.get("test_range", {}).get("title", "")))
	check(Game.PRACTICE_MISSIONS.has("test_range") and Game.is_unlocked("test_range"), "Übungseinsatz, immer freigeschaltet")
	check(not Game.MP_MAPS.has("test_range"), "nicht in der MP-Kartenliste")
	menu.show_menu("main_menu")
	await frames(2)
	menu.show_menu("singleplayer")
	await frames(2)
	var bsm: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if String(b.name).contains("bsingle mission") and not String(b.name).contains("carnage"):
			bsm = b
	check(bsm != null and not bsm.disabled, "Einzelspieler: EINZELMISSION freigegeben")
	bsm.pressed.emit()
	await frames(3)
	var ids: Array = menu.mission_buttons().map(func(b): return String(b.get_meta("mission")))
	check(menu.current_menu == "single_mission" and ids.has("test_range"), "Einzelmission-Liste enthält den Schießstand", str(ids))
	var scroll := menu.stage.get_node_or_null("MissionList") as ScrollContainer
	check(scroll != null and scroll.position.y + scroll.size.y <= 720.0, "Liste im Bildlauf innerhalb des Bildes",
		str(scroll.get_rect()) if scroll else "")
	var rb: Button = null
	for b in menu.mission_buttons():
		if String(b.get_meta("mission")) == "test_range":
			rb = b
	check(rb != null and not rb.disabled and rb.text.contains("Schießstand (Test)"), "Eintrag wählbar", rb.text if rb else "")
	menu._select_mission("test_range")
	await frames(3)
	check(menu.selected_mission == "test_range" and not menu._start_btn.disabled, "Auswahl gesetzt, Start freigegeben")
	if scroll:
		var r := rb.get_global_rect()
		var sr := scroll.get_global_rect()
		check(sr.encloses(r), "Gewählter Eintrag ist sichtbar gescrollt", "%s in %s" % [r, sr])
	# Gegenprobe: Kampagnen- und Blutbad-Einzelmission zeigen ihn nicht
	menu.show_menu("campaign")
	await frames(2)
	check(not menu.mission_buttons().any(func(b): return String(b.get_meta("mission")) == "test_range"), "nicht in der Kampagnenliste")
	Game.set_game_mode(Game.MODE_CARNAGE, true)
	menu.show_menu("single_mission")
	await frames(2)
	check(not menu.mission_buttons().any(func(b): return String(b.get_meta("mission")) == "test_range"), "nicht in Einzelmission – Blutbad")
	Game.end_single_mission()
	Game.set_game_mode(Game.MODE_CAMPAIGN, true)
	menu.show_menu("single_mission")
	await frames(2)
	menu._select_mission("test_range")
	await frames(2)
	menu._start_btn.pressed.emit()
	await frames(3)
	check(not Game.uses_sas("test_range"), "Briefing ohne SAS-Kader (Übungsausrüstung)")
	var go := _buttons_text(menu, "Einsatz beginnen")
	check(go != null, "Briefing mit „Einsatz beginnen“")
	if go == null:
		_finish()
		return
	go.pressed.emit()
	var t := 0
	while mission() == null or mission().get_script().resource_path != "res://src/missions/test_range.gd" or mission().squad == null \
			or mission().squad.members.is_empty():
		await frames(10)
		t += 10
		if t > 60 * 240:
			break
	var m := mission()
	check(m != null and m.get_script().resource_path == "res://src/missions/test_range.gd", "Mission Schießstand gestartet")
	if m and m.squad:
		for s in m.squad.members:
			s.max_health = 100000.0
			s.health = s.max_health
		check(m.squad.members.size() >= 1 and m.squad.members[0].weapons.size() > 0, "Trupp gespawnt und bewaffnet")
	await seconds(2.0)
	check(m != null and is_instance_valid(m) and m.squad.members[0].alive, "läuft stabil (2 s)")
	Game.end_single_mission()
	check(JSON.stringify(Game.campaign) == camp_before, "Kampagnenstand unverändert")
	_finish()
