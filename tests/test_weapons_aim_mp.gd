extends RefCounted
## MP-Teil von test_weapons_aim (zwei ENet-Prozesse, Team-Deathmatch, 1 KI je Team): Host (Alliierte) und Client (Achse)
## prüfen die Zielansicht (FOV, Korn/Absehen mittig) wie im Einzelspieler und schießen mit dem Zielfernrohr auf eine
## echte Figur in 100 m (Kopf/Rumpf/Bein). Der Server bestätigt dieselbe Zone, die die Originalbahn ab der Kamera trifft.

const WA := preload("res://tests/test_weapons_aim.gd")
const PORT_OFS := 53
const STEP_HOST := "user://wa_step_host.json"
const STEP_CLIENT := "user://wa_step_client.txt"
const DISPLAY_ITEMS := [0, 2, 4, 18, 13, 17]  # P08, Colt ([D] Pistolen-Zoom), K98k, MP 40, K98k-/Enfield-Zielfernrohr
const SNIPER := "o_17"
const ZONES := [&"head", &"torso", &"leg"]

var t: Node
var server_zones: Array = []


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func wait_for(cond: Callable, s := 60.0) -> bool:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await t.get_tree().create_timer(0.1).timeout
	return bool(cond.call())


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


func run(test: Node) -> void:
	t = test
	await t.get_tree().process_frame
	if Game.cli.has("wa_peer"):
		await _client()
	else:
		await _host()


## Schießstand hoch über der Karte (beide Prozesse bauen ihn gleich): Boden 30 × 130 m
static func build_range(mm: Node, base: Vector3) -> void:
	var plat := StaticBody3D.new()
	plat.name = "WaRange"
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(30, 1, 130)
	cs.shape = bx
	plat.add_child(cs)
	mm.add_child(plat)
	plat.global_position = base + Vector3(0, -0.5, -55)


static func neutral(s: Soldier) -> void:
	var w := s.current_weapon()
	var d := w.data.duplicate() as WeaponData
	d.spread_aim = 0.0
	d.spread_hip = 0.0
	d.spread_move_add = 0.0
	d.spread_per_shot = 0.0
	d.recoil_pitch = 0.0
	d.recoil_yaw = 0.0
	w.data = d
	w.bloom = 0.0
	s.orig_recoil_off = true
	s.skill_shooting = 100.0
	s.stamina = 100.0


static func pin(s: Soldier, p: Vector3, yaw: float) -> void:
	s.global_position = p
	s.velocity = Vector3.ZERO
	s.move_input = Vector3.ZERO
	s.look_yaw = yaw
	s.trigger = false


## Blick so drehen, dass die Bildmitte auf pt liegt (Kamera am Kopf → iterativ)
func aim_at(rig, s: Soldier, pt: Vector3, keep: Callable) -> void:
	for i in 6:
		var cam: Camera3D = rig.camera
		var dv := pt - cam.global_position
		var fwd := -cam.global_basis.z
		s.look_yaw += wrapf(atan2(-dv.x, -dv.z) - atan2(-fwd.x, -fwd.z), -PI, PI)
		s.look_pitch = clampf(s.look_pitch + atan2(dv.y, Vector2(dv.x, dv.z).length()) - asin(clampf(fwd.y, -1.0, 1.0)), -1.2, 1.2)
		for j in 6:
			keep.call()
			await t.frames(1)


static func zone_box(victim: Soldier, zone: StringName) -> Hitbox:
	var best: Hitbox = null
	for hb in victim.model.orig_zones:
		if hb.zone != zone:
			continue
		var y := (hb.get_child(0) as Node3D).global_position.y
		if best == null or (zone == &"leg" and y > (best.get_child(0) as Node3D).global_position.y):
			best = hb
	return best


