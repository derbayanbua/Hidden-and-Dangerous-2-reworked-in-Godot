extends Node
## 0.11.6 MP-Minikarte (src/ui/mp_minimap.gd), zwei echte ENet-Prozesse, Team-Deathmatch, 1 KI je Team, alle unverwundbar:
##  Host (Alliierte) + Client (Achse). Prüft: eigene Marke (Mitte = eigene Figur), Verbündete sichtbar (KI des eigenen
##  Teams), Gegner unsichtbar bis zum Schuss; echter Netzschuss des Gegners → Marke an der Schützenlage, blendet aus und
##  verschwindet; Schalldämpferschüsse (mp40_sd) und eigene Schüsse nie; Schalldämpfer-Erkennung.
##  0.11.7: Regel „minimap“ (Standard aus → Kompass), Konsole „minimap 1“ → Minikarte links unten über der Truppleiste,
##  Kompass aus, Client empfängt die Regel (Client-Prozess im Fenster, Bilder test_output/mp_minimap/), Einschussloch eines
##  Netzschusses beim Client (test_output/impacts/mp_remote_hole.png).
##  0.11.7: große Karte M (TDM ohne Zonen = Übersicht) mit denselben Marken (eigene Lage, Verbündeter, Gegnerschuss),
##  Zuschauerregel über MapMarks.mp_center; Kontrollbild test_output/mp_minimap/bigmap_marks.png (Client-Fenster).
##   tools\godot.cmd --headless -- --autoplay=test_mp_minimap
## Client-Teilprozess (startet der Test selbst): --mm_peer=1

const PORT_OFS := 53
const FALLBACK_MAP := "mp_arena_a1_blizzard"
const STEP_HOST := "user://mm_step_host.txt"
const STEP_CLIENT := "user://mm_step_client.txt"
const RESULT := "user://mm_client_result.txt"
const MM := preload("res://src/ui/mp_minimap.gd")
const GOD := 1 << 60

var passed := 0
var failed := 0
var lines: PackedStringArray = []
var peer_mode := false


static func _map() -> String:
	if Game.cli.has("mm_map"):
		return String(Game.cli["mm_map"])
	for id in Game.MP_MAPS:
		if int(Game.MISSIONS.get(id, {}).get("mp_mode", -1)) == Net.Mode.TEAM_DEATHMATCH:
			return String(id)
	return FALLBACK_MAP


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	peer_mode = Game.cli.has("mm_peer")
	get_tree().create_timer(900.0 if peer_mode else 1500.0, true, false, true).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	check(false, "Zeitüberschreitung des Testlaufs")
	_finish()


func check(ok: bool, label: String, detail := "") -> void:
	var line: String = ("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")")
	print(line)
	lines.append(line)
	if ok:
		passed += 1
	else:
		failed += 1


func wait_for(cond: Callable, s := 60.0) -> bool:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return bool(cond.call())


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _mm():
	var m = Game.current_mission()
	var hud = m.get_node_or_null("MpHud") if m else null
	return hud.minimap if hud else null


func _bots() -> Dictionary:
	var out := {}
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if int(id) < 0 and is_instance_valid(s) and s.alive:
			out[s.team] = s
	return out


func _client_peer() -> int:
	for id in Net._soldiers:
		if int(id) > 1 and is_instance_valid(Net._soldiers[id]):
			return int(id)
	return 0


func _client_loaded() -> bool:
	var mm = Game.current_mission()
	return mm != null and mm.is_node_ready() and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1) and _bots().size() == 2


## 0.11.7: Kompass sichtbar (OrigHud bzw. eigenes HUD)
func _compass_visible() -> bool:
	var h = Game.current_mission().hud
	if h.orig_hud:
		return h.orig_hud.compass_shown()
	return h._compass.is_visible_in_tree()


## 0.11.7: Standard = Regel aus → Kompass, keine Minikarte
func _default_off(tag: String) -> void:
	var mm = _mm()
	await get_tree().create_timer(0.5).timeout
	check(not bool(Net.rule("minimap")) and not Net.minimap_enabled(), "%s: Regel minimap standardmäßig aus" % tag)
	check(not mm.visible, "%s: Minikarte aus (Standard)" % tag)
	check(_compass_visible(), "%s: Kompass sichtbar (Standard)" % tag)


