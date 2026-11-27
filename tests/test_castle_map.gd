extends Node
## Testkarte Castle (Gerüst): Boden, freie Starts, Navmesh verbunden, harte Grenze, Zonen.
## tools/godot.cmd --headless -- --mission=castle --autoplay=test_castle_map
var failed := 0
var passed := 0


func _ready() -> void:
	_run.call_deferred()
	# echte Burg: Navmesh ohne Cache bis ~3–4 min unter Last (run_tests-Grenze 900 s)
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
		check(false, "Karte/Navigation nach 600 s nicht bereit")
		_finish())


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)


func _capsule_free(space: PhysicsDirectSpaceState3D, pos: Vector3) -> Array:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis(), pos + Vector3.UP * 0.85)
	q.collision_mask = 1 | 16
	return space.intersect_shape(q)


func _run() -> void:
	var m: Mission
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	while not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
	await get_tree().physics_frame
	for id in ["castle", "castle_tdm", "castle_occupation"]:
		check(Game.MISSIONS.has(id) and Game.MP_MAPS.has(id), "Im MP-Kartenregister: " + id)
	check(Game.MP_MAPS.find("castle") > Game.MP_MAPS.find("bavaria"), "Castle am Ende der MP-Liste")
	check(not Game.PRACTICE_MISSIONS.has("castle"), "Kein Übungseinsatz")
	# Kartendaten vorhanden → Burg muss gebaut sein (sonst wäre ein Baufehler als Platzhalter-Erfolg getarnt)
	check(FileAccess.file_exists("res://assets/maps/castle/data/buildings.json"), "Öffentliche Kartendaten vorhanden")
	if preload("res://src/maps/castle/castle_real.gd").available() and String(Game.cli.get("castle_real", "1")) != "0":
		check(m.get("real") != null and m.real.buildings.count > 0 and (m.layout.get("spawns", []) as Array).size() >= 16,
			"Burg aus Kartendaten gebaut")
		if failed > 0:
			_finish()
			return
	if m.get("real") != null:
		await _run_real(m)
		_finish()
		return
	var b: Rect2 = m.bounds()
	check(b.size.x >= 190 and b.size.x <= 210 and b.size.y >= 190 and b.size.y <= 210, "Grenze ca. 200 × 200 m: %s" % str(b.size))
	check(get_tree().get_nodes_in_group("castle_blocks").size() == (m.layout.blocks as Array).size(), "Alle Platzhalter-Blöcke gebaut")
	var space := m.get_world_3d().direct_space_state
	# Boden: Raster über die Fläche, Treffer auf Geländehöhe, Normale nach oben
	var ground_ok := true
	for x in range(-90, 91, 15):
		for z in range(-90, 91, 15):
			var p := Vector3(x, 0, z)
			var h: float = m.ground_y(x, z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 40, p + Vector3.DOWN * 10, 1))
			if hit.is_empty() or (hit.position.y < h - 0.05):
				ground_ok = false
				print("BODEN FEHLT ", p)
			elif hit.collider.get_parent().name == "PlayableGround" and hit.normal.y < 0.9:
				ground_ok = false
				print("BODEN NORMALE ", p, " ", hit.normal)
	check(ground_ok, "Boden trägt überall, Normalen oben")
	check(absf(m.ground_y(23, 0)) > 0.1, "Gelände leicht wellig")
	var spawns: Array = m.mp_spawns()
	check(spawns.size() == 16, "16 DM-Starts")
	check(spawns.filter(func(s): return s.team == 0).size() == 8, "8 Starts je Team (TDM)")
	for i in spawns.size():
		var pos: Vector3 = spawns[i].pos
		check(m.inside_map(pos), "Start %02d innerhalb der Grenze" % i)
		var hits := _capsule_free(space, pos)
		check(hits.is_empty(), "Start %02d mit freier Soldatenkapsel %s" % [i, str(hits.map(func(h): return h.collider.name))])
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2, pos + Vector3.DOWN * 2, 1))
		check(not hit.is_empty() and absf(hit.position.y - m.ground_y(pos.x, pos.z)) < 0.1, "Start %02d über Boden" % i)
	var map: RID = m.get_world_3d().navigation_map
	var from: Vector3 = spawns[0].pos
	for i in range(1, spawns.size()):
		var path := NavigationServer3D.map_get_path(map, from, spawns[i].pos, true)
		check(path.size() > 1 and path[-1].distance_to(spawns[i].pos) < 2.0, "KI-Pfad Start 00 → %02d" % i)
	check(m.mp_zones().is_empty(), "Deathmatch: keine Zonen für Net/HUD")
	var zones: Array = m.all_zones()
	check(zones.size() == 5, "Fünf Eroberungszonen")
	check(zones.filter(func(z): return z.owner == 0).size() == 1 and zones.filter(func(z): return z.owner == 1).size() == 1,
		"Je eine Teambasis, Rest neutral")
	for z in zones:
		var c: Vector3 = z.xf.origin
		check(m.inside_map(c), "Zone %s innerhalb der Grenze" % z.name)
		var path := NavigationServer3D.map_get_path(map, from, c, true)
		check(path.size() > 1 and Vector2(path[-1].x, path[-1].z).distance_to(Vector2(c.x, c.z)) < 2.0, "Zone %s per KI erreichbar" % z.name)
		check((z.slots as Array).size() == 4, "Zone %s mit 4 Spawns" % z.name)
		for s in z.slots:
			check(m.inside_map(s.pos) and _capsule_free(space, s.pos).is_empty(), "Freier Zonenspawn %s %s" % [z.name, str(s.pos)])
	# Burghof (Zone B) nur durchs Tor: Pfad muss durch die Torlücke (|x| < 6, z ≈ -20)
	var hof: Vector3 = zones[1].xf.origin
	var hp := NavigationServer3D.map_get_path(map, from, hof, true)
	print("HOFPFAD ", hp)
	var wall_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-36, 1.5, -45), Vector3(-24, 1.5, -45), 1))
	check(not wall_hit.is_empty(), "Westmauer blockiert physisch: " + (str(wall_hit.collider.name) if wall_hit else "-"))
	var cp := NavigationServer3D.map_get_closest_point(map, Vector3(-30, 0.6, -45))
	check(absf(cp.x + 30.0) > 1.0, "Kein Navmesh im Mauerinneren: %s" % str(cp))
	check(hp.size() > 1 and Array(hp).any(func(p): return absf(p.x) < 6.5 and absf(p.z + 20.0) < 3.0), "Weg in den Burghof führt durchs Tor")
	var bcount := get_tree().get_nodes_in_group("castle_boundaries").size()
	check(bcount == m.boundary.size(), "Grenze an allen %d Seiten" % m.boundary.size())
	for i in m.boundary.size():
		var a: Vector2 = m.boundary[i]
		var e: Vector2 = m.boundary[(i + 1) % m.boundary.size()]
		var mid := (a + e) * 0.5
		var outward := Vector2(-(e - a).y, (e - a).x).normalized()
		if Geometry2D.is_point_in_polygon(mid + outward, m.boundary):
			outward = -outward
		var c := Vector3(mid.x, m.ground_y(mid.x, mid.y) + 1.0, mid.y)
		var ray := PhysicsRayQueryParameters3D.create(c - Vector3(outward.x, 0, outward.y) * 3, c + Vector3(outward.x, 0, outward.y) * 3, 16)
		check(not space.intersect_ray(ray).is_empty(), "Grenze %d blockiert Bewegung (Ebene 5)" % i)
		var shot := PhysicsRayQueryParameters3D.create(c - Vector3(outward.x, 0, outward.y) * 3, c + Vector3(outward.x, 0, outward.y) * 3, 1)
		check(space.intersect_ray(shot).is_empty(), "Grenze %d lässt Sicht/Schüsse frei" % i)
	# Echter Lauf gegen die Grenze: Trupp-Soldat kommt nicht hinaus
	var s: Soldier = m.squad.members[m.squad.active_index] if m.squad and not m.squad.members.is_empty() else null
	check(s != null, "Direktstart: Trupp vorhanden")
	if s:
		m.controller.process_mode = Node.PROCESS_MODE_DISABLED
		s.global_position = Vector3(-95, m.ground_y(-95, 0) + 0.3, 0)
		s.velocity = Vector3.ZERO
		s.look_yaw = PI * 0.5   # Westen
		for i in 180:
			s.move_input = Vector3(-1, 0, 0)
			await get_tree().physics_frame
		s.move_input = Vector3.ZERO
		check(m.inside_map(s.global_position), "Soldat läuft nicht über die Grenze: %s" % str(s.global_position))
	_finish()


