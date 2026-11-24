extends Node
## Testkarte Castle im Mehrspieler: zwei echte ENet-Prozesse (Host + Client), Karte, Bots, Spawn, Bewegung.
## Spieler (Host und Client) sind auf dem Server unverwundbar (protect_until), Bots laufen frei.
##  ohne Schalter  – Deathmatch: Starts und alle Figuren in der Spielfläche (Höfe F, E, D), Bots bleiben dort (innere Grenze)
##  --tdm=1        – Team-Deathmatch: Alliierte starten im Hof D, Achse in der Hauptburg F (Host, Client, Bots)
##  --occupation=1 – Eroberung, ganze Burg, Zonen A–F mit FRONTLINE: Wege zwischen allen Zonen, Bots nehmen ihre
##                   Nachbarzone ein, nicht benachbarte Zone bleibt gesperrt, Host nimmt die Front bis E ein (neutral →
##                   eigen, gegnerisch → neutral → eigen, Punkte), Flaggen beim Client, Wiedereinstieg an eigener Zone.
## tools/godot.cmd --headless -- --autoplay=test_castle_mp [--tdm=1 | --occupation=1]
var failed := 0
var passed := 0
var child_pid := -1
var peer_mode := false
var map_id := "castle"
var game_mode := Net.Mode.DEATHMATCH
const PORT_OFFSET := 43


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	peer_mode = Game.cli.has("castle_peer")
	if Game.cli.has("occupation"):
		map_id = "castle_occupation"
		game_mode = Net.Mode.OCCUPATION
	elif Game.cli.has("tdm"):
		map_id = "castle_tdm"
		game_mode = Net.Mode.TEAM_DEATHMATCH
	# erster Lauf ohne Navmesh-Cache: Backen der ganzen Burg ~3–4 min je Prozess (Client liest danach den Cache)
	var limit := 840.0 if game_mode == Net.Mode.OCCUPATION else 600.0
	get_tree().create_timer(limit, true, false, true).timeout.connect(func():
		check(false, "MP-Zeitüberschreitung")
		_finish())
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)