## 0.11.7: Regel an → Minikarte links unten über den Spielersymbolen, Kompass weg
func _layout_on(tag: String) -> void:
	var mm = _mm()
	await wait_for(func(): return not _compass_visible(), 5.0)
	check(not _compass_visible(), "%s: Kompass ausgeblendet (Minikarte ersetzt ihn)" % tag)
	var root := mm.get_parent() as Control
	var h: float = root.size.y
	if h < 300.0:
		return       # kopflos 64×64 px: Lage nur im Fensterprozess prüfbar
	var r: Rect2 = mm.get_global_rect()
	var bar: float = mm.squad_bar_top(h)
	check(r.position.x <= root.size.x * 0.05, "%s: Minikarte am linken Rand" % tag, str(r))
	check(r.end.y <= bar + 0.5 and r.end.y >= bar - 30.0, "%s: Minikarte direkt über den Spielersymbolen" % tag,
		"Unterkante %.0f, Truppleiste %.0f" % [r.end.y, bar])
	check(r.position.y > h * 0.4, "%s: Minikarte in der unteren Bildhälfte" % tag, str(r))
	var oh = Game.current_mission().hud.orig_hud
	if oh and oh.elements.has("soldier00"):
		check(not r.intersects(oh.elements["soldier00"]["screen"]), "%s: keine Überdeckung mit dem Spielerfeld" % tag)


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in 4:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/mp_minimap"))
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://test_output/mp_minimap/%s.png" % name))


## Marken einer Quelle in der Gegnerliste der Minikarte
func _marks_of(mm, src: Soldier) -> Array:
	return mm.enemy_shots().filter(func(e): return e["src"] == src)


func _fire(s: Soldier) -> void:
	var w := s.current_weapon()
	if w:
		w.in_mag = w.data.magazine_size
		s.has_aim_point = false
		s._fire_shot(w)


class SpecProbe extends RefCounted:
	var spectating := false
	var spec_free := false
	var spec_target_id := 0


## 0.11.7: große Karte M (MpHud.ZoneMap, im TDM ohne Zonen als Übersicht) zeigt dieselben Marken wie die Minikarte
func _big_map(tag: String, me: Soldier, expect_shot: bool) -> void:
	var hud = Game.current_mission().get_node_or_null("MpHud")
	var ev := InputEventAction.new()
	ev.action = &"tactical_map"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	check(hud.zone_map_open(), "%s: Taste M öffnet die große Karte (ohne Spawnzonen: Übersicht)" % tag)
	if not hud.zone_map_open():
		return
	var zm = hud._zone_panel
	zm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var md: Dictionary = zm.marks_drawn
	var exp_p: Vector2 = (zm.world_xf * Vector2(me.global_position.x, me.global_position.z)).clamp(
		zm.marks_area.grow(-4.0).position, zm.marks_area.grow(-4.0).end)
	check(md.get("self") != null and (md["self"] as Vector2).distance_to(exp_p) < 1.0, "%s: große Karte – eigene Lage + Blickrichtung" % tag, str(md))
	check(int(md.get("allies", -1)) == 1, "%s: große Karte – Verbündeter (Team-Stil) wie Minikarte" % tag, str(md))
	if expect_shot:
		check(int(md.get("shots", 0)) >= 1, "%s: große Karte – schießender Gegner sichtbar" % tag, str(md))
	await _shot("bigmap_marks")
	# Zuschauerregel (gemeinsame Sicht MapMarks.mp_center für Minikarte und große Karte): beobachteter Spieler bzw.
	# freie Kamera → keine Marken
	var other: Soldier = Net._soldiers.get(1)
	var fake := SpecProbe.new()
	fake.spectating = true
	fake.spec_target_id = 1
	check(MapMarks.mp_center(fake) == other, "%s: Zuschauer – Kartenmitte = beobachteter Spieler" % tag)
	fake.spec_free = true
	check(MapMarks.mp_center(fake) == null, "%s: Zuschauer mit freier Kamera – keine Marken" % tag)
	hud.toggle_zone_map()
	await get_tree().process_frame
	check(not hud.zone_map_open(), "%s: große Karte wieder geschlossen" % tag)


func _run() -> void:
	await get_tree().process_frame
	if peer_mode:
		await _client()
	else:
		await _host()
	_finish()


