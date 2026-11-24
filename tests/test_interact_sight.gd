extends Node
## Sichtlinie beim Benutzen (Interactable.sight_clear, PlayerController, Server Net._use).
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_interact_sight
## Je Waffenstellung der Karte: Punkt im Stollen darunter (Decke zwischen Soldat und Schützenplatz) → keine Besetzung;
## Gegenprobe normal davor auf der Oberfläche → Benutzen-Ziel ist die Stellung, Besetzen gelingt.
var failed := 0
var passed := 0
var m: Mission

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(400.0, true, false, true).timeout.connect(func():
		check(false, "Zeitlimit")
		_finish())

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	while not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
	await get_tree().physics_frame
	var pc = m.get("controller")
	var s: Soldier = pc.active if pc else null
	check(s != null, "aktiver Soldat vorhanden")
	if s == null:
		_finish()
		return
	var emps: Array = []
	for n in get_tree().get_nodes_in_group("emplacements"):
		if n is OrigInteractive.OrigEmplacement:
			emps.append(n)
	check(emps.size() >= 1, "Waffenstellungen: %d" % emps.size())
	var under_found := 0
	for e in emps:
		var spot: Vector3 = e.gunner_spot()
		var below := _tunnel_below(spot)
		if below.is_finite():
			under_found += 1
			s.global_position = below
			s.velocity = Vector3.ZERO
			s.look_yaw = _yaw_to(below, spot)
			await _settle(s, below)
			check(not Interactable.sight_clear(s, e), "%s: aus dem Stollen darunter keine Sichtlinie (%s → %s)" % [e.name, below, spot])
			pc._update_interact_target()
			check(pc.interact_target != e, "%s: aus dem Stollen kein Benutzen-Ziel" % e.name)
		# Gegenprobe: normal davor (Oberfläche, 1,2 m hinter dem Schützenplatz)
		var front := _front_point(e, spot)
		if front.is_finite():
			s.global_position = front
			s.velocity = Vector3.ZERO
			s.look_yaw = _yaw_to(front, spot)
			await _settle(s, front)
			check(Interactable.sight_clear(s, e), "%s: von davor Sichtlinie frei" % e.name)
			pc._update_interact_target()
			check(pc.interact_target == e, "%s: von davor Benutzen-Ziel (%s)" % [e.name, pc.interact_target])
			if pc.interact_target == e and e.can_interact(s):
				e.interact(s)
				check(s.mounted == e, "%s: von davor besetzt" % e.name)
				if s.mounted == e:
					e.interact(s)
					await get_tree().physics_frame
	check(under_found >= 1, "mindestens eine Stellung mit Stollen darunter geprüft (%d)" % under_found)
	_finish()

func _finish() -> void:
	print("ERGEBNIS test_interact_sight: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _settle(s: Soldier, p: Vector3) -> void:
	for i in 3:
		await get_tree().physics_frame
		s.global_position = p
		s.velocity = Vector3.ZERO

func _yaw_to(a: Vector3, b: Vector3) -> float:
	var to := b - a
	return atan2(-to.x, -to.z)

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return m.get_world_3d().direct_space_state.intersect_ray(q)

## Punkt im Stollen in Benutzen-Reichweite (waagrecht < 2,3 m) unter dem Schützenplatz: Boden darunter, Decke darüber
func _tunnel_below(spot: Vector3) -> Vector3:
	for r in [0.0, 0.6, 1.2, 1.8, 2.2]:
		for k in 16:
			var a := TAU * k / 16.0
			var x: float = spot.x + cos(a) * float(r)
			var z: float = spot.z + sin(a) * float(r)
			var top := _ray(Vector3(x, spot.y + 3.0, z), Vector3(x, spot.y - 10.0, z))
			if top.is_empty():
				continue
			var gy: float = top.position.y
			var fl := _ray(Vector3(x, gy - 0.3, z), Vector3(x, gy - 10.0, z))
			if fl.is_empty():
				continue
			var fy: float = fl.position.y
			var ce := _ray(Vector3(x, fy + 0.3, z), Vector3(x, gy + 0.5, z))
			if ce.is_empty() or ce.position.y - fy < 1.7 or ce.position.y > spot.y - 0.1:
				continue
			return Vector3(x, fy + 0.05, z)
	return Vector3.INF

func _front_point(e, spot: Vector3) -> Vector3:
	var fwd: Vector3 = (e.global_position - spot)
	fwd.y = 0
	var back := -fwd.normalized() if fwd.length() > 0.1 else Vector3.BACK
	for dist in [1.2, 1.6, 0.8]:
		for side in [0.0, 0.8, -0.8]:
			var p: Vector3 = spot + back * dist + Vector3(-back.z, 0, back.x) * side
			var h := _ray(p + Vector3.UP * 1.5, p + Vector3.DOWN * 2.0)
			if not h.is_empty():
				return h.position + Vector3.UP * 0.05
	return Vector3.INF