## Pfadsuche ohne 4096-Polygon-Grenze (lange Burg)
func _path(m: Mission, a: Vector3, b: Vector3) -> PackedVector3Array:
	var q := NavigationPathQueryParameters3D.new()
	q.map = m.get_world_3d().navigation_map
	q.start_position = a
	q.target_position = b
	if "path_search_max_polygons" in q:
		q.set("path_search_max_polygons", 0)
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.path


## Turmstellungen (castle_emplacements.gd): je Turm eine (gerade Treppe = Flak, Wendel = MG 42) auf der Plattform,
## Bedienerplatz frei; der Soldat auf dem ersten Turm besetzt die Flak, richtet, steigt wieder ab
func _test_emplacements(m: Mission, r, s: Soldier, space: PhysicsDirectSpaceState3D) -> void:
	var em: Array = m.get("emplacements")
	if not DirAccess.dir_exists_absolute(OrigLevel.cache_root()):
		return
	check(em.size() == r.kit.towers.size(), "Turmstellungen: %d (Türme %d)" % [em.size(), r.kit.towers.size()])
	var kinds := {}
	for g in em:
		var tid := String(g.get_meta("tower"))
		var tw: Dictionary = {}
		for t in r.kit.towers:
			if String(t.id) == tid:
				tw = t
		kinds[g.get_meta("kind")] = int(kinds.get(g.get_meta("kind"), 0)) + 1
		var fp: Vector3 = g.frame.global_position
		var plat: float = (tw.pos as Vector3).y + 12.0
		check(absf(fp.y - plat) < 0.3 and Vector2(fp.x - tw.pos.x, fp.z - tw.pos.z).length() < 3.6,
			"%s auf Turm %s: auf der Plattform (y %.2f, Plattform %.2f)" % [g.get_meta("kind"), tid, fp.y, plat])
		var gs: Vector3 = g.gunner_spot()
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(gs + Vector3.UP, gs + Vector3.DOWN * 2.0, 1))
		check(not floor_hit.is_empty() and absf(floor_hit.position.y - plat) < 0.35 and _capsule_free(space, Vector3(gs.x, plat + 0.05, gs.z)).is_empty(),
			"%s Turm %s: Bedienerplatz frei auf der Plattform %s" % [g.get_meta("kind"), tid, str(gs)])
		check(g.muzzle != null, "%s Turm %s: Mündung SHDUM00 vorhanden" % [g.get_meta("kind"), tid])
	check(int(kinds.get("Flak", 0)) >= 1 and int(kinds.get("MG42", 0)) >= 1, "Flak und MG-Nester vorhanden %s" % str(kinds))
	var tw0: String = String(r.kit.towers[0].id)
	for g in em:
		if String(g.get_meta("tower")) != tw0:
			continue
		s.global_position = g.gunner_spot() + Vector3.UP * 0.1
		s.velocity = Vector3.ZERO
		await m.get_tree().physics_frame
		g.mount(s)
		await m.get_tree().physics_frame
		check(g.gunner == s, "Soldat besetzt die %s auf Turm %s" % [g.get_meta("kind"), tw0])
		s.look_pitch = 0.6
		for i in 10:
			s.health = 100.0
			await m.get_tree().physics_frame
		g.dismount()
		await m.get_tree().physics_frame
		check(g.gunner == null and s.alive, "Soldat verlässt die Stellung")