func wait_for(condition: Callable, seconds := 90.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return condition.call()


## Server: alle Spielerfiguren unverwundbar halten (auch nach Respawn); Bots nicht
func _protect_players() -> void:
	while is_inside_tree() and Net.is_online:
		for id in Net._soldiers:
			var s: Soldier = Net._soldiers[id]
			if int(id) > 0 and is_instance_valid(s) and not s.has_meta("test_mortal"):
				s.set_meta("protect_until", 1 << 60)
		await get_tree().create_timer(0.25).timeout


func _sec(m: Mission, p: Vector3) -> String:
	return m.real.section_of(Vector2(p.x, p.z)) if m.real != null else ""


func _run() -> void:
	await get_tree().process_frame
	if peer_mode:
		await _client()
		_finish()
		return
	var menu := get_tree().current_scene
	menu.open_lan()
	await get_tree().process_frame
	var lm: LanMenu = menu.lan_menu
	var found := -1
	for i in lm._map.item_count:
		if lm._map.get_item_metadata(i) == map_id:
			found = i
	check(found >= 0, "Castle (%s) im LAN-Menü auswählbar" % map_id)
	if found >= 0:
		lm._map.select(found)
		lm._sync_mode()
		check(lm._mode.selected == game_mode, "Passender Spielmodus gewählt")
	Net.local_name = "CastleHost"
	Net.local_team = 0
	check(Net.host({"name": "Castle Test", "map": map_id, "mode": game_mode,
		"port": Net.PORT + PORT_OFFSET, "max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5,
		"bots_per_team": 1, "password": "", "allow_vehicles": false, "flood_protect": false}), "Server gestartet")
	_protect_players()
	var ready := await wait_for(func(): return Game.current_mission() != null and Net._soldiers.has(1) and Net._soldiers.size() >= 3)
	check(ready, "Host und zwei MP-Bots erzeugt")
	if not ready:
		_finish()
		return
	var m: Mission = Game.current_mission()
	check(m.enemies.is_empty(), "Keine Kampagnengegner")
	check(m.get("play_mode") == game_mode, "Karte im Modus %s gebaut" % Net.MODE_NAMES[game_mode])
	# Startlagen (Bots bewegen sich erst nach dem Navmesh)
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		var p := s.global_position
		check(m.in_play_area(p), "Start %s in der Spielfläche (Hof %s)" % [str(id), _sec(m, p)])
		if m.real != null and game_mode == Net.Mode.TEAM_DEATHMATCH:
			check(_sec(m, p) == ("D" if s.team == 0 else "F"), "TDM: %s (Team %d) startet im Hof %s" % [str(id), s.team, "D" if s.team == 0 else "F"])
		if m.real != null and game_mode == Net.Mode.OCCUPATION:
			check(_sec(m, p) == ("A" if s.team == 0 else "F"), "Eroberung: %s (Team %d) startet an der eigenen Zone" % [str(id), s.team])
	check(await wait_for(func(): return m.nav_ready and m.actors_root.process_mode != Node.PROCESS_MODE_DISABLED, 400.0),
		"Host-Navigation bereit und Bots freigegeben")
	_test_vehicles(m)
	if game_mode == Net.Mode.OCCUPATION:
		_test_paths(m)
		Net.move_check = false      # Testclient parkt seine Figur per Versetzen außerhalb der Zonen
	var args := ["--headless", "--log-file",
		ProjectSettings.globalize_path("res://test_output/castle_mp_client.log"), "--", "--autoplay=test_castle_mp", "--castle_peer=1"]
	if OS.has_feature("editor"):
		args.insert(1, "--path")
		args.insert(2, ProjectSettings.globalize_path("res://"))
	if game_mode == Net.Mode.OCCUPATION:
		args.append("--occupation=1")
	elif game_mode == Net.Mode.TEAM_DEATHMATCH:
		args.append("--tdm=1")
	child_pid = OS.create_process(OS.get_executable_path(), args)
	check(child_pid > 0, "Zweiter Spielprozess gestartet")
	var joined := await wait_for(func(): return Net.players.values().any(func(p): return String(p.get("name", "")) == "CastleGuest"), 240.0)
	check(joined, "Client beigetreten")
	var ack := await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text", "")).begins_with("CASTLE_CLIENT_")), 400.0)
	check(ack and Net.chat_log.any(func(e): return String(e.get("text", "")) == "CASTLE_CLIENT_OK"), "Client bestätigt Karte, Spawn und Bewegung")
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		check(is_instance_valid(s) and m.inside_map(s.global_position) and s.global_position.y > m.ground_y(s.global_position.x, s.global_position.z) - 0.5,
			"Netzfigur %s innerhalb der Karte über Boden" % str(id))
	if game_mode == Net.Mode.OCCUPATION:
		await _test_occupation(m)
	else:
		# Bots jagen 25 s frei: niemand verlässt die Spielfläche (innere Grenze C|D)
		await get_tree().create_timer(25.0).timeout
		for id in Net._soldiers:
			var s: Soldier = Net._soldiers[id]
			if is_instance_valid(s) and s.alive:
				check(m.in_play_area(s.global_position), "Nach 25 s: %s in der Spielfläche (Hof %s)" % [str(id), _sec(m, s.global_position)])
	Net.leave(false)
	if child_pid > 0:
		await wait_for(func(): return not OS.is_process_running(child_pid), 8.0)
	_finish()


func _client() -> void:
	Net.local_name = "CastleGuest"
	Net.local_team = 1
	Net.join("127.0.0.1", Net.PORT + PORT_OFFSET, "")
	var ready := await wait_for(func():
		return Game.current_mission() != null and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1), 240.0)
	check(ready, "Client hat Castle und beide Spieler geladen")
	if not ready:
		return
	check(Game.current_mission_id == map_id and Net.mode() == game_mode, "Client erhält richtige Karte und Spielmodus")
	var m: Mission = Game.current_mission()
	var me: Soldier = Net._soldiers[Net.my_id()]
	check(await wait_for(func(): return m.nav_ready and m.actors_root.process_mode != Node.PROCESS_MODE_DISABLED, 400.0),
		"Client-Navigation bereit")
	check(m.in_play_area(me.global_position) and me.alive, "Client lebt in der Spielfläche (Hof %s)" % _sec(m, me.global_position))
	if m.real != null and game_mode == Net.Mode.TEAM_DEATHMATCH:
		check(_sec(m, me.global_position) == "F", "TDM: Client (Achse) startet in der Hauptburg F")
	# Fahrzeuge: gleiche Knoten an gleicher Stelle wie beim Host (Netzabgleich über den Knotenpfad)
	var vs: Array = m.get("vehicles")
	var want_n := 0 if game_mode == Net.Mode.DEATHMATCH else 4
	check(vs.size() == want_n, "Client: %d Fahrzeuge (erwartet %d)" % [vs.size(), want_n])
	var start := me.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(1.2).timeout
	Input.action_release("move_forward")
	check(me.global_position.distance_to(start) > 0.8, "Client kann sich bewegen")
	if game_mode == Net.Mode.OCCUPATION:
		check(await wait_for(func(): return Net.zone_owner.size() == m.mp_zones().size() and Net.zone_owner.size() == 6), "Client erhält sechs Zonen")
		check(m.frontline, "Client: Frontlinie aktiv")
		# Figur außerhalb aller Zonen parken (Hauptburg), damit sie keine Einnahme blockiert
		var park := _park_point(m)
		check(park.is_finite(), "Parkplatz außerhalb der Zonen gefunden")
		if park.is_finite():
			me.global_position = park
			me.velocity = Vector3.ZERO
			await get_tree().create_timer(1.0).timeout
	Net.send_chat("CASTLE_CLIENT_OK" if failed == 0 else "CASTLE_CLIENT_FAIL")
	if game_mode == Net.Mode.OCCUPATION:
		# Host nimmt die Front bis E ein: Besitz und Flagge der Zone E beim Client
		# erst Neutralisieren durch die Alliierten (Testzustand: E bei der Achse), dann Einnahme
		var neut := await wait_for(func(): return Net.zone_events.any(func(e): return e[0] == 4 and e[1] == -1 and e[2] == 0), 360.0)
		check(neut, "Client erhält die Neutralisierung der Zone E")
		var ok := await wait_for(func(): return Net.zone_owner.size() == 6 and Net.zone_owner[4] == 0, 60.0)
		check(ok, "Client erhält den Besitzwechsel der Zone E")
		var fl: Dictionary = m.mp_zones()[4].flags
		var flag_ok: bool = ok and m.runtime.find_frame(fl.allied).visible and not m.runtime.find_frame(fl.axis).visible \
			and not m.runtime.find_frame(fl.neutral).visible
		check(flag_ok, "Client zeigt die Flagge des neuen Besitzers")
		Net.send_chat("CASTLE_FLAGS_OK" if flag_ok else "CASTLE_FLAGS_FAIL")
	await wait_for(func(): return not Net.is_online, 120.0)


