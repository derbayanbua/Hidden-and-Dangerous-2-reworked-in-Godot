extends Node
## B-011: Artillerieschlag / Luftangriff per Funkgerät, zwei echte ENet-Prozesse.
##  Host (Alliierte) + Client (Achse) + je 1 KI. Prüft Regeln/Konfiguration/SPIEL-INFO, offene Karte, Funkgerät-Spawn
##  (Original-Modell, freier Himmel, bei allen), Aufnahme (Server), Untermenü wie Original 0x4C02DD (nur passende Art),
##  Zielwahl → 3D-Kreis bei allen → Einschlag nach 5 s, Schaden nur im Radius, Kill-Feed-Ursache bei beiden, zweite Art
##  (abwechselnd), Ablehnung ohne Funkgerät, Bots nehmen das Funkgerät (supportbots), Abschalten per Konsole.
##   tools\godot.cmd --headless -- --autoplay=test_support_strike   (Client-Teilprozess: --ss_peer=1)

const PORT_OFS := 53
const STEP_HOST := "user://ss_step_host.json"
const STEP_CLIENT := "user://ss_step_client.txt"
const RESULT := "user://ss_client_result.txt"
const FB := preload("res://src/ui/mp_feedback.gd")

var passed := 0
var failed := 0
var lines: PackedStringArray = []
var peer_mode := false


static func _map() -> String:
	if Game.cli.has("ss_map"):
		return String(Game.cli["ss_map"])
	if Game.MISSIONS.has("mp_africa2_mp_zone"):
		return "mp_africa2_mp_zone"      # Original-Karte mit AIRCRAFTATACK und Funkgerätstellen
	return "mp_arena_a1_blizzard"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	peer_mode = Game.cli.has("ss_peer")
	Net.move_check = false        # B-022 F-003: der Test versetzt Figuren direkt (zum Funkgerät/Ziel) – kein Spielzug
	get_tree().create_timer(900.0 if peer_mode else 1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


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


func _client_peer() -> int:
	for id in Net._soldiers:
		if int(id) > 1 and is_instance_valid(Net._soldiers[id]):
			return int(id)
	return 0


func _run() -> void:
	await get_tree().process_frame
	if peer_mode:
		await _client()
	elif Game.cli.has("ss_probe"):
		await _probe()
	else:
		await _host()
	_finish()


# --- Sonde (nur Host): Funkgerät-Stellen einer Karte wie ein Spieler prüfen --------------------------------
##  tools\run_tests.ps1 -Only test_support_strike -ExtraArgs "--ss_probe=1 --ss_map=<id>"

func _probe() -> void:
	Net.local_name = "Host"
	Net.local_team = Soldier.TEAM_ALLIED
	var ok := Net.host({"name": "Funk", "map": _map(), "mode": int(Game.MISSIONS.get(_map(), {}).get("mp_mode", Net.Mode.TEAM_DEATHMATCH)),
		"port": Net.PORT + PORT_OFS, "max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 3,
		"bots_per_team": 0, "password": "", "allow_vehicles": false, "allow_respawn": true,
		"support_strike": 3, "support_interval_min": 1, "flood_protect": false})
	check(ok, "Server gestartet", Net.last_error)
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() and Net._soldiers.has(1), 400.0)
	var m: Mission = Game.current_mission()
	await wait_for(func(): return m.nav_ready, 240.0)
	var sup: SupportStrike = Net.support
	await wait_for(func(): return sup.map_open, 5.0)
	var pts: Array = m.mp_spawns() if m.has_method("mp_spawns") else []
	var box := AABB(pts[0]["pos"], Vector3.ZERO) if not pts.is_empty() else AABB()
	for p in pts:
		box = box.expand(p["pos"])
	check(sup.map_open, "Karte offen", "%s spawns=%d ausdehnung=%.0f m mitte=%s boden=%s erneut=%s" % [_map(), pts.size(),
		Vector2(box.size.x, box.size.z).length(), sup.center, sup._find_ground(sup.center, false), sup._detect_open()])
	if not sup.map_open:
		var c := sup.center
		var down := sup._ray(c + Vector3.UP * 150.0, c + Vector3.DOWN * 300.0)
		lines.append("DIAG down=%s" % _hit_s(down))
		if not down.is_empty():
			var g: Vector3 = down["position"]
			lines.append("DIAG up=%s" % _hit_s(sup._ray(g + Vector3.UP * 0.6, g + Vector3.UP * SupportStrike.SKY_CLEAR)))
		var g2 := sup._ray(c + Vector3.UP * 3.0, c + Vector3.DOWN * 20.0)
		lines.append("DIAG nah=%s" % _hit_s(g2))
		if not g2.is_empty():
			var gg: Vector3 = g2["position"]
			lines.append("DIAG nah_up=%s" % _hit_s(sup._ray(gg + Vector3.UP * 0.6, gg + Vector3.UP * SupportStrike.SKY_CLEAR)))
		print("\n".join(lines.slice(-4)))
	var cands: Array = sup.spawn_candidates.duplicate()
	if cands.is_empty():
		cands = [sup.center]
	for i in cands.size():
		sup.spawn_candidates = [cands[i]]
		sup._set_radio(0, 0, Vector3.INF, 0)
		await get_tree().process_frame
		sup.server_spawn()
		await get_tree().create_timer(0.3).timeout
		lines.append("STELLE %d orig=%s radio=%s" % [i, cands[i], sup.radio_pos])
		print(lines[-1])
		check(sup.radio_state == 1, "Stelle %d: Funkgerät gespawnt" % i)
		if sup.radio_state == 1:
			check(_radio_visible(sup), "Stelle %d: Modell sichtbar am Boden" % i, _radio_vis_detail(sup))
			check(_reachable(m, sup.radio_pos), "Stelle %d: zu Fuß erreichbar" % i, _reach_detail(m, sup.radio_pos))
			var cv: Vector3 = cands[i]
			check(Vector2(sup.radio_pos.x - cv.x, sup.radio_pos.z - cv.z).length() < 70.0, "Stelle %d: an der Funkstelle bzw. Kartenmitte" % i)
	sup.spawn_candidates = cands


