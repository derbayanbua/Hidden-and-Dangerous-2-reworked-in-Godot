extends Node
## Kontrollbilder der Testkarte Castle (Fenster, kein --headless):
## tools/godot.cmd -- --mission=castle --autoplay=screenshots_castle [--shots=overview,hof_a,...]
## Platzhalter: test_output/castle_overview.png. Echte Burg zusätzlich: Höfe A–F auf Augenhöhe, Wehrgang, Tor,
## Turmplattform, Brücke → test_output/castle/*.png


func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func(): get_tree().quit(1))


func _shot(cam: Camera3D, name: String, pos: Vector3, target: Vector3, fov := 65.0) -> bool:
	cam.global_position = pos
	if pos.distance_to(target) > 0.01:
		cam.look_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.98 else Vector3.FORWARD)
	cam.fov = fov
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://test_output/%s.png" % name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var ok := img.save_png(path) == OK
	print("SHOT ", path, " ", ok)
	# Prüfhilfe: --probe=<bild>:x,y;x,y (Pixel im 1280×720-Bild) → Physiktreffer und sichtbare Knoten auf dem Strahl
	var pr := String(Game.cli.get("probe", ""))
	if pr.begins_with(name.get_file() + ":"):
		var vp := get_viewport().get_visible_rect().size
		for px in pr.substr(name.get_file().length() + 1).split(";"):
			var xy := px.split_floats(",")
			var sp := Vector2(xy[0] / 1280.0 * vp.x, xy[1] / 720.0 * vp.y)
			var o := cam.project_ray_origin(sp)
			var d := cam.project_ray_normal(sp)
			var hit := cam.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + d * 200.0, 0xFFFFFFFF))
			print("PROBE ", px, " Treffer ", (str(hit.collider.get_path()) + " @%.1f m" % o.distance_to(hit.position)) if not hit.is_empty() else "-")
			for gi in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
				var g := gi as GeometryInstance3D
				if not g.is_visible_in_tree():
					continue
				var bb := g.global_transform * g.get_aabb()
				if bb.size.length() > 120.0:
					continue
				var seg = bb.intersects_segment(o, o + d * 60.0)
				if seg != null:
					print("   SICHTBAR ", g.get_path(), " %s Abstand %.1f m" % [g.get_class(), o.distance_to(seg)])
	return ok