func _reach(m: Mission, a: Vector3, b: Vector3, tol := 2.0) -> bool:
	var p := _path(m, a, b)
	var ok := p.size() > 1 and p[-1].distance_to(b) < tol
	if not ok:
		print("PFAD_ENDE ", b, " → ", p[-1] if p.size() > 0 else Vector3.INF, " (", p.size(), " Punkte)")
	return ok


## Echte Burg (lokale Daten vorhanden): Aufbau, Boden, Starts, Wege zwischen allen Höfen, Wehrgang, Türme, Tore,
## Brücken, Grenze. Spielfiguren nur mit voller Gesundheit je Bild (unverwundbar; Karte ohne Gegner).
func _run_real(m: Mission) -> void:
	var r = m.real
	var space := m.get_world_3d().direct_space_state
	print("CASTLE_STATS ", r.kit.stats, " Gebäude ", r.buildings.count, " Durchgänge ", r.buildings.passages.size(), " Brücken ", r.bridges.size())
	check(r.buildings.count >= 80, "Gebäude gebaut: %d" % r.buildings.count)
	check(r.kit.stats.missing.is_empty(), "Bausatzmodelle vorhanden")
	check(r.kit.stats.walk >= 150, "Wehrgangmodule am Bering: %d" % r.kit.stats.walk)
	check(r.kit.stats.towers >= 3, "Besteigbare Türme: %d" % r.kit.stats.towers)
	check(r.kit.stats.stairs >= 4, "Treppen zum Wehrgang: %d" % r.kit.stats.stairs)
	check(r.dividers.size() == 5, "Fünf Quermauern zwischen den Höfen A–F")
	check(r.bridges.size() >= 2, "Grabenbrücken am Hauptweg: %d" % r.bridges.size())
	var b: Rect2 = m.bounds()
	check(b.size.y > 800.0, "Burglänge > 800 m: %s" % str(b.size))
	# Boden: Raster in allen Höfen trägt
	var ground_ok := true
	var n_ground := 0
	for sec in r.sections:
		if sec == "G":
			continue
		for p in r._candidates([sec], 12.0, 6.0):
			var y: float = m.ground_y(p.x, p.y)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 30, p.y), Vector3(p.x, y - 5, p.y), 1))
			n_ground += 1
			if hit.is_empty() or hit.position.y < y - 0.1:
				ground_ok = false
				print("BODEN FEHLT ", p)
	check(ground_ok and n_ground > 100, "Hofboden trägt (%d Proben)" % n_ground)
	# --- Spielart Deathmatch (Direktstart castle): Spielfläche F + E + D, Starts, Zonen nur intern ---
	check(m.play_mode == Net.Mode.DEATHMATCH and r.restricted, "Direktstart castle = Deathmatch mit eingeschränkter Spielfläche")
	check(not m.frontline and m.mp_zones().is_empty(), "DM: keine Zonen für Net/HUD, keine Frontlinie")
	var spawns: Array = m.mp_spawns()
	check(spawns.size() >= 16, "DM: mindestens 16 Starts (%d)" % spawns.size())
	var per_sec := {}
	for i in spawns.size():
		var pos: Vector3 = spawns[i].pos
		var sec: String = r.section_of(Vector2(pos.x, pos.z))
		per_sec[sec] = int(per_sec.get(sec, 0)) + 1
		check(m.inside_map(pos) and m.in_play_area(pos) and sec in ["D", "E", "F"], "Start %02d in der Spielfläche (Hof %s)" % [i, sec])
		var hits := _capsule_free(space, pos)
		check(hits.is_empty(), "Start %02d mit freier Soldatenkapsel %s" % [i, str(hits.map(func(h): return h.collider.name))])
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2, pos + Vector3.DOWN * 2, 1))
		check(not hit.is_empty() and absf(hit.position.y - m.ground_y(pos.x, pos.z)) < 0.15, "Start %02d über Boden" % i)
	print("CASTLE_DM_STARTS je Hof ", per_sec)
	check(int(per_sec.get("D", 0)) >= 4 and int(per_sec.get("E", 0)) >= 4 and int(per_sec.get("F", 0)) >= 4, "DM-Starts über F, E und D verteilt")
	var from: Vector3 = spawns[0].pos
	for i in range(1, spawns.size()):
		check(_reach(m, from, spawns[i].pos), "KI-Pfad Start 00 → %02d" % i)
	# TDM-Startsatz: Alliierte im Hof D, Achse in der Hauptburg F
	var tdm: Array = r.spawn_sets.get("tdm", [])
	var t0 := tdm.filter(func(s): return int(s.team) == 0)
	var t1 := tdm.filter(func(s): return int(s.team) == 1)
	check(t0.size() >= 8 and t1.size() >= 8, "TDM: je Team 8 Starts (%d/%d)" % [t0.size(), t1.size()])
	check(t0.all(func(s): return r.section_of(Vector2(s.pos[0], s.pos[1])) == "D"), "TDM: Alliierte starten im Hof D")
	check(t1.all(func(s): return r.section_of(Vector2(s.pos[0], s.pos[1])) == "F"), "TDM: Achse startet in der Hauptburg F")
	var occ: Array = r.spawn_sets.get("occupation", [])
	check(occ.filter(func(s): return int(s.team) == 0 and r.section_of(Vector2(s.pos[0], s.pos[1])) == "A").size() >= 4,
		"Eroberung (Rückfall-Starts): Alliierte im Hof A")
	# --- Zonen A–F (Eroberung; Geometrie unabhängig von der Spielart) ---
	var zones: Array = m.all_zones()
	check(zones.size() == 6, "Sechs Zonen, je Hof eine: %d" % zones.size())
	var owners: Array = zones.map(func(z): return int(z.owner))
	check(owners == [0, -1, -1, -1, -1, 1], "Besitz zu Beginn: Alliierte A, Achse F, Rest neutral %s" % str(owners))
	var letters := ["A", "B", "C", "D", "E", "F"]
	for zi in zones.size():
		var z: Dictionary = zones[zi]
		var c: Vector3 = z.xf.origin
		var sec: String = letters[zi] if zi < letters.size() else "?"
		var poly: PackedVector2Array = r.sections.get(sec, PackedVector2Array())
		check(m.inside_map(c) and r.section_of(Vector2(c.x, c.z)) == sec, "Zone %s liegt im Hof %s" % [z.name, sec])
		check(String(z.shape) == "box", "Zone %s als Quader entlang des Hofs" % z.name)
		if String(z.shape) == "box":
			var sc: Vector3 = z.scale
			var xf: Transform3D = z.xf
			var corners_in := true
			for u in [-0.5, 0.5]:
				for v in [-0.5, 0.5]:
					var w: Vector3 = xf * Vector3(u * sc.x, 0, v * sc.z)
					corners_in = corners_in and Geometry2D.is_point_in_polygon(Vector2(w.x, w.z), poly)
			check(corners_in and sc.x >= 12.0 and sc.z >= 16.0, "Zone %s: Quader %.0f × %.0f m ganz im Hof" % [z.name, sc.x, sc.z])
			check(Net.zone_contains(z, c) and Net.zone_contains(z, xf * Vector3(sc.x * 0.45, -0.8, sc.z * 0.45)) \
				and not Net.zone_contains(z, xf * Vector3(sc.x * 0.6, 0, 0)), "Zone %s: Einnahmebereich = Quader" % z.name)
		var slots: Array = z.slots
		check(slots.size() >= 4, "Zone %s mit ≥ 4 Spawnplätzen (%d)" % [z.name, slots.size()])
		var ground := NavigationServer3D.map_get_closest_point(m.get_world_3d().navigation_map, c - Vector3(0, 0.8, 0))
		for s in slots:
			var sp: Vector3 = s.pos
			var np := NavigationServer3D.map_get_closest_point(m.get_world_3d().navigation_map, sp)
			check(m.inside_map(sp) and _capsule_free(space, sp).is_empty() and Vector2(np.x - sp.x, np.z - sp.z).length() < 0.6,
				"Freier Zonenspawn %s auf dem Netz %s" % [z.name, str(sp)])
			check(_reach(m, ground, sp, 1.5), "Zonenspawn %s von der Zonenmitte erreichbar %s" % [z.name, str(sp)])
		print("CASTLE_ZONE_TEST ", z.name, " Mitte ", c, " Plätze ", slots.size(), " ", m.slot_stats.get(z.name, {}))
	# Wege zwischen Nachbarzonen (Tortunnel, Brücken): A→B→C und D→E→F verbunden, C→D durch die innere Grenze getrennt
	for zi in range(0, zones.size() - 1):
		var a3: Vector3 = (zones[zi].xf as Transform3D).origin - Vector3(0, 0.8, 0)
		var b3: Vector3 = (zones[zi + 1].xf as Transform3D).origin - Vector3(0, 0.8, 0)
		if zi == 2:
			check(not _reach(m, a3, b3, 3.0), "DM: kein Weg von Zone C nach Zone D (innere Grenze)")
		else:
			check(_reach(m, a3, b3, 2.5), "Weg Zone %s → Zone %s über das Netz" % [zones[zi].name, zones[zi + 1].name])
	await _test_inner_boundary(m, r, space, from)
	await _test_hints(m, r, from)
	for pas in r.buildings.passages:
		print("DURCHGANG ", pas.building, " Mitte ", pas.center, " t ", pas.t0, "…", pas.t1, " h ", pas.h0, "…", pas.h1, " offen ", pas.open)
	var ig: Vector3 = r.inner_gate.get("pos", Vector3.INF)
	# DM/TDM: der Durchgang C|D ist absichtlich verrammelt (innere Grenze) – dort nicht „frei/begehbar“ prüfen
	var shut := func(p2: Vector2) -> bool: return ig.is_finite() and Vector2(ig.x, ig.z).distance_to(p2) < 8.0
	for g in r.kit.gate_points:
		var gp: Vector3 = g
		if shut.call(Vector2(gp.x, gp.z)):
			continue
		# Boden im Tor bzw. im Gebäudedurchgang (Strahl von oben bis unter die Durchgangsdecke)
		var top := gp.y + 3.0
		for pas in r.buildings.passages:
			if (pas.center as Vector2).distance_to(Vector2(gp.x, gp.z)) < 0.1:
				top = maxf(pas.h0, pas.h1) + 3.0
		var fl := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(gp.x, top, gp.z), Vector3(gp.x, top - 25.0, gp.z), 1))
		var gy: float = fl.position.y if not fl.is_empty() else m.ground_y(gp.x, gp.z)
		var hits := _capsule_free(space, Vector3(gp.x, gy + 0.15, gp.z))
		check(hits.is_empty(), "Tor frei %s %s" % [str(gp), str(hits.map(func(h): return h.collider.get_parent().name))])
	for d in r.dividers:
		var gp: Vector2 = d.gate
		var gy: float = m.ground_y(gp.x, gp.y)
		var near := NavigationServer3D.map_get_closest_point(m.get_world_3d().navigation_map, Vector3(gp.x, gy, gp.y))
		check(Vector2(near.x, near.z).distance_to(gp) < 3.0, "Durchgang %s im Navmesh (%s)" % [d.name, "Gebäude" if d.passage else "Tor"])
	# Treppen zum Wehrgang: in der Spielfläche vom Start 00, in A–C (nur Eroberung) von der Zone A aus
	var a_ref: Vector3 = (zones[0].xf as Transform3D).origin - Vector3(0, 0.8, 0)
	for s in r.kit.stairs_at:
		var sp: Vector3 = s
		var src: Vector3 = from if m.in_play_area(sp) else a_ref
		var ok_st := _reach(m, src, sp, 2.0)
		check(ok_st, "Wehrgang über Treppe erreichbar %s" % str(sp))
		if not ok_st:
			_diag_cross(m, r, src, sp)
	# Runde 2: Durchgänge durchgängig begehbar (Boden per Strahl an beiden Enden, Kapsel in der Mitte frei)
	for pas in r.buildings.passages:
		var c: Vector2 = pas.center
		var d: Vector2 = pas.dir
		if shut.call(c):
			continue
		var ends: Array = []
		for t in [float(pas.t0) - 1.2, float(pas.t1) + 1.2]:
			var q: Vector2 = c + d * t
			var top: float = maxf(pas.h0, pas.h1) + 3.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q.x, top, q.y), Vector3(q.x, top - 30.0, q.y), 1))
			ends.append(Vector3(q.x, hit.position.y if not hit.is_empty() else m.ground_y(q.x, q.y), q.y))
		var fl: Array = pas.floor
		var ki: int = fl.size() / 2
		var tm: float = lerpf(float(pas.t0), float(pas.t1), float(ki) / maxf(fl.size() - 1, 1))
		var mid: Vector2 = c + d * tm
		var fy: float = fl[ki]
		var hits := _capsule_free(space, Vector3(mid.x, fy + 0.15, mid.y))
		check(hits.is_empty(), "Durchgang %s Mitte frei %s" % [pas.building, str(hits.map(func(h): return h.collider.get_parent().name))])
		check(_reach(m, ends[0], ends[1], 2.5), "Durchgang %s durchgängig begehbar" % pas.building)
	# Hauptburg F: Zone im Abschnitt F, freie Hoffläche flächendeckend erreichbar
	check(zones.size() == 6 and r.section_of(Vector2(zones[5].xf.origin.x, zones[5].xf.origin.z)) == "F", "Zone der Hauptburg liegt in F")
	var fn := 0
	var fok := 0
	# freie Hofzellen der Hauptburg laut Flutfüllung (5-m-Raster, ohne Gebäude/Rand) per Navmesh prüfen
	var fpoly: PackedVector2Array = r.sections["F"]
	var fb := Rect2(fpoly[0], Vector2.ZERO)
	for p in fpoly:
		fb = fb.expand(p)
	var gx := fb.position.x
	while gx < fb.end.x:
		var gz := fb.position.y
		while gz < fb.end.y:
			var p := Vector2(gx, gz)
			if Geometry2D.is_point_in_polygon(p, fpoly) and r._reachable_f(p) and not r.in_building(p, 1.5) and r.boundary_dist(p) > 4.0 \
					and r._flat(p) and not r.near_passage(p, 3.0):
				fn += 1
				if _reach(m, from, Vector3(p.x, m.ground_y(p.x, p.y), p.y), 2.0):
					fok += 1
			gz += 5.0
		gx += 5.0
	check(fn >= 20 and fok >= fn * 0.95, "Hauptburg-Höfe per KI erreichbar: %d/%d Rasterpunkte" % [fok, fn])
	print("CASTLE_SPLIT ", r.buildings.split_parts)
	check(not r.buildings.split_parts.is_empty(), "Hauptburgblock in benannte Teile aufgeteilt")
	# Türme mit Innentreppe: vom Hof bis auf die Plattform
	var ts := 0
	for tw in r.kit.towers:
		if not tw.stairs:
			continue
		ts += 1
		var door: Vector3 = tw.door
		door.y = m.ground_y(door.x, door.z)
		check(_reach(m, door, tw.stair_top, 1.5), "Turm %s: Innentreppe bis zur Plattform" % tw.id)
	check(ts >= 2, "Mindestens zwei Türme mit Innentreppe: %d" % ts)
	# Runde 3: Wendeltreppen (eigene Stufenkollision), Garten, Kriegsdeko
	check(int(r.kit.stats.get("tower_spirals", 0)) >= 1, "Türme mit Wendeltreppe: %d" % int(r.kit.stats.get("tower_spirals", 0)))
	for tw in r.kit.towers:
		if tw.get("spiral", false):
			var door: Vector3 = tw.door
			door.y = m.ground_y(door.x, door.z)
			var p1: Vector3 = tw.pos + (tw.basis as Basis) * Vector3(-2.2, 4.16, -2.2)
			check(_reach(m, door, p1, 1.5), "Turm %s: Wendeltreppe ins 1. Obergeschoss" % tw.id)
	print("CASTLE_GARTEN ", r.garden.size(), " Teile, Deko ", r.cover.size(), " Requisiten ", r.kit.stats.get("props", 0))
	check(r.garden.size() >= 6, "Garten im Hof B: %d Teile" % r.garden.size())
	check(r.cover.size() >= 15, "Kriegsdeko/Deckung in den Höfen: %d" % r.cover.size())
	# Hofausstattung nach Entwurf (castle_dressing)
	if String(Game.cli.get("castle_dressing", "1")) != "0":
		var ds: Dictionary = r.dressing.stats
		print("CASTLE_DRESSING_TEST ", ds)
		check(int(ds.trees) >= 8, "Laubbäume in den Höfen: %d" % int(ds.trees))
		check(int(ds.hedges) >= 10 and int(ds.hedges) <= 60, "Hecken am Weg (10–60 Stück): %d" % int(ds.hedges))
		check(int(ds.stairs) >= 1, "Überdachte Außentreppe im Hof der Hauptburg: %d" % int(ds.stairs))
		for st in r.dressing.stairs:
			var top: Vector3 = st.top
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top + Vector3.UP * 1.0, top + Vector3.DOWN * 1.5, 1))
			check(not hit.is_empty() and absf(hit.position.y - top.y) < 0.3, "Außentreppe: Podest trägt bei %s" % str(top.snapped(Vector3.ONE * 0.1)))
			var foot: Vector3 = st.foot
			foot.y = m.ground_y(foot.x, foot.z)
			check(_reach(m, foot, top, 1.5), "Außentreppe: vom Hof bis aufs Podest begehbar")
		if not r.bridges.is_empty():
			check(r.bridges.any(func(b): return b.get("wood", false)), "Holzbrücke vor dem Tor D|E vorhanden")
	# Außentor geschlossen
	check(r.kit.closed_gates.size() >= 1, "Außentor als geschlossenes Tor: %d" % r.kit.closed_gates.size())
	for g in r.kit.closed_gates:
		var gp: Vector3 = g
		check(not _capsule_free(space, gp + Vector3.UP * 0.3).is_empty(), "Geschlossenes Tor sperrt %s" % str(gp))
	for br in r.bridges:
		var lo: Vector3 = br.low
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(lo + Vector3.UP * 3, lo + Vector3.DOWN * 30, 1))
		print("BRUECKE ", br.a, " → ", br.b, " Tiefe %.1f m" % br.depth)
		check(not hit.is_empty() and absf(hit.position.y - lo.y) < 0.6, "Brückendeck über dem Graben %s (Tiefe %.1f m)" % [str(lo), br.depth])
		check(_reach(m, br.a + Vector3.UP * 0.2, br.b + Vector3.UP * 0.2, 2.5), "Brücke begehbar %s" % str(lo))
	for i in m.boundary.size():
		var a: Vector2 = m.boundary[i]
		var e: Vector2 = m.boundary[(i + 1) % m.boundary.size()]
		var mid := (a + e) * 0.5
		var outward: Vector2 = -r._inward(a, e)
		var c := Vector3(mid.x, m.ground_y(mid.x + outward.x * 1.5, mid.y + outward.y * 1.5) + 1.0, mid.y)
		var ray := PhysicsRayQueryParameters3D.create(c, c + Vector3(outward.x, 0, outward.y) * 4, 16)
		check(not space.intersect_ray(ray).is_empty(), "Grenze %d blockiert Bewegung (Ebene 5)" % i)
	# Turm besteigen (echte Leiter, Soldat unverwundbar gehalten)
	var s: Soldier = m.squad.members[m.squad.active_index] if m.squad and not m.squad.members.is_empty() else null
	check(s != null, "Direktstart: Trupp vorhanden")
	if s and not r.kit.towers.is_empty():
		m.controller.process_mode = Node.PROCESS_MODE_DISABLED
		var tw: Dictionary = r.kit.towers[0]
		var lad = null
		for l in m.get_tree().get_nodes_in_group("castle_ladders"):
			if not l.at_top and (l.bottom as Vector3).distance_to(tw.ladder) < 0.1:
				lad = l
		s.global_position = tw.ladder + Vector3.UP * 0.2
		s.velocity = Vector3.ZERO
		for i in 20:
			s.health = 100.0
			await m.get_tree().physics_frame
		check(lad != null and lad.can_interact(s), "Leiter am Turmfuß benutzbar")
		if lad:
			lad.interact(s)
			for i in 600:
				s.health = 100.0
				await m.get_tree().physics_frame
				if i > 30 and not s.is_climbing():
					break
			for i in 30:
				s.health = 100.0
				await m.get_tree().physics_frame
			print("TURM oben ", s.global_position, " Ziel ", tw.top)
			check(absf(s.global_position.y - tw.top.y) < 0.6 and s.is_on_floor(), "Turmplattform erreicht und Stand stabil")
			await _test_emplacements(m, r, s, space)
		# Vom Wehrgang aus nach außen laufen: Grenze hält
		var wp: Vector3 = r.kit.walk_points[r.kit.walk_points.size() / 2]
		s.global_position = wp + Vector3.UP * 0.3
		s.velocity = Vector3.ZERO
		var c2 := Vector2(wp.x, wp.z)
		var best := INF
		var outd := Vector2.ZERO
		for i in m.boundary.size():
			var a: Vector2 = m.boundary[i]
			var e: Vector2 = m.boundary[(i + 1) % m.boundary.size()]
			var d := Geometry2D.get_closest_point_to_segment(c2, a, e).distance_to(c2)
			if d < best:
				best = d
				outd = -r._inward(a, e)
		s.look_yaw = atan2(-outd.x, -outd.y)
		for i in 240:
			s.health = 100.0
			s.move_input = Vector3(0, 0, -1)
			s.jump_or_climb() if i % 40 == 0 and s.has_method("jump_or_climb") else null
			await m.get_tree().physics_frame
		s.move_input = Vector3.ZERO
		check(m.inside_map(s.global_position), "Soldat verlässt die Burg nicht über den Wehrgang: %s" % str(s.global_position))