static func _hit_s(h: Dictionary) -> String:
	if h.is_empty():
		return "-"
	var c = h.get("collider")
	return "%s n=%s %s" % [h["position"], h["normal"], (c as Node).get_path() if c is Node else str(c)]


static func _action(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = a
	up.pressed = false
	Input.parse_input_event(up)


static func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


static func _click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)


## Blick so drehen, dass der Kamerastrahl (Fadenkreuz) auf p zeigt
func _aim_at(me: Soldier, p: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var from: Vector3 = cam.global_position if cam else me.global_position + Vector3.UP * 1.6
	var d := p - from
	var h := Vector2(d.x, d.z).length()
	me.look_yaw = atan2(-d.x, -d.z)
	# 3.-Person-Kamera sitzt versetzt zum Drehpunkt: tatsächliche Kamerablickrichtung nachführen (sonst trifft der
	# Fadenkreuzstrahl bei flachem Blick den Boden vor dem Ziel – je nach Standort reproduzierbar ~9 m zu kurz)
	var corr := float(me.get_meta("_aim_corr", 0.0))
	if cam:
		var f := -cam.global_basis.z
		var cam_pitch := atan2(f.y, Vector2(f.x, f.z).length())
		var want := atan2(d.y, maxf(h, 0.1))
		corr = clampf(corr + (want - cam_pitch) * 0.5, -0.5, 0.5)
		me.set_meta("_aim_corr", corr)
	me.look_pitch = atan2(d.y, maxf(h, 0.1)) + corr


static func _radio_aabb(sup: SupportStrike) -> AABB:
	var box := AABB()
	var first := true
	if not is_instance_valid(sup._radio_node):
		return box
	for n in sup._radio_node.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var b := vi.global_transform * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Modell im Baum, sichtbar, Unterkante nahe am Boden (nicht im Boden/Himmel), Größe wie ein Funkgerät
func _radio_visible(sup: SupportStrike) -> bool:
	var n = sup._radio_node
	if not is_instance_valid(n) or not n.is_inside_tree() or not n.is_visible_in_tree():
		return false
	var b := _radio_aabb(sup)
	var g: Vector3 = sup.radio_pos
	return b.size.y > 0.08 and b.size.y < 2.0 and b.position.y > g.y - 0.25 and b.position.y < g.y + 0.4 \
		and Vector2(b.get_center().x - g.x, b.get_center().z - g.z).length() < 0.8


func _radio_vis_detail(sup: SupportStrike) -> String:
	return "aabb=%s boden=%s" % [_radio_aabb(sup), sup.radio_pos]


func _nav_end(m: Mission, p: Vector3) -> Vector3:
	var map := m.get_world_3d().navigation_map
	var sp: Array = m.mp_spawns() if m.has_method("mp_spawns") else []
	var from: Vector3 = sp[0]["pos"] if not sp.is_empty() else p
	var path := AIBrain.nav_path(map, NavigationServer3D.map_get_closest_point(map, from), p)
	return path[path.size() - 1] if path.size() > 0 else Vector3.INF


func _reachable(m: Mission, p: Vector3) -> bool:
	var map := m.get_world_3d().navigation_map
	var q := NavigationServer3D.map_get_closest_point(map, p)
	if q.distance_to(p) > 1.5:
		return false
	var e := _nav_end(m, p)
	return e.is_finite() and e.distance_to(p) < 2.0


func _reach_detail(m: Mission, p: Vector3) -> String:
	var map := m.get_world_3d().navigation_map
	return "netz=%s pfadende=%s" % [NavigationServer3D.map_get_closest_point(map, p), _nav_end(m, p)]


func _freeze_bots() -> void:
	for id in Net._soldiers:
		var b: Soldier = Net._soldiers[id]
		if int(id) < 0 and is_instance_valid(b):
			var br := b.get_node_or_null("EnemyBrain")
			if br:
				br.process_mode = Node.PROCESS_MODE_DISABLED
			b.move_input = Vector3.ZERO
			b.trigger = false


# --- Host ----------------------------------------------------------------------------------------------

func _host() -> void:
	for p in [STEP_HOST, STEP_CLIENT, RESULT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	# Regeln/Konfiguration
	var d := Net.style_defaults(Net.Mode.TEAM_DEATHMATCH)
	check(int(d["support_strike"]) == 0 and int(d["support_interval_min"]) == 5 and not bool(d["support_bots"]),
		"Regeln: Unterstützung Standard aus, 5 min, KI aus")
	check(Net.RULE_KEYS.get("support_strike") == "supportstrike" and Net.RULE_KEYS.get("support_interval_min") == "supportinterval"
		and Net.RULE_KEYS.get("support_bots") == "supportbots", "Konsolen-/Konfigurationsschlüssel supportstrike/supportinterval/supportbots")
	var ct := LanMenu.config_text({"name": "x", "map": _map(), "support_strike": 3, "support_interval_min": 7, "support_bots": true})
	check(ct.contains("supportstrike 3") and ct.contains("supportinterval 7") and ct.contains("supportbots 1"),
		"Konfigurationsdatei des dedizierten Servers")
	check(SupportStrike.radio_model(SupportStrike.KIND_ART).get_meta("radio_model", "") != "", "Original-Funkgerätmodell (d_radio*) vorhanden")
	Net.local_name = "Host"
	Net.local_team = Soldier.TEAM_ALLIED
	var ok := Net.host({"name": "Funk", "map": _map(), "mode": int(Game.MISSIONS.get(_map(), {}).get("mp_mode", Net.Mode.TEAM_DEATHMATCH)),
		"port": Net.PORT + PORT_OFS, "max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 3,
		"bots_per_team": 1, "password": "", "allow_vehicles": false, "friendly_fire": false, "allow_respawn": true,
		"support_strike": 3, "support_interval_min": 1, "support_interval_s": 4.0, "support_bots": false, "flood_protect": false})
	check(ok and Net.is_online, "Server gestartet", Net.last_error)
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() and Net._soldiers.has(1), 400.0)
	var m: Mission = Game.current_mission()
	await wait_for(func(): return m.nav_ready, 240.0)
	m.controller.input_enabled = false
	var sup: SupportStrike = Net.support
	check(is_instance_valid(sup) and sup.map_open, "Unterstützung aktiv, Karte als offen erkannt", "%s open=%s" % [_map(), sup.map_open if sup else false])
	var info: Dictionary = Net.server_info()["rules"]
	check(int(info.get("support_strike", -1)) == 3 and int(info.get("support_interval_min", 0)) == 1, "SPIEL-INFO: Regeln in der Serverabfrage")
	check(FileAccess.get_file_as_string("res://src/ui/game_info_screen.gd").contains("Funk-Unterstützung"), "SPIEL-INFO zeigt Funk-Unterstützung")
	var orig_hidden := true
	for n in get_tree().get_nodes_in_group("world_items"):
		if int(n.get("item")) in SupportStrike.ITEM and n.visible:
			orig_hidden = false
	check(orig_hidden, "Frei liegende Original-Funkgeräte im Netz durch das Server-Funkgerät ersetzt")
	# Client
	var exe := OS.get_executable_path()
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/support_strike_client.log")]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	check(OS.create_process(exe, args + ["--", "--autoplay=test_support_strike", "--ss_peer=1"]) > 0, "Client-Prozess gestartet")
	await wait_for(func(): return _client_peer() != 0, 420.0)
	var cid := _client_peer()
	check(cid != 0, "Client beigetreten")
	if cid == 0:
		return
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("loaded"), 300.0)
	_freeze_bots()
	# Funkgerät erscheint (Test-Intervall 4 s)
	await wait_for(func(): return sup.radio_state == 1, 60.0)
	check(sup.radio_state == 1 and sup.radio_pos.is_finite() and sup.sky_open(sup.radio_pos), "Funkgerät erscheint auf begehbarem Boden unter freiem Himmel",
		str(sup.radio_pos))
	check(sup.radio_pos.distance_to(sup.center) < 400.0 or not sup.spawn_candidates.is_empty(), "Funkgerät ungefähr in der Kartenmitte bzw. an Original-Funkstelle")
	var first_kind := sup.radio_kind
	var base := sup.radio_pos
	var target := base + Vector3(6, 0, 0)
	var g := sup._find_ground(target)
	target = g if g.is_finite() else base
	var me: Soldier = Net._soldiers[1]
	me.global_position = target + Vector3.UP * 0.2
	me.set_meta("protect_until", 0)
	var puppet: Soldier = Net._soldiers[cid]
	# Ablehnung ohne Funkgerät
	check(sup.server_call(cid, first_kind, target) != "", "Anforderung ohne Funkgerät abgelehnt")
	_write(STEP_HOST, JSON.stringify({"step": "radio", "pos": [base.x, base.y, base.z], "kind": first_kind, "target": [target.x, target.y, target.z]}))
	await wait_for(func(): return sup.radio_state == 2 and sup.carrier == cid, 60.0)
	check(sup.radio_state == 2 and sup.carrier == cid, "Server: Client hat das Funkgerät aufgenommen")
	puppet.set_meta("protect_until", 0)
	var kf0 := Net.kill_feed.size()
	await wait_for(func(): return not sup.strikes.is_empty() or sup.ev_log.any(func(e): return String(e["ev"]) == "call"), 60.0)
	var call_ms := Time.get_ticks_msec()
	check(not sup.strikes.is_empty(), "Server: Schlag angefordert (Funkgerät verbraucht)", str(sup.radio_state))
	check(sup.radio_state == 0, "Funkgerät nach dem Schlag weg (genau ein Schlag)")
	if not sup.strikes.is_empty():
		var sp: Vector3 = sup.strikes[0]["pos"]
		check(Vector2(sp.x - target.x, sp.z - target.z).length() < 6.0, "Client hat per Fadenkreuz ungefähr das Ziel anvisiert", "%s ↔ %s" % [sp, target])
		me.global_position = sp + Vector3.UP * 0.2      # Host steht im tatsächlichen Wirkungsbereich
		me.velocity = Vector3.ZERO
	check(sup.markers_shown >= 1, "Host: 3D-Kreis am Ziel sichtbar")
	await wait_for(func(): return sup.ev_log.any(func(e): return String(e["ev"]) == "wave"), 15.0)
	var c_ms := 0
	var w_ms := 0
	for ev in sup.ev_log:
		if String(ev["ev"]) == "call" and c_ms == 0:
			c_ms = int(ev["ms"])
		if String(ev["ev"]) == "wave" and w_ms == 0:
			w_ms = int(ev["ms"])
	var dt: int = w_ms - c_ms if c_ms > 0 and w_ms > 0 else Time.get_ticks_msec() - call_ms
	check(dt >= 4200 and dt <= 6500, "Einschlag nach ca. 5 s", "%d ms" % dt)
	await wait_for(func(): return not me.alive, 5.0)
	check(not me.alive, "Host im Wirkungsbereich getötet")
	await get_tree().create_timer(0.5).timeout
	var e: Dictionary = Net.kill_feed.back() if Net.kill_feed.size() > 0 else {}
	check(Net.kill_feed.size() > kf0 and int(e.get("killer", 0)) == cid and String(e.get("cause", "")) == SupportStrike.CAUSE[first_kind],
		"Kill-Feed: Funker als Schütze, Ursache %s" % SupportStrike.CAUSE[first_kind], str(e))
	check(FB.weapon_label(String(e.get("cause", ""))) != "" and FB.weapon_icon(String(e.get("cause", "")), 0) != null,
		"Kill-Feed: Bezeichnung und Funkgerätsymbol", FB.weapon_label(String(e.get("cause", ""))))
	check(sup.booms >= 3, "Host: Explosionen dargestellt", str(sup.booms))
	if first_kind == SupportStrike.KIND_AIR:
		check(sup.planes_shown >= 1, "Luftangriff: Flugzeug-Überflug")
	_write(STEP_HOST, JSON.stringify({"step": "struck", "kind": first_kind}))
	# Zweites Funkgerät (andere Art), Host nimmt es selbst und trifft den Client
	await wait_for(func(): return Net._soldiers.has(1) and is_instance_valid(Net._soldiers[1]) and Net._soldiers[1].alive, 30.0)
	await wait_for(func(): return sup.radio_state == 1, 30.0)
	check(sup.radio_state == 1 and sup.radio_kind != first_kind, "Zweites Funkgerät mit der anderen Art (abwechselnd)", str(sup.radio_kind))
	me = Net._soldiers[1]
	check(_radio_visible(sup), "Host: Funkgerät-Modell sichtbar am Boden", _radio_vis_detail(sup))
	check(_reachable(m, sup.radio_pos), "Host: Funkgerät zu Fuß erreichbar", _reach_detail(m, sup.radio_pos))
	var hs: Vector3 = sup._find_ground(sup.radio_pos + Vector3(0, 0, 1.2))
	me.global_position = (hs if hs.is_finite() and absf(hs.y - sup.radio_pos.y) < 0.6 else sup.radio_pos) + Vector3.UP * 0.2
	me.velocity = Vector3.ZERO
	me.look_yaw = 0.0                                # Blick nach Norden (−Z) = zum Funkgerät
	m.controller.input_enabled = true
	await wait_for(func(): return m.controller.interact_target == sup._radio_node, 5.0)
	check(m.controller.interact_target == sup._radio_node, "Host: Benutzen-Ziel ist das Funkgerät", str(m.controller.interact_target))
	_action("interact")
	await wait_for(func(): return sup.carrying(), 5.0)
	check(sup.carrying(), "Host nimmt das Funkgerät per Benutzen-Taste auf", "alive=%s d=%.1f state=%d" % [me.alive, me.global_position.distance_to(sup.radio_pos), sup.radio_state])
	_action("command_all")
	await get_tree().process_frame
	check(sup.menu_open, "Host: Ziffernblock 0 öffnet das Untermenü")
	m.controller.input_enabled = false
	var ml := sup.menu_lines()
	check(not ml[sup.radio_kind + 1].contains("(–)") and ml[2 - sup.radio_kind].contains("(–)"),
		"Untermenü wie Original: nur passende Art wählbar (T7280/T7281)", " | ".join(ml))
	check(not sup.choose(1 - sup.radio_kind) and sup.targeting == -1, "Falsche Art nicht wählbar")
	sup.open_menu()
	var k2 := sup.radio_kind
	check(sup.choose(k2) and sup.targeting == k2, "Zielwahl gestartet")
	puppet = Net._soldiers[cid]
	puppet.set_meta("protect_until", 0)
	var cpos := puppet.global_position
	var aw: Vector3 = sup._find_ground(base + Vector3(-45, 0, 0))
	if not cpos.is_finite() or not sup.sky_open(cpos):
		cpos = aw if aw.is_finite() else base + Vector3(-45, 0, 0)
	me.global_position = cpos + Vector3(40, 0, 0) if sup._find_ground(cpos + Vector3(40, 0, 0)).is_finite() else me.global_position
	_write(STEP_HOST, JSON.stringify({"step": "second", "kind": k2}))
	sup.confirm_target(cpos)
	check(not sup.strikes.is_empty(), "Host: zweiter Schlag angefordert", "%s cpos=%s sky=%s" % [str(sup.ev_log.slice(-3)), cpos, sup.sky_open(cpos)])
	await wait_for(func(): return not puppet.alive or not is_instance_valid(puppet), 12.0)
	await get_tree().create_timer(0.5).timeout
	e = Net.kill_feed.back() if Net.kill_feed.size() > 0 else {}
	check(String(e.get("cause", "")) == SupportStrike.CAUSE[k2] and int(e.get("killer", 0)) == 1,
		"Zweiter Schlag: Client getötet, Ursache %s" % SupportStrike.CAUSE[k2], str(e))
	check(SupportStrike.RADIUS[SupportStrike.KIND_ART] == 10.0 and SupportStrike.RADIUS[SupportStrike.KIND_AIR] == 12.5
		and SupportStrike.WAVE_STRENGTH[SupportStrike.KIND_ART] * SupportStrike.WAVES[SupportStrike.KIND_ART]
			> SupportStrike.WAVE_STRENGTH[SupportStrike.KIND_AIR] * SupportStrike.WAVES[SupportStrike.KIND_AIR],
		"Artillerie 20 m stark, Luftangriff 25 m schwächer")
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("second_done"), 60.0)
	# Bots (supportbots)
	var log0 := sup.ev_log.size()
	Net.server_command("supportbots 1", 0)
	await wait_for(func(): return sup.radio_state == 1, 30.0)
	var bot: Soldier = null
	for id in Net._soldiers:
		if int(id) < 0 and is_instance_valid(Net._soldiers[id]) and Net._soldiers[id].alive:
			bot = Net._soldiers[id]
	if bot:
		var bb = bot.get_node_or_null("EnemyBrain")
		check(bb == null or sup.bot_goal(bb).is_finite() or not bb.is_leader(), "KI-Führer läuft zum Funkgerät (bot_goal)")
		# Aufnahme durch einen Bot laut Ereignisprotokoll: ein KI-Funker mit Ziel ruft sofort an (Zustand 2 dann nur
		# Bruchteile einer Sekunde – die Abfrage alle 0,2 s verpasst ihn sonst)
		var bot_took := func() -> bool:
			for i in range(log0, sup.ev_log.size()):
				var ev: Dictionary = sup.ev_log[i]
				if String(ev.get("ev", "")) == "pickup" and int(ev.get("carrier", 0)) < 0:
					return true
			return sup.radio_state == 2 and sup.carrier < 0
		# Bot bis zur Aufnahme auf dem Funkgerät halten (seine KI läuft sonst ggf. sofort weiter)
		await wait_for(func():
			if is_instance_valid(bot) and bot.alive and sup.radio_state == 1:
				bot.global_position = sup.radio_pos + Vector3.UP * 0.2
				bot.velocity = Vector3.ZERO
			return bot_took.call(), 8.0)
		check(bot_took.call(), "KI nimmt das Funkgerät auf (supportbots)",
			"state=%d carrier=%d bot_alive=%s d=%.2f log=%s" % [sup.radio_state, sup.carrier,
			str(is_instance_valid(bot) and bot.alive),
			bot.global_position.distance_to(sup.radio_pos) if is_instance_valid(bot) else -1.0, str(sup.ev_log.slice(-4))])
	# Abschalten per Konsole
	var r := Net.server_command("supportstrike 0", 0)
	await get_tree().create_timer(0.5).timeout
	check(r.contains("supportstrike") and sup.radio_state == 0 and not sup.enabled(), "Konsole „supportstrike 0“ schaltet ab", r)
	_write(STEP_HOST, JSON.stringify({"step": "done"}))
	await wait_for(func(): return FileAccess.file_exists(RESULT), 120.0)
	for l in _read(RESULT).split("\n"):
		if l.begins_with("PASS") or l.begins_with("FAIL"):
			check(l.begins_with("PASS"), "Client: " + l.substr(6))


