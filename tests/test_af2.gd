extends "res://tests/test_gameplay.gd"
## 0.11.9 AFRICA2 (af2_flugschau) – Nutzerbefund „Strecke schlecht sichtbar, Flugzeuge greifen zu viel an, Gegner fehlen,
## Teamkameraden nutzen die Fahrzeugwaffen nicht“ (Status docs/status/b0119_af2.md):
##   tools\godot.cmd --headless -- --mission=af2_flugschau --autoplay=test_af2
## Prüft:
##   1. Gegnerbestand: jeder Mensch-Akteur aus actors.bin (Typ 3) ist als Figur da, sichtbar, Seite Gegner; Leichen
##      (AF2_mrtvola.scr → HUMAN_Kill) tot; Panzerbesatzung (HUMAN_BoardVehicle Panzer01) im Panzer.
##   2. Trupp im Fahrzeug (Cutscene HUMAN_BoardVehicle): ein Kamerad sitzt auf dem Bordwaffensitz (Jeep S1 Browning,
##      Opel S2 Flak 38); Vorgabe [D]: vor dem ersten Befehl kein Feuer (Startsperre), nach Taste K (toggle_roe)
##      feuert er vom Sitz; Freigabe bleibt beim Umsteigen erhalten.
##   3. AirAttack: Wenderate 0,4 rad/s (hd2.exe 0x5E5960 → 0x5E7550(±_DAT_0080f554 = 0,4)) [B].
## Unverwundbarkeit: alle Truppmitglieder max_health 100000.


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission() as OrigMission
	check(m != null and m.runtime != null, "AFRICA2 geladen", Game.current_mission_id)
	if m == null:
		_finish()
		return
	var rt := m.runtime
	rt.auto_skip = true
	for s in m.squad.members:
		s.max_health = 100000.0
		s.health = s.max_health
	# Cutscene laufen lassen (sie setzt den Trupp per HUMAN_BoardVehicle ins Fahrzeug), dann überspringen
	await seconds(3.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	await seconds(3.0)
	for s in m.squad.members:
		s.max_health = 100000.0
		s.health = s.max_health
	_census(m)
	await _gunner(m)
	await _plane_turn(m)
	await _after_curve(m)
	_finish()


## 4. Gegner nach der ersten Kurve (MG-Nest AF2_14/AF2_15 mit w_mg42Crouch_01, Beobachter AF2_13 auf der Düne):
## Original AF2_15.scr: _PlayerInRange(300) → aktiv; OnAlarm → HUMAN_Move("AF2_kulomet01") + HUMAN_BoardVehicle(MG, 1, 0).
## AF2_13.scr: _PlayerInRange(300) → Fernglas; OnAlarm → läuft AF2_13_01/02, Signal 1/5 an af2_activator.
func _after_curve(m: OrigMission) -> void:
	var rt := m.runtime
	var e15: Soldier = rt.actors.get("AF2_15")
	var e14: Soldier = rt.actors.get("AF2_14")
	var e13: Soldier = rt.actors.get("AF2_13")
	var mg = rt.actors.get("W_MG42CROUCH_01")
	check(e15 != null and e14 != null and e13 != null and mg != null, "MG-Nest nach der Kurve: AF2_13/14/15 + MG 42 vorhanden")
	if e15 == null or mg == null:
		return
	var lead := m.squad.leader()
	var veh: Vehicle = lead.vehicle
	# Trupp (im Fahrzeug) ~110 m vor das MG-Nest, Richtung Spielerstart
	var nest := e15.global_position
	var away := Vector3(1, 0, 0.45).normalized()
	var p := nest + away * float(Game.cli.get("curve_dist", "60"))
	var sp := lead.get_world_3d().direct_space_state
	var g := sp.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 300.0, p + Vector3.DOWN * 300.0, 1))
	if not g.is_empty():
		p = g.position
	if veh:
		veh.linear_velocity = Vector3.ZERO
		veh.angular_velocity = Vector3.ZERO
		veh.global_position = p + Vector3.UP * 1.5
		veh.look_at(nest, Vector3.UP)
	else:
		lead.global_position = p + Vector3.UP * 0.5
	# Trupp hält das Feuer (nur das Gegnerverhalten wird geprüft)
	for s in m.squad.members:
		var sb2 := m.squad.brain_of(s)
		if sb2:
			sb2.roe = SquadBrain.ROE.HOLD_FIRE
			sb2.enabled = false
			s.trigger = false
	var shots := {"AF2_15": 0, "AF2_14": 0, "AF2_13": 0}
	for nm in shots.keys():
		var s: Soldier = rt.actors.get(nm)
		s.shot_fired.connect(func(_w): shots[nm] += 1)
	var active := false
	var mounted := false
	var moved_front := false
	for i in 60 * 60:      # 60 s
		await get_tree().physics_frame
		for s in m.squad.members:
			s.health = s.max_health
		var b15 := e15.get_node("EnemyBrain") as EnemyBrain
		if b15 and not b15.suspended:
			active = true
		if e15.mounted != null:
			mounted = true
		if mounted and shots["AF2_15"] > 0:
			break
		# Stellung besetzt: Trupp in den Richtbereich vor das MG (Original-Sichtkegel ±50° um die Waffe)
		if mounted and not moved_front and e15.mounted.has_method("barrel_dir"):
			moved_front = true
			var bd: Vector3 = e15.mounted.barrel_dir()
			bd.y = 0.0
			var q: Vector3 = nest + bd.normalized() * 60.0
			var g2 := sp.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 300.0, q + Vector3.DOWN * 300.0, 1))
			if not g2.is_empty():
				q = g2.position
			if veh:
				veh.linear_velocity = Vector3.ZERO
				veh.global_position = q + Vector3.UP * 1.5
			print("AF2 Kurve: Trupp vor das MG bei %s" % q.round())
	for nm in ["AF2_13", "AF2_14", "AF2_15"]:
		var s: Soldier = rt.actors.get(nm)
		var b := s.get_node("EnemyBrain") as EnemyBrain
		print("AF2 Kurve %s lebt=%s ruht=%s zustand=%s skript=%s stellung=%s schuss=%d pos=%s ziel=%s waffe=%s ergeben=%s illfire=%.1f an=%s" % [nm, s.alive, b.suspended,
			b.state_name(), b.script_control, str(s.mounted.name) if s.mounted else "-", shots[nm], s.global_position.round(),
			str(b.perception.best_target().name) if b.perception.best_target() else "-",
			str(s.current_weapon().data.id) if s.current_weapon() else "-", b.surrendered, b._ill_fire_t, b.enabled])
		print("AF2 Kurve %s Angreifer=%s Ursache=%s" % [nm, str(s.last_attacker.name) if is_instance_valid(s.last_attacker) else "-",
			str(s.get("last_cause"))])
	if e15.alive:
		var per15: Perception = e15.get_node("Perception")
		var crew: Soldier = m.squad.members[1]
		var eye := e15.eye_position()
		var tp := crew.global_position + Vector3.UP * 1.2
		var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(eye, tp, 1, [e15.get_rid()]))
		print("AF2 Kurve Sicht AF2_15→%s: d=%.0f winkel=%.0f° sicht=%s bewusst=%.2f reach=%.0f LOS-Treffer=%s orig=%s" % [crew.name,
			eye.distance_to(tp), rad_to_deg(e15.aim_direction().angle_to(tp - eye)), per15.visible_now.get(crew, false),
			float(per15.awareness.get(crew, 0.0)), per15.orig_visibility_distance(crew) if per15.orig_formula else per15.sight_range,
			str(hit.get("collider").get_path()) if not hit.is_empty() else "-", per15.orig_formula])
	check(active, "AF2_15 wird bei Annäherung aktiv (_PlayerInRange(300))")
	check(mounted, "AF2_15 besetzt nach Alarm das MG 42 (HUMAN_BoardVehicle w_mg42Crouch_01)")
	check(shots["AF2_15"] > 0, "AF2_15 feuert vom MG 42 auf den Trupp", "%d Schuss" % shots["AF2_15"])
	if String(Game.cli.get("shots", "0")) == "1":
		await seconds(0.5)
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://test_output/af2_kurve_mgnest.png")
		print("SHOT test_output/af2_kurve_mgnest.png")