## DM/TDM: innere Grenze an der Quermauer C|D – Bewegungssperre (Ebene 5) über die ganze Breite inkl. Wehrgang, kein
## Netzweg nach C, verrammeltes Tor sichtbar mit Kollision, echter Lauf gegen Tor und Wehrgangsperre (Soldat unverwundbar)
func _test_inner_boundary(m: Mission, r, space: PhysicsDirectSpaceState3D, from: Vector3) -> void:
	var bodies := get_tree().get_nodes_in_group("castle_inner_boundary")
	check(not r.inner_lines.is_empty() and bodies.size() == r.inner_lines.size(), "Innere Grenze C|D gebaut: %d Abschnitte" % bodies.size())
	check(bodies.all(func(b): return (b as CollisionObject3D).collision_layer == LevelBuilder.FENCE_LAYER),
		"Innere Grenze nur Bewegungssperre (Ebene 5, Sicht/Schüsse frei)")
	var n_ok := 0
	var n := 0
	for ln in r.inner_lines:
		var a: Vector2 = ln[0]
		var b: Vector2 = ln[1]
		var nrm := (b - a).orthogonal().normalized()
		for k in 7:
			var p := a.lerp(b, (k + 0.5) / 7.0)
			var dside: Vector2 = nrm if r.in_play(p + nrm * 3.0) else -nrm
			for lift in [1.0, 5.0]:
				var y: float = m.ground_y(p.x, p.y) + lift
				var o := Vector3(p.x + dside.x * 2.0, y, p.y + dside.y * 2.0)
				var e := Vector3(p.x - dside.x * 2.0, y, p.y - dside.y * 2.0)
				n += 1
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(o, e, LevelBuilder.FENCE_LAYER)).is_empty():
					n_ok += 1
	check(n > 0 and n_ok == n, "Innere Grenze sperrt über die ganze Breite (Boden und Wehrganghöhe): %d/%d" % [n_ok, n])
	var zc: Vector3 = (m.all_zones()[2].xf as Transform3D).origin - Vector3(0, 0.8, 0)
	var leak := _reach(m, from, zc, 3.0)
	check(not leak, "Kein KI-Weg aus der Spielfläche in den Hof C")
	if leak:
		# Fehlersuche: wo kreuzt der Weg die Seite C?
		var p := _path(m, from, zc)
		for i in range(1, p.size()):
			if r.in_play(Vector2(p[i - 1].x, p[i - 1].z)) and not r.in_play(Vector2(p[i].x, p[i].z)):
				print("LECK ", p[i - 1], " → ", p[i], " Abstand %.1f m" % p[i - 1].distance_to(p[i]))
				for l in m.find_children("*", "NavigationLink3D", true, false):
					var lk := l as NavigationLink3D
					var ls := lk.global_transform * lk.start_position
					var le := lk.global_transform * lk.end_position
					if ls.distance_to(p[i]) < 3.0 or le.distance_to(p[i]) < 3.0 or ls.distance_to(p[i - 1]) < 3.0:
						print("   LINK ", lk.get_path(), " ", ls, " → ", le, " Meta ", lk.get_meta_list())
				var space2 := m.get_world_3d().direct_space_state
				var hit := space2.intersect_ray(PhysicsRayQueryParameters3D.create(p[i - 1] + Vector3.UP * 0.6, p[i] + Vector3.UP * 0.6, 0xFFFFFFFF))
				print("   STRAHL ", hit.collider.get_path() if not hit.is_empty() else "-")
				var cap := CapsuleShape3D.new()
				cap.radius = 0.25
				cap.height = 1.4
				var prm := PhysicsShapeQueryParameters3D.new()
				prm.shape = cap
				prm.collision_mask = 1 | (1 << 4) | LevelBuilder.BORDER_LAYER
				prm.transform = Transform3D(Basis(), p[i - 1] + Vector3.UP * 1.15)
				prm.motion = Vector3(p[i].x - p[i - 1].x, 0, p[i].z - p[i - 1].z)
				print("   KAPSEL cast_motion ", space2.cast_motion(prm))
				prm.motion = Vector3.ZERO
				prm.transform = Transform3D(Basis(), (p[i - 1] + p[i]) * 0.5 + Vector3.UP * 1.15)
				print("   KAPSEL Mitte ", space2.intersect_shape(prm, 4).map(func(x): return x.collider.name))
				for b in get_tree().get_nodes_in_group("castle_inner_boundary"):
					print("   GRENZE ", (b as Node3D).global_transform)
	var ig: Dictionary = r.inner_gate
	check(not ig.is_empty() and r.kit.closed_gates.any(func(g): return (g as Vector3).distance_to(ig.pos) < 0.1),
		"Verrammeltes Tor im Durchgang C|D")
	if ig.is_empty():
		return
	var gp: Vector3 = ig.pos
	var out: Vector3 = ig.out
	check(m.in_play_area(gp + out * 2.0) and not m.in_play_area(gp - out * 6.0), "Tor auf der Seite der Spielfläche, Blick nach D")
	var leaf := space.intersect_ray(PhysicsRayQueryParameters3D.create(gp + out * 1.5 + Vector3.UP * 1.5, gp - out * 1.5 + Vector3.UP * 1.5, 1))
	check(not leaf.is_empty(), "Torflügel sichtbar und fest (Ebene 1)")
	var s: Soldier = m.squad.members[m.squad.active_index] if m.squad and not m.squad.members.is_empty() else null
	if s == null:
		return
	m.controller.process_mode = Node.PROCESS_MODE_DISABLED
	# Lauf gegen das Tor (aus 2 m vor dem Flügel) …
	var runs: Array = [[gp + out * 2.0, -out, "Tor C|D"]]
	# … und auf dem Wehrgang über die Grenzlinie (nächster Wehrgangpunkt an einem Grenzende, Seite D)
	var ln0: Array = r.inner_lines[0]
	var nrm := ((ln0[1] as Vector2) - (ln0[0] as Vector2)).orthogonal().normalized()
	for end in r.inner_ends:
		var best := Vector3.INF
		var bd := 9.0
		for w in r.kit.walk_points:
			var wp: Vector3 = w
			var d := Vector2(wp.x, wp.z).distance_to(end)
			if d < bd and r.in_play(Vector2(wp.x, wp.z)):
				bd = d
				best = wp
		print("WEHRGANG an der inneren Grenze ", end, " → ", best)
		if best.is_finite():
			var to_c: Vector2 = -nrm if r.in_play(Vector2(best.x, best.z) + nrm * 3.0) else nrm
			runs.append([best, Vector3(to_c.x, 0, to_c.y), "Wehrgang"])
	for run in runs:
		var start: Vector3 = run[0]
		var dir: Vector3 = run[1]
		s.global_position = start + Vector3.UP * 0.3
		s.velocity = Vector3.ZERO
		s.look_yaw = atan2(-dir.x, -dir.z)
		for i in 240:
			s.health = 100.0
			s.move_input = Vector3(0, 0, -1)
			if i % 40 == 20:
				s.jump_or_climb()
			await get_tree().physics_frame
		s.move_input = Vector3.ZERO
		check(m.in_play_area(s.global_position) and r.section_of(Vector2(s.global_position.x, s.global_position.z)) != "C",
			"Lauf gegen die innere Grenze (%s) endet in der Spielfläche: %s" % [run[2], str(s.global_position)])


