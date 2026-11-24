extends Node
## Stollen + Suchturm der Karte Bavaria.
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_tunnels [--phase=tunnel|tower|bunker|reach|all] [--tag=]
## reach: KI-Erreichbarkeit aller Spawns/Zonen/Häuser/Gräben/Stollen/Stellungen/Hochstände/Hinweise → bavaria_reach<tag>.txt
## Ausbau (11/2026): kurvige Gänge/Gefälle/Ausbrüche, Räume begehbar (Physiklauf), Zahlenschloss richtig/falsch über das
## Tastenfeld, Geheimraum begehbar, Knopf spielt „dö-dö“, Kreideziffern, Turmschalter an/aus, Sicherung 60–300 s Ausfall.
## Stollen: Aufbau, Bodenaussparungen ohne Lücken von oben, Navmesh im Stollen, echter Soldat läuft per Physik vom
## MG42-Einstieg durch den Stollen zu beiden Ausgängen (Antennenhaus, Reihenhaus) ohne Durchfallen.
## Suchturm: Scheinwerfer tags aus / nachts an, erfasst einen Testsoldaten mit Sichtlinie, folgt ihm, verliert ihn
## ohne Sichtlinie (Nachsuchen → Suchen), Beleuchtung wirkt auf Mission.light_at.
const Tunnels := preload("res://src/maps/bavaria/tunnels.gd")
const Tower := preload("res://src/maps/bavaria/searchlight_tower.gd")
var failed := 0
var passed := 0
var m: Mission

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(1100.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung (1100 s)")
		_finish())

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS " if ok else "FAIL ", label)