## Bodenpunkt in der Hauptburg F auf dem Netz, außerhalb aller Zonen (≥ 6 m Rand)
## Fahrzeuge (castle_vehicles.gd): DM keine; TDM/Eroberung je Seite zwei an der Basis (≤ 40 m vom ersten Spawnpunkt),
## in der Spielfläche, auf dem Boden, unbeschädigt, Originalmodell (mit Cache); Einsteigen als Fahrer und Aussteigen
func _test_vehicles(m: Mission) -> void:
	var vs: Array = m.get("vehicles")
	if game_mode == Net.Mode.DEATHMATCH:
		check(vs.is_empty(), "DM: keine Fahrzeuge")
		return
	check(vs.size() == 4, "Vier Fahrzeuge an den Basen (%d)" % vs.size())
	var VS = load("res://src/maps/castle/castle_vehicles.gd")
	for v in vs:
		var veh := v as Vehicle
		var team := int(String(veh.name).split("_")[2])
		var base: Vector3 = VS.base_point(m, team)
		var p := veh.global_position
		var d := Vector2(p.x - base.x, p.z - base.z).length()
		check(d <= 40.0 and m.in_play_area(p), "%s an der Basis %d (%.1f m, Hof %s)" % [veh.vehicle_name, team, d, _sec(m, p)])
		check(not veh.wrecked and absf(p.y - m.ground_y(p.x, p.z)) < 3.0 and veh.global_basis.y.y > 0.9,
			"%s steht unbeschädigt auf dem Boden (y %.1f, Boden %.1f)" % [veh.vehicle_name, p.y, m.ground_y(p.x, p.z)])
		if DirAccess.dir_exists_absolute(OrigLevel.cache_root()):
			check(veh.custom_visual != null and veh.drive_model != "", "%s mit Originalmodell %s" % [veh.vehicle_name, veh.drive_model])
	var names: Array = vs.map(func(v): return String(v.vehicle_name))
	check(names.has("Jeep") and names.has("Kübelwagen") and names.filter(func(n): return n.contains("Halbkette") or n.contains("Sd.Kfz")).size() == 2,
		"Jeep, Kübelwagen und zwei Halbketten (%s)" % str(names))
	var host: Soldier = Net._soldiers.get(1)
	if is_instance_valid(host) and not vs.is_empty():
		var veh := vs[0] as Vehicle
		# Testserver läuft mit allow_vehicles = false (Bots); Regel für diese Prüfung kurz an
		var had = Net.settings.get("allow_vehicles")
		Net.settings["allow_vehicles"] = true
		var ok: bool = veh.board(host, true)
		check(ok and host.vehicle == veh and host.seat_index == 0, "Host steigt als Fahrer in %s ein" % veh.vehicle_name)
		if ok:
			veh.leave(host)
			check(host.vehicle == null, "Host steigt wieder aus")
		Net.settings["allow_vehicles"] = had


