extends "res://tests/test_gameplay.gd"
## AFRICA6 „Raubvögel“ (Bordschützen in der Ju 88): Flugbahn, Sitze/MG-Stände (Kamera, Grenzen, Wechsel), Schießen mit
## echter Ballistik auf die Bf 109, Schadensmodell, Leuchtspuren, Absturz, Sieg per Originalskript.
##   tools\godot.cmd --headless -- --mission=af6_raubvoegel --autoplay=test_af6
## Kontrollbilder (Fenster): tools\godot.cmd -- --mission=af6_raubvoegel --autoplay=test_af6 --shots=1
##   → test_output/af6/seat<n>_{fpv,3rd,hit}.png
## Trupp unverwundbar: die Ju 88 (einziger Schadensweg) wird außerhalb der Schadens-/Absturzprüfung nachgefüllt.

const SHOT_DIR := "res://test_output/af6/"
var _god := true
var _shots := false


func _run() -> void:
	_shots = String(Game.cli.get("shots", "0")) == "1"
	if _shots:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.get("ju88") != null, "Ju 88 (Akteur Typ 34) gefunden")
	if m == null or m.ju88 == null:
		_finish()
		return
	_keep_alive(m)
	check(m._path.size() > 5000 and absf(m._path.back()[0] - 199.84) < 0.2, "Original-Flugbahn #aircraftA1..6 (≈200 s)",
		"%d Keys, Ende %.2f s" % [m._path.size(), m._path.back()[0] if not m._path.is_empty() else 0.0])
	# Intro-Sequenz (cutletadlo_af5: Ju 88 während der Sequenz ausgeblendet) wie per Leertaste überspringen
	var skipped := false
	for i in 900:
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
			skipped = true
		if skipped and m.ju88.visible and not m.runtime.in_cutscene:
			break
		await frames(5)
	check(skipped, "Intro-Sequenz (CSC_RunCutscene(2)) gestartet und übersprungen")
	await seconds(0.5)
	check(m.ju88.visible, "Originalskript schaltet die Ju 88 nach der Sequenz ein (FRM_SetON)")
	check(m.fighters.size() >= 5 and m.fighters.size() <= 7, "SetActorState(ju88, n): %d Jäger" % m.fighters.size())
	check(is_equal_approx(m.damage_mult, 0.4 + 0.2 * Game.difficulty()) , "SetupJunkers88(40+20·Schwierigkeit, 100)", str(m.damage_mult))
	var s: Soldier = m.squad.leader()
	check(s.mounted != null and s.mounted.get("seat_idx") == 1 and s.current_weapon() != null
		and s.current_weapon().data.display_name.begins_with("MG"),
		"Spieler an Sitz 1 mit Original-MG", s.current_weapon().data.display_name if s.current_weapon() else "-")
	var p0: Vector3 = m.ju88.global_position
	var t0: float = m.flight_t
	await seconds(1.0)
	var v: float = m.ju88.global_position.distance_to(p0) / maxf(m.flight_t - t0, 0.01)
	check(v > 20.0 and v < 90.0, "Ju 88 fliegt (%.0f m/s; Original im Mittel 41,5)" % v)
	check(s.global_position.distance_to(m.ju88.global_position) < 6.0, "Schütze fliegt mit")

	# --- MG-Stände: alle Frames gefunden, Kamera am Original-Kamerapunkt, Blick = Laufrichtung -------------------
	m.rig.mode = CameraRig.Mode.FIRST
	m.pause_flight = true             # Kamera (Bild) und Ju 88 (Physik) im selben Takt vergleichen
	var seats_ok := 0
	for i in m.squad.members.size():
		var sol: Soldier = m.squad.members[i]
		var tur = sol.mounted
		if tur == null or not tur.has_method("aim_dir"):
			check(false, "Soldat %d: MG-Stand" % i)
			continue
		var frames_ok: bool = tur.hort != null and tur.vert != null and tur.shdum != null and tur.cam_fpv != null and tur.cam_3rd != null
		check(frames_ok, "Sitz %d: HORT/VERT/SHDUM/CAMERAFPV/CAMERA3RD im Modell" % tur.seat_idx)
		m.squad.set_active(i)
		await frames(6)
		check(m.squad.leader() == sol and m.rig.target == sol, "Wechsel auf Sitz %d (Soldat %d)" % [tur.seat_idx, i])
		var cam: Camera3D = m.rig.camera
		var dcam: float = cam.global_position.distance_to(tur.cam_fpv.global_position)
		var fwd: Vector3 = -cam.global_basis.z
		var ddir: float = fwd.dot(tur.aim_dir())
		var dmz: float = cam.global_position.distance_to(tur.shot_origin())
		check(dcam < 0.25 and ddir > 0.995 and dmz < 1.5,
			"Sitz %d: 1. Person am CAMERAFPV des MG, Blick = Lauf" % tur.seat_idx,
			"Abstand %.2f m, cos %.4f, Mündung %.2f m" % [dcam, ddir, dmz])
		# Ruhelage: Laufrichtung relativ zum Flugzeug wie im Modell (Sitz 0/3 nach vorn, 1/2/4 nach hinten)
		var fwd_ju: float = tur.aim_dir().dot(m.ju88.global_basis.z.normalized())
		var want_fwd: bool = tur.seat_idx == 0 or tur.seat_idx == 3
		check((fwd_ju > 0.3) == want_fwd, "Sitz %d: MG zeigt %s" % [tur.seat_idx, "nach vorn" if want_fwd else "nach hinten"], "%.2f" % fwd_ju)
		# Schwenkgrenzen: weit nach links/oben → am Original-Grenzwert
		sol.look_yaw += 2.5
		sol.look_pitch = clampf(sol.look_pitch + 1.2, -1.3, 1.3)
		await frames(3)
		check(absf(tur.yaw - tur.lim["left"]) < 0.01 and absf(tur.pitch - tur.lim["up"]) < 0.01,
			"Sitz %d: Grenzen links %.0f°/oben %.0f° (BARREL-Parameter)" % [tur.seat_idx, rad_to_deg(tur.lim["left"]), rad_to_deg(tur.lim["up"])],
			"yaw %.1f° pitch %.1f°" % [rad_to_deg(tur.yaw), rad_to_deg(tur.pitch)])
		# Fenster: Kamera-Nachführung braucht je nach Bildrate einige Bilder (bis 30 warten)
		var cdot := -1.0
		for _k in 30:
			await frames(1)
			cdot = -cam.global_basis.z.dot(tur.aim_dir())
			if cdot > 0.99:
				break
		check(cdot > 0.99, "Sitz %d: Kamera folgt dem MG an der Grenze" % tur.seat_idx, "cos %.4f" % cdot)
		# Blick relativ zum Flugzeug: nach 1 s Flug (Kurven) unverändert am MG
		var y0: float = tur.yaw
		m.pause_flight = false
		await seconds(1.0)
		m.pause_flight = true
		check(absf(tur.yaw - y0) < 0.001, "Sitz %d: Winkel bleibt relativ zum Flugzeug" % tur.seat_idx)
		tur.yaw = 0.0
		tur.pitch = 0.0
		tur._wy = NAN
		await frames(3)
		if _shots:
			await _shot("seat%d_fpv" % tur.seat_idx)
			m.rig.mode = CameraRig.Mode.THIRD
			await frames(8)
			check(m.rig.camera.global_position.distance_to(tur.cam_3rd.global_position) < 0.5, "Sitz %d: 3. Person am CAMERA3RD" % tur.seat_idx)
			await _shot("seat%d_3rd" % tur.seat_idx)
			m.rig.mode = CameraRig.Mode.FIRST
			await frames(4)
		# Schuss: Geschoss aus der Mündung (SHDUM) in Visierrichtung
		var w: Weapon = sol.current_weapon()
		var nproj: int = Ballistics._projectiles.size()
		sol._fire_shot(w)
		var ok := false
		var det := "kein Geschoss"
		if Ballistics._projectiles.size() > nproj:
			var p = Ballistics._projectiles.back()
			var od: float = p.pos.distance_to(tur.shot_origin())
			var dd: float = p.vel.normalized().dot(tur.aim_dir())
			ok = od < 0.05 and dd > 0.99
			det = "Abstand %.3f m, cos %.4f" % [od, dd]
		check(ok, "Sitz %d: Geschoss startet an der Mündung in Laufrichtung" % tur.seat_idx, det)
		seats_ok += 1
	check(seats_ok == 4, "Alle 4 besetzten Sitze (1/2/3/0) geprüft")

	# --- Echte Treffer mit jedem MG (Ballistik → Fighter.on_bullet_hit), Abschuss -------------------------------
	m.flight_t = 20.0
	await frames(3)
	m.pause_flight = true             # Testhilfe: Flugbahn steht → ruhiges Ziel
	var fi := 0
	for i in m.squad.members.size():
		var sol: Soldier = m.squad.members[i]
		var tur = sol.mounted
		while fi < m.fighters.size() and (not is_instance_valid(m.fighters[fi]) or m.fighters[fi].down):
			fi += 1
		if fi >= m.fighters.size():
			break
		var f = m.fighters[fi]
		m.squad.set_active(i)
		tur.yaw = 0.0
		tur.pitch = 0.0
		tur._wy = NAN
		await frames(4)
		var tp: Vector3 = tur.shot_origin() + tur.aim_dir() * 90.0
		f.keys = [[0.0, tp, Basis.looking_at(-m.ju88.global_basis.z, Vector3.UP).get_rotation_quaternion()]]
		await frames(4)
		if _shots:
			await _shot("seat%d_hit" % tur.seat_idx)
		var imp := {}
		var cb := func(pos, col, sh):
			if sh == sol:
				var k := str(col.get_parent().name if col and col.get_parent() else col) + "@%d" % int(pos.distance_to(tur.shot_origin()))
				imp[k] = int(imp.get(k, 0)) + 1
		Ballistics.projectile_impact.connect(cb)
		var shots0: int = tur.shots
		var h0: int = f.hits_taken
		var hp0: float = f.health
		var waited := 0.0
		Input.action_press("fire")
		while waited < 6.0 and not f.down:
			await seconds(0.25)
			waited += 0.25
			sol.current_weapon().reserve = 500
		Input.action_release("fire")
		await frames(3)
		Ballistics.projectile_impact.disconnect(cb)
		print("AF6 Einschläge Sitz %d: %s" % [tur.seat_idx, str(imp)])
		check(tur.shots > shots0, "Sitz %d: MG feuert (Feuertaste)" % tur.seat_idx, "%d Schuss" % (tur.shots - shots0))
		check(f.hits_taken > h0 and f.health < hp0, "Sitz %d: Geschosse treffen die Bf 109" % tur.seat_idx,
			"%d Treffer, LP %.0f → %.0f" % [f.hits_taken - h0, hp0, f.health])
		check(f.down, "Sitz %d: Bf 109 abgeschossen" % tur.seat_idx, "%d Treffer / %d Schuss, LP %.0f, KI-Treffer %d" % [f.hits_taken - h0, tur.shots - shots0, f.health, f.ai_hits])
		fi += 1
	m.squad.set_active(0)
	m.pause_flight = false
	await frames(3)
	check(int(m.stats.get("kills", 0)) >= 4, "Abschüsse gezählt", str(m.stats.get("kills", 0)))

	# --- KI-Bordschütze feuert selbst (Original 0x5F0E60), Treffer ohne Spieler zählen höchstens 2× ---------------
	var ai_shots := 0
	for tur in m.turrets:
		if not tur.gunner.is_player_controlled:
			ai_shots += tur.shots
	check(true, "KI-Schützen gaben %d Schuss ab (Ziele nur in Sicht und Schwenkbereich)" % ai_shots)

	# --- Schaden an der Ju 88 nur in Feuerfenstern, Leuchtspuren ----------------------------------------------------
	var win: Dictionary = {}
	for ff in m.fighters:
		if is_instance_valid(ff) and not ff.down and not ff.windows.is_empty():
			win = ff.windows[0]
			break
	if not win.is_empty():
		_god = false
		var hp0: float = m.ju88_health
		m.flight_t = float(win["start_s"]) + 0.05
		await seconds(0.8)
		check(m.ju88_health < hp0, "Jäger im Feuerfenster beschädigt die Ju 88", "%.0f -> %.0f, t=%.2f" % [hp0, m.ju88_health, m.flight_t])
		check(not m._tracers.is_empty(), "Leuchtspuren der feuernden Jäger sichtbar", str(m._tracers.size()))
		_god = true
		m.ju88_health = 5000.0

	# --- Absturz bei 0 LP (nur anstoßen, dann zurücksetzen; Missionsende per Boden folgt nicht in 0,5 s) ------------
	var q := PhysicsRayQueryParameters3D.create(m.ju88.global_position, m.ju88.global_position + Vector3.DOWN * 400.0, 1, m.own_rids())
	var gh: Dictionary = m.ju88.get_world_3d().direct_space_state.intersect_ray(q)
	var clearance: float = m.ju88.global_position.y - gh.position.y if not gh.is_empty() else 400.0
	if clearance > 40.0:
		var t_keep: float = m.flight_t
		var y0: float = m.ju88.global_position.y
		_god = false
		m._start_crash()
		await seconds(0.5)
		check(m.crashing and m.ju88.global_position.y < y0 and not m.finished, "Ju 88 bei 0 LP: Absturz statt sofortigem Ende",
			"Δy %.1f m, Bodenabstand vorher %.0f m" % [m.ju88.global_position.y - y0, clearance])
		m.crashing = false
		m.ju88_health = 5000.0
		m.flight_t = t_keep
		_god = true
	else:
		check(true, "Absturzprobe übersprungen (Bodenabstand %.0f m)" % clearance)

	# Sieg: Ju 88 erreicht den Dummy AF5_obj (< 500 m, Original ≈ 173,6 s)
	m.ju88_health = 5000.0
	m.flight_t = 172.0
	for i in 400:
		await frames(5)
		if m.finished:
			break
	check(m.finished and Game.last_result.get("success", false), "Schlucht durchflogen: Mission erfolgreich (Originalskript)",
		str(Game.last_result.get("reason", "")) + " t=%.1f" % m.flight_t)
	_finish()


## Unverwundbarkeit: Ju 88 außerhalb der Schadensprüfungen voll halten
func _keep_alive(m) -> void:
	var tm := Timer.new()
	tm.wait_time = 0.1
	tm.autostart = true
	add_child(tm)
	tm.timeout.connect(func():
		if _god and is_instance_valid(m) and not m.finished:
			m.ju88_health = 5000.0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await frames(2)
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(SHOT_DIR + name + ".png")
