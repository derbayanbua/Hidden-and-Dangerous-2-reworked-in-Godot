extends "res://tests/test_gameplay.gd"
## Fallschaden wie im Original (0.11.6, hd2.exe 0x770C30, docs/status/fall_damage.md).
##   Einzelspieler: tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_fall_damage
##     Testfiguren (Kameraden ohne KI) fallen auf eine Testplattform hoch über der Karte: unter 3 m kein Schaden,
##     darüber (h − 3) · 24 LP, ab 1000 zotti gedeckelt (tödlich für 100 LP), Leiter/Treppe/Rampe ohne Schaden.
##     Der Spieler bleibt unverwundbar (Gesundheit 1000, nachgefüllt).
##   Mehrspieler (zwei Prozesse): tools\godot.cmd --headless -- --autoplay=test_fall_damage --phase=mp
##     Client fällt 6 m → Server zieht den Schaden ab (Ursache „fall“); dann tödlicher Sturz → Kill-Feed „fall“.

const RESULT := "user://fall_damage_client_result.txt"
const MP_PORT := 11046
const BASE := Vector3(0.0, 400.0, 20.0)     ## Oberkante der Testplattform (weit über der Karte)

var _probe: Soldier = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1200.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _run() -> void:
	if String(Game.cli.get("phase", "sp")) == "mp":
		await _run_mp()
		return
	for i in 600:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null and m.squad.members.size() >= 3, "Mission und Trupp geladen")
	if m == null or m.squad.members.size() < 3:
		_finish()
		return
	isolate_enemies([])
	var lead: Soldier = m.squad.leader()
	(m.controller as PlayerController).set_active(lead)
	_god(lead)
	_build_course()
	await frames(5)
	lead.global_position = BASE + Vector3(-15, 0.2, -15)
	lead.velocity = Vector3.ZERO
	# Formel (statisch)
	check(Soldier.fall_damage_for(2.9) == 0.0 and Soldier.fall_damage_for(3.0) == 0.0, "Formel: bis 3 m kein Schaden")
	check(is_equal_approx(Soldier.fall_damage_for(5.0), 48.0), "Formel: 5 m = 2 m · 240 zotti = 48 LP",
		str(Soldier.fall_damage_for(5.0)))
	check(is_equal_approx(Soldier.fall_damage_for(30.0), 100.0), "Formel: Deckel 1000 zotti = 100 LP",
		str(Soldier.fall_damage_for(30.0)))
	var t1: Soldier = m.squad.members[1]
	var t2: Soldier = m.squad.members[2]
	for t in [t1, t2]:
		_no_brain(t)
	_probe = t1
	# 1. Fallhöhen unter/über der Schwelle
	for h in [1.0, 2.0, 2.8]:
		var r := await _drop(t1, h)
		check(r.get("damage", -1.0) == 0.0 and t1.health == t1.max_health, "%.1f m: kein Schaden" % h,
			"h=%.2f hp=%.1f" % [r.get("h", -1.0), t1.health])
	for h in [4.0, 5.0, 6.5]:
		var r := await _drop(t1, h)
		var mh: float = r.get("h", 0.0)
		var want := Soldier.fall_damage_for(mh)
		check(absf(mh - h) < 0.2 and want > 0.0 and absf((t1.max_health - t1.health) - want) < 0.6 and t1.alive,
			"%.1f m: Schaden laut Kurve (%.0f LP)" % [h, (h - 3.0) * 24.0],
			"gemessen h=%.2f, Schaden %.1f, erwartet %.1f" % [mh, t1.max_health - t1.health, want])
	# 2. Tödliche Höhe (100 LP: ab ≈ 7,17 m), Deckel greift
	t2.max_health = 100.0
	t2.health = 100.0
	var rd := await _drop(t2, 12.0)
	check(not t2.alive and is_equal_approx(rd.get("damage", 0.0), 100.0), "12 m: tödlich (Deckel 100 LP)",
		"h=%.2f dmg=%.1f alive=%s" % [rd.get("h", -1.0), rd.get("damage", -1.0), t2.alive])
	# 3. Leiter (Kletterbewegung wie OrigLadder) hinauf/hinunter: kein Schaden
	_heal(t1)
	var foot := BASE + Vector3(6.0, 0.02, 0.0)
	var top := BASE + Vector3(8.0, 8.02, 0.0)       # Turm 8 m (Mitte x = 8,5)
	_place(t1, foot)
	await seconds(0.4)
	t1.start_path_climb(foot, Vector3(foot.x + 0.4, top.y + 0.1, foot.z), top + Vector3(0.5, 0, 0), 4.0)
	await seconds(4.6)
	check(absf(t1.global_position.y - top.y) < 0.4, "Leiter: oben angekommen", "y=%.2f" % (t1.global_position.y - BASE.y))
	t1.start_path_climb(t1.global_position, Vector3(foot.x + 0.4, top.y + 0.1, foot.z), foot, 4.0)
	await seconds(4.8)
	check(absf(t1.global_position.y - BASE.y) < 0.3 and t1.health == t1.max_health, "Leiter 8 m hinauf/hinunter: kein Schaden",
		"y=%.2f hp=%.1f" % [t1.global_position.y - BASE.y, t1.health])
	# 3b. Vom Turm gehen (8 m): Schaden laut Kurve
	t1.max_health = 200.0
	t1.health = 200.0
	_place(t1, top + Vector3(0.3, 0, 0))
	await seconds(0.5)
	t1.last_fall = {}
	t1.look_yaw = PI * 0.5                     # Blick nach −X (vom Turm herunter)
	t1.move_input = Vector3(-1, 0, 0)
	await _wait_land(t1, 6.0)
	t1.move_input = Vector3.ZERO
	var tf: Dictionary = t1.last_fall
	check(tf.get("h", 0.0) > 7.5 and t1.max_health - t1.health > 1.0
		and absf((t1.max_health - t1.health) - Soldier.fall_damage_for(tf.get("h", 0.0))) < 0.6,
		"Von 8 m Kante gelaufen: Schaden laut Kurve", "h=%.2f hp=%.1f" % [tf.get("h", -1.0), t1.health])
	# 4. Treppe 6 m hinab (20 Stufen à 0,3 m) und Rampe 6 m hinab: kein Schaden
	_heal(t1)
	_place(t1, BASE + Vector3(-8.0, 6.05, 8.5))
	await seconds(0.5)
	t1.last_fall = {}
	t1.move_input = Vector3(0, 0, -1)
	await seconds(4.5)
	t1.move_input = Vector3.ZERO
	await seconds(0.4)
	check(t1.global_position.y - BASE.y < 0.3 and t1.health == t1.max_health, "Treppe 6 m hinab: kein Schaden",
		"y=%.2f hp=%.1f fall=%s" % [t1.global_position.y - BASE.y, t1.health, str(t1.last_fall)])
	_heal(t1)
	_place(t1, BASE + Vector3(4.0, 6.05, 14.5))
	await seconds(0.5)
	t1.last_fall = {}
	t1.move_input = Vector3(0, 0, -1)
	for i in 100:
		await seconds(0.1)
		if t1.global_position.y - BASE.y < 0.2:
			break
	await seconds(1.0)
	t1.move_input = Vector3.ZERO
	await seconds(0.4)
	check(t1.global_position.y - BASE.y < 0.3 and t1.health == t1.max_health, "Rampe 30° 6 m hinab: kein Schaden",
		"y=%.2f hp=%.1f fall=%s" % [t1.global_position.y - BASE.y, t1.health, str(t1.last_fall)])
	# 5. Versetzen in der Luft nach unten zählt nicht als Fall
	_heal(t1)
	_place(t1, BASE + Vector3(-4, 15.0, -4))
	await frames(3)
	t1.global_position = BASE + Vector3(-4, 1.0, -4)
	await _wait_land(t1, 3.0)
	check(t1.health == t1.max_health, "Versetzen nach unten in der Luft: kein Fallschaden", "hp=%.1f" % t1.health)
	check(lead.alive and lead.health >= 999.0, "Spieler unverwundbar geblieben")
	_finish()


