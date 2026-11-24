extends RefCounted
## KI-Hinweispunkte der Testkarte Castle (Muster: Bavaria bot_hints.gd). Die allgemeine Bot-KI fragt sie über die
## optionalen Missionsmethoden bot_hints(center, radius) / bot_hint_stance(pos) ab (BotGoals.hold_spot/overwatch_spot).
## Hinweisarten:
##   high  – Wehrgang (hockend hinter den Zinnen, Blick in den Hof) und Turmplattform (stehend über der Brüstung)
##   choke – Engstelle: seitlich vor den Tor-/Gebäudedurchgängen (hockend, Mauerecke als Deckung)
##   cover – an Kriegsdeko/Deckung der Höfe (hockend)
## Keine funktionsfähigen Waffenstellungen (MG-Nester sind Deko) → keine „emplacement“-Hinweise.
## Nur Punkte der Spielfläche (DM/TDM: Höfe D, E, F). Erzeugt nach dem Navmesh schrittweise (step, Zeitbudget):
## jeder Punkt wird ans Netz geheftet und muss über das Netz erreichbar sein (Wehrgang ab der nächsten Treppe,
## Turmplattform ab der Turmtür, Bodenpunkte ab dem nächsten Start/Zonenmittelpunkt) – unerreichbare Wehrgangstücke
## (ohne Treppe) fallen weg, sonst würde hold_spot einen Platz wählen, den der Bot nie erreicht.

const STAND := 0     # Soldier.Stance.STAND
const CROUCH := 1    # Soldier.Stance.CROUCH

var hints: Array[Dictionary] = []
var done := false
var dropped := 0
var stats := {"high": 0, "tower": 0, "choke": 0, "cover": 0, "dropped": 0}
var _raw: Array = []          # {pos, kind, stance, high?, ref: Vector3}
var _i := 0
var _map: RID


func prepare(m) -> void:
	var r = m.real
	_map = m.get_world_3d().navigation_map
	var refs: Array = []         # Bodenbezugspunkte (Starts, Zonenmitten)
	for s in m.mp_spawns():
		refs.append(s.pos)
	for z in m.all_zones():
		if r.in_play(Vector2(z.xf.origin.x, z.xf.origin.z)):
			refs.append(z.xf.origin - Vector3(0, 0.8, 0))
	# Wehrgang: jedes zweite Modul, Bezug = nächster Treppenaustritt (≤ 160 m)
	var stairs: Array = r.kit.stairs_at
	var walk: Array = r.kit.walk_points
	for k in range(0, walk.size(), 2):
		var w: Vector3 = walk[k]
		if not r.in_play(Vector2(w.x, w.z)):
			continue
		var ref := _nearest(stairs, w, 160.0)
		if ref.is_finite():
			_raw.append({"pos": w, "kind": "high", "stance": CROUCH, "high": true, "ref": ref})
	# Turmplattformen: Leiteraustritt (stehend über der Brüstung), Treppenaustritt; Bezug = Turmtür am Boden
	for tw in r.kit.towers:
		var door: Vector3 = tw.door
		if not r.in_play(Vector2(door.x, door.z)):
			continue
		door.y = m.ground_y(door.x, door.z)
		var bs: Basis = tw.basis
		var o: Vector3 = tw.pos
		for lp in [Vector3(-1.6, 12.0, 1.6), Vector3(1.6, 12.0, 1.6), Vector3(-1.6, 12.0, -1.0)]:
			_raw.append({"pos": o + bs * lp, "kind": "high", "stance": STAND, "high": true, "ref": door, "tower": true})
	# Engstellen: je Durchgangsende links/rechts der Öffnung, 3 m vor dem Ende
	var gates: Array = []
	for pas in r.buildings.passages:
		var c: Vector2 = pas.center
		var dv: Vector2 = pas.dir
		gates.append([c + dv * (float(pas.t0) - 3.0), dv])
		gates.append([c + dv * (float(pas.t1) + 3.0), dv])
	for i in r.kit.gate_points.size():
		var gp: Vector3 = r.kit.gate_points[i]
		var ax: Vector3 = r.kit.gate_axes[i] if i < r.kit.gate_axes.size() else Vector3.FORWARD
		if r.buildings.passages.any(func(p): return (p.center as Vector2).distance_to(Vector2(gp.x, gp.z)) < 0.1):
			continue
		var a2 := Vector2(ax.x, ax.z).normalized()
		gates.append([Vector2(gp.x, gp.z) - a2 * 4.0, a2])
		gates.append([Vector2(gp.x, gp.z) + a2 * 4.0, a2])
	var ig: Vector3 = r.inner_gate.get("pos", Vector3.INF)
	for g in gates:
		var e: Vector2 = g[0]
		var side: Vector2 = (g[1] as Vector2).orthogonal()
		for sg: float in [-3.2, 3.2]:
			var p: Vector2 = e + side * sg
			if not r.in_play(p) or r.in_building(p, 0.4) or (ig.is_finite() and Vector2(ig.x, ig.z).distance_to(p) < 7.0):
				continue
			_raw.append({"pos": Vector3(p.x, m.ground_y(p.x, p.y), p.y), "kind": "choke", "stance": CROUCH, "ref": _nearest(refs, Vector3(p.x, 0, p.y), 1e9)})
	# Deckung: Kriegsdeko/Wracks/Sandsäcke der Höfe, vier Punkte rundum
	for cv in r.cover:
		var c3: Vector3 = cv
		for k in 4:
			var a := TAU * float(k) / 4.0 + 0.4
			var p := Vector2(c3.x, c3.z) + Vector2(cos(a), sin(a)) * 2.6
			if not r.in_play(p) or r.in_building(p, 0.4):
				continue
			_raw.append({"pos": Vector3(p.x, m.ground_y(p.x, p.y), p.y), "kind": "cover", "stance": CROUCH, "ref": _nearest(refs, Vector3(p.x, 0, p.y), 1e9)})