## gemeinsame Anfangsprüfung: eigene Marke, Verbündeter sichtbar, Gegner unsichtbar
func _initial(tag: String, ally_bot: Soldier, enemies: Array) -> void:
	var mm = _mm()
	await wait_for(func(): return mm.visible and mm.center_soldier != null, 20.0)
	var me: Soldier = Net._soldiers.get(Net.my_id())
	check(mm.visible and mm.center_soldier == me, "%s: Minikarte sichtbar, Mitte = eigene Figur (eigene Marke)" % tag)
	var al: Array = mm.allies()
	check(al.has(ally_bot) and al.size() == 1, "%s: Verbündeter (KI des eigenen Teams) sichtbar, sonst niemand" % tag, str(al.size()))
	var leak := enemies.any(func(e): return al.has(e))
	check(not leak and mm.enemy_shots().is_empty(), "%s: Gegner ohne Schuss nicht sichtbar" % tag)


func _host() -> void:
	for p in [STEP_HOST, STEP_CLIENT, RESULT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	check(MM.is_silenced_noise(15.0) and not MM.is_silenced_noise(130.0)
		and MM.is_silenced_noise(130.0, WeaponDB.get_weapon(&"mp40_sd")), "Schalldämpfer-Erkennung (Geräuschweite / Klangklasse)")
	Net.local_name = "Host"
	Net.local_team = Soldier.TEAM_ALLIED
	Net.local_figure = ""
	Net.move_check = false
	var ok := Net.host({"name": "MP-Minimap", "map": _map(), "mode": Net.Mode.TEAM_DEATHMATCH, "port": Net.PORT + PORT_OFS,
		"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 1,
		"password": "", "allow_vehicles": false, "friendly_fire": false})
	check(ok and Net.is_online, "Server gestartet (Team-Deathmatch)", Net.last_error)
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() and Net._soldiers.has(1), 400.0)
	var m: Mission = Game.current_mission()
	await wait_for(func(): return m.nav_ready and _bots().size() == 2, 240.0)
	check(_bots().size() == 2, "Zwei KI-Soldaten (je Team einer)")
	var me: Soldier = Net._soldiers.get(1)
	m.controller.input_enabled = false
	var bots := _bots()
	for t in bots:
		var b: Soldier = bots[t]
		var br := b.get_node_or_null("EnemyBrain")
		if br:
			br.process_mode = Node.PROCESS_MODE_DISABLED
		b.move_input = Vector3.ZERO
		b.trigger = false
	var exe := OS.get_executable_path()
	# 0.11.7: Client im Fenster (1280×720) → echte Lageprüfung der Minikarte + Kontrollbilder test_output/mp_minimap/
	var args := ["--resolution", "1280x720", "--log-file", ProjectSettings.globalize_path("res://test_output/mp_minimap_client.log")]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	var pid := OS.create_process(exe, args + ["--", "--autoplay=test_mp_minimap", "--mm_peer=1"])
	check(pid > 0, "Client-Prozess gestartet")
	await wait_for(func(): return _client_peer() != 0, 420.0)
	var cid := _client_peer()
	check(cid != 0 and int(Net.players[cid]["team"]) == Soldier.TEAM_AXIS, "Client beigetreten (Achse)")
	if cid == 0:
		return
	var puppet: Soldier = Net._soldiers[cid]
	for id in Net._soldiers:             # Unverwundbarkeit für alle (Server entscheidet Schaden)
		if is_instance_valid(Net._soldiers[id]):
			Net._soldiers[id].set_meta("protect_until", GOD)
	var ally: Soldier = bots[Soldier.TEAM_ALLIED]
	var axis_bot: Soldier = bots[Soldier.TEAM_AXIS]
	ally.global_position = me.global_position + Vector3(4, 0, 0)
	axis_bot.global_position = me.global_position + Vector3(-6, 0, 0)
	await get_tree().create_timer(1.0).timeout
	await _default_off("Host")
	_write(STEP_HOST, "default")
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("c_default"), 240.0)
	# 0.11.7: Server-Konsole „minimap 1“ → Regel an, an alle Clients (_rules_changed, Protokoll unverändert)
	var reply := Net.server_command("minimap 1")
	check(bool(Net.rule("minimap")) and Net.minimap_enabled(), "Konsole „minimap 1“ schaltet die Minikarte an", reply)
	check(bool(Net.server_info()["rules"].get("minimap", false)), "Serverinfo/Spiel-Info enthält die Regel minimap")
	await _initial("Host", ally, [puppet, axis_bot])
	await _layout_on("Host")
	_write(STEP_HOST, "ready")
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("c_ready"), 240.0)
	check(_read(STEP_CLIENT).begins_with("c_ready"), "Client: Anfangsprüfung abgeschlossen")
	# 1) Gegner (Client) feuert echt über ENet (ohne Schalldämpfer) → Marke beim Host
	var mm = _mm()
	# Spawn-Schutz sperrt auch das Schießen: kurz aufheben, der Client schießt steil in den Himmel (trifft niemanden)
	puppet.set_meta("protect_until", 0)
	_write(STEP_HOST, "fire_client")
	var seen := await wait_for(func(): return not _marks_of(mm, puppet).is_empty(), 20.0)
	check(seen, "Host: Gegner-Schuss (Netz, ohne Schalldämpfer) erscheint auf der Minikarte",
		"%s rejects=%s" % [_read(STEP_CLIENT), str(Net.rejects.slice(-3))])
	if seen:
		var e: Dictionary = _marks_of(mm, puppet)[0]
		check((e["pos"] as Vector3).distance_to(puppet.global_position) < 4.0, "Host: Marke an der Schützenlage")
		var t0 := float(e["t"])
		await get_tree().create_timer(1.0).timeout
		var still: Array = _marks_of(mm, puppet)
		check(not still.is_empty() and float(still[0]["t"]) < t0, "Host: Marke blendet aus (Restzeit sinkt)",
			"%.2f → %.2f" % [t0, float(still[0]["t"]) if not still.is_empty() else -1.0])
		await wait_for(func(): return _marks_of(mm, puppet).is_empty(), 5.0)
		check(_marks_of(mm, puppet).is_empty(), "Host: Marke nach %.1f s verschwunden" % MM.SHOT_TTL)
	puppet.set_meta("protect_until", GOD)
	check(not mm.allies().has(puppet), "Host: Gegner nach dem Schuss nicht als Verbündeter")
	await _big_map("Host", me, false)
	# 2) Schalldämpferschüsse: gegnerische KI (Server-lokal) und verbündete KI mit mp40_sd; eigener Schuss
	axis_bot.equip(["mp40_sd"])
	ally.equip(["mp40_sd"])
	await get_tree().process_frame
	_fire(axis_bot)
	_fire(ally)
	await get_tree().create_timer(0.5).timeout
	check(_marks_of(mm, axis_bot).is_empty(), "Host: Schalldämpferschuss des Gegners erscheint nicht")
	me.look_pitch = -1.2                 # 0.11.7: in den Boden → Einschussloch auch beim Client (Netzschuss)
	await get_tree().create_timer(0.3).timeout
	_fire(me)
	await get_tree().process_frame
	check(mm.enemy_shots().is_empty(), "Host: eigener Schuss erscheint nicht als Gegnermarke",
		str(me.current_weapon().data.id) if me.current_weapon() else "-")
	_write(STEP_HOST, "host_fired")
	await wait_for(func(): return FileAccess.file_exists(RESULT), 120.0)
	for line in _read(RESULT).split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	Net.leave(false)


