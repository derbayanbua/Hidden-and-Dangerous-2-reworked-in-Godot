extends "res://tests/test_weapons_aim.gd"
## 0.11.9 Scharfschütze im Mehrspieler (Status test_output/b0119_mp_sniper.md): zwei ENet-Prozesse, Beitritt per IP:Port
## (nicht LAN-Suche), Team-Deathmatch, 1 KI je Team. Klasse Scharfschütze (Net.local_class = 1, Kaderwerte der Klasse,
## Streuung + Original-Rückstoß wie im Spiel, nur das Atemwackeln wird wie beim Anhalten des Atems festgehalten).
## Ziel = KI-Figur auf dem Schießstand 20/50/100/150 m, Schütze stehend/hockend/liegend, Zielfernrohr (RMT), Absehen auf
## die Rumpfmitte; danach bewegtes Ziel (2,5 m/s quer) auf 50/100 m mit Vorhalt um die Flugzeit.
## Gezählt: lokaler Treffer (Geschoss des Schützen trifft beim Schützen die Zielfigur) und serverbestätigter Treffer
## (Net.hit_confirmed beim Client bzw. Events.soldier_damaged beim Host). Verworfene Schüsse: Net.rejects.
##   tools\godot.cmd --headless -- --autoplay=test_mp_sniper [--ms_dedicated=1] [--net_lag_ms=120 --net_jitter_ms=30]
##                                 [--lagcomp=0] [--ms_shots=4]       (Client: --ms_peer=1, startet der Test)

const MP := preload("res://tests/test_weapons_aim_mp.gd")
const PORT_OFS := 57
const STEP_HOST := "user://ms_step_host.json"
const STEP_CLIENT := "user://ms_step_client.json"
const MS_DISTS := [20.0, 50.0, 100.0, 150.0]
const MOVING := [50.0, 100.0]
const MOVE_SPEED := 2.5
const HOST_GUN := "o_17"        ## Alliierte: Lee-Enfield ZF (Host)
const CLIENT_GUN := "o_13"      ## Achse: K98k ZF (Client)
## Mindesttrefferquote serverbestätigt (Rumpf angezielt; Rest = Streuung/Rückstoß der Klasse)
const MIN_RATE_STATIC := 0.6
const MIN_RATE_MOVING := 0.5

var mp_helper
var _ms_target: Soldier
var _ms_move := false
var _ms_x := 0.0
var _ms_dir := 1.0
var _ms_at := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mp_mode = true
	get_tree().create_timer(float(Game.cli.get("test_timeout", "1700")), true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_write_ms_report()
		_finish())
	_run.call_deferred()


func _run() -> void:
	mp_helper = MP.new()
	mp_helper.t = self
	await get_tree().process_frame
	if Game.cli.has("ms_peer"):
		await _client()
		get_tree().quit()
		return
	await _host()
	_write_ms_report()
	_finish()


func _write_ms_report() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_output/mp_sniper%s.txt" % _tag()), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n")


func _tag() -> String:
	var t := ""
	if String(Game.cli.get("ms_dedicated", "0")) == "1":
		t += "_ded"
	if int(Game.cli.get("net_lag_ms", "0")) > 0:
		t += "_lag%d" % int(Game.cli.get("net_lag_ms", "0"))
	if String(Game.cli.get("lagcomp", "1")) == "0":
		t += "_nocomp"
	return t


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


static func build_range(mm: Node, base: Vector3) -> void:
	var plat := StaticBody3D.new()
	plat.name = "MsRange"
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40, 1, 200)
	cs.shape = bx
	plat.add_child(cs)
	mm.add_child(plat)
	plat.global_position = base + Vector3(0, -0.5, -90)


## Bedingungen: [Entfernung, Haltung, bewegt]
static func conditions() -> Array:
	var out := []
	for d in MS_DISTS:
		for st in [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]:
			out.append([d, int(st), false])
	for d in MOVING:
		out.append([d, int(Soldier.Stance.STAND), true])
	return out