func _god(s: Soldier) -> void:
	s.max_health = 1000.0
	s.health = 1000.0


func _heal(s: Soldier) -> void:
	s.max_health = 100.0
	s.health = 100.0


func _no_brain(s: Soldier) -> void:
	for c in s.get_children():
		if c is AIBrain:
			(c as Node).process_mode = Node.PROCESS_MODE_DISABLED
	s.move_input = Vector3.ZERO


func _place(s: Soldier, at: Vector3) -> void:
	s.global_position = at
	s.velocity = Vector3.ZERO
	s.move_input = Vector3.ZERO


## Testfigur aus h m über der Plattform fallen lassen, Ergebnis der Landung
func _drop(s: Soldier, h: float) -> Dictionary:
	_heal(s)
	_place(s, BASE + Vector3(-4.0 - 3.0 * s.get_index(), 0.05, -4.0))
	await seconds(0.3)
	s.last_fall = {}
	_place(s, BASE + Vector3(-4.0 - 3.0 * s.get_index(), h, -4.0))
	await _wait_land(s, 5.0)
	await frames(3)
	return s.last_fall


func _wait_land(s: Soldier, limit: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(limit * 1000.0):
		await get_tree().physics_frame
		if not s.last_fall.is_empty() or (not s.alive):
			return


func _box(center: Vector3, size: Vector3, basis := Basis()) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	get_tree().current_scene.add_child(b)
	b.global_transform = Transform3D(basis, center)


## Plattform 40 × 40 m, Turm 8 m (Leiter/Kante), Treppe 6 m (20 Stufen), Rampe 30° (6 m Höhe)
func _build_course() -> void:
	_box(BASE + Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_box(BASE + Vector3(8.5, 4.0, 0), Vector3(1.0, 8.0, 2.0))
	for i in 20:                                                   # Stufe i: Höhe (20 − i) · 0,3, Tiefe 0,35 nach −Z
		var hh := (20 - i) * 0.3
		_box(BASE + Vector3(-8.0, hh * 0.5, 7.5 - 0.35 * i - 0.175), Vector3(2.0, hh, 0.35))
	_box(BASE + Vector3(-8.0, 3.0, 8.5), Vector3(2.0, 6.0, 2.0))   # Podest oben an der Treppe (z 7,5 … 9,5)
	var run := 6.0 / tan(deg_to_rad(30.0))                         # 10,4 m
	var len := 6.0 / sin(deg_to_rad(30.0))                         # 12 m
	var rb := Basis(Vector3.RIGHT, deg_to_rad(-30.0))              # steigt nach +Z
	_box(BASE + Vector3(4.0, 3.0, 14.0 - run * 0.5) + rb * Vector3(0, -0.25, 0), Vector3(2.0, 0.5, len), rb)
	_box(BASE + Vector3(4.0, 3.0, 15.0), Vector3(2.0, 6.0, 2.0))   # Podest oben an der Rampe (z 14 … 16)


# --- Mehrspieler (Server-Seite, zweiter Prozess = test_fall_damage_client) ------------------------------

func _run_mp() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	await frames(5)
	Net.local_name = "Host"
	Net.move_check = false        # Testclient versetzt seine Figur direkt in die Luft – kein Spielzug
	var ok := Net.host({"name": "Fall", "map": "mp_arena_a1_blizzard", "mode": Net.Mode.DEATHMATCH, "max_players": 4,
		"time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "password": "", "port": MP_PORT,
		"friendly_fire": true, "bots_per_team": 0, "falling_damage": true, "spawn_protect_s": 0, "flood_protect": false})
	check(Net.is_online and multiplayer.is_server(), "Server gestartet", str(ok) + " " + Net.last_error)
	check(bool(Net.rule("falling_damage")), "Regel Fallschaden an")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		await get_tree().process_frame
		var m: Node = Game.current_mission()
		if m and m.get("squad") and m.is_node_ready():
			break
	await frames(30)
	var exe := OS.get_executable_path()
	var clog := ProjectSettings.globalize_path("res://test_output/fall_damage_client.log")
	var proj: Array = [] if OS.has_feature("template") else ["--path", ProjectSettings.globalize_path("res://")]
	var pid := OS.create_process(exe, ["--headless", "--log-file", clog] + proj + ["--",
		"--autoplay=test_fall_damage_client"])
	check(pid > 0, "Client-Prozess gestartet", str(pid))
	var cid := 0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000 and cid == 0:
		await get_tree().create_timer(0.25).timeout
		for id in Net._soldiers:
			if id != 1 and is_instance_valid(Net._soldiers[id]):
				cid = id
	check(cid != 0, "Client beigetreten")
	if not await _wait_chat("bereit", 400.0):
		check(false, "Client hat die Karte geladen")
		_finish_mp(pid)
		return
	var me: Soldier = Net._soldiers.get(1)
	if is_instance_valid(me):
		_god(me)
	# Fall 1: 6 m, Client hat 500 LP
	var cs: Soldier = Net._soldiers.get(cid)
	cs.set_meta("protect_until", 0)
	cs.max_health = 500.0
	cs.health = 500.0
	await get_tree().create_timer(1.0).timeout
	Net.send_chat("los1")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and cs.health > 499.0:
		await get_tree().create_timer(0.1).timeout
	var lost := 500.0 - cs.health
	check(lost > 60.0 and lost < 90.0 and cs.alive, "Server: 6 m-Sturz des Clients kostet ≈ 72 LP", "%.1f" % lost)
	check(String(cs.get_meta("last_cause", "")) == "fall", "Server: Ursache des Treffers = fall",
		String(cs.get_meta("last_cause", "")))
	# Fall 2: tödlich
	cs.health = 50.0
	await _wait_chat("gelandet1", 60.0)
	Net.send_chat("los2")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and is_instance_valid(cs) and cs.alive:
		await get_tree().create_timer(0.1).timeout
	check(not (is_instance_valid(cs) and cs.alive), "Server: tödlicher Sturz tötet den Client")
	await frames(10)
	check(Net.kill_feed.any(func(e): return int(e.get("victim", 0)) == cid and String(e.get("cause", "")) == "fall"),
		"Server: Kill-Feed-Eintrag mit Ursache fall")
	check(not is_instance_valid(me) or me.health >= 999.0, "Host unverwundbar geblieben")
	_finish_mp(pid)


func _wait_chat(text: String, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(limit * 1000.0):
		if Net.chat_log.any(func(e): return String(e["text"]) == text):
			return true
		await get_tree().create_timer(0.25).timeout
	return false


func _finish_mp(pid: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000 and not FileAccess.file_exists(RESULT):
		await get_tree().create_timer(0.5).timeout
	var txt := FileAccess.get_file_as_string(RESULT) if FileAccess.file_exists(RESULT) else ""
	check(txt != "", "Client-Ergebnisse empfangen")
	for line in txt.split("\n", false):
		check(line.begins_with("PASS"), "Client: " + line.substr(6))
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	Net.leave(false)
	_finish()