func _client() -> void:
	Net.local_name = "Gast"
	Net.local_team = Soldier.TEAM_AXIS
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1", Net.PORT + PORT_OFS, "")
	await wait_for(_client_loaded, 420.0)
	await wait_for(func(): return _read(STEP_HOST).begins_with("default"), 420.0)
	await get_tree().create_timer(1.0).timeout
	var m: Mission = Game.current_mission()
	if m and m.controller:
		m.controller.input_enabled = false
	var bots := _bots()
	var me: Soldier = Net._soldiers.get(Net.my_id())
	var host_s: Soldier = Net._soldiers.get(1)
	var axis_bot: Soldier = bots.get(Soldier.TEAM_AXIS)
	var allied_bot: Soldier = bots.get(Soldier.TEAM_ALLIED)
	await wait_for(func(): return _read(STEP_HOST).begins_with("default"), 240.0)
	await _default_off("Client")
	await _shot("minimap_off_compass")
	_write(STEP_CLIENT, "c_default")
	await wait_for(func(): return _read(STEP_HOST).begins_with("ready"), 240.0)
	await wait_for(func(): return bool(Net.rule("minimap")), 90.0)   # Fensterprozess unter WARP: RPC-Verarbeitung langsam
	check(bool(Net.rule("minimap")), "Client: Regel minimap vom Server empfangen")
	await _initial("Client", axis_bot, [host_s, allied_bot])
	await _layout_on("Client")
	await _shot("minimap_on")
	_write(STEP_CLIENT, "c_ready")
	await wait_for(func(): return _read(STEP_HOST).begins_with("fire_client"), 120.0)
	var w := me.current_weapon()
	check(w != null and not MM.is_silenced_noise(w.data.noise_radius, w.data), "Client: eigene Waffe ohne Schalldämpfer",
		String(w.data.id) if w else "-")
	me.look_pitch = 1.3
	await get_tree().create_timer(0.3).timeout
	_fire(me)
	_write(STEP_CLIENT, "fired " + (String(w.data.id) if w else "-"))
	var mm = _mm()
	await get_tree().process_frame
	check(mm.enemy_shots().is_empty(), "Client: eigener Schuss erscheint nicht als Gegnermarke")
	var holes0: int = Effects.holes_made
	await wait_for(func(): return _read(STEP_HOST).begins_with("host_fired"), 120.0)
	await wait_for(func(): return Effects.holes_made > holes0, 5.0)
	check(Effects.holes_made > holes0 and Effects.last_hole != null and Effects.last_hole.size.x >= 0.1,
		"Client: Einschussloch des Netzschusses (Host) sichtbar", "%d → %d" % [holes0, Effects.holes_made])
	if Effects.last_hole and DisplayServer.get_name() != "headless":
		var cam := get_viewport().get_camera_3d()
		if cam:
			# Kamera auf das Loch (1,2 m Abstand) → Kontrollbild test_output/impacts/mp_remote_hole.png
			var hp: Vector3 = Effects.last_hole.global_position
			var up: Vector3 = Effects.last_hole.global_basis.y
			var probe := Camera3D.new()
			get_tree().root.add_child(probe)
			probe.global_position = hp + up * 1.2 + Vector3(0.01, 0, 0.01)
			probe.look_at(hp, Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP)
			probe.make_current()
			for i in 4:
				await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/impacts"))
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/impacts/mp_remote_hole.png"))
			probe.queue_free()
			cam.make_current()
	var seen := await wait_for(func(): return not _marks_of(mm, host_s).is_empty(), 10.0)
	check(seen, "Client: Schuss des gegnerischen Hosts (Netz) erscheint")
	check(_marks_of(mm, allied_bot).is_empty(), "Client: Schalldämpferschuss der gegnerischen KI erscheint nie")
	check(_marks_of(mm, axis_bot).is_empty(), "Client: Schuss der verbündeten KI ist keine Gegnermarke")
	await _big_map("Client", me, seen)
	# die beobachtete Marke verschwindet nach SHOT_TTL (spätere Netzschüsse des Hosts zählen als neue Marken)
	var first: Dictionary = _marks_of(mm, host_s)[0] if seen else {}
	await wait_for(func(): return not mm.shots.has(first), 30.0)   # Fensterprozess unter WARP: wenige Bilder/s
	check(seen and not mm.shots.has(first), "Client: Marken ausgeblendet",
		str(mm.enemy_shots().map(func(e): return "%s %.2f" % [str(e["src"].name) if is_instance_valid(e["src"]) else "?", float(e["t"])])))
	_write(RESULT, "\n".join(lines))
	await wait_for(func(): return not Net.is_online, 120.0)


func _finish() -> void:
	if peer_mode:
		if not FileAccess.file_exists(RESULT):
			_write(RESULT, "\n".join(lines))
		Net.leave(false)
		get_tree().quit(0)
		return
	print("ERGEBNIS: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	_write(ProjectSettings.globalize_path("res://test_output/test_mp_minimap.txt"), "\n".join(lines) + "\nERGEBNIS: %d/%d\n" % [passed, passed + failed])
	get_tree().quit(1 if failed > 0 else 0)
