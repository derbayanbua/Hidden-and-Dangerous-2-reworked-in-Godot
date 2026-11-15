extends Node
## 0.11.6 MP-Minikarte (src/ui/mp_minimap.gd), zwei echte ENet-Prozesse, Team-Deathmatch, 1 KI je Team, alle unverwundbar:
##  Host (Alliierte) + Client (Achse). Prüft: eigene Marke (Mitte = eigene Figur), Verbündete sichtbar (KI des eigenen
##  Teams), Gegner unsichtbar bis zum Schuss; echter Netzschuss des Gegners → Marke an der Schützenlage, blendet aus und
##  verschwindet; Schalldämpferschüsse (mp40_sd) und eigene Schüsse nie; Schalldämpfer-Erkennung.
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


## Marken einer Quelle in der Gegnerliste der Minikarte
func _marks_of(mm, src: Soldier) -> Array:
	return mm.enemy_shots().filter(func(e): return e["src"] == src)


func _fire(s: Soldier) -> void:
	var w := s.current_weapon()
	if w:
		w.in_mag = w.data.magazine_size
		s.has_aim_point = false
		s._fire_shot(w)


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
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/mp_minimap_client.log")]
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
	await _initial("Host", ally, [puppet, axis_bot])
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
	# 2) Schalldämpferschüsse: gegnerische KI (Server-lokal) und verbündete KI mit mp40_sd; eigener Schuss
	axis_bot.equip(["mp40_sd"])
	ally.equip(["mp40_sd"])
	await get_tree().process_frame
	_fire(axis_bot)
	_fire(ally)
	await get_tree().create_timer(0.5).timeout
	check(_marks_of(mm, axis_bot).is_empty(), "Host: Schalldämpferschuss des Gegners erscheint nicht")
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
	await wait_for(func(): return _read(STEP_HOST).begins_with("ready"), 240.0)
	await get_tree().create_timer(1.0).timeout
	var m: Mission = Game.current_mission()
	if m and m.controller:
		m.controller.input_enabled = false
	var bots := _bots()
	var me: Soldier = Net._soldiers.get(Net.my_id())
	var host_s: Soldier = Net._soldiers.get(1)
	var axis_bot: Soldier = bots.get(Soldier.TEAM_AXIS)
	var allied_bot: Soldier = bots.get(Soldier.TEAM_ALLIED)
	await _initial("Client", axis_bot, [host_s, allied_bot])
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
	await wait_for(func(): return _read(STEP_HOST).begins_with("host_fired"), 120.0)
	var seen := await wait_for(func(): return not _marks_of(mm, host_s).is_empty(), 10.0)
	check(seen, "Client: Schuss des gegnerischen Hosts (Netz) erscheint")
	check(_marks_of(mm, allied_bot).is_empty(), "Client: Schalldämpferschuss der gegnerischen KI erscheint nie")
	check(_marks_of(mm, axis_bot).is_empty(), "Client: Schuss der verbündeten KI ist keine Gegnermarke")
	await wait_for(func(): return mm.enemy_shots().is_empty(), 5.0)
	check(mm.enemy_shots().is_empty(), "Client: Marken ausgeblendet")
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