func _park_point(m: Mission) -> Vector3:
	if m.real == null:
		return Vector3.INF
	var map: RID = m.get_world_3d().navigation_map
	var zs: Array = m.all_zones()
	for p in m.real._candidates(["F"], 4.0, 6.0):
		var g := Vector3(p.x, m.ground_y(p.x, p.y), p.y)
		var q := NavigationServer3D.map_get_closest_point(map, g)
		if q.distance_to(g) > 0.5:
			continue
		var clear := true
		for z in zs:
			for o in [Vector3.ZERO, Vector3(6, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 6), Vector3(0, 0, -6)]:
				if Net.zone_contains(z, q + Vector3.UP * 0.5 + o):
					clear = false
		if clear:
			return q + Vector3.UP * 0.3
	return Vector3.INF


## Pfad ohne 4096-Polygon-Grenze
func _reach(m: Mission, a: Vector3, b: Vector3, tol := 2.5) -> bool:
	var q := NavigationPathQueryParameters3D.new()
	q.map = m.get_world_3d().navigation_map
	q.start_position = a
	q.target_position = b
	if "path_search_max_polygons" in q:
		q.set("path_search_max_polygons", 0)
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.path.size() > 1 and r.path[r.path.size() - 1].distance_to(b) < tol


## Eroberung (ganze Burg): Weg von Zone zu Zone über Tortunnel und Brücken
func _test_paths(m: Mission) -> void:
	var zs: Array = m.mp_zones()
	check(zs.size() == 6 and m.frontline, "Sechs Zonen A–F, Frontlinie aktiv")
	check(m.real == null or (m.real.inner_lines.is_empty() and get_tree().get_nodes_in_group("castle_inner_boundary").is_empty()),
		"Eroberung: keine innere Grenze")
	for i in zs.size() - 1:
		var a: Vector3 = (zs[i].xf as Transform3D).origin - Vector3(0, 0.8, 0)
		var b: Vector3 = (zs[i + 1].xf as Transform3D).origin - Vector3(0, 0.8, 0)
		check(_reach(m, a, b), "Weg %s → %s über das Netz" % [zs[i].name, zs[i + 1].name])


func _bots() -> Array:
	var out: Array = []
	for id in Net._soldiers:
		if int(id) < 0 and is_instance_valid(Net._soldiers[id]):
			out.append(Net._soldiers[id])
	return out