static func _nearest(list: Array, p: Vector3, maxd: float) -> Vector3:
	var best := Vector3.INF
	var bd := maxd
	for q in list:
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = q
	return best


## Punkte ans Netz heften und Erreichbarkeit prüfen, bis budget_ms verbraucht sind; true = fertig
func step(m, budget_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while _i < _raw.size() and Time.get_ticks_msec() - t0 < budget_ms:
		var h: Dictionary = _raw[_i]
		_i += 1
		var p: Vector3 = h.pos
		var q := NavigationServer3D.map_get_closest_point(_map, p)
		var high: bool = h.get("high", false)
		if Vector2(q.x - p.x, q.z - p.z).length() > 1.2 or absf(q.y - p.y) > (0.6 if high else 1.5):
			dropped += 1
			continue
		var ref: Vector3 = h.ref
		if not ref.is_finite() or not _reach(NavigationServer3D.map_get_closest_point(_map, ref), q):
			dropped += 1
			continue
		h.pos = q
		h.erase("ref")
		hints.append(h)
		var kind := "tower" if h.get("tower", false) else String(h.kind)
		stats[kind] = int(stats.get(kind, 0)) + 1
	if _i >= _raw.size() and not done:
		done = true
		stats.dropped = dropped
		print("CASTLE_HINTS ", stats, " (", hints.size(), " Punkte)")
	return done


## Weg über das Netz (Godot-Standardgrenze der Polygonsuche; Bezugspunkte liegen nahe) endet am Ziel
func _reach(a: Vector3, b: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(_map, a, b, true)
	return path.size() > 1 and path[path.size() - 1].distance_to(b) < 1.0


func near(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for h in hints:
		var p: Vector3 = h.pos
		if Vector2(p.x - center.x, p.z - center.z).length_squared() <= r2:
			out.append(h)
	return out


func stance_at(pos: Vector3) -> int:
	for h in hints:
		var p: Vector3 = h.pos
		if Vector2(p.x - pos.x, p.z - pos.z).length() < 1.5 and absf(p.y - pos.y) < 1.6:
			return int(h.stance)
	return -1