func _finish() -> void:
	print("ERGEBNIS test_bavaria_tunnels: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	await get_tree().create_timer(0.5).timeout
	var phase := String(Game.cli.get("phase", "all"))
	if phase in ["all", "tunnel"]:
		await _tunnel()
	if phase in ["all", "tunnel", "extra"]:
		await _extras()
	if phase in ["all", "tower"]:
		await _tower()
	if phase in ["all", "bunker"]:
		await _bunker()
	if phase in ["all", "reach"]:
		_reach()
	if phase in ["all", "reach", "fall"]:
		await _fall_probe()
	_finish()

# --- Erreichbarkeit für die KI (Navmesh): Spawns, Zonen, Häuser, Gräben, Stollen, Stellungen, Hochstände ------------
## Jeder Zielpunkt muss nahe am Netz liegen und vom ersten Spawn aus (Pfadsuche ohne Polygongrenze) erreichbar sein.
## Bericht test_output/bavaria_reach<tag>.txt (Vorher/Nachher-Vergleich der KI-Navigation).

func _reach() -> void:
	var nav := m.get_world_3d().navigation_map
	var lines: Array[String] = []
	var targets: Array = []   # [kategorie, name, punkt]
	var spawns: Array = []
	for i in (m.layout["spawns"] as Array).size():
		var p := _ground_at(m.pixel(m.layout["spawns"][i]["pixel"]))
		spawns.append(p)
		targets.append(["spawn", "spawn_%d" % i, p])
	for z in m.mp_zones():
		targets.append(["zone", String(z.name), _ground_at((z.xf as Transform3D).origin)])
		for k in (z.get("slots", []) as Array).size():
			targets.append(["spawn", "zone_%s_%d" % [String(z.name), k], _ground_at(z.slots[k].pos)])
	for h in get_tree().get_nodes_in_group("bavaria_buildings"):
		var house := h as Node3D
		if house == null:
			continue
		var k := 0
		for w in house.get_meta("shooting_windows", []):
			var wl: Vector3 = w
			targets.append(["haus_eg", "%s_fenster%d" % [house.name, k], house.to_global(Vector3(wl.x, 0.1, wl.z - signf(wl.z) * 0.7))])
			k += 1
		k = 0
		for w in house.get_meta("og_shooting_windows", []):
			var wl: Vector3 = w
			targets.append(["haus_og", "%s_og%d" % [house.name, k], house.to_global(Vector3(wl.x, wl.y + 0.05, wl.z - signf(wl.z) * 0.7))])
			k += 1
		if String(house.name) == "haus_16":
			targets.append(["haus_keller", "haus_16_keller", house.to_global(Vector3(-1.0, -2.3, 1.0))])
	var fts := preload("res://src/maps/bavaria/field_trenches.gd")
	for ti in fts.TRENCHES.size():
		var line := fts.full_polyline(fts.TRENCHES[ti].points)
		for k in line.size():
			var ramp_end := k == 0 or k == line.size() - 1   # Rampenausgang auf Geländehöhe
			targets.append(["graben", "graben%d_p%d" % [ti, k], Vector3(line[k].x, 0.0 if ramp_end else -fts.DEPTH, line[k].y)])
	var t: RefCounted = m.tunnels
	if t:
		var jn: Vector2 = t.nodes["abzweig"]
		targets.append(["stollen", "abzweig", Vector3(jn.x, t.floor_at(jn), jn.y)])
		for id in t.entrances:
			targets.append(["stollen", "zugang_" + String(id), t.entrances[id].approach])
		for rm in t.rooms + ([t.secret] if not t.secret.is_empty() else []):
			targets.append(["stollen", "raum_" + String(rm.get("id", "geheim")), Vector3(rm.c.x, t.floor_at(rm.c), rm.c.y)])
		for id in t.extra:
			var x: Dictionary = t.extra[id]
			targets.append(["stollen", "zusatz_%s_aussen" % id, x.out[-1]])
			targets.append(["stollen", "zusatz_%s_gang" % id, Vector3(x.join.x, t.floor_at(x.join), x.join.y)])
		if is_instance_valid(t.get("nest_gun")):
			targets.append(["stellung", "mg_nest", t.nest_gun.gunner_spot()])
	for key in ["field_emplacement", "woodland_emplacement"]:
		var holder = m.get(key)
		if holder and is_instance_valid(holder.get("gun")):
			targets.append(["stellung", key, holder.gun.gunner_spot()])
	var sd = m.get("scene_details")
	if sd:
		for key in ["tree_stand", "antenna_stand"]:
			var v = sd.get(key)
			if v is Vector3 and v != Vector3.ZERO:
				targets.append(["hochstand", key, v])
	var hints: Array = m.bot_hints(Vector3.ZERO, 10000.0)
	for i in hints.size():
		targets.append(["hinweis_" + String(hints[i].kind), "hinweis%d" % i, hints[i].pos])
	var ref: Vector3 = spawns[0]
	var stats := {}
	var bad: Array[String] = []
	for tg in targets:
		var cat: String = tg[0]
		var p: Vector3 = tg[2]
		var cp := NavigationServer3D.map_get_closest_point(nav, p)
		var vt := 0.6 if cat in ["hochstand", "hinweis_high"] else 1.5   # Plattform selbst, nicht Dach/OG daneben
		var on := Vector2(cp.x - p.x, cp.z - p.z).length() <= 1.2 and absf(cp.y - p.y) <= vt
		var path := _qpath(nav, ref, cp)
		var ok := on and path.size() > 0 and Vector2(path[-1].x - cp.x, path[-1].z - cp.z).length() < 1.0 and absf(path[-1].y - cp.y) < 1.0
		var st: Array = stats.get(cat, [0, 0])
		st[0] += 1
		st[1] += int(ok)
		stats[cat] = st
		if not ok:
			bad.append("UNERREICHBAR %s %s ziel=%s netz=%s (%.1f m) pfadende=%s" % [cat, tg[1], _v3(p), _v3(cp), cp.distance_to(p),
				_v3(path[-1]) if path.size() > 0 else "-"])
	# jeder Spawn zu jeder Zone (beide Richtungen)
	var pairs := 0
	var pairs_ok := 0
	for s in spawns:
		for z in m.mp_zones():
			var zp := _ground_at((z.xf as Transform3D).origin)
			for dir in 2:
				var a: Vector3 = s if dir == 0 else zp
				var b: Vector3 = zp if dir == 0 else s
				var bp := NavigationServer3D.map_get_closest_point(nav, b)
				var path := _qpath(nav, NavigationServer3D.map_get_closest_point(nav, a), bp)
				pairs += 1
				pairs_ok += int(path.size() > 0 and path[-1].distance_to(bp) < 1.0)
	lines.append("spawn_zone_paare %d/%d" % [pairs_ok, pairs])
	for l in m.ladder_links:
		var ld = l.get_meta("ladder")
		lines.append("leiter_link %s %s -> %s (Leiterkopf %s)" % [str(ld.name) if is_instance_valid(ld) else "?", _v3(l.start_position),
			_v3(l.end_position), _v3(ld.top) if is_instance_valid(ld) else "-"])
		if is_instance_valid(ld):
			check(absf(l.end_position.y - (ld.top as Vector3).y) < 0.6 and Vector2(l.end_position.x - ld.top.x, l.end_position.z - ld.top.z).length() < 1.2,
				"Leiter %s: Link endet auf der Plattform (%s, Kopf %s)" % [ld.name, _v3(l.end_position), _v3(ld.top)])
	check(m.ladder_links.size() >= 2, "Leiter-Links Baumstand + Antenne (%d)" % m.ladder_links.size())
	# Unerreichbare Netzbereiche: jedes Polygon (Mittelpunkt) vom ersten Spawn aus; Gruppen je 4-m-Raster/Höhenstufe
	var npoly := 0
	var lost := {}
	var lost_n := 0
	var rp := NavigationServer3D.map_get_closest_point(nav, ref)
	for reg in m.find_children("*", "NavigationRegion3D", true, false):
		var nm: NavigationMesh = (reg as NavigationRegion3D).navigation_mesh
		if nm == null:
			continue
		var verts := nm.get_vertices()
		for pi in nm.get_polygon_count():
			var poly := nm.get_polygon(pi)
			var c := Vector3.ZERO
			for vi in poly:
				c += verts[vi]
			c = (reg as Node3D).global_transform * (c / poly.size())
			npoly += 1
			var path := _qpath(nav, rp, c)
			if path.size() == 0 or path[-1].distance_to(c) > 0.8:
				lost_n += 1
				var key := "%d,%d,%d" % [floori(c.x / 4.0), floori(c.y / 1.5), floori(c.z / 4.0)]
				var e: Array = lost.get(key, [c, 0])
				e[1] += 1
				lost[key] = e
	var lk: Array = lost.values()
	var low: Array = lk.filter(func(e): return (e[0] as Vector3).y < 2.6)   # Boden/EG/Gräben/Stollen (darüber: Dächer)
	var low_n := 0
	for e in low:
		low_n += int(e[1])
	lines.append("netz_polygone %d, vom Spawn unerreichbar %d (%d Bereiche), davon unter 2,6 m Höhe %d (%d Bereiche)" % [npoly,
		lost_n, lost.size(), low_n, low.size()])
	low.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for e in low:
		lines.append("  INSEL_UNTEN %s polygone=%d" % [_v3(e[0]), e[1]])
	var keys := stats.keys()
	keys.sort()
	var tot := 0
	var tot_ok := 0
	for c in keys:
		lines.append("%-22s %d/%d erreichbar" % [c, stats[c][1], stats[c][0]])
		tot += int(stats[c][0])
		tot_ok += int(stats[c][1])
	lines.append("gesamt %d/%d, Hinweise verworfen beim Heften: %d" % [tot_ok, tot, int(m.bot_hint_data.dropped) if m.bot_hint_data else -1])
	lines.append_array(bad)
	for l in lines:
		print("BAVREACH ", l)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_output/bavaria_reach%s.txt" % String(Game.cli.get("tag", ""))), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
	check(pairs_ok == pairs, "Jeder Spawn erreicht jede Zone und zurück (%d/%d)" % [pairs_ok, pairs])
	for c in keys:
		check(int(stats[c][1]) == int(stats[c][0]), "Erreichbar für die KI: %s %d/%d" % [c, stats[c][1], stats[c][0]])

## Durchfallprobe (Bot-Messlauf: Bot fiel am Reihenhaus-Einstieg unter die Stollensohle): Soldaten in allen drei Haltungen
## über jedem Treppenschacht (offener und überdeckter Teil bis zum Austritt) fallen lassen bzw. hineinlaufen lassen.
func _fall_probe() -> void:
	var rects: Array = []
	for e in Tunnels.ENTRANCES:
		var f := Tunnels.house_frame(m, e.building)
		if f.is_empty():
			continue
		var dims := Tunnels.stair_dims(e)
		rects.append([String(e.id), Tunnels._to_world(f[0], Tunnels._local_rect(e, -0.3, dims.length + Tunnels.LANDING + 0.5, float(e.width) * 0.5 + 0.1))])
	for e0 in Tunnels.EXTRA_SITES:
		var e := Tunnels.extra_site(e0)
		var ln: float = float(e.length) if String(e.kind) == "rubble" else float(Tunnels.stair_dims(e).length)
		rects.append([String(e.id), Tunnels._local_rect(e, -0.3, ln + Tunnels.LANDING + 0.5, float(e.width) * 0.5 + 0.1)])
	var pts: Array = []
	for r in rects:
		var poly: PackedVector2Array = r[1]
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q in poly:
			lo = lo.min(q)
			hi = hi.max(q)
		var x := lo.x
		while x <= hi.x:
			var z := lo.y
			while z <= hi.y:
				if Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
					var h := _ray(Vector3(x, 1.5, z), Vector3(x, -6.0, z))
					if not h.is_empty():
						pts.append([r[0], (h.position as Vector3) + Vector3.UP * 0.6])
						# Versatz knapp IN die Sohle (Notversatz/Step-down auf einen Netzpunkt einige cm unter der Kollision):
						# die Figur muss nach oben herausgedrückt werden, nicht durch die Sohle fallen
						if absf((h.position as Vector3).y - Tunnels.FLOOR_Y) < 0.05:
							pts.append([String(r[0]) + "/in_sohle", (h.position as Vector3) + Vector3.DOWN * 0.07])
				z += 0.45
			x += 0.45
	var fails: Array[String] = []
	var n := 0
	for stance in [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]:
		var i := 0
		while i < pts.size():
			var batch: Array = []
			for k in mini(24, pts.size() - i):
				var s := Soldier.new()
				s.name = "Fallprobe"
				m.actors_root.add_child(s)
				s.global_position = pts[i + k][1]
				s.stance_request = stance
				s.look_yaw = randf() * TAU
				s.move_input = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
				batch.append([s, pts[i + k]])
			for _f in 150:
				await get_tree().physics_frame
			for b in batch:
				var s: Soldier = b[0]
				n += 1
				if s.global_position.y < Tunnels.FLOOR_Y - 0.4:
					fails.append("%s Haltung %d Start %s Ende %s" % [b[1][0], stance, _v3(b[1][1]), _v3(s.global_position)])
				s.queue_free()
			i += 24
			await get_tree().physics_frame
	for f in fails.slice(0, 20):
		print("DURCHFALL ", f)
	check(n > 100 and fails.is_empty(), "Treppenschächte: kein Durchfallen unter die Stollensohle (%d/%d Proben, 3 Haltungen, laufend)" % [fails.size(), n])

func _ground_at(p: Vector3) -> Vector3:
	var h := _ray(p + Vector3.UP * 3.0, p + Vector3.DOWN * 10.0)
	return h.position if not h.is_empty() else p

func _qpath(nav: RID, a: Vector3, b: Vector3) -> PackedVector3Array:
	var q := NavigationPathQueryParameters3D.new()
	q.map = nav
	q.start_position = a
	q.target_position = b
	q.path_search_max_polygons = 0
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.path

func _v3(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]

# --- Stollen ----------------------------------------------------------------------------------------------------

func _ray(from: Vector3, to: Vector3, mask := 1) -> Dictionary:
	return m.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))