## Schussreihe mit dem Zielfernrohr auf victim (Kopf/Rumpf/Bein): [[anvisiert, Bahnzone], …]
func shoot_zones(mm, me: Soldier, victim: Soldier, keep: Callable, on_shot: Callable) -> Array:
	var rig = mm.rig
	var res := []
	Input.action_press("aim")
	rig.breath_force = 1
	await t.seconds(1.2)
	var w := me.current_weapon()
	for zone in ZONES:
		var hb := zone_box(victim, zone)
		if hb == null:
			res.append([zone, &"-"])
			continue
		rig.breath = 1.0
		rig.breath_winded = false
		# Vorhalt um den Original-Fall, damit die Bahn durch die Zonenmitte geht (Zonengrenzen + Animationsphase der
		# Figur je Prozess sind sonst knapp)
		var c := (hb.get_child(0) as Node3D).global_position
		var o: Vector3 = rig.camera.global_position
		var rh := Vector2(c.x - o.x, c.z - o.z).length()
		var drop := (o + (c - o).normalized() * (c - o).length()).y - WA.orig_path_point(o, (c - o).normalized(), w.data, rh).y
		await aim_at(rig, me, c + Vector3(0, drop, 0), keep)
		for i in 150:
			if w.cooldown <= 0.0 and not w.is_reloading() and rig.zoomed():
				break
			keep.call()
			await t.frames(1)
		w.in_mag = w.data.magazine_size
		await t.frames(2)
		var cam: Camera3D = rig.camera
		var pz := WA.predict_zone(cam.get_world_3d().direct_space_state, cam.global_position, -cam.global_basis.z, w.data, me.exclude_rids())
		await t.tap("fire")
		await on_shot.call(zone, pz)
		res.append([zone, pz])
	Input.action_release("aim")
	rig.breath_force = -1
	return res


# --- Host -------------------------------------------------------------------------------------------------------