# --- Client --------------------------------------------------------------------------------------------

func _client() -> void:
	Net.local_name = "Gast"
	Net.local_team = Soldier.TEAM_AXIS
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1", Net.PORT + PORT_OFS, "")
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() \
		and Net._soldiers.has(Net.my_id()) and is_instance_valid(Net.support), 420.0)
	var m: Mission = Game.current_mission()
	var sup: SupportStrike = Net.support
	await wait_for(func(): return sup.map_open, 10.0)
	check(is_instance_valid(sup) and sup.map_open, "Client: Unterstützung vorhanden, Karte offen")
	m.controller.input_enabled = false
	_write(STEP_CLIENT, "loaded")
	await wait_for(func(): return _read(STEP_HOST).contains("\"radio\""), 200.0)
	var st = JSON.parse_string(_read(STEP_HOST))
	await wait_for(func(): return sup.radio_state == 1, 20.0)
	check(sup.radio_state == 1 and is_instance_valid(sup._radio_node) and sup._radio_node.is_inside_tree(), "Client: Funkgerät sichtbar")
	check(_radio_visible(sup), "Client: Funkgerät-Modell sichtbar am Boden (nicht im Boden/Himmel)", _radio_vis_detail(sup))
	await wait_for(func(): return m.nav_ready, 240.0)     # Kachelnetz/Links des Clients erst nach nav_ready vollständig
	check(_reachable(m, sup.radio_pos), "Client: Funkgerät zu Fuß erreichbar (Navigationsnetz)", _reach_detail(m, sup.radio_pos))
	var me: Soldier = Net._soldiers[Net.my_id()]
	# Echter Spielerweg: 1,2 m vor dem Funkgerät stehen, hinschauen, Benutzen-Taste
	var to_r := Vector3(1.2, 0, 0)
	var stand: Vector3 = sup._find_ground(sup.radio_pos - to_r)
	me.global_position = (stand if stand.is_finite() and absf(stand.y - sup.radio_pos.y) < 0.6 else sup.radio_pos) + Vector3.UP * 0.2
	me.velocity = Vector3.ZERO
	me.look_yaw = atan2(-to_r.x, -to_r.z)          # forward = (−sin yaw, 0, −cos yaw) → zum Funkgerät
	m.controller.input_enabled = true
	await get_tree().create_timer(1.0).timeout      # eigene Lage beim Server
	await wait_for(func(): return m.controller.interact_target == sup._radio_node, 5.0)
	check(m.controller.interact_target == sup._radio_node, "Client: Benutzen-Ziel ist das Funkgerät (PlayerController.interact_target)",
		str(m.controller.interact_target))
	_action("interact")
	await wait_for(func(): return sup.carrying(), 10.0)
	check(sup.carrying(), "Client: Funkgerät per Benutzen-Taste aufgenommen (vom Server bestätigt)")
	var k := int(st["kind"])
	var tp: Array = st["target"]
	var bp: Array = st["pos"]
	# Standort außerhalb des Wirkungsbereichs mit freier Sicht (Kamera hinter der Figur) auf das Ziel
	var tgt0 := Vector3(tp[0], tp[1], tp[2])
	# Alle Standorte mit freier Sicht sammeln; die tatsächliche Kamera (3. Person) entscheidet unten, welcher taugt
	var aways: Array = []
	for dist in [20.0, 25.0, 30.0]:
		for dv in [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-0.7, 0, -0.7), Vector3(0.7, 0, 0.7)]:
			var g: Vector3 = sup._find_ground(tgt0 + dv * float(dist), false)
			if not g.is_finite() or Vector2(g.x - tgt0.x, g.z - tgt0.z).length() < 18.0:
				continue
			var back: Vector3 = g - (tgt0 - g).normalized() * 3.0 + Vector3.UP * 2.2
			if sup._ray(g + Vector3.UP * 1.7, tgt0 + Vector3.UP * 0.3).is_empty() and sup._ray(back, tgt0 + Vector3.UP * 0.3).is_empty():
				aways.append(g)
	if aways.is_empty():
		var fb: Vector3 = sup._find_ground(Vector3(bp[0], bp[1], bp[2]) + Vector3(-30, 0, 0), false)
		aways.append(fb if fb.is_finite() else Vector3(bp[0], bp[1] + 2.0, bp[2]) + Vector3(-30, 0, 0))
	me.global_position = (aways[0] as Vector3) + Vector3.UP * 0.2
	me.velocity = Vector3.ZERO
	await get_tree().create_timer(1.0).timeout
	_action("command_all")
	await get_tree().process_frame
	check(sup.menu_open, "Client: Ziffernblock 0 öffnet „Unterst. anf.“")
	_key(KEY_KP_1 + k)
	await get_tree().process_frame
	check(not sup.menu_open and sup.targeting == k, "Client: Ziffer %d wählt %s" % [k + 1, SupportStrike.NAME[k]])
	# Blick auf das Ziel richten (Fadenkreuz), Vorschaukreis abwarten, Linksklick
	var tgt := Vector3(tp[0], tp[1], tp[2])
	for ai in aways.size():
		if ai > 0:                                   # Kamera sah das Ziel nicht (Geländekante) → nächster Standort
			me.global_position = (aways[ai] as Vector3) + Vector3.UP * 0.2
			me.velocity = Vector3.ZERO
			me.set_meta("_aim_corr", 0.0)
		if await wait_for(func():
				_aim_at(me, tgt)
				return sup.target_preview.is_finite() and Vector2(sup.target_preview.x - tgt.x, sup.target_preview.z - tgt.z).length() < 6.0, 6.0):
			break
	_aim_at(me, tgt)
	await get_tree().process_frame
	check(sup.target_preview.is_finite() and is_instance_valid(sup._preview)
		and Vector2(sup.target_preview.x - tgt.x, sup.target_preview.z - tgt.z).length() < 6.0,
		"Client: Zielvorschau unter dem Fadenkreuz", "%s ↔ %s" % [sup.target_preview, tgt])
	_click()
	await get_tree().process_frame
	check(sup.targeting == -1, "Client: Linksklick bestätigt das Ziel")
	await wait_for(func(): return sup.markers_shown >= 1, 10.0)
	check(sup.markers_shown >= 1 and sup.radio_state == 0, "Client: 3D-Kreis empfangen, Funkgerät verbraucht")
	await wait_for(func(): return sup.booms >= 3, 12.0)
	check(sup.booms >= 3, "Client: Einschläge empfangen")
	if k == SupportStrike.KIND_AIR:
		check(sup.planes_shown >= 1, "Client: Flugzeug-Überflug")
	await wait_for(func(): return Net.kill_feed.any(func(e): return String(e["cause"]) == SupportStrike.CAUSE[k]), 10.0)
	check(Net.kill_feed.any(func(e): return String(e["cause"]) == SupportStrike.CAUSE[k] and int(e["killer"]) == Net.my_id()),
		"Client: Kill-Feed mit Ursache %s" % SupportStrike.CAUSE[k])
	await wait_for(func(): return _read(STEP_HOST).contains("\"second\""), 60.0)
	await wait_for(func(): return sup.markers_shown >= 2, 10.0)
	check(sup.markers_shown >= 2, "Client: zweiter Zielkreis sichtbar")
	await wait_for(func(): return Net.kill_feed.any(func(e): return int(e["killer"]) == 1 and String(e["cause"]).begins_with("support_")), 15.0)
	check(Net.kill_feed.any(func(e): return int(e["killer"]) == 1 and String(e["cause"]).begins_with("support_")), "Client: eigener Tod im Kill-Feed (Unterstützung)")
	_write(STEP_CLIENT, "second_done")
	await wait_for(func(): return _read(STEP_HOST).contains("\"done\""), 120.0)
	_write(RESULT, "\n".join(lines))


func _finish() -> void:
	if peer_mode:
		if not FileAccess.file_exists(RESULT):
			_write(RESULT, "\n".join(lines))
		Net.leave(false)
		get_tree().quit(0)
		return
	print("ERGEBNIS: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	_write(ProjectSettings.globalize_path("res://test_output/test_support_strike.txt"), "\n".join(lines) + "\nERGEBNIS: %d/%d\n" % [passed, passed + failed])
	Net.leave(false)
	get_tree().quit(1 if failed > 0 else 0)