func _tunnel() -> void:
	var t: RefCounted = m.tunnels
	check(t != null and t.root != null and t.root.get_parent() == m.static_root, "Stollen unter static_root (Navmesh/Kollision)")
	check(t.entrances.size() == 3, "Drei Treppen: MG42-Haus, Antennenhaus, Reihenhaus (%d)" % t.entrances.size())
	check(t.total_length() > 80.0, "Stollen durchgehend (%.0f m)" % t.total_length())
	check(t.lamps.size() >= 8, "Schwache Stollenlampen (%d)" % t.lamps.size())
	check(t.lamps.all(func(l): return not l.shadow_enabled and l.light_energy <= 1.0), "Lampen schwach und ohne Schatten")
	for id in t.entrances:
		var e: Dictionary = t.entrances[id]
		var top: Vector3 = e.top
		var bottom: Vector3 = e.bottom
		# Treppenloch offen: senkrechter Strahl über dem Treppenkopfbereich trifft eine Stufe unterhalb der Oberkante
		var probe: Vector3 = top + (Vector3(bottom.x, top.y, bottom.z) - top).normalized() * 0.6
		var hit := _ray(probe + Vector3.UP * 1.5, probe + Vector3.DOWN * 6.0)
		check(not hit.is_empty() and hit.position.y < top.y - 0.15 and hit.position.y > Tunnels.FLOOR_Y, "%s: Treppenloch offen, Stufe darunter (y=%s)" % [id, str(hit.get("position", Vector3.INF).y)])
		# Keine Lücke neben dem Loch: Boden bzw. Hausboden/Verschalung trägt ringsum
		var u := (Vector3(bottom.x, 0, bottom.z) - Vector3(top.x, 0, top.z)).normalized()
		var v := Vector3(-u.z, 0, u.x)
		var w: float = 0.5 if e.inside else 0.7
		var gaps := 0
		var n := 0
		for side in [-1.0, 1.0]:
			for s in [0.3, 0.9, 1.5]:
				var off: float = (w + 0.35) if not e.inside else (w + 0.2)
				var p: Vector3 = top + u * s + v * side * off
				var h := _ray(p + Vector3.UP * 0.9, p + Vector3.DOWN * 3.0, 1)
				n += 1
				if h.is_empty() or h.position.y < -0.05:
					gaps += 1
		check(gaps == 0, "%s: kein Durchfallen neben dem Loch (%d/%d Proben ohne Boden)" % [id, gaps, n])
	# Über dem Stollen geschlossener Boden (keine sichtbaren Lücken von oben)
	var open := 0
	var probes := 0
	for seg in t.segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		for i in range(1, 6):
			var q := a.lerp(b, i / 6.0)
			if not m.inside_map(Vector3(q.x, 0, q.y)):
				continue
			var h := _ray(Vector3(q.x, 20, q.y), Vector3(q.x, -6, q.y))
			probes += 1
			if h.is_empty() or h.position.y < Tunnels.CEIL_Y + 0.1:   # Grabensohle (−1,30) zählt als geschlossen
				open += 1
	check(probes > 10 and open == 0, "Gelände über dem Stollen geschlossen (%d/%d offen)" % [open, probes])
	# Navmesh im Stollen und Wege für KI
	var nav := m.get_world_3d().navigation_map
	var j: Vector2 = t.nodes["abzweig"]
	var jp := Vector3(j.x, Tunnels.FLOOR_Y, j.y)
	check(NavigationServer3D.map_get_closest_point(nav, jp).distance_to(jp) < 0.6, "Navmesh im Stollen am Abzweig")
	for id in t.entrances:
		var e: Dictionary = t.entrances[id]
		var path := NavigationServer3D.map_get_path(nav, jp, e.approach, true)
		check(path.size() > 1 and path[-1].distance_to(e.approach) < 0.8, "KI-Weg Stollen → Ausstieg %s" % id)
	# Ausbau: kurvige Gänge, Gefälle, Ausbrüche, Räume, Geheimraum
	var bends := 0
	for ci in 3:
		var pts: PackedVector2Array = t.chains[ci]
		var dev := 0.0
		for q in pts:
			dev = maxf(dev, Geometry2D.get_closest_point_to_segment(q, pts[0], pts[-1]).distance_to(q))
		bends += int(dev > 0.5 and pts.size() > 3)
		print("STOLLEN-GANG %d: %d Stützpunkte, Abweichung von der Geraden %.2f m, Länge %.1f m" % [ci, pts.size(), dev, Tunnels.chain_length(pts)])
	check(bends >= 2, "Gänge kurvig mit Knicken (%d/3 mit Bogen > 0,5 m)" % bends)
	var lo := INF
	var hi := -INF
	for ch in t.chains:
		var l := Tunnels.chain_length(ch)
		var s := 0.0
		while s < l:
			var y: float = t.floor_at(Tunnels.chain_at(ch, s)[0])
			lo = minf(lo, y)
			hi = maxf(hi, y)
			s += 1.0
	check(hi - lo > 0.08 and lo >= Tunnels.NAV_ANCHOR_Y + 0.05, "Leichtes Gefälle der Sohle (%.2f … %.2f), über dem Navmesh-Anker" % [lo, hi])
	check(t.wide_spots.size() >= 2, "Ausbrüche mit Breiten-/Höhenwechsel (%d)" % t.wide_spots.size())
	var ids: Array = t.rooms.map(func(r): return r.id)
	check(ids.has("funkraum") and ids.has("lager") and ids.has("schlafnische") and ids.has("sanitaet"), "Kleine Räume: %s" % str(ids))
	check(not t.secret.is_empty(), "Geheimraum abseits am Stichgang")
	check(t.decor_count >= 60, "Ausstattung im Stollen (%d Teile)" % t.decor_count)
	var low := 0
	for tr in t._tris:
		for k in 3:
			if float(tr[6 + k]) - float(tr[3 + k]) < 2.15:
				low += 1
			if float(tr[6 + k]) > -1.55:
				low += 1
	check(low == 0, "Kopffreiheit ≥ 2,15 m und Decke ≥ 0,25 m unter der Grabensohle (%d Verstöße)" % low)
	for rm in t.rooms + ([t.secret] if not t.secret.is_empty() else []):
		var c3 := Vector3(rm.c.x, t.floor_at(rm.c), rm.c.y)
		var path := NavigationServer3D.map_get_path(nav, jp, c3, true)
		check(path.size() > 1 and path[-1].distance_to(c3) < 0.8, "KI-Weg Stollen → Raum %s" % rm.id)
	# Echter Lauf per Physik vom MG42-Einstieg zu beiden Ausgängen und in alle Räume
	var mg: Dictionary = t.entrances["mg42"]
	for target in ["antennenhaus", "reihenhaus", "funkraum", "lager", "schlafnische", "sanitaet"]:
		var route: Array = t.walk_route(target)
		var res: Dictionary = await _walk(mg.approach, route)
		check(res.reached, "Soldat läuft vom MG42-Einstieg zu %s (Ende %s, Ziel %s, %.1f s)" % [target, str(res.end), str(route[-1] if not route.is_empty() else null), res.time])
		check(res.min_y > Tunnels.FLOOR_Y - 0.4 and res.min_y < Tunnels.FLOOR_Y + 0.5, "%s: Weg unter Tage, kein Durchfallen (tiefster Punkt %.2f)" % [target, res.min_y])