## Host-Figur in eine Zone setzen und warten, bis sie eigen ist; prüft Punkte (+2 neutralisieren, +5 einnehmen)
func _capture(m: Mission, host: Soldier, zi: int) -> bool:
	var zs: Array = m.mp_zones()
	var before := int(Net.zone_owner[zi])
	var team := host.team
	var score0 := int(Net.players[1]["score"])
	host.global_position = (zs[zi].xf as Transform3D).origin - Vector3(0, 0.5, 0)
	host.velocity = Vector3.ZERO
	var cap := float(zs[zi].capture_time)
	if before not in [-1, team]:
		check(await wait_for(func(): return Net.zone_owner[zi] == -1, cap + 10.0), "Gegnerzone %s wird neutral" % zs[zi].name)
	var ok := await wait_for(func(): return Net.zone_owner[zi] == team, cap + 10.0)
	check(ok, "Zone %s wird eingenommen" % zs[zi].name)
	var want := score0 + Net.ZONE_CAPTURE_PTS + (Net.ZONE_NEUTRALIZE_PTS if before not in [-1, team] else 0)
	check(int(Net.players[1]["score"]) == want, "Punktewertung Zone %s (%d → %d, erwartet %d)" % [zs[zi].name, score0,
		int(Net.players[1]["score"]), want])
	return ok