## 1. Gegnerbestand gegen actors.bin
func _census(m: OrigMission) -> void:
	var humans := 0
	var present := 0
	var visible := 0
	var corpses_dead := 0
	var corpses := 0
	var missing: Array = []
	for a in m.orig.actors:
		if int(a.get("actor_type", -1)) != 3 or String(a.get("model", "")) == "":
			continue
		var nm := String(a.get("name", ""))
		humans += 1
		var s = m.runtime.actors.get(nm.to_upper())
		if not (s is Soldier) or not is_instance_valid(s):
			missing.append(nm)
			continue
		present += 1
		var so := s as Soldier
		if so.is_visible_in_tree() and (so.model == null or so.model.visible or so.vehicle != null):
			visible += 1
		else:
			print("AF2 unsichtbar: %s pos %s" % [nm, so.global_position])
		var sc := String(m.orig.scripts.get(nm, "")) if "scripts" in m.orig else ""
		if nm.begins_with("AF2_m0"):
			corpses += 1
			if not so.alive:
				corpses_dead += 1
		print("AF2 Gegner %s lebt=%s team=%d fahrzeug=%s pos=%s %s" % [nm, so.alive, so.team,
			so.vehicle.name if so.vehicle else "-", so.global_position.round(), sc])
	check(humans == 32 and present == humans, "alle Mensch-Akteure aus actors.bin gespawnt", "%d/%d fehlen %s" % [present, humans, str(missing)])
	check(visible == present, "alle Gegnerfiguren sichtbar (oder im Panzer)", "%d/%d" % [visible, present])
	check(corpses == 5 and corpses_dead == 5, "Leichen AF2_m01–m05 tot (AF2_mrtvola.scr HUMAN_Kill)", "%d/%d" % [corpses_dead, corpses])
	var tank = m.runtime.actors.get("PANZER01")
	var crew := 0
	if tank is Vehicle:
		for o in (tank as Vehicle).occupants:
			if is_instance_valid(o):
				crew += 1
	check(crew == 3, "Panzer01: Besatzung tank1_01..03 an Bord", "%d" % crew)