static func cond_label(c: Array) -> String:
	return "%3d m %s%s" % [int(c[0]), ["stehend", "hockend", "liegend"][int(c[1])], " bewegt" if bool(c[2]) else ""]


## Zielfigur festhalten bzw. quer bewegen (Server, 20-Hz-Takt)
func _drive_target(dt: float) -> void:
	if not is_instance_valid(_ms_target):
		return
	_ms_target.max_health = 100000.0
	_ms_target.health = 100000.0
	_ms_target.set_meta("protect_until", 0)
	_ms_target.aiming = false
	_ms_target.trigger = false
	_ms_target.move_input = Vector3.ZERO
	_ms_target.look_yaw = 0.0
	if _ms_move:
		_ms_x += _ms_dir * MOVE_SPEED * dt
		if absf(_ms_x) > 6.0:
			_ms_dir = -_ms_dir
			_ms_x = clampf(_ms_x, -6.0, 6.0)
		_ms_target.global_position = _ms_at + Vector3(_ms_x, 0, 0)
		_ms_target.velocity = Vector3(_ms_dir * MOVE_SPEED, 0, 0)
	else:
		_ms_target.global_position = _ms_at
		_ms_target.velocity = Vector3.ZERO


## Schütze: Stellung/Haltung, Zielfernrohr, n Schüsse auf die Rumpfmitte; on_shot(i) wartet auf die Bestätigung.
## Liefert [lokale Treffer, Zonen-Liste lokal]
func _shoot_series(mm: Mission, me: Soldier, victim: Soldier, stance: int, moving: bool, n: int, keep: Callable,
		on_shot: Callable) -> Array:
	var rig = mm.rig
	me.stance_request = stance
	for i in 120:
		keep.call()
		await frames(1)
		if me.stance == stance:
			break
	Input.action_press("aim")
	for i in 240:
		keep.call()
		await frames(1)
		if rig.zoomed() and float(rig.get("_zoom_t")) >= 1.0:
			break
	rig.breath_force = 1
	var w := me.current_weapon()
	var local_hits := 0
	var zones: Array[String] = []
	for k in n:
		rig.breath = 1.0
		rig.breath_winded = false
		for i in 200:
			keep.call()
			await frames(1)
			if w.cooldown <= 0.0 and not w.is_reloading() and rig.zoomed():
				break
		w.in_mag = w.data.magazine_size
		var hb := MP.zone_box(victim, &"torso")
		if hb == null:
			zones.append("-")
			continue
		var c := (hb.get_child(0) as Node3D).global_position
		await mp_helper.aim_at(rig, me, c, keep)
		if moving:
			# mitschwenken: je Bild auf die gesehene Rumpfmitte + Vorhalt um die Flugzeit (gesehene Geschwindigkeit)
			var p0 := victim.global_position
			var t0 := Time.get_ticks_usec()
			await seconds(0.2)
			var seen_v := (victim.global_position - p0) / maxf(float(Time.get_ticks_usec() - t0) / 1e6, 0.01)
			seen_v.y = 0.0
			for i in 12:
				var cam: Camera3D = rig.camera
				var p := (hb.get_child(0) as Node3D).global_position
				var fl := p.distance_to(cam.global_position) / maxf(w.data.muzzle_velocity, 1.0)
				var dv := p + seen_v * (fl + 1.0 / 60.0) - cam.global_position
				var fwd := -cam.global_basis.z
				me.look_yaw += wrapf(atan2(-dv.x, -dv.z) - atan2(-fwd.x, -fwd.z), -PI, PI)
				me.look_pitch = clampf(me.look_pitch + atan2(dv.y, Vector2(dv.x, dv.z).length()) - asin(clampf(fwd.y, -1.0, 1.0)), -1.2, 1.2)
				keep.call()
				await frames(1)
		var got := [""]
		var icb := func(_pos: Vector3, col: Object, sh: Node):
			if sh == me and got[0] == "":
				got[0] = String((col as Hitbox).zone) if col is Hitbox and (col as Hitbox).soldier == victim else "x"
		Ballistics.projectile_impact.connect(icb)
		await tap("fire")
		await on_shot.call(k)
		for i in 30:
			if got[0] != "":
				break
			await frames(1)
		Ballistics.projectile_impact.disconnect(icb)
		if got[0] != "" and got[0] != "x":
			local_hits += 1
		zones.append(got[0] if got[0] != "" else "-")
	Input.action_release("aim")
	rig.breath_force = -1
	return [local_hits, zones]