## Fehlersuche: Weg a → b, Stellen, an denen er den Bering kreuzt, mit Links in der Nähe
func _diag_cross(m: Mission, r, a: Vector3, b: Vector3) -> void:
	var p := _path(m, a, b)
	print("DIAG Weg ", a, " → ", b, ": ", p.size(), " Punkte, Ende ", p[p.size() - 1] if p.size() > 0 else Vector3.INF)
	for i in range(1, p.size()):
		var i0: bool = m.inside_map(p[i - 1])
		var i1: bool = m.inside_map(p[i])
		if i0 != i1:
			print("   KREUZT ", p[i - 1], " → ", p[i], " (", "hinaus" if i0 else "hinein", ")")
			for l in m.find_children("*", "NavigationLink3D", true, false):
				var lk := l as NavigationLink3D
				var ls := lk.global_transform * lk.start_position
				var le := lk.global_transform * lk.end_position
				if ls.distance_to(p[i]) < 2.0 or le.distance_to(p[i]) < 2.0 or ls.distance_to(p[i - 1]) < 2.0 or le.distance_to(p[i - 1]) < 2.0:
					print("      LINK ", lk.name, " ", ls, " → ", le, " ", lk.get_meta_list())
	# Umgebung als Raster 1 m (# = Netz erreichbar, o = Netz unerreichbar, . = kein Netz, X = außerhalb der Karte)
	var map := m.get_world_3d().navigation_map
	for dz in range(-10, 11):
		var row := ""
		for dx in range(-10, 11):
			var q := Vector3(b.x + dx, 0, b.z + dz)
			q.y = m.ground_y(q.x, q.z)
			var cp := NavigationServer3D.map_get_closest_point(map, q)
			var ch := "."
			if not m.inside_map(q):
				ch = "X"
			elif Vector2(cp.x - q.x, cp.z - q.z).length() < 0.4 and absf(cp.y - q.y) < 1.5:
				ch = "#" if _reach(m, a, cp, 0.6) else "o"
			row += ch
		print("   RASTER %+03d %s" % [dz, row])
	print("   BLOCKIERT ", r._blocked.filter(func(e): return (e[0] as Vector2).distance_to(Vector2(b.x, b.z)) < 12.0))
	for c in r.cover:
		if (c as Vector3).distance_to(b) < 14.0:
			print("   DECKUNG ", c)
	# Treppe: Fuß und Umgebung
	for off in [Vector3(-6, 0, 0), Vector3(6, 0, 0), Vector3(0, 0, -6), Vector3(0, 0, 6)]:
		var q: Vector3 = b + off
		q.y = m.ground_y(q.x, q.z)
		var cp := NavigationServer3D.map_get_closest_point(map, q)
		print("   UMGEBUNG ", q, " → Netz ", cp, " in Karte ", m.inside_map(q), " erreichbar ", _reach(m, a, cp, 1.0))


