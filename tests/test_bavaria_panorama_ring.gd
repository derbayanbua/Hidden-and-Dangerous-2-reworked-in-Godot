extends Node
## Umlaufende Fernkulisse als Ring (src/maps/bavaria/panorama_ring.gd).
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_panorama_ring
## Prüft: Ring vorhanden, ohne Kollision/Schatten/Navmesh, Radius größer als die Entfernung beider Blickfänge (inkl. Rauch),
## ganzer Ring innerhalb der Kamera-far von jedem Grenzpunkt, Himmelsstreifen abgeschaltet, Tageslicht übernommen.
## Ohne Panoramabilder (öffentlicher Stand) gibt es keinen Ring: dann nur die Gegenprobe „Himmel unverändert“.
var failed := 0
var passed := 0

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung (300 s)")
		_finish())

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS " if ok else "FAIL ", label)

func _finish() -> void:
	print("ERGEBNIS test_bavaria_panorama_ring: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	var ring = m.get("panorama_ring")
	var env: Environment = m.get_world_3d().environment if m.get_world_3d() else null
	var sky := env.sky.sky_material as ShaderMaterial if env and env.sky else null
	if sky == null or sky.get_shader_parameter("far_enabled") != true:   # null ohne lokale Bilder
		check(ring == null, "ohne Panoramabilder kein Ring")
		_finish()
		return
	check(ring != null and ring.get_parent() == m and ring.is_in_group("bavaria_panorama_ring"), "Ring vorhanden, Kind der Mission")
	if ring == null:
		_finish()
		return
	var coll: int = ring.find_children("*", "CollisionObject3D", true, false).size() + ring.find_children("*", "CollisionShape3D", true, false).size()
	check(coll == 0 and not (ring is CollisionObject3D), "keine Kollision (%d)" % coll)
	check(m.static_root == null or not m.static_root.is_ancestor_of(ring), "nicht unter static_root (Navmesh/PerfTuning)")
	check(ring.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ohne Schatten")
	check(ring.mesh.get_surface_count() == 1, "eine Oberfläche = ein Zeichenaufruf")
	check(bool(sky.get_shader_parameter("ring_active")), "Himmelsstreifen abgeschaltet (ring_active)")
	var c: Vector2 = ring.center
	var r: float = ring.RADIUS
	# --- Ring hinter beiden Blickfängen (alle Ecken + Rauch-AABB) ---
	for lm in [m.get("landmark"), m.get("factory_landmark")]:
		if lm == null:
			continue
		var maxr := 0.0
		for mi in (lm as Node).find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var w: Vector3 = (mi as MeshInstance3D).global_transform * v
					if w.y > -0.2:          # sichtbare Teile (Geländeschürzen unter dem Außenboden zählen nicht)
						maxr = maxf(maxr, Vector2(w.x, w.z).distance_to(c))
		for p in (lm as Node).find_children("*", "GPUParticles3D", true, false):
			var box: AABB = (p as GPUParticles3D).global_transform * (p as GPUParticles3D).visibility_aabb
			var mid := box.get_center()
			maxr = maxf(maxr, Vector2(mid.x, mid.z).distance_to(c))
		check(r > maxr, "Ring (%.0f m) hinter %s (%.0f m)" % [r, (lm as Node).name, maxr])
	# --- innerhalb der Kamera-far von jedem Grenzpunkt ---
	var far: float = m.VIEW_FAR
	var maxd := 0.0
	for q in m.boundary:
		var eye := Vector3(q.x, 1.7, q.y)
		for k in 64:
			var a := TAU * k / 64.0
			for y in [-8.0, ring.top_y()]:
				maxd = maxf(maxd, eye.distance_to(Vector3(c.x + cos(a) * r, y, c.y + sin(a) * r)))
	check(maxd < far, "ganzer Ring innerhalb der Kamera-far (%.0f < %.0f m)" % [maxd, far])
	var cam := get_viewport().get_camera_3d()
	check(cam == null or cam.far <= far + 0.1, "Kamera-far ≤ VIEW_FAR (%.0f)" % (cam.far if cam else 0.0))
	# --- Tag/Nacht übernommen ---
	m.day_night.set_hour(12.0, 0.0)
	await get_tree().create_timer(0.7).timeout
	var d_day := float(ring.material.get_shader_parameter("daylight"))
	m.day_night.set_hour(0.5, 0.0)
	await get_tree().create_timer(0.7).timeout
	var n_night := float(ring.material.get_shader_parameter("night"))
	check(d_day > 0.9 and n_night > 0.9, "Tageslicht/Nacht vom Zyklus übernommen (Tag %.2f, Nacht %.2f)" % [d_day, n_night])
	_finish()