func _host() -> void:
	for p in [STEP_HOST, STEP_CLIENT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Net.local_name = "Host"
	Net.local_team = Soldier.TEAM_ALLIED
	Net.local_figure = ""
	Net.move_check = false          # Testfiguren werden direkt auf den Schießstand gesetzt
	var map: String = load("res://tests/test_mp_feedback.gd")._map()
	var ok := Net.host({"name": "Weapons-Aim", "map": map, "mode": Net.Mode.TEAM_DEATHMATCH, "port": Net.PORT + PORT_OFS,
		"max_players": 8, "time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 1,
		"password": "", "allow_vehicles": false, "kill_cam": false, "friendly_fire": false, "hit_indicator": true})
	t.check(ok and Net.is_online, "MP: Server gestartet (%s)" % map, Net.last_error)
	# 0.11.7 [D]: kein Zielfernrohr-Ausgleich im MP, auch mit Settings.scope_zero an (Kugel fällt realistisch)
	var sz_old: bool = Settings.scope_zero
	var fc_old: int = Ballistics.force_compensation
	Settings.scope_zero = true
	Ballistics.force_compensation = -1
	t.check(not Ballistics.scope_compensation_enabled(), "MP: kein Zielfernrohr-Ausgleich (scope_zero an)")
	Settings.scope_zero = sz_old
	Ballistics.force_compensation = fc_old
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() and Net._soldiers.has(1), 400.0)
	var mm: Mission = Game.current_mission()
	await wait_for(func(): return mm.nav_ready and _bots().size() == 2, 300.0)
	var bots := _bots()
	t.check(bots.size() == 2, "MP: zwei KI-Soldaten")
	if bots.size() < 2:
		return
	var me: Soldier = Net._soldiers[1]
	for b in bots.values():
		var br = (b as Soldier).get_node_or_null("EnemyBrain")
		if br:
			br.process_mode = Node.PROCESS_MODE_DISABLED
	var base := me.global_position + Vector3(0, 80, 0)
	build_range(mm, base)
	var axis_bot: Soldier = bots[Soldier.TEAM_AXIS]
	var allied_bot: Soldier = bots[Soldier.TEAM_ALLIED]
	var allied_at := [base + Vector3(4, 0.1, -100)]
	var keep := func():
		for s in [me, axis_bot, allied_bot]:
			s.max_health = 100000.0          # Vorgabe: Unverwundbarkeit
			s.health = 100000.0
			s.set_meta("protect_until", 0)
		pin(axis_bot, base + Vector3(-4, 0.1, -100), 0.0)
		pin(allied_bot, allied_at[0], 0.0)
		axis_bot.aiming = false
		allied_bot.aiming = false
	keep.call()
	pin(me, base + Vector3(-4, 0.1, 0), 0.0)
	await t.seconds(1.5)
	var tick := func():
		keep.call()
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(tick)
	mm.add_child(timer)
	# Darstellung beim Host (eigener Spieler auf dem Server)
	await WA.phase_display(t, mm, me, "MP-Host", DISPLAY_ITEMS)
	pin(me, base + Vector3(-4, 0.1, 0), 0.0)
	# Host schießt mit dem Zielfernrohr auf den Achsen-Bot
	me.equip([SNIPER, "colt", "no36", "", "knife"])
	me.select_slot(WeaponData.Slot.PRIMARY)
	await t.seconds(1.4)
	neutral(me)
	var dmg_cb := func(s: Node, _a: float, zone: StringName, att: Node):
		server_zones.append([s, String(zone), att])
	Events.soldier_damaged.connect(dmg_cb)
	var bad: Array[String] = []
	var host_shot := func(zone: StringName, pz: StringName):
		server_zones.clear()
		await wait_for(func(): return not server_zones.is_empty(), 3.0)
		var got: String = server_zones[0][1] if not server_zones.is_empty() else "-"
		t.report.append("  Host  %-5s → Bahn %-5s → Server %s" % [zone, pz, got])
		if got != String(pz) or pz == &"-":
			bad.append("%s→%s (Bahn %s)" % [zone, got, pz])
	await shoot_zones(mm, me, axis_bot, keep, host_shot)
	t.check(bad.is_empty(), "MP-Host: Zielfernrohr 100 m, Kopf/Rumpf/Bein – Server trifft die Zone der Originalbahn", ", ".join(bad))
	# Client starten
	var exe := OS.get_executable_path()
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/weapons_aim_client.log")]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	var pid := OS.create_process(exe, args + ["--", "--autoplay=test_weapons_aim", "--phase=mp", "--wa_peer=1",
		"--wa_port=%d" % (Net.PORT + PORT_OFS)])
	t.check(pid > 0, "MP: Client-Prozess gestartet")
	await wait_for(func(): return _client_peer() != 0, 420.0)
	var cid := _client_peer()
	t.check(cid != 0, "MP: Client beigetreten")
	if cid == 0:
		return
	var puppet: Soldier = Net._soldiers[cid]
	puppet.equip([SNIPER, "colt", "no36", "", "knife"])     # Serverstand der Waffen (Besitzprüfung)
	puppet.select_slot(WeaponData.Slot.PRIMARY)
	var keep2 := func():
		if not (is_instance_valid(puppet) and is_instance_valid(me) and is_instance_valid(axis_bot) and is_instance_valid(allied_bot)):
			return
		keep.call()
		puppet.max_health = 100000.0
		puppet.health = 100000.0
		puppet.set_meta("protect_until", 0)
	timer.timeout.disconnect(tick)
	timer.timeout.connect(keep2)
	_write(STEP_HOST, JSON.stringify({"step": "go", "base": [base.x, base.y, base.z],
		"allied": int(Net._soldiers.find_key(allied_bot))}))
	# Client-Schüsse: der Server notiert die Zone je Treffer des Clients
	var log_srv: Array[String] = []
	var srv_cb := func(s: Node, _a: float, zone: StringName, att: Node):
		if att == puppet and s == allied_bot:
			log_srv.append(String(zone))
	Events.soldier_damaged.connect(srv_cb)
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("done"), 600.0)
	var cl := _read(STEP_CLIENT)
	var j = JSON.parse_string(cl.substr(5)) if cl.begins_with("done") else null
	var want: Array = j.get("bahn", []) if j is Dictionary else []
	t.check(want.size() == 3 and log_srv == Array(want).map(func(x): return String(x)),
		"MP-Server: Client-Zielfernrohrschüsse treffen auf dem Server dieselben Zonen wie die Originalbahn des Clients",
		"Server %s / Client-Bahn %s" % [str(log_srv), str(want)])
	for l in (j.get("lines", []) if j is Dictionary else []):
		t.check(String(l).begins_with("PASS"), "Client: " + String(l).substr(6))
	for r in (j.get("report", []) if j is Dictionary else []):
		t.report.append(String(r))
	# Schrotflinte ungezoomt (Client): Bot 10 m vor dem Client, 5 Schüsse aus der Hüfte (3. Person)
	puppet.equip(["o_23", "colt", "no36", "", "knife"])
	puppet.select_slot(WeaponData.Slot.PRIMARY)
	allied_at[0] = base + Vector3(4, 0.1, -10)
	log_srv.clear()
	var srv_imp: Array[String] = []
	var simp := func(pos: Vector3, col: Object, sh: Node):
		if sh == puppet:
			srv_imp.append("%s@%s" % [(col as Node).name if col is Node else "?", str((pos - allied_bot.global_position).snapped(Vector3.ONE * 0.01))])
	Ballistics.projectile_impact.connect(simp)
	await t.seconds(0.5)
	_write(STEP_HOST, JSON.stringify({"step": "shotgun"}))
	await wait_for(func(): return _read(STEP_CLIENT).begins_with("done2"), 300.0)
	Ballistics.projectile_impact.disconnect(simp)
	t.report.append("  Schrot Server-Einschläge (relativ zum Bot): " + ", ".join(srv_imp))
	var c2 := _read(STEP_CLIENT)
	var j2 = JSON.parse_string(c2.substr(6)) if c2.begins_with("done2") else null
	var conf := int(j2.get("confirmed", -1)) if j2 is Dictionary else -1
	t.check(conf >= 4 and log_srv.size() == conf, "MP Schrot ungezoomt 10 m: Server-Treffer = Client-Bestätigungen, ≥ 4/5",
		"Server %d / Client %d" % [log_srv.size(), conf])
	for l in (j2.get("lines", []) if j2 is Dictionary else []):
		t.check(String(l).begins_with("PASS"), "Client: " + String(l).substr(6))
	Events.soldier_damaged.disconnect(dmg_cb)
	Events.soldier_damaged.disconnect(srv_cb)
	timer.stop()
	timer.timeout.disconnect(keep2)
	_write(STEP_HOST, JSON.stringify({"step": "quit"}))
	await t.seconds(1.0)
	Net.leave()