## KI-Hinweise: erzeugt, Arten vorhanden, nur Spielfläche, Wehrgang/Turm über das Netz erreichbar, Haltungen
func _test_hints(m: Mission, r, from: Vector3) -> void:
	var until := Time.get_ticks_msec() + 120000
	while (m.bot_hint_data == null or not m.bot_hint_data.done) and Time.get_ticks_msec() < until:
		await get_tree().create_timer(0.2).timeout
	var h = m.bot_hint_data
	check(h != null and h.done, "KI-Hinweise erzeugt")
	if h == null:
		return
	print("CASTLE_HINT_TEST ", h.stats, " gesamt ", h.hints.size())
	check(int(h.stats.high) >= 10, "Wehrgang-Hinweise (high): %d" % int(h.stats.high))
	check(int(h.stats.tower) >= 2, "Turmplattform-Hinweise (high): %d" % int(h.stats.tower))
	check(int(h.stats.choke) >= 6, "Engstellen an Tortunneln (choke): %d" % int(h.stats.choke))
	check(int(h.stats.cover) >= 8, "Deckungs-Hinweise (cover): %d" % int(h.stats.cover))
	check(h.hints.all(func(x): return m.in_play_area(x.pos)), "Alle Hinweise in der Spielfläche (DM)")
	var hi: Array = h.hints.filter(func(x): return x.get("high", false))
	var ok := 0
	for x in hi:
		if _reach(m, from, x.pos, 1.5):
			ok += 1
	check(not hi.is_empty() and ok == hi.size(), "Erhöhte Stellungen vom Start 00 erreichbar: %d/%d" % [ok, hi.size()])
	var tw: Array = h.hints.filter(func(x): return x.get("tower", false))
	var ww: Array = h.hints.filter(func(x): return x.kind == "high" and not x.get("tower", false))
	check(not tw.is_empty() and m.bot_hint_stance(tw[0].pos) == 0, "Turmplattform: stehend über der Brüstung")
	check(not ww.is_empty() and m.bot_hint_stance(ww[0].pos) == 1, "Wehrgang: hockend hinter den Zinnen")
	check(not BotGoals.map_hints((tw[0].pos as Vector3) if not tw.is_empty() else from, 30.0).is_empty(), "Bot-KI erhält Kartenhinweise (BotGoals.map_hints)")


func _finish() -> void:
	print("ERGEBNIS: Castle Karte: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(1 if failed else 0)