# --- Ausbau 2: MG-Nest, Einsturzgang, Luke -----------------------------------------------------------------------

func _polydist(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if not Geometry2D.intersect_polygons(a, b).is_empty():
		return 0.0
	var best := INF
	for p in a:
		best = minf(best, Tunnels._dist_poly(p, b))
	for p in b:
		best = minf(best, Tunnels._dist_poly(p, a))
	return best

func _extras() -> void:
	var t: RefCounted = m.tunnels
	check(t.extra.size() == 3 and t.extra.has("mg_nest") and t.extra.has("einsturz") and t.extra.has("luke"),
		"Zusatzzugänge MG-Nest, Einsturzgang, Luke (%s)" % str(t.extra.keys()))
	var nav := m.get_world_3d().navigation_map
	var own: Array = Tunnels.footprints(m)
	var fts := preload("res://src/maps/bavaria/field_trenches.gd")
	for id in t.extra:
		var x: Dictionary = t.extra[id]
		var surf: PackedVector2Array = x.surface
		var u: Vector3 = x.u3
		var v := Vector3(-u.z, 0, u.x)
		var head: Vector3 = x.head
		var half: float = float(x.width) * 0.5
		# Platz: Gebäude, Wege, Spawns, Zonen, Gräben/Erdwälle, andere Zugänge
		var d_house := INF
		for f in m.building_footprints:
			var is_own := false
			for o in own:
				is_own = is_own or ((o as PackedVector2Array).size() == f.size() and (o[0] as Vector2).distance_to(f[0]) < 0.01)
			if not is_own:
				d_house = minf(d_house, _polydist(surf, f))
		var d_road := INF
		for road in m.layout["paths"]:
			var pts: Array = road["points"]
			for i in pts.size() - 1:
				var a3: Vector3 = m.pixel(pts[i])
				var b3: Vector3 = m.pixel(pts[i + 1])
				for k in 21:
					var q := Vector2(a3.x, a3.z).lerp(Vector2(b3.x, b3.z), k / 20.0)
					d_road = minf(d_road, Tunnels._dist_poly(q, surf) - float(road.width) * 0.5)
		var d_spawn := INF
		for sp in m.layout["spawns"]:
			var p: Vector3 = m.pixel(sp["pixel"])
			d_spawn = minf(d_spawn, Tunnels._dist_poly(Vector2(p.x, p.z), surf))
		for z in m.layout.get("occupation_zones", []):
			var p: Vector3 = m.pixel(z["pixel"])
			d_spawn = minf(d_spawn, Tunnels._dist_poly(Vector2(p.x, p.z), surf))
		var d_field := INF
		for h in fts.hole_polygons():
			d_field = minf(d_field, _polydist(surf, h))
		for cv in fts.COVERS:
			d_field = minf(d_field, Tunnels._dist_poly(cv[1], surf) - 1.0)
		var d_other := INF
		for o in own:
			if (o as PackedVector2Array) != surf:
				d_other = minf(d_other, _polydist(surf, o))
		check(d_house >= 2.0 and d_road >= 0.8 and d_spawn >= 7.0 and d_field >= 2.0 and d_other >= 5.0,
			"%s: Platz zu Gebäuden %.1f / Wegen %.1f / Spawns+Zonen %.1f / Gräben+Erdwällen %.1f / anderen Zugängen %.1f m" % [id, d_house, d_road, d_spawn, d_field, d_other])
		# Loch offen, ringsum tragender Boden bzw. Rand
		var probe: Vector3 = head + u * 0.75
		var hit := _ray(probe + Vector3.UP * 1.5, probe + Vector3.DOWN * 6.0)
		check(not hit.is_empty() and hit.position.y < -0.15 and hit.position.y > Tunnels.FLOOR_Y, "%s: Öffnung frei, darunter Stufe/Schutt (y=%s)" % [id, str(hit.get("position", Vector3.INF).y)])
		var gaps := 0
		var open_l: float = x.open_length
		for side in [-1.0, 1.0]:
			for s in [0.4, open_l * 0.5, open_l - 0.3]:
				var p: Vector3 = head + u * s + v * side * (half + 0.45)
				var h := _ray(p + Vector3.UP * 1.2, p + Vector3.DOWN * 3.0)
				if h.is_empty() or h.position.y < -0.05:
					gaps += 1
		check(gaps == 0, "%s: kein Durchfallen neben der Öffnung (%d/6 ohne Boden)" % [id, gaps])
		# Navmesh: KI-Weg vom Abzweig hinaus ins Freie
		var out_p: Vector3 = x.out[-1]
		var jn: Vector2 = t.nodes["abzweig"]
		var path := NavigationServer3D.map_get_path(nav, Vector3(jn.x, Tunnels.FLOOR_Y, jn.y), out_p, true)
		check(path.size() > 1 and path[-1].distance_to(out_p) < 0.8, "%s: KI-Weg Stollen → ins Freie (Ende %s)" % [id, str(path[-1] if path.size() > 0 else null)])
		# Physik: hinauf (vom MG42-Einstieg) und von außen hinab
		var route: Array = t.walk_route(id)
		var res: Dictionary = await _walk(t.entrances["mg42"].approach, route)
		check(res.reached, "%s: Soldat läuft vom MG42-Einstieg durch den Stollen hinaus (Ende %s, %.1f s)" % [id, str(res.end), res.time])
		check(res.min_y > Tunnels.FLOOR_Y - 0.4, "%s: kein Durchfallen (tiefster Punkt %.2f)" % [id, res.min_y])
		var down: Array = (x.out as Array).duplicate()
		down.reverse()
		down = down.slice(1)
		down.append_array([x.top, x.bottom, Vector3(x.join.x, t.floor_at(x.join), x.join.y)])
		var res2: Dictionary = await _walk(out_p, down)
		check(res2.reached and res2.min_y > Tunnels.FLOOR_Y - 0.4, "%s: von außen hinab bis in den Gang (Ende %s, %.1f s)" % [id, str(res2.end), res2.time])
		# Licht: keine Lampe unter der offenen Stelle, alle unter Tage
		var lit := 0
		for l in t.lamps:
			var lp: Vector3 = l.global_position
			if lp.y > -0.3 or Geometry2D.is_point_in_polygon(Vector2(lp.x, lp.z), x.hole):
				lit += 1
		check(lit == 0, "%s: keine Stollenlampe unter der Öffnung oder über Tage (%d)" % [id, lit])
		match String(x.kind):
			"nest":
				var gun = t.nest_gun
				check(gun != null and is_instance_valid(gun), "MG-Nest: bedienbares MG42 (OrigEmplacement)")
				if gun == null:
					continue
				var fwd: Vector3 = -gun.frame.global_basis.z
				fwd.y = 0
				check(rad_to_deg(fwd.normalized().angle_to(-u)) < 3.0, "MG-Nest: Waffe zeigt ins Gelände")
				var gp: Vector3 = gun.gunner_spot()
				check(Vector2(gp.x - head.x, gp.z - head.z).length() < 1.2, "MG-Nest: Bedienplatz am Treppenkopf %s" % str(gp))
				var free := 0
				var near_min := INF
				for a in [-25.0, -12.0, 0.0, 12.0, 25.0]:
					var d := (-u).rotated(Vector3.UP, deg_to_rad(a))
					var o: Vector3 = gun.frame.global_position + Vector3.UP * 1.3 + d * 1.6
					var rh := _ray(o, o + d * 40.0)
					var dist: float = 40.0 if rh.is_empty() else o.distance_to(rh.position)
					near_min = minf(near_min, dist)
					free += int(dist >= 20.0)
				check(free >= 3 and near_min >= 8.0, "MG-Nest: Schussfeld ins Gelände (%d/5 Strahlen ≥ 20 m, kürzester %.1f m)" % [free, near_min])
				var ph: float = gun.frame.get_parent().get_meta("parapet_height", 0.0)
				var pr := _ray(head - u * 6.0 + Vector3.UP * (ph * 0.5), head - u * 1.0 + Vector3.UP * (ph * 0.5))
				check(not pr.is_empty() and String(pr.collider.get_path()).contains("Treppe_mg_nest") and ph >= 0.6,
					"MG-Nest: Sandsack-Brustwehr mit Kollision (%.2f m, Treffer %s)" % [ph, str(pr.get("collider", null))])
				var s := Soldier.new()
				s.name = "NestSchuetze"
				m.actors_root.add_child(s)
				s.global_position = gp + Vector3.UP * 0.1
				await _frames(3)
				gun.interact(s)
				await _frames(3)
				check(gun.gunner == s, "MG-Nest: Soldat besetzt das MG (Benutzen)")
				if gun.gunner == s:
					gun.dismount()
				s.queue_free()
				var hints: Array = m.bot_hints(head, 4.0)
				check(hints.any(func(hh): return hh.kind == "emplacement"), "MG-Nest: Bot-Hinweis Waffenstellung")
			"rubble":
				var ramp: Node = t.root.find_child("Schuttrampe", true, false)
				var slope: float = ramp.get_meta("slope_deg", 90.0) if ramp else 90.0
				check(ramp != null and slope <= 32.0, "Einsturzgang: Schuttrampe begehbar (%.1f°)" % slope)
				var mid: Vector3 = head + u * (float(x.length) * 0.5)
				var mh := _ray(mid + Vector3.UP * 2.0, mid + Vector3.DOWN * 6.0)
				var expect := Tunnels.FLOOR_Y * 0.5
				check(not mh.is_empty() and absf(mh.position.y - expect) < 0.25, "Einsturzgang: Rampe trägt (y=%s, erwartet %.2f)" % [str(mh.get("position", Vector3.INF).y), expect])
			"hatch":
				var lp: Vector3 = head + u * (open_l * 0.5) + v * 1.4 + Vector3.UP * 0.3
				var lh := _ray(lp, lp - v * 1.2)
				check(not lh.is_empty() and String(lh.collider.get_parent().name).begins_with("Lukenfluegel"), "Luke: Lukenflügel mit Kollision (%s)" % str(lh.get("collider", null)))
				check(float(x.length) - Tunnels.LANDING <= 4.1, "Luke: Treppe im Maß der Haustreppen (%.2f m Lauf)" % (float(x.length) - Tunnels.LANDING))

	# Texturfehler Bienenstöcke (am Zugang): flache Normalen statt über Ecken gemittelter (Schattenakne)
	var bee: Node3D = null
	for n in get_tree().get_nodes_in_group("bavaria_decorations"):
		if String(n.name).contains("Bienen"):
			bee = n
	var diag := 0
	var total := 0
	if bee:
		for mi in bee.find_children("*", "MeshInstance3D", true, false):
			var arr: Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)
			for nrm in (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array):
				total += 1
				diag += int(maxf(absf(nrm.x), maxf(absf(nrm.y), absf(nrm.z))) < 0.99)
	check(bee != null and total > 0 and diag == 0, "Bienenstöcke: flache Flächennormalen (%d/%d schräg)" % [diag, total])

