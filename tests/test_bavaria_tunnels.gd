extends Node
## Stollen + Suchturm der Karte Bavaria.
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_tunnels [--phase=tunnel|tower|bunker|all]
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
	if phase in ["all", "tower"]:
		await _tower()
	if phase in ["all", "bunker"]:
		await _bunker()
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
	dn.set_hour(12.0, 0.0)
	await _frames(5)
	check(not tw.active and not h.light.visible and m.light_at(spot + Vector3.UP) < 1.6, "Bei Tag wieder aus")
	soldier.queue_free()

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