## 2. Bordschütze im Truppfahrzeug feuert ohne Befehl
func _gunner(m: OrigMission) -> void:
	var gunner: Soldier = null
	var veh: Vehicle = null
	for s in m.squad.members:
		print("AF2 Trupp %s fahrzeug=%s sitz=%d waffe=%s" % [s.soldier_name, s.vehicle.name if s.vehicle else "-", s.seat_index,
			s.vehicle.seat_weapon(s.seat_index).data.id if s.vehicle and s.vehicle.seat_weapon(s.seat_index) else "-"])
		if s.vehicle and s.seat_index > 0 and s.vehicle.seat_weapon(s.seat_index) != null and s != m.controller.active:
			gunner = s
			veh = s.vehicle
	check(gunner != null, "Kamerad auf dem Bordwaffensitz (Cutscene HUMAN_BoardVehicle)")
	if gunner == null:
		return
	var sb := m.squad.brain_of(gunner) as SquadBrain
	print("AF2 Schütze %s Sitz %d awaiting_order=%s roe=%d order=%d" % [gunner.soldier_name, gunner.seat_index, sb.awaiting_order, sb.roe, sb.order])
	# Ziel: Gegner AF2_12 vor das Fahrzeug stellen (Gegner-KI aus, er soll nur Ziel sein)
	var e: Soldier = m.runtime.actors.get("AF2_12")
	check(e != null, "Zielgegner AF2_12 vorhanden")
	if e == null:
		return
	var eb := e.get_node_or_null("EnemyBrain") as EnemyBrain
	if eb:
		eb.enabled = false
	var w := veh.seat_weapon(gunner.seat_index)
	# Zielplatz im Sichtfeld des Schützen (Blickrichtung = Bordwaffe, Kegel ±50°)
	var fwd := gunner.aim_direction()
	print("AF2 Schütze Blick %s Fahrzeug vorn %s" % [fwd, -veh.global_basis.z])
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best := Vector3.INF
	var sp := veh.get_world_3d().direct_space_state
	for d in [45.0, 35.0, 60.0, 25.0]:
		for ang in [0.0, 0.3, -0.3, 0.6, -0.6]:
			var p: Vector3 = veh.global_position + fwd.rotated(Vector3.UP, ang) * d
			var g := sp.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 200.0, p + Vector3.DOWN * 200.0, 1))
			if g.is_empty():
				continue
			var gp: Vector3 = g.position
			var los := sp.intersect_ray(PhysicsRayQueryParameters3D.create(gunner.eye_position(), gp + Vector3.UP * 1.3, 1,
				[veh.get_rid()]))
			if los.is_empty():
				best = gp
				break
		if best.is_finite():
			break
	check(best.is_finite(), "freie Sicht vom Bordschützen zu einem Zielplatz")
	if not best.is_finite():
		return
	e.global_position = best + Vector3.UP * 0.1
	e.velocity = Vector3.ZERO
	var shots0 := w.total_ammo() + w.in_mag
	var mag0 := w.in_mag
	# Vorgabe [D] 0.11.9: vor dem ersten Befehl schießt auch der Bordschütze nicht (Startsperre awaiting_order)
	var last_pre := gunner.last_shot_time
	var seen_pre := false
	for i in 480:      # 8 s
		await get_tree().physics_frame
		gunner.health = gunner.max_health
		if sb.perception.best_target() == e:
			seen_pre = true
	check(seen_pre and gunner.last_shot_time == last_pre and sb.awaiting_order,
		"Bordschütze sieht den Gegner, schießt aber nicht vor dem ersten Befehl (Startsperre)",
		"gesehen=%s schuss=%s await=%s" % [seen_pre, gunner.last_shot_time != last_pre, sb.awaiting_order])
	# Befehl wie Taste K (Feuer frei/halten umschalten) → Freigabe
	m.squad.toggle_roe()
	check(not sb.awaiting_order and sb.roe == SquadBrain.ROE.FIRE_AT_WILL, "Taste K: Feuer frei, Startsperre aufgehoben")
	# Freigabe bleibt beim Umsteigen erhalten
	var seat0 := gunner.seat_index
	var free := veh.free_seat()
	if free > 0 and veh.switch_seat(gunner, free):
		await frames(2)
		veh.switch_seat(gunner, seat0)
		await frames(2)
	check(gunner.vehicle == veh and gunner.seat_index == seat0 and not sb.awaiting_order and sb.roe == SquadBrain.ROE.FIRE_AT_WILL,
		"Freigabe bleibt beim Umsteigen erhalten", "Sitz %d, await=%s" % [gunner.seat_index, sb.awaiting_order])
	var fired := false
	var last0 := gunner.last_shot_time
	for i in 900:      # 15 s
		await get_tree().physics_frame
		gunner.health = gunner.max_health
		if gunner.last_shot_time != last0:
			fired = true
			break
	print("AF2 Schütze: Ziel %s Abstand %.0f m, Magazin %d→%d, Wahrnehmung %s sicht=%s bewusst=%.2f reichweite=%.0f" % [best.round(),
		gunner.global_position.distance_to(best), mag0, w.in_mag,
		str(sb.perception.best_target().name if sb.perception.best_target() else "-"), str(sb.perception.visible_now.get(e, false)),
		float(sb.perception.awareness.get(e, 0.0)), sb.perception.sight_range])
	check(fired, "Kamerad feuert nach dem Befehl die Bordwaffe (%s) vom Sitz auf sichtbaren Gegner" % w.data.id, "Munition %d→%d" % [shots0, w.total_ammo() + w.in_mag])
	e.global_position += Vector3.DOWN * 500.0    # aus dem Weg
	if eb:
		eb.enabled = true


## 3. Wenderate des angreifenden Flugzeugs (Phase 1)
func _plane_turn(m: OrigMission) -> void:
	var plane: Node3D = m.runtime.actors.get("MES04")
	check(plane != null and plane.has_method("set_air_target"), "mes04 als AirAttack-Akteur")
	if plane == null:
		return
	plane.visible = true
	plane.global_position = m.squad.leader().global_position + Vector3(0, 120, 0) - Vector3(1, 0, 0) * 600.0
	plane.dir = Vector3(-1, 0, 0)       # vom Ziel weg
	plane._dir_init = true
	plane.set_air_target(m.squad.leader(), true)
	plane.state = 1                     # Anflug: Kurve zum Ziel
	await get_tree().physics_frame
	var h0 := Vector3(plane.dir.x, 0, plane.dir.z).normalized()
	await seconds(1.0)
	var h1 := Vector3(plane.dir.x, 0, plane.dir.z).normalized()
	var rate := absf(h0.signed_angle_to(h1, Vector3.UP))
	check(absf(rate - 0.4) < 0.06, "AirAttack Wenderate 0,4 rad/s wie hd2.exe (_DAT_0080f554)", "%.2f rad/s" % rate)
	plane.set_air_target(null, false)