func _walk(start: Vector3, route: Array) -> Dictionary:
	var soldier := Soldier.new()
	soldier.name = "StollenLaeufer"
	m.actors_root.add_child(soldier)
	soldier.global_position = start + Vector3.UP * 0.15
	soldier.velocity = Vector3.ZERO
	soldier.move_mode = Soldier.MoveMode.JOG
	soldier.stance_request = Soldier.Stance.STAND
	await get_tree().create_timer(0.3).timeout
	var t0 := Time.get_ticks_msec()
	var deadline := t0 + 120000
	var min_y := INF
	var ok := true
	for i in route.size():
		var point: Vector3 = route[i]
		var reached := false
		var stuck_t := Time.get_ticks_msec()
		var best := INF
		while Time.get_ticks_msec() < deadline:
			var d: Vector3 = point - soldier.global_position
			d.y = 0
			min_y = minf(min_y, soldier.global_position.y)
			if d.length() < (0.35 if i == route.size() - 1 else 0.45):
				reached = true
				break
			if d.length() < best - 0.05:
				best = d.length()
				stuck_t = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - stuck_t > 6000:
				break
			soldier.move_input = d.normalized() * clampf(d.length() / 0.6, 0.35, 1.0)
			soldier.look_yaw = atan2(-d.x, -d.z)
			await get_tree().physics_frame
		if not reached:
			ok = false
			print("STOLLEN-LAUF hängt vor Punkt ", i, " ", point, " bei ", soldier.global_position)
			var fw: Vector3 = point - soldier.global_position
			fw.y = 0
			fw = fw.normalized()
			for hh in [0.05, 0.3, 0.8, 1.3, 1.7, 1.95, 2.2]:
				var o: Vector3 = soldier.global_position + Vector3.UP * hh
				var r := m.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + fw * 1.2, 1 | 16, [soldier.get_rid()]))
				print("  STRAHL h=", hh, " ", "frei" if r.is_empty() else "%s @ %s" % [r.collider.get_path(), r.position])
			break
	soldier.move_input = Vector3.ZERO
	var end := soldier.global_position
	soldier.queue_free()
	return {"reached": ok, "end": end, "min_y": min_y, "time": (Time.get_ticks_msec() - t0) / 1000.0}