# --- Server ------------------------------------------------------------------------------------------------------

func _host() -> void:
	for p in [STEP_HOST, STEP_CLIENT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var ded := String(Game.cli.get("ms_dedicated", "0")) == "1"
	var lag := int(Game.cli.get("net_lag_ms", "0"))
	var shots := int(Game.cli.get("ms_shots", "4"))
	Net.local_name = "Host"
	Net.local_team = Soldier.TEAM_ALLIED
	Net.local_class = 1
	Net.local_figure = ""
	Net.move_check = false          # Testfiguren werden direkt auf den Schießstand gesetzt
	var map: String = load("res://tests/test_mp_feedback.gd")._map()
	var ok := Net.host({"name": "Sniper", "map": map, "mode": Net.Mode.TEAM_DEATHMATCH, "port": Net.PORT + PORT_OFS,
		"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 1,
		"password": "", "allow_vehicles": false, "kill_cam": false, "friendly_fire": false, "hit_indicator": true,
		"dedicated": ded})
	check(ok and Net.is_online, "MP: Server gestartet (%s, %s)" % [map, "dediziert" if ded else "Host spielt mit"], Net.last_error)
	report.append("Lauf %s: Karte %s, Verzug %d ms (Jitter %s ms), Ausgleich %s" % [_tag(), map, lag,
		String(Game.cli.get("net_jitter_ms", "0")), "aus" if String(Game.cli.get("lagcomp", "1")) == "0" else "an"])
	await mp_helper.wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() \
		and (ded or Net._soldiers.has(1)), 400.0)
	var mm: Mission = Game.current_mission()
	await mp_helper.wait_for(func(): return mm.nav_ready and mp_helper._bots().size() == 2, 300.0)
	var bots: Dictionary = mp_helper._bots()
	check(bots.size() == 2, "MP: zwei KI-Soldaten")
	if bots.size() < 2:
		return
	for b in bots.values():
		var br = (b as Soldier).get_node_or_null("EnemyBrain")
		if br:
			br.process_mode = Node.PROCESS_MODE_DISABLED
	var axis_bot: Soldier = bots[Soldier.TEAM_AXIS]
	var allied_bot: Soldier = bots[Soldier.TEAM_ALLIED]
	var base: Vector3 = ((Net._soldiers[1] as Soldier).global_position if not ded else axis_bot.global_position) + Vector3(0, 80, 0)
	build_range(mm, base)
	var me: Soldier = Net._soldiers.get(1) if not ded else null
	var shooter_at := [base + Vector3(-4, 0.1, 0)]
	var keep_all := func():
		for b in [axis_bot, allied_bot]:
			if is_instance_valid(b) and b != _ms_target:
				b.max_health = 100000.0
				b.health = 100000.0
				b.set_meta("protect_until", 0)
				MP.pin(b, base + Vector3(14 if b == axis_bot else -14, 0.1, -190), 0.0)
		if is_instance_valid(me):
			me.max_health = 100000.0
			me.health = 100000.0
			me.set_meta("protect_until", 0)
			me.global_position = shooter_at[0]
			me.velocity = Vector3.ZERO
			me.move_input = Vector3.ZERO
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(func():
		keep_all.call()
		_drive_target(0.05))
	mm.add_child(timer)
	var rej0 := Net.rejects.size()
	var table: Array[String] = []
	# --- Host schießt (Server-Spieler) ---
	if is_instance_valid(me):
		me.equip([HOST_GUN, "colt", "no36", "", "knife"])
		me.select_slot(WeaponData.Slot.PRIMARY)
		me.stamina = 100.0
		report.append("Host: Klasse Scharfschütze, Schießen %.0f, Waffe %s (%s)" % [me.skill_shooting, HOST_GUN, me.current_weapon().data.display_name])
		_ms_target = axis_bot
		var srv := [0]
		var dcb := func(s: Node, _a: float, _z: StringName, att: Node):
			if att == me and s == axis_bot:
				srv[0] += 1
		Events.soldier_damaged.connect(dcb)
		var tot := [0, 0, 0]
		for c in conditions():
			_ms_at = base + Vector3(4, 0.1, -float(c[0]))
			_ms_move = bool(c[2])
			_ms_x = 0.0
			await seconds(1.0)
			var s0: int = srv[0]
			var r: Array = await _shoot_series(mm, me, axis_bot, int(c[1]), bool(c[2]), shots, func(): pass,
				func(_k): await seconds(0.4))
			var sh: int = srv[0] - s0
			tot[0] += shots
			tot[1] += int(r[0])
			tot[2] += sh
			table.append("  Host   %-22s Schüsse %d  lokal %d  Server %d  Zonen %s" % [cond_label(c), shots, int(r[0]), sh, ",".join(r[1])])
			var want := MIN_RATE_MOVING if bool(c[2]) else MIN_RATE_STATIC
			check(float(sh) >= ceilf(want * shots), "Host %s: serverbestätigte Treffer ≥ %d %%" % [cond_label(c), int(want * 100)], "%d/%d" % [sh, shots])
		Events.soldier_damaged.disconnect(dcb)
		report.append("Host gesamt: %d Schüsse, lokal %d, Server %d" % tot)
		me.stance_request = Soldier.Stance.STAND
		shooter_at[0] = base + Vector3(-14, 0.1, 30)     # Host aus der Schusslinie
	# --- Client ---
	_ms_target = allied_bot
	_ms_move = false
	_ms_at = base + Vector3(4, 0.1, -60)
	var exe := OS.get_executable_path()
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/mp_sniper_client%s.log" % _tag())]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	var pass_args := ["--autoplay=test_mp_sniper", "--ms_peer=1", "--ms_port=%d" % (Net.PORT + PORT_OFS), "--ms_shots=%d" % shots]
	for k in ["net_lag_ms", "net_jitter_ms"]:
		if Game.cli.has(k):
			pass_args.append("--%s=%s" % [k, String(Game.cli[k])])
	var pid := OS.create_process(exe, args + ["--"] + pass_args)
	check(pid > 0, "MP: Client-Prozess gestartet")
	await mp_helper.wait_for(func(): return mp_helper._client_peer() != 0, 420.0)
	var cid: int = mp_helper._client_peer()
	check(cid != 0, "MP: Client beigetreten (IP:Port)")
	if cid == 0:
		return
	if lag > 0:
		Net.ping_override[cid] = lag      # künstlicher Verzug (ENet misst ihn nicht); echter Ping sonst ENet-Umlaufzeit
	var puppet: Soldier = Net._soldiers[cid]
	puppet.equip([CLIENT_GUN, "colt", "no36", "", "knife"])     # Serverstand der Waffen (Besitzprüfung)
	puppet.select_slot(WeaponData.Slot.PRIMARY)
	var srv_c := [0]
	var zones_c: Array[String] = []
	var ccb := func(s: Node, _a: float, z: StringName, att: Node):
		if att == puppet and s == allied_bot:
			srv_c[0] += 1
			zones_c.append(String(z))
	Events.soldier_damaged.connect(ccb)
	var keep_p := func():
		if is_instance_valid(puppet):
			puppet.max_health = 100000.0
			puppet.health = 100000.0
			puppet.set_meta("protect_until", 0)
			var pw := puppet.current_weapon()
			if pw and pw.in_mag < 3:
				pw.in_mag = pw.data.magazine_size      # Serverstand: der Client füllt sein Magazin im Test ebenfalls auf
	timer.timeout.connect(keep_p)
	_write(STEP_HOST, JSON.stringify({"step": "go", "base": [base.x, base.y, base.z], "allied": int(Net._soldiers.find_key(allied_bot))}))
	var conds := conditions()
	var done := false
	var last := -1
	var t0 := Time.get_ticks_msec()
	var srv_at_cond := {}
	while Time.get_ticks_msec() - t0 < 900000:
		await get_tree().create_timer(0.1).timeout
		var cl = JSON.parse_string(_read(STEP_CLIENT)) if _read(STEP_CLIENT) != "" else null
		if not (cl is Dictionary):
			continue
		if String(cl.get("step", "")) == "done":
			done = true
			break
		var ci := int(cl.get("cond", -1))
		if String(cl.get("step", "")) == "cond" and ci != last and ci >= 0 and ci < conds.size():
			last = ci
			srv_at_cond[ci] = srv_c[0]
			_ms_at = base + Vector3(4, 0.1, -float(conds[ci][0]))
			_ms_move = bool(conds[ci][2])
			_ms_x = 0.0
			_write(STEP_HOST, JSON.stringify({"step": "cond", "cond": ci}))
	check(done, "Client-Lauf beendet")
	var cl2 = JSON.parse_string(_read(STEP_CLIENT))
	var res: Array = cl2.get("results", []) if cl2 is Dictionary else []
	srv_at_cond[conds.size()] = srv_c[0]
	var tot_c := [0, 0, 0, 0]
	for r in res:
		var ci := int(r["cond"])
		var srv_n: int = int(srv_at_cond.get(ci + 1, srv_c[0])) - int(srv_at_cond.get(ci, 0))
		var c: Array = conds[ci]
		tot_c[0] += int(r["shots"])
		tot_c[1] += int(r["local"])
		tot_c[2] += int(r["confirmed"])
		tot_c[3] += srv_n
		table.append("  Client %-22s Schüsse %d  lokal %d  bestätigt %d (Server %d)  Zonen %s" % [cond_label(c), int(r["shots"]),
			int(r["local"]), int(r["confirmed"]), srv_n, String(r["zones"])])
		var want := MIN_RATE_MOVING if bool(c[2]) else MIN_RATE_STATIC
		check(float(r["confirmed"]) >= ceilf(want * int(r["shots"])) and int(r["confirmed"]) == srv_n,
			"Client %s: serverbestätigte Treffer ≥ %d %% (Bestätigungen = Servertreffer)" % [cond_label(c), int(want * 100)],
			"%d/%d, Server %d" % [int(r["confirmed"]), int(r["shots"]), srv_n])
	report.append("Client gesamt: %d Schüsse, lokal %d, bestätigt %d, Server %d" % tot_c)
	for l in (cl2.get("lines", []) if cl2 is Dictionary else []):
		check(String(l).begins_with("PASS"), "Client: " + String(l).substr(6))
		report.append("  " + String(l))
	for r in (cl2.get("report", []) if cl2 is Dictionary else []):
		report.append(String(r))
	var rej1 := Net.rejects.size()
	var rej_txt := ", ".join(Net.rejects.slice(rej0).map(func(e): return str(e)))
	check(rej1 == rej0, "Keine verworfenen Schüsse (NET-AUTH)", "%d → %d %s" % [rej0, rej1, rej_txt])
	if rej1 > rej0:
		report.append("Verworfen: " + rej_txt)
	report.append_array(table)
	Events.soldier_damaged.disconnect(ccb)
	timer.stop()
	_write(STEP_HOST, JSON.stringify({"step": "quit"}))
	await seconds(1.0)
	Net.leave()