func _test_occupation(m: Mission) -> void:
	var zs: Array = m.mp_zones()
	check(zs.size() == 6 and Net.zone_owner.size() == 6, "Sechs Zonen mit Besitz")
	var host: Soldier = Net._soldiers[1]
	var team := host.team
	check(team == 0, "Host spielt die Alliierten")
	# 1. Bots: jede Seite nimmt ihre Nachbarzone (Alliierte B, Achse E), Weg über Tortunnel/Brücken
	var t0 := Time.get_ticks_msec()
	var seen := {0: false, 1: false}       # Bot war in der Nachbarzone (B bzw. E)
	var next_log := 0
	while Time.get_ticks_msec() - t0 < 240000:
		for b in _bots():
			var tz := 1 if b.team == 0 else 4
			if b.alive and Net.zone_contains(zs[tz], b.global_position + Vector3.UP * 0.5):
				seen[b.team] = true
		if Time.get_ticks_msec() >= next_log:
			next_log = Time.get_ticks_msec() + 10000
			for b in _bots():
				var br = b.get_node_or_null("EnemyBrain")
				print("BOTLAUF %3.0f s %s Team %d Hof %s %s Ziel %s/%s Merkmal %s" % [(Time.get_ticks_msec() - t0) / 1000.0, b.soldier_name,
					b.team, _sec(m, b.global_position), str(b.global_position), str(br.get("goal_kind")) if br else "-",
					str(br.get("goal_zone")) if br else "-", str(br.get("persona")) if br else "-"])
			print("BOTLAUF Besitz ", Net.zone_owner)
		if (Net.zone_owner[1] == 0 or seen[0]) and (Net.zone_owner[4] == 1 or seen[1]):
			break
		await get_tree().create_timer(0.5).timeout
	print("BOTS Besitz nach %.0f s: %s, in Nachbarzone %s" % [(Time.get_ticks_msec() - t0) / 1000.0, str(Net.zone_owner), str(seen)])
	check(Net.zone_owner[1] == 0 or seen[0], "Bot der Alliierten erreicht bzw. nimmt die Nachbarzone B")
	check(Net.zone_owner[4] == 1 or seen[1], "Bot der Achse erreicht bzw. nimmt die Nachbarzone E")
	# Bots anhalten und weit über der Karte parken (keine Einnahme/Blockade während der Host-Prüfungen)
	for b in _bots():
		b.process_mode = Node.PROCESS_MODE_DISABLED
		b.global_position = (zs[0].xf as Transform3D).origin + Vector3(0, 60, 0)
	check(await wait_for(func():
		for id in Net._soldiers:
			if int(id) > 1 and is_instance_valid(Net._soldiers[id]):
				for z in zs:
					if Net.zone_contains(z, Net._soldiers[id].global_position):
						return false
		return true, 30.0), "Client-Figur steht außerhalb aller Zonen")
	host.process_mode = Node.PROCESS_MODE_DISABLED
	# Testzustand für die Host-Prüfungen (unabhängig davon, wie weit die Bots kamen): A Alliierte, E und F Achse, Rest neutral
	Net.zone_owner = [0, -1, -1, -1, 1, 1]
	Net.zone_progress = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	Net.zone_attacker = [-1, -1, -1, -1, -1, -1]
	Net._zones.rpc(Net.zone_owner, Net.zone_progress)
	await get_tree().create_timer(1.0).timeout
	# 2. FRONTLINE: neutrale Zone ohne eigene Nachbarzone ist nicht einnehmbar
	var k := -1
	for i in range(2, 5):
		if Net.zone_owner[i] != team and Net.zone_owner[i - 1] != team and Net.zone_owner[i + 1] != team:
			k = i
			break
	check(k >= 0, "Nicht benachbarte Zone vorhanden (Besitz %s)" % str(Net.zone_owner))
	if k >= 0:
		var own_before := int(Net.zone_owner[k])
		host.global_position = (zs[k].xf as Transform3D).origin - Vector3(0, 0.5, 0)
		host.velocity = Vector3.ZERO
		await get_tree().create_timer(float(zs[k].capture_time) * 0.5 + 3.0).timeout
		check(int(Net.zone_owner[k]) == own_before and int(Net.zone_attacker[k]) == -1 and not Net._attackable(m, k, team),
			"FRONTLINE: Zone %s ohne eigene Nachbarzone bleibt gesperrt" % zs[k].name)
	# 3. Front bis E vorschieben (B…E), gegnerische Zone: neutral → eigen
	var front_ok := true
	for i in range(1, 5):
		if Net.zone_owner[i] == team:
			continue
		check(Net._attackable(m, i, team), "Zone %s ist Nachbar einer eigenen Zone" % zs[i].name)
		front_ok = await _capture(m, host, i) and front_ok
		if not front_ok:
			break
	var side := "allied" if team == 0 else "axis"
	check(m.runtime.find_frame(zs[4].flags[side]).visible and not m.runtime.find_frame(zs[4].flags.neutral).visible,
		"Flaggenwechsel Zone E (Host)")
	check(Net.zone_owner[5] == 1, "Hauptburg F bleibt bei der Achse (Runde läuft weiter)")
	# 4. Flaggen beim Client
	check(await wait_for(func(): return Net.chat_log.any(func(e): return String(e.get("text", "")).begins_with("CASTLE_FLAGS_")), 40.0)
		and Net.chat_log.any(func(e): return String(e.get("text", "")) == "CASTLE_FLAGS_OK"), "Client zeigt die Flagge der eingenommenen Zone")
	# 5. Wiedereinstieg: eigene Frontzone E wählen, sterben, Respawn-Welle an E
	host.global_position = (zs[3].xf as Transform3D).origin - Vector3(0, 0.5, 0)
	Net.request_zone(4)
	check(int(Net.players[1].get("zone", -1)) == 4, "Eigene Zone E als Wiedereinstieg wählbar")
	host.set_meta("test_mortal", true)
	host.set_meta("protect_until", 0)
	host.apply_hit(1000, &"torso", null, Vector3.FORWARD)
	check(await wait_for(func():
		var s: Soldier = Net._soldiers.get(1)
		return is_instance_valid(s) and s != host and s.alive, 20.0), "Respawn-Welle erzeugt neuen Soldaten")
	var respawned: Soldier = Net._soldiers[1]
	check((zs[4].slots as Array).any(func(slot): return (slot.pos as Vector3).distance_to(respawned.global_position) < 2.0),
		"Wiedereinstieg an der Zone E (%s)" % str(respawned.global_position))


func _finish() -> void:
	if Net.is_online:
		Net.leave(false)
	if child_pid > 0 and OS.is_process_running(child_pid):
		OS.kill(child_pid)
	print("ERGEBNIS: Castle MP %s (%s): %d bestanden, %d fehlgeschlagen" % ["Client" if peer_mode else "Host", map_id, passed, failed])
	get_tree().quit(1 if failed else 0)