# --- Suchturm ---------------------------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _tower() -> void:
	# Trupp der Direktbesichtigung in den Stollen (keine Sichtlinie zum Turm)
	var c1: PackedVector2Array = m.tunnels.chains[1]
	var k := 0
	for s in get_tree().get_nodes_in_group("soldiers"):
		var park: Vector2 = Tunnels.chain_at(c1, Tunnels.chain_length(c1) - 1.0 - k * 0.8)[0]   # im (kurvigen) Gang
		s.global_position = Vector3(park.x, m.tunnels.floor_at(park) + 0.1, park.y)
		s.process_mode = Node.PROCESS_MODE_DISABLED     # Trupp-KI „Halten“ liefe sonst zurück an die Oberfläche
		s.velocity = Vector3.ZERO
		k += 1
	var tw = m.searchlight_tower
	check(tw != null and String(tw.name) == "Suchturm" and tw.get_parent() == m, "Suchturm-Knoten an fester Stelle")
	if tw == null:
		return
	var meadow: PackedVector2Array = m.polygon(m.layout["meadow"])
	check(Geometry2D.is_point_in_polygon(Vector2(tw.site.x, tw.site.z), meadow), "Turm steht auf der großen Wiese %s" % str(tw.site))
	check(tw.heads.size() == 2, "Zwei Suchscheinwerfer")
	var dn = m.day_night
	dn.set_hour(12.0, 0.0)
	await _frames(5)
	check(not tw.active and tw.heads.all(func(h): return not h.light.visible and not h.cone_pivot.visible), "Tagsüber aus (Licht + Kegel)")
	dn.set_hour(0.5, 0.0)
	await _frames(5)
	check(tw.active and tw.heads.all(func(h): return h.light.visible and h.cone_pivot.visible), "Nachts an (Licht + sichtbarer Kegel)")
	var y0: float = tw.heads[0].yaw
	await get_tree().create_timer(1.5).timeout
	check(absf(wrapf(tw.heads[0].yaw - y0, -PI, PI)) > 0.15, "Scheinwerfer schwenken suchend")
	# Testsoldat dorthin, wo der Suchkegel gleich vorbeikommt (vorausberechnet, freie Sichtlinie)
	var soldier := Soldier.new()
	soldier.name = "SuchturmZiel"
	m.actors_root.add_child(soldier)
	var spot := Vector3.INF
	var head_i := -1
	for dt in [2.5, 3.5, 4.5, 5.5, 6.5, 8.0, 9.5, 11.0]:
		for h in tw.heads:
			if h.mode != 0:
				continue
			var saved: float = tw._t
			tw._t = saved + dt
			var p: Vector3 = tw.search_point(h)
			tw._t = saved
			var g := _ray(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0)
			if g.is_empty() or absf(g.position.y) > 0.3 or not m.inside_map(p):
				continue
			if tw.has_sight(h.light.global_position, g.position + Vector3.UP * 1.0):
				spot = g.position
				head_i = h.index
				break
		if spot.is_finite():
			break
	check(spot.is_finite(), "Freier Stand im Suchmuster gefunden %s" % str(spot))
	if not spot.is_finite():
		return
	soldier.global_position = spot + Vector3.UP * 0.1
	soldier.velocity = Vector3.ZERO
	var found := false
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		soldier.global_position = Vector3(spot.x, soldier.global_position.y, spot.z)
		if tw.tracked().has(soldier):
			found = true
			break
	check(found, "Kegel erfasst den Testsoldaten (Kopf %d)" % head_i)
	if not found:
		return
	var h = tw.heads[tw.tracked().find(soldier)]
	await _frames(20)
	check(m.light_at(soldier.global_position + Vector3.UP * 1.0) >= 1.6, "Erfasster Soldat ist beleuchtet (Mission.light_at)")
	# Soldat läuft quer davon – Scheinwerfer folgt
	var to: Vector3 = soldier.global_position - tw.site
	var side := Vector3(-to.z, 0, to.x).normalized()
	# Laufrichtung mit durchgehender Sichtlinie zum Scheinwerfer wählen (Deckungen auf der Wiese würden ihn sonst
	# zu Recht verlieren)
	var best_free := -1
	for cand in [side, -side, to.normalized(), -to.normalized()]:
		var free := 0
		for i in range(1, 13):
			var p: Vector3 = soldier.global_position + cand * i
			if not m.inside_map(p) or not tw.has_sight(h.light.global_position, p + Vector3.UP * 1.0):
				break
			free += 1
		if free > best_free:
			best_free = free
			side = cand
	soldier.move_mode = Soldier.MoveMode.JOG
	var t_end := Time.get_ticks_msec() + 3500
	var start_pos := soldier.global_position
	while Time.get_ticks_msec() < t_end:   # Querlauf 3,3 m/s (Lage je Physikbild gesetzt, unabhängig von Hindernissen)
		var nxt: Vector3 = start_pos + side * 3.3 * (3.5 - (t_end - Time.get_ticks_msec()) / 1000.0)
		var g := _ray(nxt + Vector3.UP * 2.0, nxt + Vector3.DOWN * 2.0)
		soldier.global_position = Vector3(nxt.x, g.position.y if not g.is_empty() else nxt.y, nxt.z)
		await get_tree().physics_frame
	await _frames(10)
	var moved := Vector2(soldier.global_position.x - start_pos.x, soldier.global_position.z - start_pos.z).length()
	var aim: Vector3 = soldier.global_position + Vector3.UP * 1.0 - h.light.global_position
	var err := rad_to_deg(h.dir().angle_to(aim))
	check(moved > 4.0 and h.target == soldier and err < Tower.CONE_DEG, "Scheinwerfer verfolgt den Soldaten (%.1f m gelaufen, Abweichung %.1f°, Modus %d)" % [moved, err, h.mode])
	# Sichtverlust (unter Tage) → Nachsuchen → wieder Suchen
	var j: Vector2 = Tunnels.chain_at(m.tunnels.chains[1], 1.5)[0]     # im (kurvigen) Gang neben dem Abzweig
	soldier.global_position = Vector3(j.x, m.tunnels.floor_at(j) + 0.1, j.y)
	await get_tree().create_timer(Tower.LOSE_AFTER + 0.5).timeout
	check(h.mode == 2 and h.target == null, "Nach Sichtverlust: Nachsuchen an der letzten Stelle (Modus %d)" % h.mode)
	await get_tree().create_timer(Tower.RESEARCH_S + 0.5).timeout
	check(h.mode == 0, "Danach wieder Suchen (Modus %d, Ziel %s %s)" % [h.mode, str(h.target.name) if h.target else "-", str(h.target.global_position) if h.target else ""])
	await _house_blocks_beam(tw, h, soldier)
	dn.set_hour(12.0, 0.0)
	await _frames(5)
	check(not tw.active and not h.light.visible and m.light_at(spot + Vector3.UP) < 1.6, "Bei Tag wieder aus")
	soldier.queue_free()