# --- Client ------------------------------------------------------------------------------------------------------

func _client() -> void:
	var lines: Array[String] = []
	var rep: Array[String] = []
	var shots := int(Game.cli.get("ms_shots", "4"))
	Net.local_name = "Client"
	Net.local_team = Soldier.TEAM_AXIS
	Net.local_class = 1
	Net.local_figure = ""
	Net.join("127.0.0.1", int(Game.cli.get("ms_port", str(Net.PORT + PORT_OFS))))
	await mp_helper.wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() \
		and Net._soldiers.has(Net.my_id()) and _read(STEP_HOST).contains("\"go\""), 420.0)
	var mm: Mission = Game.current_mission()
	var st = JSON.parse_string(_read(STEP_HOST))
	var b: Array = st.get("base", [0, 0, 0]) if st is Dictionary else [0, 0, 0]
	var base := Vector3(b[0], b[1], b[2])
	build_range(mm, base)
	var me: Soldier = Net._soldiers.get(Net.my_id())
	var allied: Soldier = Net._soldiers.get(int(st.get("allied", 0))) if st is Dictionary else null
	lines.append(("PASS  " if is_instance_valid(me) and is_instance_valid(allied) else "FAIL  ") + "eigene Figur und Ziel-Bot vorhanden")
	if not (is_instance_valid(me) and is_instance_valid(allied)):
		_write(STEP_CLIENT, JSON.stringify({"step": "done", "results": [], "lines": lines}))
		return
	var spot := base + Vector3(4, 0.1, 0)
	var keep := func():
		me.max_health = 100000.0
		me.health = 100000.0
		me.global_position = spot
		me.velocity = Vector3.ZERO
		me.move_input = Vector3.ZERO
	keep.call()
	me.equip([CLIENT_GUN, "colt", "no36", "", "knife"])
	me.select_slot(WeaponData.Slot.PRIMARY)
	me.stamina = 100.0
	await seconds(1.5)
	rep.append("Client: Klasse Scharfschütze, Schießen %.0f, Waffe %s (%s), Verzug %s ms" % [me.skill_shooting, CLIENT_GUN,
		me.current_weapon().data.display_name, String(Game.cli.get("net_lag_ms", "0"))])
	var confirmed := [0]
	var conf_cb := func(_info: Dictionary): confirmed[0] += 1
	Net.hit_confirmed.connect(conf_cb)
	var results := []
	var conds := conditions()
	var wait_ms := 1500 + int(Game.cli.get("net_lag_ms", "0")) * 2
	for ci in conds.size():
		_write(STEP_CLIENT, JSON.stringify({"step": "cond", "cond": ci}))
		await mp_helper.wait_for(func(): return _read(STEP_HOST).contains("\"cond\":%d" % ci) or _read(STEP_HOST).contains("\"cond\": %d" % ci), 60.0)
		for i in 90:                      # Lage der Zielfigur kommt an (Bewegung: einschwingen)
			keep.call()
			await frames(1)
		var c0: int = confirmed[0]
		var on_shot := func(_k):
			var n0: int = confirmed[0]
			var tw := Time.get_ticks_msec()
			while confirmed[0] == n0 and Time.get_ticks_msec() - tw < wait_ms:
				keep.call()
				await frames(1)
		var r: Array = await _shoot_series(mm, me, allied, int(conds[ci][1]), bool(conds[ci][2]), shots, keep, on_shot)
		await seconds(0.3)
		results.append({"cond": ci, "shots": shots, "local": int(r[0]), "confirmed": confirmed[0] - c0, "zones": ",".join(r[1])})
	Net.hit_confirmed.disconnect(conf_cb)
	_write(STEP_CLIENT, JSON.stringify({"step": "done", "results": results, "lines": lines, "report": rep}))
	await mp_helper.wait_for(func(): return _read(STEP_HOST).contains("quit"), 120.0)
	Net.leave()
