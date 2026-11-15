extends Node
## Stollen + Suchturm der Karte Bavaria.
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_tunnels [--phase=tunnel|tower|all]
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
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung (600 s)")
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
	if phase in ["all", "tower"]:
		await _tower()
	_finish()

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
	# Echter Lauf per Physik vom MG42-Einstieg zu beiden Ausgängen
	var mg: Dictionary = t.entrances["mg42"]
	for target in ["antennenhaus", "reihenhaus"]:
		var dst: Dictionary = t.entrances[target]
		var route: Array = [mg.top, mg.bottom, Vector3(t.nodes["mg42"].x, Tunnels.FLOOR_Y, t.nodes["mg42"].y), jp,
			Vector3(t.nodes[target].x, Tunnels.FLOOR_Y, t.nodes[target].y), dst.bottom, dst.top, dst.approach]
		var res: Dictionary = await _walk(mg.approach, route)
		check(res.reached, "Soldat läuft vom MG42-Einstieg zum Ausgang %s (Ende %s, Ziel %s, %.1f s)" % [target, str(res.end), str(dst.approach), res.time])
		check(res.min_y > Tunnels.FLOOR_Y - 0.4 and res.min_y < Tunnels.FLOOR_Y + 0.5, "%s: Weg unter Tage, kein Durchfallen (tiefster Punkt %.2f)" % [target, res.min_y])

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
	var park: Vector2 = m.tunnels.nodes.get("antennenhaus", Vector2.ZERO)
	var k := 0
	for s in get_tree().get_nodes_in_group("soldiers"):
		s.global_position = Vector3(park.x, Tunnels.FLOOR_Y + 0.1, park.y) + Vector3(k * 0.7 - 1.0, 0, 0)
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
	var j: Vector2 = m.tunnels.nodes["abzweig"]
	soldier.global_position = Vector3(j.x + 1.5, Tunnels.FLOOR_Y + 0.1, j.y)
	await get_tree().create_timer(Tower.LOSE_AFTER + 0.5).timeout
	check(h.mode == 2 and h.target == null, "Nach Sichtverlust: Nachsuchen an der letzten Stelle (Modus %d)" % h.mode)
	await get_tree().create_timer(Tower.RESEARCH_S + 0.5).timeout
	check(h.mode == 0, "Danach wieder Suchen (Modus %d)" % h.mode)
	dn.set_hour(12.0, 0.0)
	await _frames(5)
	check(not tw.active and not h.light.visible and m.light_at(spot + Vector3.UP) < 1.6, "Bei Tag wieder aus")
	soldier.queue_free()