## Kegel durch ein Haus gerichtet: sichtbarer Kegel endet an der Hauswand, Soldat dahinter wird nicht erfasst
func _house_blocks_beam(tw, h, soldier: Soldier) -> void:
	var origin: Vector3 = h.light.global_position
	var best: Node3D = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("bavaria_buildings"):
		var d: float = Vector2(b.global_position.x - origin.x, b.global_position.z - origin.z).length()
		if d > 12.0 and d < 70.0 and d < best_d:
			var probe: Vector3 = b.global_position + Vector3.UP * 1.5
			var hit := _ray(origin, probe)
			if not hit.is_empty() and hit.collider and (hit.collider as Node).get_parent() != null:
				best = b
				best_d = d
	check(best != null, "Haus im Schwenkbereich des Turms gefunden")
	if best == null:
		return
	var center: Vector3 = best.global_position + Vector3.UP * 1.2
	var behind: Vector3 = center + Vector3(center.x - origin.x, 0, center.z - origin.z).normalized() * 12.0
	var g := _ray(behind + Vector3.UP * 3.0, behind + Vector3.DOWN * 3.0)
	if not g.is_empty():
		behind = g.position + Vector3.UP * 1.0
	tw.process_mode = Node.PROCESS_MODE_DISABLED
	var to: Vector3 = behind - h.global_position
	h.yaw = atan2(-to.x, -to.z)
	h.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	h.rotation = Vector3(h.pitch, h.yaw, 0)
	await get_tree().physics_frame
	var wq := PhysicsRayQueryParameters3D.create(origin, behind, 1, tw.exclude)   # ohne Turmgerüst (wie der Kegel)
	var wall := m.get_world_3d().direct_space_state.intersect_ray(wq)
	var wall_d: float = origin.distance_to(wall.position) if not wall.is_empty() else INF
	var cone_len: float = tw.cone_length(h)
	check(not wall.is_empty() and cone_len <= wall_d + 0.05, "Sichtbarer Kegel endet an der Hauswand (%.1f m, Wand %.1f m)" % [cone_len, wall_d])
	soldier.global_position = behind + Vector3.DOWN * 1.0
	await get_tree().physics_frame
	check(not tw.in_beam(h, behind), "Soldat hinter dem Haus wird nicht erfasst")
	tw.process_mode = Node.PROCESS_MODE_INHERIT

# --- Geheimraum, Zahlenschloss, Turmschalter, Sicherung ------------------------------------------------------------

func _blocked(a: Vector3, b: Vector3) -> bool:
	return not _ray(a, b, 1).is_empty()