# --- Client ------------------------------------------------------------------------------------------------------

func _client() -> void:
	var lines: Array[String] = []
	var rep: Array[String] = []
	var ccheck := func(ok: bool, label: String, detail := ""):
		lines.append(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	Net.local_name = "Client"
	Net.local_team = Soldier.TEAM_AXIS
	Net.local_figure = ""
	Net.join("127.0.0.1", int(Game.cli.get("wa_port", str(Net.PORT + PORT_OFS))))
	await wait_for(func(): return Game.current_mission() != null and Game.current_mission().is_node_ready() \
		and Net._soldiers.has(Net.my_id()) and _read(STEP_HOST).contains("\"go\""), 420.0)
	var mm: Mission = Game.current_mission()
	var st = JSON.parse_string(_read(STEP_HOST))
	var b: Array = st.get("base", [0, 0, 0]) if st is Dictionary else [0, 0, 0]
	var base := Vector3(b[0], b[1], b[2])
	build_range(mm, base)
	var me: Soldier = Net._soldiers[Net.my_id()]
	var allied: Soldier = Net._soldiers.get(int(st.get("allied", 0))) if st is Dictionary else null
	ccheck.call(is_instance_valid(me) and is_instance_valid(allied), "Client: eigene Figur und Ziel-Bot vorhanden")
	var keep := func():
		me.max_health = 100000.0
		me.health = 100000.0
	pin(me, base + Vector3(4, 0.1, 0), 0.0)
	await t.seconds(1.5)
	# Darstellung beim Client
	var shim := _Shim.new(t, rep, ccheck)
	await WA.phase_display(shim, mm, me, "MP-Client", DISPLAY_ITEMS)
	pin(me, base + Vector3(4, 0.1, 0), 0.0)
	me.equip([SNIPER, "colt", "no36", "", "knife"])
	me.select_slot(WeaponData.Slot.PRIMARY)
	await t.seconds(1.4)
	neutral(me)
	var bahn: Array = []
	var bad: Array[String] = []
	var cl_shot := func(zone: StringName, pz: StringName):
		var n0 := Net.hit_log.size()
		await wait_for(func(): return Net.hit_log.size() > n0, 4.0)
		var got: String = String(Net.hit_log.back()["zone"]) if Net.hit_log.size() > n0 else "-"
		bahn.append(String(pz))
		rep.append("  Client %-5s → Bahn %-5s → Server bestätigt %s" % [zone, pz, got])
		if got != String(pz) or pz == &"-":
			bad.append("%s→%s (Bahn %s)" % [zone, got, pz])
	if is_instance_valid(allied):
		await shoot_zones(mm, me, allied, keep, cl_shot)
	ccheck.call(bad.is_empty() and bahn.size() == 3, "Client: Zielfernrohr 100 m – Server bestätigt die Zone der Originalbahn (Kopf/Rumpf/Bein)", ", ".join(bad))
	_write(STEP_CLIENT, "done " + JSON.stringify({"bahn": bahn, "lines": lines, "report": rep}))
	# Schrotflinte ungezoomt
	await wait_for(func(): return _read(STEP_HOST).contains("shotgun"), 300.0)
	var lines2: Array[String] = []
	me.equip(["o_23", "colt", "no36", "", "knife"])
	me.select_slot(WeaponData.Slot.PRIMARY)
	me.skill_shooting = 100.0
	me.orig_recoil_off = false
	if mm.rig.mode != CameraRig.Mode.THIRD:
		mm.rig.toggle_mode()
	await t.seconds(1.5)
	var w := me.current_weapon()
	var confirmed := 0
	var hitinfo: Array[String] = []
	var icb := func(pos: Vector3, col: Object, sh: Node):
		if sh == me:
			hitinfo.append("%s@%s" % [(col as Node).name if col is Node else "?", str((pos - allied.global_position).snapped(Vector3.ONE * 0.01))])
	Ballistics.projectile_impact.connect(icb)
	for k in 5:
		# Trefferreaktion des Bots (Server-Clip; die Netzfigur des Clients zeigt sie nur bei fallender Gesundheit, die der
		# Test festhält) abklingen lassen, sonst stehen die Zonen auf Server und Client verschieden
		await t.seconds(1.5)
		var hb := zone_box(allied, &"torso")
		await aim_at(mm.rig, me, (hb.get_child(0) as Node3D).global_position, keep)
		for i in 150:
			if w.cooldown <= 0.0 and not w.is_reloading():
				break
			await t.frames(1)
		w.in_mag = w.data.magazine_size
		var n0 := Net.hit_log.size()
		await t.tap("fire")
		if await wait_for(func(): return Net.hit_log.size() > n0, 3.0):
			confirmed += 1
	Ballistics.projectile_impact.disconnect(icb)
	lines2.append(("PASS  " if confirmed >= 4 else "FAIL  ") + "Client: Schrot ungezoomt 10 m, %d/5 vom Server bestätigt  (lokal %s)" % [confirmed, ", ".join(hitinfo)])
	_write(STEP_CLIENT, "done2 " + JSON.stringify({"confirmed": confirmed, "lines": lines2}))
	await wait_for(func(): return _read(STEP_HOST).contains("quit"), 60.0)


## Testschnittstelle für phase_display im Clientprozess (Ergebnisse gehen an den Host)
class _Shim:
	var t: Node
	var report: Array[String]
	var ccheck: Callable

	func _init(test: Node, rep: Array[String], cc: Callable) -> void:
		t = test
		report = rep
		ccheck = cc

	func check(ok: bool, label: String, detail := "") -> void:
		ccheck.call(ok, label, detail)

	func frames(n: int) -> void:
		await t.frames(n)

	func seconds(s: float) -> void:
		await t.seconds(s)