func _run() -> void:
	var m: Mission
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	while not m.nav_ready:
		await get_tree().create_timer(0.2).timeout
	if m.hud:
		m.hud.visible = false
	for s in m.squad.members if m.squad else []:
		s.visible = false
	var cam := Camera3D.new()
	cam.set_meta("b041_keep_far", true)
	cam.far = 4000.0
	m.add_child(cam)
	cam.make_current()
	var ok := 0
	var total := 0
	var only: Array = String(Game.cli.get("shots", "")).split(",", false)
	var r = m.get("real")
	if r == null:
		total += 1
		if await _shot(cam, "castle_overview", Vector3(0, 150, 170), Vector3(0, 0, -10), 55.0):
			ok += 1
	else:
		var list: Array = []   # [Name, Position, Ziel, FOV]
		var bb: Rect2 = m.bounds()
		var c := bb.get_center()
		list.append(["castle/overview", Vector3(c.x + 420, 260, c.y + 120), Vector3(c.x, 0, c.y), 50.0])
		list.append(["castle/overview_north", Vector3(c.x + 60, 140, bb.position.y - 120), Vector3(c.x, 0, c.y - 150), 55.0])
		list.append(["castle/overview_south", Vector3(c.x - 40, 120, bb.end.y + 90), Vector3(c.x + 40, 0, c.y + 200), 55.0])
		var zones: Array = m.all_zones() if m.has_method("all_zones") else m.mp_zones()
		for z in zones:
			var p: Vector3 = z.xf.origin
			var letter := String(z.name).substr(5, 1).to_lower() if String(z.name).begins_with("zone_") else String(z.text).substr(0, 1).to_lower()
			list.append(["castle/hof_" + letter, p + Vector3(0, 0.9, 0), p + Vector3(0, 0.9, 0) + Vector3(0.3, -0.05, -1.0), 70.0])
			# Eroberung: Zonenmarke (Mast, Flagge, Name, Eckpfosten) schräg von oben aus einer Ecke des Quaders
			if m.occupation():
				var xf: Transform3D = z.xf
				var sc: Vector3 = z.scale if String(z.shape) == "box" else Vector3(24, 10, 24)
				# Kamera: erste Ecke/Höhe mit freiem Augpunkt und freier Sicht auf den Mast (Ebene 1) – in kleinen Höfen
				# (Hauptburg F) lag die feste Ecke sonst hinter der Hofmauer bzw. über dem Graben
				var space := m.get_world_3d().direct_space_state
				var look := p + Vector3(0, 1.0, 0)
				var eye := Vector3.INF
				for cu in [Vector2(0.65, -0.65), Vector2(-0.65, -0.65), Vector2(0.65, 0.65), Vector2(-0.65, 0.65), Vector2(0.4, -0.4),
						Vector2(-0.4, 0.4), Vector2(0.4, 0.4), Vector2(-0.4, -0.4), Vector2(0.25, -0.25), Vector2(-0.25, 0.25)]:
					var e3: Vector3 = xf * Vector3(sc.x * cu.x, 0, sc.z * cu.y)
					if not (m.inside_map(e3) and r.boundary_dist(Vector2(e3.x, e3.z)) > 4.0 and not r.in_building(Vector2(e3.x, e3.z), 1.0)):
						continue
					for hgt in [7.0, 5.0, 3.5]:
						var cand := Vector3(e3.x, m.ground_y(e3.x, e3.z) + hgt, e3.z)
						var ray := PhysicsRayQueryParameters3D.create(cand, look, 1)
						if space.intersect_ray(ray).is_empty():
							eye = cand
							break
					if eye != Vector3.INF:
						break
				if eye == Vector3.INF:   # Rückfall: über dem Mast schräg von oben
					eye = p + (xf.basis * Vector3(sc.x * 0.2, 0, -sc.z * 0.2)) + Vector3.UP * 12.0
				list.append(["castle/zone_" + letter, eye, look, 70.0])
		# DM/TDM: innere Grenze – verrammeltes Tor C|D von der Spielfläche aus, Grenzlinie von oben
		if not r.inner_gate.is_empty():
			var gp: Vector3 = r.inner_gate.pos
			var out: Vector3 = r.inner_gate.out
			var side := Vector3(-out.z, 0, out.x)
			var e1 := gp + out * 11.0 + side * 2.5
			list.append(["castle/innere_grenze_tor", Vector3(e1.x, m.ground_y(e1.x, e1.z) + 1.7, e1.z), gp + Vector3.UP * 1.6, 70.0])
			var e2 := gp + out * 35.0 + side * 18.0
			list.append(["castle/innere_grenze_oben", Vector3(e2.x, gp.y + 28.0, e2.z), gp - out * 10.0, 60.0])
		for sec in ["B"]:
			var cand: Array = r._candidates([sec], 6.0, 8.0)
			if not cand.is_empty():
				var p2: Vector2 = cand[cand.size() / 2]
				var y: float = m.ground_y(p2.x, p2.y) + 1.7
				list.append(["castle/hof_b", Vector3(p2.x, y, p2.y), Vector3(p2.x + 0.2, y - 0.1, p2.y - 1.0), 70.0])
		if not r.kit.walk_points.is_empty():
			var w: Vector3 = r.kit.walk_points[r.kit.walk_points.size() / 3]
			var w2: Vector3 = r.kit.walk_points[r.kit.walk_points.size() / 3 + 3]
			list.append(["castle/wehrgang", w + Vector3.UP * 1.7, w2 + Vector3.UP * 1.5, 70.0])
			# Prüfhilfe: nächste Gebäude am Wehrgangbild
			for i in r.buildings.footprints.size():
				var dd: float = r.buildings.dist_to_poly(Vector2(w.x, w.z), r.buildings.footprints[i])
				if dd < 12.0:
					print("WEHRGANG_NAEHE ", r.buildings.ids[i], " %.1f m" % dd)
		if not r.kit.stairs_at.is_empty():
			var s: Vector3 = r.kit.stairs_at[0]
			list.append(["castle/treppe", s + Vector3(4, 2.5, 4), s + Vector3(0, -2, 0), 70.0])
		# Tore/Durchgänge: Kamera auf der Durchgangsachse 6 m vor dem Eingang, Blick durch den Durchgang
		var space := m.get_world_3d().direct_space_state
		var floor_at := func(q: Vector2, top: float) -> float:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q.x, top, q.y), Vector3(q.x, top - 30.0, q.y), 1))
			return hit.position.y if not hit.is_empty() else m.ground_y(q.x, q.y)
		var k := 0
		for pas in r.buildings.passages:
			var pc: Vector2 = pas.center
			var dir: Vector2 = pas.dir
			var top: float = maxf(pas.h0, pas.h1) + 3.0
			var name := "castle/durchgang_%d_%s" % [k, String(pas.building).get_slice("_", 0)]
			for d in r.dividers:
				if (d.gate as Vector2).distance_to(pc) < 0.1:
					name = "castle/tor_" + String(d.name).replace("|", "")
			var a: Vector2 = pc + dir * (float(pas.t0) - 6.0)
			var b: Vector2 = pc + dir * (float(pas.t1) + 6.0)
			list.append([name, Vector3(a.x, floor_at.call(a, top) + 1.7, a.y), Vector3(b.x, floor_at.call(b, top) + 1.5, b.y), 70.0])
			k += 1
		for i in r.kit.gate_points.size():
			var gp: Vector3 = r.kit.gate_points[i]
			var ax: Vector3 = r.kit.gate_axes[i] if i < r.kit.gate_axes.size() else Vector3.FORWARD
			if r.buildings.passages.any(func(p): return (p.center as Vector2).distance_to(Vector2(gp.x, gp.z)) < 0.1):
				continue
			var a3 := gp - ax * 10.0
			var b3 := gp + ax * 10.0
			list.append(["castle/tor_bausatz_%d" % i, Vector3(a3.x, m.ground_y(a3.x, a3.z) + 1.7, a3.z), Vector3(b3.x, m.ground_y(b3.x, b3.z) + 1.5, b3.z), 70.0])
		for i in r.kit.closed_gates.size():
			var gp: Vector3 = r.kit.closed_gates[i]
			var bc: Vector2 = m.bounds().get_center()
			var inward := Vector3(bc.x - gp.x, 0, bc.y - gp.z).normalized()
			var p3 := gp + inward * 14.0
			list.append(["castle/aussentor_%d" % i, Vector3(p3.x, m.ground_y(p3.x, p3.z) + 1.7, p3.z), gp + Vector3.UP * 2.0, 70.0])
		var got := {}
		for tw in r.kit.towers:
			var bs: Basis = tw.basis
			var o: Vector3 = tw.pos
			if tw.get("spiral", false) and not got.has("w"):
				got["w"] = true
				list.append(["castle/turm_wendeltreppe", o + bs * Vector3(-2.6, 1.7, -2.6), o + bs * Vector3(1.0, 1.6, 0.8), 85.0])
			elif tw.stairs and not tw.get("spiral", false) and not got.has("s"):
				got["s"] = true
				list.append(["castle/turm_treppe", o + bs * Vector3(2.4, 1.7, -2.4), o + bs * Vector3(-1.0, 2.6, 2.6), 80.0])
		if not r.garden.is_empty():
			var gc := Vector3.ZERO
			for g in r.garden:
				gc += g.pos
			gc /= r.garden.size()
			# Kamera auf der Hofseite (Richtung Abschnittsmitte), 3 m über dem Gelände
			var sc: Vector2 = Vector2.ZERO
			for q in r.sections["B"]:
				sc += q
			sc /= (r.sections["B"] as PackedVector2Array).size()
			var away := (Vector2(gc.x, gc.z) - sc).normalized() * -14.0
			var cp := Vector2(gc.x, gc.z) + away
			list.append(["castle/garten", Vector3(cp.x, m.ground_y(cp.x, cp.y) + 3.0, cp.y), gc + Vector3(0, 0.8, 0), 70.0])
		if r.cover.size() > 3:
			var cv: Vector3 = r.cover[3]
			list.append(["castle/deko", cv + Vector3(7, 2.2, 5), cv + Vector3(0, 0.6, 0), 65.0])
		if not r.kit.towers.is_empty():
			var t: Dictionary = r.kit.towers[0]
			list.append(["castle/turm_aussen", t.door + (t.door - t.pos).normalized() * 12.0 + Vector3.UP * 3.0, t.pos + Vector3.UP * 7.0, 70.0])
			list.append(["castle/turm_oben", t.top + Vector3.UP * 1.7, t.top + Vector3.UP * 1.0 + (t.pos - t.door).normalized() * -20.0, 75.0])
		for i in r.bridges.size():
			var br: Dictionary = r.bridges[i]
			var mid: Vector3 = (br.a + br.b) * 0.5
			var dir3: Vector3 = (br.b - br.a).normalized()
			var side := Vector3(-dir3.z, 0, dir3.x)
			list.append(["castle/bruecke_%d" % i, mid + side * 25.0 + Vector3.UP * 4.0, mid, 60.0])
		# Hofausstattung (castle_dressing): Außentreppe der Hauptburg, Baumpark, Grabenzaun
		var dr = r.dressing
		for i in dr.stairs.size():
			var st: Dictionary = dr.stairs[i]
			# Kamera vor der Wand auf der Hofseite (Wandnormale n), schräg versetzt, Augenhöhe über dem Fuß
			var sn: Vector3 = st.n
			var sm: Vector3 = st.mid
			var along3 := Vector3(-sn.z, 0, sn.x)
			var tgt: Vector3 = sm + sn * 1.0 + Vector3.UP * 1.8
			var sspace := get_viewport().find_world_3d().direct_space_state
			var stair_cam := Vector3.INF
			for dist in [9.0, 7.0, 11.0, 5.5, 13.0]:
				for off in [-3.0, 3.0, 0.0, -6.0, 6.0]:
					if stair_cam != Vector3.INF:
						break
					var sep: Vector3 = sm + sn * dist - along3 * off
					var spos := Vector3(sep.x, maxf(m.ground_y(sep.x, sep.z), sm.y) + 1.7, sep.z)
					var srq := PhysicsRayQueryParameters3D.create(spos, tgt)
					srq.collision_mask = 1
					var shot_hit := sspace.intersect_ray(srq)
					if shot_hit.is_empty() or (shot_hit.position as Vector3).distance_to(tgt) < 1.5:
						stair_cam = spos
			if stair_cam == Vector3.INF:
				var sep2: Vector3 = sm + sn * 9.0
				stair_cam = Vector3(sep2.x, sm.y + 4.0, sep2.z)
			list.append(["castle/aussentreppe_%d" % i, stair_cam, tgt, 75.0])
		if dr.trees.size() > 0:
			var sec0: String = r.section_of(Vector2(dr.trees[0].x, dr.trees[0].z))
			var tc := Vector3.ZERO
			var tn := 0
			for t in dr.trees:
				if r.section_of(Vector2(t.x, t.z)) == sec0:
					tc += t
					tn += 1
			tc /= maxf(tn, 1)
			var pp := Vector2(tc.x, tc.z)
			var cand_e: Array = r._candidates([sec0], 4.0, 5.0)
			cand_e.sort_custom(func(a, b): return absf(a.distance_to(pp) - 28.0) < absf(b.distance_to(pp) - 28.0))
			if not cand_e.is_empty():
				var cp2: Vector2 = cand_e[0]
				list.append(["castle/baumpark", Vector3(cp2.x, m.ground_y(cp2.x, cp2.y) + 1.8, cp2.y), tc + Vector3.UP * 4.0, 75.0])
		if dr.fence.size() > 2:
			var fa: Vector3 = dr.fence[dr.fence.size() / 2][0]
			var fb: Vector3 = dr.fence[dr.fence.size() / 2][1]
			var fd := (fb - fa).normalized()
			var fn := Vector3(-fd.z, 0, fd.x)
			var fp := fa + fn * 6.0
			if m.ground_y(fp.x, fp.z) < fa.y - 1.5:
				fp = fa - fn * 6.0
			list.append(["castle/grabenzaun", Vector3(fp.x, m.ground_y(fp.x, fp.z) + 1.7, fp.z), fa + Vector3.UP * 0.2 - (fp - fa) * 0.6, 70.0])
		for e in list:
			var name: String = e[0]
			if not only.is_empty() and not only.any(func(o): return name.get_file().begins_with(o)):
				continue
			total += 1
			if await _shot(cam, name, e[1], e[2], e[3]):
				ok += 1
	print("ERGEBNIS: Castle Bilder: %d bestanden, %d fehlgeschlagen" % [ok, total - ok])
	get_tree().quit(0 if ok == total else 1)