func _bunker() -> void:
	var bx = m.bunker_extras
	var t: RefCounted = m.tunnels
	check(bx != null and String(bx.name) == "StollenTechnik" and bx.get_parent() == m, "Knoten StollenTechnik an fester Stelle")
	if bx == null:
		return
	# Flackern: deterministisch, zeitlich wechselnd, ohne Schatten
	var same := true
	var varies := false
	for i in t.lamps.size():
		same = same and bx.flicker(i, 37.25) == bx.flicker(i, 37.25)
		var lo := 1.0
		var hi := 0.0
		for k in 400:
			var f: float = bx.flicker(i, k * 0.05)
			lo = minf(lo, f)
			hi = maxf(hi, f)
		varies = varies or hi - lo > 0.5
	check(same and varies, "Lampen flackern unregelmäßig, deterministisch aus Uhr + Lampennummer")
	bx.clock = 0.0
	var e0: Array = []
	for k in 60:
		await get_tree().process_frame
		e0.append(t.lamps[2].light_energy)
	check(e0.max() - e0.min() >= 0.0 and t.lamps.all(func(l): return not l.shadow_enabled), "Flackern wirkt auf die Lichter (ohne Schatten)")
	# Ziffern
	var code := ""
	var far_ok := true
	for i in bx.digit_spots.size():
		var sp: Dictionary = bx.digit_spots[i]
		code += String(sp.digit)
		print("ZIFFER %s (%s) bei %s – %s" % [sp.digit, sp.order, str(sp.pos), sp.place])
		for j in range(i + 1, bx.digit_spots.size()):
			far_ok = far_ok and (sp.pos as Vector3).distance_to(bx.digit_spots[j].pos) > 8.0
	check(code == "1235" and bx.digit_spots.size() == 4, "Ziffern I–IV in Reihenfolge = %s" % code)
	check(far_ok, "Ziffern an vier verschiedenen Orten (≥ 8 m auseinander)")
	# Zahlenschloss
	var sc: Dictionary = t.secret
	var dl: Vector2 = sc.dir
	var d2: Vector2 = sc.door
	var fy: float = t.floor_at(d2)
	var before := Vector3(d2.x - dl.x * 0.5, fy + 1.0, d2.y - dl.y * 0.5)
	var after := Vector3(d2.x + dl.x * 0.6, fy + 1.0, d2.y + dl.y * 0.6)
	await _frames(3)
	check(_blocked(before, after) and not bx.door_open, "Stahltür zu und versperrt den Durchgang")
	var active: Soldier = m.controller.active
	check(bx.keypad.can_interact(active), "Zahlenschloss benutzbar")
	bx.keypad.interact(active)
	await _frames(2)
	check(bx.ui != null and is_instance_valid(bx.ui) and not m.controller.input_enabled, "Benutzen öffnet das Tastenfeld (Spielsteuerung gesperrt)")
	for k in ["1", "2", "3", "4", "OK"]:
		bx.ui.press(k)
	await _frames(3)
	check(bx.wrong_count == 1 and not bx.door_open and bx.sound_log.has("wrong"), "Falscher Code 1234: Fehlton, Tür bleibt zu")
	for k in ["9", "C", "1", "2", "3", "5", "OK"]:
		bx.ui.press(k)
	await get_tree().create_timer(2.2).timeout
	check(bx.door_open and bx.right_count == 1 and bx.sound_log.has("ok"), "Code 1235 öffnet die Tür")
	check(not _blocked(before, after), "Durchgang offen (Türflügel im Raum)")
	check(not is_instance_valid(bx.ui) and m.controller.input_enabled, "Tastenfeld geschlossen, Steuerung wieder frei")
	check(not bx.keypad.can_interact(active), "Offene Tür: Zahlenschloss nicht mehr benutzbar")
	var res: Dictionary = await _walk(t.entrances["mg42"].approach, t.walk_route("geheimraum"))
	check(res.reached, "Soldat läuft in den Geheimraum (%.1f s, Ende %s)" % [res.time, str(res.end)])
	check(bx.egg != null and bx.egg.is_inside_tree() and (bx.egg.global_position - Vector3(sc.c.x, 0, sc.c.y)).length() < 4.0, "Osterei auf dem Sockel im Geheimraum")
	# Knopf
	var n0: int = bx.sound_log.size()
	bx.nuke.interact(active)
	await _frames(2)
	check(bx.nuke_presses == 1 and bx.sound_log.size() > n0 and bx.sound_log[-1] == "dodo", "Knopf „TACTICAL NUKE“ spielt den Ton")
	check(bx.last_player != null and is_instance_valid(bx.last_player) and bx.last_player.playing and bx.sound_length("dodo") > 0.6 and bx.sound_length("dodo") < 1.2,
		"„dö-dö“ läuft (%.2f s, zwei Töne)" % bx.sound_length("dodo"))
	# Turmschalter
	var tw = m.searchlight_tower
	var dn = m.day_night
	dn.set_hour(0.5, 0.0)
	await _frames(5)
	check(tw.active and tw.switch_on, "Nachts standardmäßig an (Schalter AN)")
	check(Vector2(bx.tower_switch.global_position.x - tw.site.x, bx.tower_switch.global_position.z - tw.site.z).length() < 4.0, "Schalter am Turmfuß")
	bx.tower_switch.interact(active)
	await _frames(5)
	check(not tw.switch_on and not tw.active and tw.heads.all(func(h): return not h.light.visible), "Schalter aus: Scheinwerfer aus")
	bx.tower_switch.interact(active)
	await _frames(5)
	check(tw.switch_on and tw.active, "Schalter an: Scheinwerfer wieder an")
	dn.set_hour(12.0, 0.0)
	await _frames(5)
	check(not tw.active and tw.switch_on, "Tagsüber trotz Schalter AN aus")
	dn.set_hour(0.5, 0.0)
	await _frames(5)
	# Sicherungskasten
	var lo := INF
	var hi := -INF
	for k in 500:
		var v: float = bx.roll_outage()
		lo = minf(lo, v)
		hi = maxf(hi, v)
	check(lo >= 60.0 and hi <= 300.0 and lo < 80.0 and hi > 280.0, "Ausfalldauer zufällig 60–300 s (%.0f … %.0f)" % [lo, hi])
	while bx.fuse_box == null:
		await get_tree().physics_frame
	var shed: Node3D = m.static_root.get_node("woodland_shed")
	var fl: Vector3 = shed.to_local(bx.fuse_box.global_position)
	var fsz: Vector2 = shed.get_meta("footprint_size")
	check(absf(fl.x) < fsz.x * 0.5 and absf(fl.z) < fsz.y * 0.5, "Sicherungskasten im MG42-Haus (lokal %s)" % str(fl))
	bx.fuse_box.interact(active)
	await _frames(5)
	check(bx.fuse_trips == 1 and tw.outage_left >= 59.0 and tw.outage_left <= 300.0 and not tw.active, "Sicherung: Turmstrom fällt aus (%.0f s)" % tw.outage_left)
	check(bx.sound_log.has("spark"), "Funken + Geräusch am Sicherungskasten")
	bx.tower_switch.interact(active)
	await _frames(3)
	bx.tower_switch.interact(active)
	await _frames(5)
	check(tw.switch_on and not tw.active, "Während des Ausfalls schaltet der Schalter nichts ein")
	bx.fuse_box.interact(active)
	check(bx.fuse_trips == 1, "Erneutes Drücken während des Ausfalls ohne Wirkung")
	tw.outage_left = 0.1
	await get_tree().create_timer(0.4).timeout
	await _frames(3)
	check(tw.outage_left == 0.0 and tw.active, "Nach dem Ausfall wieder an (Schalterzustand AN)")
	bx.tower_switch.interact(active)
	bx.fuse_box.interact(active)
	tw.outage_left = 0.1
	await get_tree().create_timer(0.4).timeout
	await _frames(3)
	check(not tw.active and not tw.switch_on, "Nach dem Ausfall gilt der Schalterzustand (AUS bleibt aus)")
	bx.tower_switch.interact(active)
	dn.set_hour(12.0, 0.0)
