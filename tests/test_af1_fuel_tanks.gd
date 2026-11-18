extends "res://tests/test_gameplay.gd"
## AFRICA1 Treibstofftanks (m_nadrz*, Modelle m_nadrz02/03, Akteur Typ 25 „Treibstofftanks“):
## Nutzermeldung „nur eine Textur, man kann durchlaufen“. Ursache: das Modell mischt undurchsichtige und alpha-getestete
## Materialien in EINEM Mesh → `OrigLevel._is_foliage` hielt das ganze Mesh für Laub → keine Kollision.
## Prüft: echtes 3D-Mesh, Kollision Ebene 1, Zerstörbarkeit (hit_proxy → OrigDestructible), Navmesh umgeht den Tank,
## Soldat läuft per Physik gegen den Tank und kommt nicht hindurch.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_af1_fuel_tanks
##   Fenster: tools\godot.cmd -- --mission=af1_spaghetti_airport --autoplay=test_af1_fuel_tanks --shots=1 --tag=_nachher
##     → test_output/a1_tanks_<n><tag>.png


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _tanks(m: Mission) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("destructibles"):
		var f = n.get("frame")
		if f is Node3D and String(f.get_meta("orig_model", "")).begins_with("m_nadrz") or (f is Node3D and String(f.name).to_lower().begins_with("m_nadrz")):
			if not out.has(f):
				out.append(f)
	return out


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000 * 1000:
		if mission() and mission().squad and mission().squad.leader() and mission().orig and mission().get("nav_ready"):
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null and m.orig != null, "AFRICA1 mit Originallevel geladen")
	if m == null or m.orig == null:
		_finish()
		return
	if m.get("runtime") != null:
		await seconds(2.0)
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
		await seconds(1.0)
		(m.get("runtime") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var lead: Soldier = m.squad.leader()
	lead.max_health = 1e9
	lead.health = 1e9
	var far := Vector3(5000, -900, 5000)
	for so in get_tree().get_nodes_in_group("soldiers"):
		if so == lead:
			continue
		for c in so.get_children():
			c.process_mode = Node.PROCESS_MODE_DISABLED
		(so as Node3D).global_position = far
		so.process_mode = Node.PROCESS_MODE_DISABLED
		far.x += 3.0
	# PlayerController überschreibt move_input jedes Physikbild aus der Tastatur → für die Laufprobe anhalten
	for pc in get_tree().root.find_children("*", "PlayerController", true, false):
		pc.set_physics_process(false)
	var tanks := _tanks(m)
	check(tanks.size() >= 5, "Treibstofftanks gefunden", str(tanks.size()))
	if tanks.is_empty():
		_finish()
		return
	var shots: bool = String(Game.cli.get("shots", "0")) == "1"
	var tag := String(Game.cli.get("tag", ""))
	var k := 0
	for t in tanks:
		k += 1
		var f := t as Node3D
		var meshes := f.find_children("*", "MeshInstance3D", true, false)
		var box := AABB()
		var first := true
		for mi in meshes:
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		check(not meshes.is_empty() and f.is_visible_in_tree() and box.size.y > 1.5 and minf(box.size.x, box.size.z) > 1.5,
			"%s: sichtbares 3D-Mesh" % f.name, str(box.size))
		var bodies := f.find_children("*", "StaticBody3D", true, false)
		var solid := 0
		var proxied := 0
		for b in bodies:
			if (b as StaticBody3D).collision_layer & 1:
				solid += 1
			if b.has_meta("hit_proxy"):
				proxied += 1
		check(solid > 0, "%s: Kollision Ebene 1" % f.name, str(bodies.size()))
		check(proxied == bodies.size() and proxied > 0, "%s: Treffer gehen an den zerstörbaren Akteur" % f.name, str(proxied))
		# Ab hier zählt der Kesselkörper = Hülle der Kollisionsformen (die Mesh-Hülle enthält Pumpe/Vordach daneben)
		var cfirst := true
		for b in bodies:
			for cs in (b as Node).get_children():
				if cs is CollisionShape3D and (cs as CollisionShape3D).shape:
					var sb: AABB = (cs as CollisionShape3D).global_transform * (cs as CollisionShape3D).shape.get_debug_mesh().get_aabb()
					if cfirst or sb.get_volume() > box.get_volume():   # größte Form = Kessel
						box = sb
					cfirst = false
		print("TANK %s Kollisionshülle %s" % [f.name, box])
		# Navmesh: Mittelpunkt des Tanks liegt nicht auf dem Netz (nächster Netzpunkt außerhalb der Grundfläche)
		var c := box.get_center()
		var map := m.get_world_3d().navigation_map
		var np := NavigationServer3D.map_get_closest_point(map, Vector3(c.x, box.position.y + 0.3, c.z))
		var inside := np.x > box.position.x + 0.4 and np.x < box.end.x - 0.4 and np.z > box.position.z + 0.4 \
			and np.z < box.end.z - 0.4 and np.y < box.position.y + 1.5     # Bodenhöhe im Tank (Oberseite zählt nicht)
		check(not inside, "%s: Navmesh umgeht den Tank" % f.name, "Netzpunkt %s, Tank %s" % [np, box])
		# Pfad von einer Längsseite zur anderen darf die Grundfläche nicht auf Bodenhöhe kreuzen
		var side := Vector3(1, 0, 0) if box.size.x < box.size.z else Vector3(0, 0, 1)
		var half := (box.size.x if side.x > 0 else box.size.z) * 0.5 + 1.5
		var pa := NavigationServer3D.map_get_closest_point(map, c - side * half + Vector3.DOWN * c.y)
		var pb := NavigationServer3D.map_get_closest_point(map, c + side * half + Vector3.DOWN * c.y)
		var path := NavigationServer3D.map_get_path(map, pa, pb, true)
		var crosses := false
		for i in range(1, path.size()):
			for s in 9:
				var q2: Vector3 = path[i - 1].lerp(path[i], s / 8.0)
				if q2.x > box.position.x + 0.3 and q2.x < box.end.x - 0.3 and q2.z > box.position.z + 0.3 \
						and q2.z < box.end.z - 0.3 and q2.y < box.position.y + 1.5:
					crosses = true
		check(path.size() >= 2 and not crosses, "%s: Bot-Pfad führt um den Tank herum" % f.name, "%d Punkte" % path.size())
		# Physik: Soldat 3 m vor dem Tank, läuft 3 s auf den Mittelpunkt zu
		var dir := Vector3(c.x - box.position.x, 0, 0).normalized() if box.size.x < box.size.z else Vector3(0, 0, 1)
		var start := Vector3(c.x, 0, c.z) - dir * (maxf(box.size.x, box.size.z) * 0.5 + 3.0)
		var h := get_tree().root.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(start + Vector3.UP * 10.0, start + Vector3.DOWN * 20.0, 1))
		if h.is_empty():
			check(false, "%s: Boden vor dem Tank" % f.name)
			continue
		start = h.position + Vector3.UP * 0.05
		lead.global_position = start
		lead.velocity = Vector3.ZERO
		lead.look_yaw = atan2(-dir.x, -dir.z)
		lead.move_input = dir
		for i in 180:
			await get_tree().physics_frame
		lead.move_input = Vector3.ZERO
		var q := lead.global_position
		var passed := (q - c).dot(dir) > 0.0
		var in_box := q.x > box.position.x + 0.3 and q.x < box.end.x - 0.3 and q.z > box.position.z + 0.3 and q.z < box.end.z - 0.3 \
			and q.y < box.end.y - 0.5
		check(Vector2(q.x - start.x, q.z - start.z).length() > 1.0, "%s: Soldat ist losgelaufen" % f.name, str(q))
		check(not passed and not in_box, "%s: Soldat läuft per Physik nicht durch den Tank" % f.name,
			"Start %s Ende %s Tank %s" % [start, q, box])
		if shots:
			lead.global_position = start - dir * 5.0
			lead.look_yaw = atan2(-dir.x, -dir.z)
			lead.look_pitch = -0.1
			await seconds(1.5)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var p := ProjectSettings.globalize_path("res://test_output/a1_tanks_%d%s.png" % [k, tag])
			img.save_png(p)
			print("SHOT ", p)
	# Zerstörbarkeit unverändert: erster Tank per Explosion zerstören → Kollision aus
	var d: Node = null
	for n in get_tree().get_nodes_in_group("destructibles"):
		if n.get("frame") == tanks[0]:
			d = n
	check(d != null, "Tank ist zerstörbarer Akteur (OrigDestructible)")
	if d:
		d.on_explosion(1e6, null)
		await seconds(0.5)
		var any_solid := false
		for b in (tanks[0] as Node3D).find_children("*", "StaticBody3D", true, false):
			any_solid = any_solid or ((b as StaticBody3D).collision_layer != 0)
		check(bool(d.get("destroyed")) and not any_solid, "Zerstörung schaltet die Kollision ab")
	_finish()
