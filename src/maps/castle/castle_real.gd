extends RefCounted
## Castle: echte Burg aus lokal abgeleiteten Daten (nur zur Laufzeit aus res://local/castle/derived/ gelesen;
## keine Koordinaten im Repository). Abschnitte A–F = Höfe, Spielfläche = Bering (Umriss West + Ost).
## Gelände (Höhenfeld), LoD2-Gebäude, Bering mit Wehrgang/Treppen, Quermauern mit Toren, Türme mit Leiter,
## Grabenbrücken entlang des Hauptwegs, Deckung 1944/45, Platzhalter-Starts/Zonen.
## Real castle builder from local derived data (runtime only).

const DATA := "res://local/castle/derived/"
const MeshBatch := preload("res://src/maps/castle/castle_mesh.gd")
const TerrainScript := preload("res://src/maps/castle/castle_terrain.gd")
const BuildingsScript := preload("res://src/maps/castle/castle_buildings.gd")
const KitScript := preload("res://src/maps/castle/castle_kit.gd")
const LayoutScript := preload("res://src/maps/castle/castle_layout.gd")
const LibraryModels := preload("res://src/maps/bavaria/library_models.gd")
const DressingScript := preload("res://src/maps/castle/castle_dressing.gd")
const RoadScript := preload("res://src/maps/castle/castle_road.gd")
const COURT_SECTIONS := ["A", "B", "C", "D", "E", "F"]

var terrain = TerrainScript.new()
var buildings = BuildingsScript.new()
var kit = KitScript.new()
var dressing = DressingScript.new()
var road = RoadScript.new()
var features := {}
var boundary := PackedVector2Array()
var sections := {}                 # Code → PackedVector2Array
var dividers: Array = []           # {name, a: Vector2, b: Vector2, gate: Vector2, passage: bool}
var path := PackedVector2Array()
var bridges: Array = []            # {a: Vector3, b: Vector3}
var cover: Array = []              # Vector3 Deckungsobjekte
var _fp_boxes: Array = []          # [Rect2, PackedVector2Array]
var _blocked: Array = []           # [Vector2, Radius]
var play_rect := Rect2()
## Spielart (Net.Mode, vor build() von castle.gd gesetzt): DM/TDM = Spielfläche Hauptburg + erster/zweiter Vorhof
## (F, E, D), innere Grenze an der Quermauer C|D; Eroberung = ganze Burg, je Hof eine Zone (A–F, FRONTLINE)
var play_mode := 0
var restricted := false
const PLAY_SECTIONS := ["D", "E", "F"]
const INNER_DIVIDER := "C|D"
var inner_lines: Array = []        # [Vector2, Vector2] Abschnitte der inneren Grenze (nur DM/TDM)
var inner_ends: Array = []         # Vector2: wo die innere Grenze den Bering kreuzt (Wehrgang)
var inner_gate := {}               # {pos: Vector3, out: Vector3 (Richtung Spielfläche)} verrammeltes Tor C|D
var spawn_sets := {}               # "dm" / "tdm" / "occupation" → Array {pos: [x, z], team, yaw}


static func available() -> bool:
	for f in ["buildings.json", "castle_features.json", "terrain.json"]:
		if not FileAccess.file_exists(DATA + f):
			return false
	return true


static func _json(name: String) -> Dictionary:
	if not FileAccess.file_exists(DATA + name):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA + name))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _v2(p) -> Vector2:
	if p is Dictionary:
		p = p.xz
	return Vector2(float(p[0]), float(p[1]))


# ---------------------------------------------------------------- Abfragen

func in_building(p: Vector2, grow := 0.0) -> bool:
	for e in _fp_boxes:
		if (e[0] as Rect2).grow(grow).has_point(p):
			if grow <= 0.0:
				if Geometry2D.is_point_in_polygon(p, e[1]):
					return true
			elif BuildingsScript.dist_to_poly(p, e[1]) <= grow:
				return true
	return false


## Gebäudeart am Punkt ("" = frei); LoD2-Mauern/Bauwerke ("wall"/"structure") werden nie durchtunnelt
func building_kind_at(p: Vector2, grow := 0.0) -> String:
	for e in _fp_boxes:
		if (e[0] as Rect2).grow(grow).has_point(p):
			if (grow <= 0.0 and Geometry2D.is_point_in_polygon(p, e[1])) or (grow > 0.0 and BuildingsScript.dist_to_poly(p, e[1]) <= grow):
				return String(e[2])
	return ""


func path_info(p: Vector2) -> Array:
	# [Abstand, Richtung (Süd-gerichtet entlang des Wegs)]
	var best := INF
	var dir := Vector2(0, 1)
	for i in path.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
		var d := p.distance_to(q)
		if d < best:
			best = d
			dir = (path[i + 1] - path[i]).normalized()
	return [best, dir]


func section_of(p: Vector2) -> String:
	for c in sections:
		if Geometry2D.is_point_in_polygon(p, sections[c]):
			return c
	return ""


func boundary_dist(p: Vector2) -> float:
	var best := INF
	for i in boundary.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, boundary[i], boundary[(i + 1) % boundary.size()])))
	return best


## Liegt p näher als r an einem Gebäudedurchgang (Achse inkl. 3 m vor/hinter den Enden)?
func near_passage(p: Vector2, r: float) -> bool:
	for pas in buildings.passages:
		var c: Vector2 = pas.center
		var d: Vector2 = pas.dir
		var a := c + d * (float(pas.t0) - 3.0)
		var b := c + d * (float(pas.t1) + 3.0)
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < r:
			return true
	return false


func blocked(p: Vector2, extra := 0.0) -> bool:
	for e in _blocked:
		if p.distance_to(e[0]) < float(e[1]) + extra:
			return true
	return false


func _inward(a: Vector2, b: Vector2) -> Vector2:
	var n := Vector2(a.y - b.y, b.x - a.x).normalized()
	var mid := (a + b) * 0.5
	return n if Geometry2D.is_point_in_polygon(mid + n * 2.0, boundary) else -n


# ---------------------------------------------------------------- Aufbau

func build(m: Node) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	features = _json("castle_features.json")
	var bdata := _json("buildings.json")
	terrain.setup(_json("terrain.json"), _json("terrain_castle_1m.json"))
	LayoutScript.apply_kit_materials(m.lb)
	LayoutScript.apply_pack17_materials(m.lb)
	if m.lb._mats.has("c_retain"):
		kit.found_mat = "c_retain"
	var west: Array = []
	var east: Array = []
	for w in features.get("walls", []):
		if String(w.id).begins_with("enceinte_west"):
			west = w.points
		elif String(w.id).begins_with("enceinte_east"):
			east = w.points
	for p in west:
		boundary.append(_v2(p))
	for i in range(east.size() - 1, -1, -1):
		boundary.append(_v2(east[i]))
	if Geometry2D.is_polygon_clockwise(boundary):
		pass
	for s in features.get("sections", []):
		var poly := PackedVector2Array()
		for p in s.polygon:
			poly.append(_v2(p))
		sections[String(s.code)] = poly
	for p in features.get("main_path", {}).get("points", []):
		path.append(_v2(p))
	var br := Rect2(boundary[0], Vector2.ZERO)
	for p in boundary:
		br = br.expand(p)
	play_rect = br.grow(25.0)
	for b in bdata.get("buildings", []):
		if String(b.get("kind", "")) == "bridge":
			continue
		var fp := BuildingsScript.fp_of(b)
		var r := Rect2(fp[0], Vector2.ZERO)
		for p in fp:
			r = r.expand(p)
		_fp_boxes.append([r, fp, String(b.get("kind", ""))])
	_find_dividers()
	_plan_bridges()
	# Gebäude (Tordurchgänge an den Quermauer-Toren; Achse = Hauptweg)
	var gps: Array = []
	for d in dividers:
		gps.append([d.gate, path_info(d.gate)[1]])
	# weitere gelistete Tore innerhalb der Burg, die in einem Gebäude liegen (z. B. Zugang zum inneren Hof):
	# Achse quer durch die nächste Gebäudewand
	for g in features.get("gates", []):
		var gp := _v2(g.position)
		if Geometry2D.is_point_in_polygon(gp, boundary) and boundary_dist(gp) > 4.0 and in_building(gp, 3.0) \
				and not gps.any(func(q): return (q[0] as Vector2).distance_to(gp) < 12.0):
			gps.append([gp, _wall_axis(gp)])
	# Hauptburg: abgeschlossene Höfe über zusätzliche Durchgänge anbinden
	_plan_f_access(gps)
	# zusammengefassten Großblock der Hauptburg nach Planpunkten in Teilgebäude aufteilen (benannte Teile, Materialien)
	_split_main_block(bdata.get("buildings", []))
	# Zwiebelhelm auf den Uhrturm des Vorhofs A (Planpunkt a4), falls er ein kleines Kegel-/Zeltdach hat
	var a4: Dictionary = features.get("plan_points", {}).get("a4", {})
	buildings.onion_id = String(a4.get("matched_building", "")) if a4.get("matched_building") != null else ""
	buildings.build(m, bdata.get("buildings", []), terrain, gps, func(g): return path_info(g)[1], play_rect, deck_height)
	for d in dividers:
		for pas in buildings.passages:
			if (pas.center as Vector2).distance_to(d.gate) < 0.1:
				d.passage = true
				var c: Vector2 = pas.center
				var dv: Vector2 = pas.dir
				kit.gate_points.append(Vector3(c.x, terrain.height(c.x, c.y), c.y))
				kit.gate_axes.append(Vector3(dv.x, 0, dv.y))
	var t1 := Time.get_ticks_msec()
	_lb_mats = m.lb._mats
	_road_ribbons = _lb_mats.has("c_cobble") and String(Game.cli.get("castle_road", "1")) != "0"
	terrain.build(m.static_root, m.dynamic_root, m.lb, play_rect, _ground_material)
	var t2 := Time.get_ticks_msec()
	_build_bridges(m)
	if _road_ribbons:
		road.build(self, m)
		print("CASTLE_ROAD: Wegbänder %.0f m in %d Stücken (Kieselpflaster %.0f m, Sandweg %.0f m), Abweichung vom Datenweg max. %.2f m"
			% [road.stats.length_m, road.stats.runs, float(road.stats.get("pebble_m", 0.0)), float(road.stats.get("sand_m", 0.0)),
			road.stats.max_dev])
	_build_towers(m)
	_build_enceinte()
	_build_cross_walls()
	_build_details(bdata.get("buildings", []))
	_build_cover(m)
	# Hofausstattung nach Referenzansichten (Bäume, Hecken, Laternen, Bänke, Außentreppen, Grabenzaun); --castle_dressing=0 aus
	if String(Game.cli.get("castle_dressing", "1")) != "0":
		dressing.build(self, m)
	restricted = play_mode in [0, 1]
	if restricted:
		_build_inner_boundary(m)
	kit.commit(m.static_root, m.lb)
	var t3 := Time.get_ticks_msec()
	var lay := _spawns_and_zones()
	print("CASTLE_REAL: Gebäude %d (Durchgänge %d), Mauern %d (Wehrgang %d, Quer %d), Türme %d, Tore %d, Treppen %d, Brücken %d, Deckung %d, Zeiten Daten/Gebäude %d ms, Gelände %d ms, Bausatz %d ms, Rest %d ms"
		% [buildings.count, buildings.passages.size(), kit.stats.walls, kit.stats.walk, kit.stats.cross, kit.stats.towers,
		kit.stats.gates, kit.stats.stairs, bridges.size(), cover.size(), t1 - t0, t2 - t1, t3 - t2, Time.get_ticks_msec() - t3])
	if not kit.stats.missing.is_empty():
		push_warning("Castle: Bausatzmodelle fehlen: %s" % str(kit.stats.missing))
	return lay


var _lb_mats := {}
var _road_ribbons := false


## Grabensohle: unter einer Brücke (≤ 14 m seitlich der Brückenachse) und > 2 m unter dem Deck
func _in_ditch(p: Vector2) -> bool:
	for br in bridges:
		var a := Vector2(br.a.x, br.a.z)
		var b := Vector2(br.b.x, br.b.z)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if q.distance_to(p) < 14.0:
			var t := q.distance_to(a) / maxf(a.distance_to(b), 0.01)
			if terrain.height(p.x, p.y) < lerpf(br.a.y, br.b.y, t) - 2.0:
				return true
	return false


func _ground_material(x: float, z: float) -> String:
	var p := Vector2(x, z)
	if not Geometry2D.is_point_in_polygon(p, boundary):
		return "c_slope"
	# steile Flächen (> ~17°) Hangbewuchs, sehr steile (> ~35°) Nagelfluh-Fels; Pflaster/Weg nur auf ebenem Boden
	var dh := maxf(absf(terrain.height(x + 1.0, z) - terrain.height(x - 1.0, z)), absf(terrain.height(x, z + 1.0) - terrain.height(x, z - 1.0)))
	var has_rock: bool = _lb_mats.has("c_rock")
	if dh > 1.4 and has_rock:
		return "c_rock" if int(floor(x * 0.07) + floor(z * 0.07)) % 3 != 0 else "c_rock2"
	# Grabensohle unter den Brücken
	if _lb_mats.has("c_ditch") and _in_ditch(p):
		return "c_ditch"
	if dh > 0.6:
		return "c_slope"
	# Referenzansichten: Fahrweg durch alle Höfe gepflastert (Katzenkopf), daneben Kiesstreifen; Hauptburghof ganz gepflastert
	if section_of(p) == "F":
		# 3D-Rundgang: Innerer Hof ganz mit Flusskieseln gepflastert
		for k in ["c_pebble", "c_cobble", "c_paving"]:
			if _lb_mats.has(k):
				return k
	# Wegbänder (castle_road.gd) liegen mit runden Rändern über dem Gelände; darunter Gras. Ohne Bänder: Material je Zelle
	if _road_ribbons:
		return "c_grass"
	var cob := "c_cobble" if _lb_mats.has("c_cobble") else "c_earth"
	var pd: float = path_info(p)[0]
	if pd < 2.4:
		return cob
	if pd < 3.3 and _lb_mats.has("c_gravel"):
		return "c_gravel"
	return "c_grass"


## Quermauern = gemeinsame Kante benachbarter Abschnitte; Tor am gelisteten Tor nahe der Kante, sonst am Weg
func _find_dividers() -> void:
	for k in COURT_SECTIONS.size() - 1:
		var pa: PackedVector2Array = sections.get(COURT_SECTIONS[k], PackedVector2Array())
		var pb: PackedVector2Array = sections.get(COURT_SECTIONS[k + 1], PackedVector2Array())
		var common: Array = []
		for p in pa:
			for q in pb:
				if p.distance_to(q) < 0.05 and not common.any(func(c): return c.distance_to(p) < 0.05):
					common.append(p)
		if common.size() < 2:
			continue
		var a: Vector2 = common[0]
		var b: Vector2 = common[common.size() - 1]
		# Tor dort, wo der Hauptweg die Kante kreuzt (Brücken folgen demselben Weg); gelistete Tore nur als Rückfall
		var gate := Vector2.INF
		for i in path.size() - 1:
			var hit = Geometry2D.segment_intersects_segment(path[i], path[i + 1], a, b)
			if hit != null:
				gate = hit
				break
		if gate == Vector2.INF:
			var best := 15.0
			for g in features.get("gates", []):
				var gp := _v2(g.position)
				var d := gp.distance_to(Geometry2D.get_closest_point_to_segment(gp, a, b))
				if d < best:
					best = d
					gate = gp
		if gate == Vector2.INF:
			gate = (a + b) * 0.5
		dividers.append({"name": COURT_SECTIONS[k] + "|" + COURT_SECTIONS[k + 1], "a": a, "b": b, "gate": gate, "passage": false})


## Gräben entlang des Hauptwegs: Abschnitte, deren Gelände > 1,5 m unter dem Rand liegt, bekommen ein Steindeck
var _bridge_pts: Array = []

## Vor dem Gebäudebau: Grabenläufe bestimmen. Endet ein Lauf an einem Gebäude (Tordurchgang), liegt das Deck dort
## auf Höhe des anderen Grabenrands (waagerecht); der Durchgangsboden übernimmt diese Höhe (deck_height).
func _plan_bridges() -> void:
	var pts: Array = []    # [Vector2, Höhe, im Gebäude]
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var n := maxi(int(a.distance_to(b)), 1)
		for k in n:
			var p := a.lerp(b, float(k) / n)
			if Geometry2D.is_point_in_polygon(p, boundary):
				pts.append([p, terrain.height(p.x, p.y), in_building(p, 0.5)])
	var win := 40
	var ditch := []
	for i in pts.size():
		var lmax := -INF
		var rmax := -INF
		for k in range(maxi(i - win, 0), i + 1):
			lmax = maxf(lmax, pts[k][1])
		for k in range(i, mini(i + win + 1, pts.size())):
			rmax = maxf(rmax, pts[k][1])
		# im Gebäude (Tordurchgang) liegt das Gelände auf Gebäudefußhöhe – kein Graben, dort trägt der Durchgangsboden
		ditch.append(float(pts[i][1]) < minf(lmax, rmax) - 1.5 and not pts[i][2])
	_bridge_pts = pts
	var i := 0
	while i < pts.size():
		if not ditch[i]:
			i += 1
			continue
		var j := i
		while j + 1 < pts.size() and ditch[j + 1]:
			j += 1
		var s := maxi(i - 2, 0)
		var e := mini(j + 2, pts.size() - 1)
		var ya := float(pts[s][1])
		var yb := float(pts[e][1])
		var a_bld := bool(pts[s][2]) or in_building(pts[s][0], 1.5)
		var b_bld := bool(pts[e][2]) or in_building(pts[e][0], 1.5)
		if b_bld and not a_bld:
			yb = ya
		elif a_bld and not b_bld:
			ya = yb
		var low := s
		for k in range(s, e + 1):
			if float(pts[k][1]) < float(pts[low][1]):
				low = k
		var yl := lerpf(ya, yb, float(low - s) / maxf(e - s, 1))
		var depth := yl - float(pts[low][1])
		i = j + 1
		if depth < 1.5:
			continue   # flache Mulde, kein Graben
		var pa: Vector2 = pts[s][0]
		var pb: Vector2 = pts[e][0]
		var pl: Vector2 = pts[low][0]
		bridges.append({"a": Vector3(pa.x, ya, pa.y), "b": Vector3(pb.x, yb, pb.y), "s": s, "e": e,
			"low": Vector3(pl.x, yl, pl.y), "depth": depth})
		for k in range(s, e + 1, 3):
			_blocked.append([pts[k][0], 3.5])


## Bodenhöhe an einem Durchgangsende: Deckende einer Grabenbrücke in ≤ 5 m, sonst Gelände
func deck_height(p: Vector2) -> float:
	for br in bridges:
		for end in [br.a, br.b]:
			if Vector2(end.x, end.z).distance_to(p) < 8.0:
				return end.y
	return terrain.height(p.x, p.y)


## Brücken vor diesen Quermauer-Toren sind Holzbrücken (Bohlendeck, Holzgeländer, Holzjoche) – Referenzansicht;
## alle übrigen Grabenbrücken Stein
const WOOD_BRIDGE_DIVIDERS := ["D|E"]

func _build_bridges(m: Node) -> void:
	var mb := MeshBatch.new()
	for br in bridges:
		var mid := Vector2((br.a.x + br.b.x) * 0.5, (br.a.z + br.b.z) * 0.5)
		var nearest := ""
		var nd := 45.0
		for d in dividers:
			var dd := (d.gate as Vector2).distance_to(mid)
			if dd < nd:
				nd = dd
				nearest = String(d.name)
		br["wood"] = nearest in WOOD_BRIDGE_DIVIDERS
		if br.wood:
			_deck_wood(mb, _bridge_pts, br.s, br.e, br.a.y, br.b.y)
		else:
			_deck(mb, _bridge_pts, br.s, br.e, br.a.y, br.b.y)
	mb.commit(m.static_root, "CastleBridges", m.lb, true).add_to_group("castle_bridges")


## Holzbrücke: Bohlendeck (Oberkante wie das Steindeck), zwei Längsträger, Holzgeländer (Pfosten alle ~2 m, Ober- und
## Mittelholm; Kollision als durchgehende Kiste 1,1 m), Holzjoche (zwei Pfähle + Riegel) alle 6 m
func _deck_wood(mb: MeshBatch, pts: Array, s: int, e: int, ya: float, yb: float) -> void:
	var hw := 2.2
	for k in range(s, e):
		var p: Vector2 = pts[k][0]
		var q: Vector2 = pts[k + 1][0]
		var y0 := lerpf(ya, yb, float(k - s) / (e - s)) + 0.02
		var y1 := lerpf(ya, yb, float(k + 1 - s) / (e - s)) + 0.02
		var d := (q - p).normalized()
		var sd := Vector2(-d.y, d.x)
		var len := p.distance_to(q) + 0.15
		var mid := (p + q) * 0.5
		var ym := (y0 + y1) * 0.5
		var x := Vector3(d.x * p.distance_to(q), y1 - y0, d.y * p.distance_to(q)).normalized()
		var z := Vector3(sd.x, 0, sd.y)
		var yv := z.cross(x).normalized()
		if yv.y < 0.0:
			z = -z
			yv = -yv
		var basis := Basis(x, yv, z)
		var c := Vector3(mid.x, ym, mid.y)
		mb.box(Transform3D(basis, c + yv * -0.12), Vector3(len, 0.24, hw * 2.0), "c_wood")
		for side in [-1.0, 1.0]:
			mb.box(Transform3D(basis, c + yv * -0.45 + z * (hw - 0.5) * side), Vector3(len, 0.42, 0.3), "c_wood", true, false)
			# Geländer: Kollision durchgehend, sichtbar Holme
			mb.box(Transform3D(basis, c + yv * 0.55 + z * (hw - 0.1) * side), Vector3(len, 1.1, 0.12), "c_wood", false, true)
			for hy in [0.5, 1.02]:
				mb.box(Transform3D(basis, c + yv * hy + z * (hw - 0.1) * side), Vector3(len, 0.09, 0.08), "c_wood", true, false)
			if (k - s) % 2 == 0:
				mb.box(Transform3D(basis, c + yv * 0.52 + z * (hw - 0.1) * side), Vector3(0.14, 1.1, 0.14), "c_wood", true, false)
		if (k - s) % 6 == 3:
			var g := terrain.height(mid.x, mid.y)
			if g < ym - 1.0:
				var hgt := ym - 0.66 - g + 1.0
				var hx := Vector3(d.x, 0, d.y)
				var jb := Basis(hx, Vector3.UP, -hx.cross(Vector3.UP))
				for side in [-1.0, 1.0]:
					mb.box(Transform3D(jb, Vector3(mid.x, g - 1.0 + hgt * 0.5, mid.y) + z * (hw - 0.5) * side), Vector3(0.32, hgt, 0.32), "c_wood")
				mb.box(Transform3D(jb, Vector3(mid.x, ym - 0.8, mid.y)), Vector3(0.3, 0.3, hw * 2.0), "c_wood", true, false)
				if hgt > 4.0:
					# Kreuzstrebe
					mb.box(Transform3D(jb * Basis(Vector3.RIGHT, atan2(hgt - 1.6, hw * 2.0 - 1.0)), Vector3(mid.x, g - 0.2 + (hgt - 1.6) * 0.5, mid.y)),
						Vector3(0.16, 0.16, Vector2(hgt - 1.6, hw * 2.0 - 1.0).length()), "c_wood", true, false)


func _deck(mb: MeshBatch, pts: Array, s: int, e: int, ya: float, yb: float) -> void:
	var hw := 2.2
	for k in range(s, e):
		var p: Vector2 = pts[k][0]
		var q: Vector2 = pts[k + 1][0]
		var y0 := lerpf(ya, yb, float(k - s) / (e - s)) + 0.02
		var y1 := lerpf(ya, yb, float(k + 1 - s) / (e - s)) + 0.02
		var d := (q - p).normalized()
		var sd := Vector2(-d.y, d.x)
		var len := p.distance_to(q) + 0.15
		var mid := (p + q) * 0.5
		var ym := (y0 + y1) * 0.5
		var x := Vector3(d.x * p.distance_to(q), y1 - y0, d.y * p.distance_to(q)).normalized()
		var z := Vector3(sd.x, 0, sd.y)
		var yv := z.cross(x).normalized()
		if yv.y < 0.0:
			z = -z
			yv = -yv
		var basis := Basis(x, yv, z)
		mb.box(Transform3D(basis, Vector3(mid.x, ym - 0.3, mid.y)), Vector3(len, 0.6, hw * 2.0), "c_paving")
		for side in [-1.0, 1.0]:
			var c: Vector3 = Vector3(mid.x, ym + 0.5, mid.y) + z * (hw - 0.2) * side
			mb.box(Transform3D(basis, c), Vector3(len, 1.0, 0.4), "c_wall")
		if (k - s) % 6 == 3:
			var g := terrain.height(mid.x, mid.y)
			if g < ym - 1.0:
				var hgt := ym - 0.6 - g + 1.0
				var hx := Vector3(d.x, 0, d.y)
				mb.box(Transform3D(Basis(hx, Vector3.UP, -hx.cross(Vector3.UP)), Vector3(mid.x, g - 1.0 + hgt * 0.5, mid.y)),
					Vector3(1.6, hgt, hw * 2.0), kit.found_mat)


var detail_stats := {"helmets": 0, "onion": 0, "chimneys": 0, "dormers": 0, "portals": 0, "boulders": 0}


## Uhrturm: LoD2 setzt die Traufe sehr tief (≈ 3 m) und das Dach bis zum Knauf (≈ 10 m) – mit dem Zwiebelhelm darauf
## saß die Zwiebel am Boden (Kontrollbild hof_a). Referenzansicht: hoher verputzter Schaft, Zwiebel oben. Schaft daher bis
## 60 % der LoD2-Gesamthöhe aufmauern (Kiste entlang der längsten Grundrisskante, Gesims), Helm darauf. Gibt die neue
## Traufmitte zurück; Türme mit plausibler Traufe bleiben unverändert.
const ONION_SHAFT_K := 0.6
func _onion_shaft(h: Dictionary) -> Vector3:
	var fp: PackedVector2Array = h.get("fp", PackedVector2Array())
	var ground := float(h.get("ground", h.pos.y))
	var eave := float(h.pos.y)
	var top := eave + float(h.height)
	if fp.size() < 3 or eave - ground >= 6.0:
		return h.pos
	var new_eave := ground + (top - ground) * ONION_SHAFT_K
	if new_eave <= eave + 0.5:
		return h.pos
	var best := 0.0
	var u := Vector2.RIGHT
	for i in fp.size():
		var e: Vector2 = (fp[(i + 1) % fp.size()] as Vector2) - (fp[i] as Vector2)
		if e.length() > best:
			best = e.length()
			u = e.normalized()
	var v := u.orthogonal()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for q in fp:
		var pq: Vector2 = q
		lo = lo.min(Vector2(pq.dot(u), pq.dot(v)))
		hi = hi.max(Vector2(pq.dot(u), pq.dot(v)))
	var c2: Vector2 = u * (lo.x + hi.x) * 0.5 + v * (lo.y + hi.y) * 0.5
	var size := hi - lo
	# rechtshändige Achsen (z = −v): bei gespiegelter Basis kehrt MeshBatch.quad die Flächen um → Schaft unsichtbar
	var bs := Basis(Vector3(u.x, 0, u.y), Vector3.UP, Vector3(-v.x, 0, -v.y))
	var mat := "c_plaster" if _lb_mats.has("c_plaster") else "c_wall"
	var y0 := eave - 0.1
	kit.col.box(Transform3D(bs, Vector3(c2.x, (y0 + new_eave) * 0.5, c2.y)), Vector3(size.x, new_eave - y0, size.y), mat, true, true)
	# Traufgesims unter dem Helm
	kit.col.box(Transform3D(bs, Vector3(c2.x, new_eave - 0.15, c2.y)), Vector3(size.x + 0.4, 0.3, size.y + 0.4), mat, true, false)
	return Vector3(c2.x, new_eave, c2.y)


## Burgfassaden-Pack: Turmhelme statt LoD2-Kegeldächern (Zwiebelhelm am Uhrturm), einige Kamine und Gauben,
## Torrahmen an den Durchgangsenden, Nagelfluh-Felsbrocken auf den Hängen außerhalb des Berings (nur Optik)
func _build_details(list: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1717
	for h in buildings.helmets:
		var onion: bool = h.onion
		var model := "zwiebelhelm_uhrturm_4m" if onion else ("turmhelm_spitz_knauf_4m" if hash(str(h.pos)) % 2 == 0 else "turmhelm_spitz_4m")
		var hpos: Vector3 = h.pos
		var hw: float = float(h.width)
		var hh: float = float(h.height)
		if onion:
			hpos = _onion_shaft(h)
			hh = float(h.pos.y) + float(h.height) - hpos.y
			if float(h.get("area", 0.0)) > 1.0:
				hw = sqrt(float(h.area)) * 0.92       # Grundriss schräg: Breite aus der Fläche statt aus der achsparallelen Box
		var sx: float = hw / (4.62 if onion else 4.0) * 1.05
		var sy: float = maxf(hh, 2.0) / (4.48 if onion else 5.8)
		kit.place(model, Transform3D(Basis().scaled(Vector3(sx, sy, sx)), hpos))
		if onion:
			print("CASTLE_ONION Helm auf %s: Traufe %.1f m über Gelände (LoD2 %.1f m), Breite %.1f m, Helmhöhe %.1f m, Helme auf Grundrissmitte versetzt %d" % [
				buildings.onion_id, hpos.y - float(h.ground), float(h.pos.y) - float(h.ground), hw, hh, buildings.helmets_recentered])
		detail_stats.helmets += 1
		detail_stats.onion += int(onion)
	for b in list:
		if String(b.get("kind", "")) != "building" or BuildingsScript.is_tower(b) or not (String(b.get("roof_type", "")) in ["gable", "hip"]):
			continue
		if not play_rect.has_point(_v2(b.centroid)):
			continue
		var rl = b.get("ridge_line")
		if rl == null or (rl as Array).size() < 2:
			continue
		var hv: int = absi(hash(String(b.id)))
		if hv % 3 == 0:
			var a := Vector3(float(rl[0][0]), float(rl[0][1]), float(rl[0][2]))
			var e := Vector3(float(rl[1][0]), float(rl[1][1]), float(rl[1][2]))
			kit.place("kamin_ziegel_1_7m" if hv % 2 == 0 else "kamin_tuffstein_1_7m", Transform3D(Basis(), a.lerp(e, 0.3) + Vector3.DOWN * 0.5))
			detail_stats.chimneys += 1
		if hv % 4 == 1 and float(b.get("footprint_area_m2", 0.0)) > 120.0:
			var best := PackedVector3Array()
			var best_a := 0.0
			var best_n := Vector3.ZERO
			for poly in b.get("roof_polygons", []):
				var p := PackedVector3Array()
				for q in poly:
					p.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
				var n := MeshBatch.newell(p)
				if n.y < 0.0:
					n = -n
				if n.y < 0.35 or n.y > 0.92:
					continue
				var ar := 0.0
				for i in range(1, p.size() - 1):
					ar += (p[i] - p[0]).cross(p[i + 1] - p[0]).length() * 0.5
				if ar > best_a:
					best_a = ar
					best = p
					best_n = n
			if best_a > 30.0:
				var c := Vector3.ZERO
				for q in best:
					c += q
				c /= best.size()
				var z := -Vector3(best_n.x, 0, best_n.z).normalized()   # Modellfront (−Z) zeigt nach außen
				var x := Vector3.UP.cross(z).normalized()
				kit.place("dachgaube_klein_1_8m", Transform3D(Basis(x, Vector3.UP, z), c + Vector3.DOWN * 0.6))
				detail_stats.dormers += 1
	for pas in buildings.passages:
		if pas.open:
			continue
		var fl: Array = pas.floor
		for end in [0, 1]:
			var t: float = pas.t0 if end == 0 else pas.t1
			var c2: Vector2 = (pas.center as Vector2) + (pas.dir as Vector2) * t
			var y: float = fl[0] if end == 0 else fl[fl.size() - 1]
			var sd: Vector2 = (pas.dir as Vector2).orthogonal()
			var bx := Vector3(sd.x, 0, sd.y)
			kit.place("erdgeschoss_tor_durchgang_8m", Transform3D(Basis(bx * 1.25, Vector3.UP * 1.1, bx.cross(Vector3.UP)), Vector3(c2.x, y, c2.y)))
			detail_stats.portals += 1
	var tries := 0
	while detail_stats.boulders < 24 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(play_rect.position.x, play_rect.end.x), rng.randf_range(play_rect.position.y, play_rect.end.y))
		if Geometry2D.is_point_in_polygon(p, boundary) or boundary_dist(p) < 6.0 or in_building(p, 3.0):
			continue
		var dh := absf(terrain.height(p.x + 1.0, p.y) - terrain.height(p.x - 1.0, p.y)) + absf(terrain.height(p.x, p.y + 1.0) - terrain.height(p.x, p.y - 1.0))
		if dh < 0.8:
			continue
		var sc := rng.randf_range(0.6, 1.3)
		kit.place("nagelfluh_felsbrocken_0%d" % (1 + detail_stats.boulders % 4),
			Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, terrain.height(p.x, p.y) - 0.4 * sc, p.y)))
		detail_stats.boulders += 1
	print("CASTLE_DETAILS ", detail_stats, " Fassaden ", buildings.stats.facade, " Dächer ", buildings.stats.roof)


## Türme: je Hof ein Bering-Knick ohne Gebäude in der Nähe → Bausatzturm mit Leiter zur Plattform
func _build_towers(m: Node) -> void:
	var used := {}
	var n := boundary.size()
	for i in n:
		var p := boundary[i]
		var sec := ""
		for c in COURT_SECTIONS:
			var poly: PackedVector2Array = sections.get(c, PackedVector2Array())
			if Array(poly).any(func(q): return q.distance_to(p) < 0.05):
				sec = c
				break
		if sec == "" or used.has(sec):
			continue
		var a := boundary[(i - 1 + n) % n]
		var b := boundary[(i + 1) % n]
		var inward := (_inward(a, p) + _inward(p, b)).normalized()
		if inward == Vector2.ZERO:
			continue
		var c := p + inward * 4.5
		if not Geometry2D.is_point_in_polygon(c, boundary) or in_building(c, 7.0) or path_info(c)[0] < 7.0:
			continue
		if dividers.any(func(d): return Geometry2D.get_closest_point_to_segment(c, d.a, d.b).distance_to(c) < 9.0):
			continue
		var door := c + inward * 5.0
		var base_y := terrain.height(door.x, door.y)
		var bottom := base_y
		for dx in [-4.0, 4.0]:
			for dz in [-4.0, 4.0]:
				bottom = minf(bottom, terrain.height(c.x + dx, c.y + dz))
		# die ersten beiden Türme mit geraden Innentreppen, die übrigen mit Wendeltreppen (Pack 18); alle mit Außenleiter
		kit.tower(m, "turm_" + sec.to_lower(), c, inward, base_y, bottom - 1.0, terrain.height, kit.towers.size() < 2, kit.towers.size() >= 2)
		_blocked.append([c, 6.5])
		_blocked.append([door, 2.5])
		used[sec] = true


## Bering: Wehrgangmodule entlang der Umrisskanten; ausgelassen in Gebäuden, an Türmen, an Toren der Außenseite
func _build_enceinte() -> void:
	var bgates: Array = []
	for g in features.get("gates", []):
		var gp := _v2(g.position)
		if boundary_dist(gp) < 4.0:
			bgates.append(gp)
	var stairs_per := {}
	var n := boundary.size()
	for i in n:
		var a := boundary[i]
		var b := boundary[(i + 1) % n]
		var L := a.distance_to(b)
		if L < 1.0:
			continue
		var along := (b - a) / L
		var inward := _inward(a, b)
		var cnt := maxi(int(round(L / 4.0)), 1)
		var seg := L / cnt
		var placed := {}
		for k in cnt:
			var c := a + along * seg * (k + 0.5)
			if in_building(c, 0.8) or in_building(c + inward * 1.5, 0.3):
				continue
			if kit.towers.any(func(t): return Vector2(t.pos.x, t.pos.z).distance_to(c) < 6.5):
				continue
			var gp = null
			for g in bgates:
				if (g as Vector2).distance_to(c) < 4.5:
					gp = g
			var base_y := maxf(terrain.height(c.x + inward.x * 1.5, c.y + inward.y * 1.5), terrain.height(c.x + inward.x * 3.0, c.y + inward.y * 3.0))
			var bottom := minf(terrain.height(c.x, c.y), minf(terrain.height(c.x - inward.x * 1.5, c.y - inward.y * 1.5),
				terrain.height(c.x - inward.x * 3.0, c.y - inward.y * 3.0))) - 1.0
			if gp != null:
				# Außentor am Bering: geschlossenes schweres Tor (Spielfläche endet hier)
				if not kit.closed_gates.any(func(q): return Vector2(q.x, q.z).distance_to(gp) < 6.0):
					kit.gate(gp, along, terrain.height(gp.x, gp.y), bottom, true)
				continue
			if near_passage(c, 3.0):
				continue
			kit.wall(c, along, inward, seg, base_y, bottom, true)
			placed[k] = [c, base_y, bottom]
		# Ecke zum nächsten Abschnitt
		var p0 := Vector3(b.x, maxf(terrain.height(b.x, b.y), terrain.height(b.x + inward.x * 3.0, b.y + inward.y * 3.0)), b.y)
		if not in_building(b, 1.0) and placed.has(cnt - 1):
			kit.pillar(p0, minf(terrain.height(b.x, b.y), p0.y) - 1.0)
		# Treppen: Modul k und Nachbar auf der +x-Seite (Rechtssystem des Moduls) vorhanden, Fuß frei
		var xdir := Vector3.UP.cross(Vector3(inward.x, 0, inward.y)).normalized()
		var step := 1 if Vector2(xdir.x, xdir.z).dot(along) > 0.0 else -1
		for k in placed:
			if not placed.has(k + step) or seg < 3.6 or seg > 4.4:
				continue
			var c: Vector2 = placed[k][0]
			var sec := section_of(c + inward * 4.0)
			if sec == "" or int(stairs_per.get(sec, 0)) >= 2:
				continue
			var ok := true
			for f in [-2.0, 0.0, 2.0, 4.0, 6.0]:
				var q: Vector2 = c + Vector2(xdir.x, xdir.z) * f + inward * 3.2
				if in_building(q, 1.5) or path_info(q)[0] < 2.5 or blocked(q, 1.0):
					ok = false
					break
			# Treppe muss zum offenen Hof zeigen (keine Gasse zwischen Bering und Häuserzeile, die nur von außen zugänglich
			# wäre): quer zur Mauer bis 11 m kein Gebäude
			for dk in [4.5, 6.5, 8.5, 11.0]:
				for f in [-2.0, 2.0]:
					if ok and in_building(c + Vector2(xdir.x, xdir.z) * f + inward * dk, 0.5):
						ok = false
			if not ok:
				continue
			if stairs_per.has(sec) and kit.stairs_at.any(func(s2): return Vector2(s2.x, s2.z).distance_to(c) < 60.0):
				continue
			kit.stair(c, along, inward, placed[k][1], minf(placed[k][2] + 1.0, placed[k][1]) - 1.0)
			stairs_per[sec] = int(stairs_per.get(sec, 0)) + 1
			for f in [0.0, 2.0, 4.0]:
				_blocked.append([c + Vector2(xdir.x, xdir.z) * f + inward * 3.2, 3.0])


## Quermauern zwischen den Höfen mit Tor (oder Durchgang durch ein Torgebäude)
func _build_cross_walls() -> void:
	for d in dividers:
		var a: Vector2 = d.a
		var b: Vector2 = d.b
		var L := a.distance_to(b)
		var along := (b - a) / L
		var nrm := Vector2(-along.y, along.x)
		var g: Vector2 = d.gate
		var tg := (g - a).dot(along)
		if not d.passage:
			var gb := minf(terrain.height(g.x + nrm.x * 2, g.y + nrm.y * 2), terrain.height(g.x - nrm.x * 2, g.y - nrm.y * 2)) - 1.0
			# Tor quer zum Weg (Durchgang entlang des Wegs)
			var pdir: Vector2 = path_info(g)[1]
			kit.gate(g, Vector2(-pdir.y, pdir.x), terrain.height(g.x, g.y), gb)
		_blocked.append([g, 6.0])
		var cnt := maxi(int(round(L / 4.0)), 1)
		var seg := L / cnt
		for k in cnt:
			var t := seg * (k + 0.5)
			if absf(t - tg) < 6.0:
				continue
			var c := a + along * t
			if boundary_dist(c) < 1.5 or in_building(c, 1.0) or near_passage(c, 3.5):
				continue
			if kit.towers.any(func(tw): return Vector2(tw.pos.x, tw.pos.z).distance_to(c) < 6.5):
				continue
			var h1 := terrain.height(c.x + nrm.x * 1.5, c.y + nrm.y * 1.5)
			var h2 := terrain.height(c.x - nrm.x * 1.5, c.y - nrm.y * 1.5)
			var base_y := minf(h1, h2)
			kit.wall(c, along, nrm, seg, base_y, minf(base_y, terrain.height(c.x, c.y)) - 1.0, false)
			kit.stats.cross += 1


## Deckung 1944/45 je Hof: Kriegsdeko aus Pack 18 (Draht, Sperren, Stellungen, Feldküche, Kisten …), dazu Sandsäcke
## und in A/C/E ein Wrack; mäßige Menge, Abstand zu Weg, Toren, Durchgängen, Starts. Ohne Pack-Modelle: Kisten/Fässer.
const WRECKS := ["halbkettenfahrzeug_3d", "pkw_wrack_offen", "transporter_wrack"]
const WW2_18 := ["stacheldrahtrolle_3m", "spanischer_reiter_holz_4m", "tschechenigel_stahl", "tarnnetz_stellung_4m",
	"mg_nest_holz_sand", "feldkueche_feuerstelle", "munitionskisten_1945", "fassstapel_1945", "kanisterstapel_1945",
	"feldfunk_tisch_1944", "scheinwerfer_stativ_1945", "flak_erdwall_abgedeckt"]

func _build_cover(m: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1945
	var col := MeshBatch.new()
	var wi := 0
	var have18 := not kit.model_aabb("munitionskisten_1945").size.is_zero_approx()
	_build_garden(rng)
	for si in COURT_SECTIONS.size():
		var sec: String = COURT_SECTIONS[si]
		var cands := _candidates([sec], 3.0, 5.0)
		if cands.is_empty():
			continue
		var items: Array = ["sandbags", "crates", "barrels", "wreck" if sec in ["A", "C", "E"] else "crates", "sandbags"]
		if have18:
			# nur texturierte Modelle (keine prozeduralen Sandsack-/Kistenblöcke)
			items = ["wreck" if sec in ["A", "C", "E"] else "p18:" + WW2_18[(si * 5 + 5) % WW2_18.size()]]
			for k in 5:
				items.append("p18:" + WW2_18[(si * 5 + k) % WW2_18.size()])
		for it in items:
			var clear := 3.0
			if String(it).begins_with("p18:"):
				var bb: AABB = kit.model_aabb(String(it).substr(4))
				clear = maxf(bb.size.x, bb.size.z) * 0.5 + 1.5
			var p := Vector2.INF
			for _try in 60:
				var q: Vector2 = cands[rng.randi() % cands.size()]
				if path_info(q)[0] > 4.0 + clear and not blocked(q, clear) and not near_passage(q, 6.0 + clear) \
						and not dividers.any(func(d): return (d.gate as Vector2).distance_to(q) < 10.0 + clear):
					p = q
					break
			if p == Vector2.INF:
				continue
			var y := terrain.height(p.x, p.y)
			var yaw := rng.randf() * TAU
			if String(it).begins_with("p18:"):
				var name := String(it).substr(4)
				# Stellungen/Sperren quer zum Weg ausrichten
				if name in ["spanischer_reiter_holz_4m", "stacheldrahtrolle_3m", "mg_nest_holz_sand"]:
					var pd: Vector2 = path_info(p)[1]
					yaw = -pd.angle() + (PI if rng.randf() < 0.5 else 0.0)
				kit.prop(name, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y - 0.03, p.y)))
				_blocked.append([p, clear])
				cover.append(Vector3(p.x, y, p.y))
				continue
			match it:
				"sandbags":
					var dir := Vector2(cos(yaw), sin(yaw))
					m.lb.sandbags(Vector3(p.x, y - 0.1, p.y), 3.2, yaw)
					var p2 := p + dir.rotated(PI * 0.5) * 1.6 + dir * 1.3
					m.lb.sandbags(Vector3(p2.x, terrain.height(p2.x, p2.y) - 0.1, p2.y), 2.4, yaw + PI * 0.5)
					_blocked.append([p, 3.0])
				"crates":
					m.lb.crate(Vector3(p.x, y - 0.05, p.y), 1.1, yaw)
					m.lb.crate(Vector3(p.x + 1.2, terrain.height(p.x + 1.2, p.y) - 0.05, p.y + 0.2), 0.9, yaw + 0.4)
					m.lb.crate(Vector3(p.x + 0.4, y + 1.05, p.y), 0.8, yaw + 0.2)
					_blocked.append([p, 2.5])
				"barrels", "wreck":
					var model: String = "fass_eiche" if it == "barrels" else WRECKS[wi % WRECKS.size()]
					if it == "wreck":
						wi += 1
					var cnt := 3 if it == "barrels" else 1
					for k in cnt:
						var q := p + Vector2(k * 0.8, (k % 2) * 0.7)
						if not _prop(m, col, model, Vector3(q.x, terrain.height(q.x, q.y), q.y), yaw + k):
							m.lb.crate(Vector3(q.x, terrain.height(q.x, q.y) - 0.05, q.y), 1.0, yaw)
					_blocked.append([p, 5.0 if it == "wreck" else 2.5])
			cover.append(Vector3(p.x, y, p.y))
	col.commit(m.static_root, "CastleCoverCollision", m.lb, true)


## Garten im Hof B (am Planpunkt des Gartens, sonst Hofmitte): Brunnen mit Holzdach, Obstbäume, Hecken, Gemüsebeete,
## Pflaster-Kies-Übergang und Grasrand (Pack 18). Abstand zum Weg; Bäume nur mit Stammkollision.
var garden: Array = []

func _build_garden(rng: RandomNumberGenerator) -> void:
	if kit.model_aabb("brunnen_holzdach").size.is_zero_approx():
		return
	var center := Vector2.INF
	for key in features.get("plan_points", {}):
		var pp: Dictionary = features.plan_points[key]
		var p := _v2(pp.position)
		if String(pp.get("kind", "")) == "feature" and section_of(p) == "B":
			center = p
			break
	var cands := _candidates(["B"], 2.0, 5.0)
	if cands.is_empty():
		return
	if center == Vector2.INF:
		center = cands[cands.size() / 2]
	cands = cands.filter(func(q): return q.distance_to(center) < 30.0 and path_info(q)[0] > 4.0)
	cands.sort_custom(func(a, b): return a.distance_to(center) < b.distance_to(center))
	var plan := [["brunnen_holzdach", 2.2, true], ["obstbaum_apfel_sommer", 2.2, false], ["obstbaum_birne_sommer", 2.2, false],
		["obstbaum_apfel_sommer", 2.2, false], ["gemuesebeet_kohl", 1.8, true], ["gemuesebeet_moehren", 1.8, true],
		["hecke_sommer_4m", 2.8, true], ["hecke_sommer_4m", 2.8, true], ["hof_pflaster_kies_4x4", 2.4, false],
		["hof_grasrand_4m", 2.4, false]]
	for it in plan:
		for q in cands:
			if blocked(q, float(it[1])):
				continue
			var y := terrain.height(q.x, q.y)
			var pdir: Vector2 = path_info(q)[1]
			var yaw: float = rng.randf() * TAU if String(it[0]).begins_with("obst") else -pdir.angle()
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, y - 0.03, q.y))
			kit.prop(String(it[0]), xf, it[2])
			if String(it[0]).begins_with("obst"):
				kit.col.box(Transform3D(Basis(), Vector3(q.x, y + 1.0, q.y)), Vector3(0.35, 2.0, 0.35), "c_wood", false, true)
			_blocked.append([q, float(it[1])])
			garden.append({"model": it[0], "pos": Vector3(q.x, y, q.y)})
			break


func _prop(m: Node, col: MeshBatch, model: String, pos: Vector3, yaw: float) -> bool:
	var root: Node3D = LibraryModels.load_model(model)
	if root == null:
		return false
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = (mi as MeshInstance3D).transform
		var p := mi.get_parent()
		while p != null and p != root:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		var bb := t * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var holder := Node3D.new()
	holder.name = "Deckung_" + model
	m.dynamic_root.add_child(holder)
	holder.position = pos - Vector3(0, box.position.y + 0.03, 0)
	holder.rotation.y = yaw
	holder.add_child(root)
	holder.add_to_group("castle_cover")
	var b := Basis(Vector3.UP, yaw)
	var c := holder.position + b * box.get_center()
	col.box(Transform3D(b, c), box.size * Vector3(0.9, 1.0, 0.9), "c_wood", false, true)
	return true


## Achse quer durch die Wand des Gebäudes, das einem Punkt am nächsten liegt (Normale der nächsten Grundrisskante)
func _wall_axis(p: Vector2) -> Vector2:
	var best := INF
	var ax := Vector2(0, 1)
	for e in _fp_boxes:
		if not (e[0] as Rect2).grow(10.0).has_point(p):
			continue
		var fp: PackedVector2Array = e[1]
		for i in fp.size():
			var a := fp[i]
			var b := fp[(i + 1) % fp.size()]
			var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
			if d < best and a.distance_to(b) > 0.5:
				best = d
				ax = (b - a).normalized().orthogonal()
	return ax


## Hauptburg F: Rasterabdeckung (1 m) des Hofs – frei = im Abschnitt, nicht im Gebäude (außer in Durchgängen),
## Stufen > 1 m sperren. Flutfüllung vom Zugang (Quermauer-Tor E|F); jede noch abgeschlossene Hoffläche ≥ 60 m² bekommt
## den kürzesten geraden Durchgang durch Gebäude zur erreichten Fläche (höchstens 6). Ergebnis auch für Platzhalter.
var _fg := {}     # ox, oz, nx, nz, inpoly, bld, open, reach

func _fi(p: Vector2) -> int:
	var i := int(floor(p.x - float(_fg.ox)))
	var j := int(floor(p.y - float(_fg.oz)))
	if i < 0 or j < 0 or i >= int(_fg.nx) or j >= int(_fg.nz):
		return -1
	return j * int(_fg.nx) + i


func _fc(k: int) -> Vector2:
	return Vector2(float(_fg.ox) + (k % int(_fg.nx)) + 0.5, float(_fg.oz) + (k / int(_fg.nx)) + 0.5)


func _mark_corridor(g: Vector2, dir: Vector2) -> void:
	var t0 := INF
	var t1 := -INF
	for e in _fp_boxes:
		if not (e[0] as Rect2).grow(40.0).has_point(g):
			continue
		var iv := BuildingsScript.passage_interval(e[1], g, dir)
		if not iv.is_empty():
			t0 = minf(t0, iv.t0)
			t1 = maxf(t1, iv.t1)
	if t0 == INF:
		return
	var a := g + dir * (t0 - 1.5)
	var b := g + dir * (t1 + 1.5)
	var s := 0.0
	var L := a.distance_to(b)
	var op: PackedByteArray = _fg.open
	var ip: PackedByteArray = _fg.inpoly
	while s <= L:
		var c := a.lerp(b, s / maxf(L, 0.01))
		for w in [-1.5, -0.75, 0.0, 0.75, 1.5]:
			var k := _fi(c + dir.orthogonal() * w)
			if k >= 0 and ip[k]:
				op[k] = 1
		s += 0.5
	_fg.open = op


func _flood_f(start: int) -> void:
	var reach := PackedByteArray()
	reach.resize(int(_fg.nx) * int(_fg.nz))
	var q: Array[int] = [start]
	reach[start] = 1
	var nx := int(_fg.nx)
	while not q.is_empty():
		var k: int = q.pop_back()
		var hk := terrain.height(_fc(k).x, _fc(k).y)
		for o in [1, -1, nx, -nx]:
			var n: int = k + o
			if n < 0 or n >= reach.size() or reach[n] or not _fg.open[n]:
				continue
			if (o == 1 or o == -1) and n / nx != k / nx:
				continue
			var c := _fc(n)
			if absf(terrain.height(c.x, c.y) - hk) > 1.0:
				continue
			reach[n] = 1
			q.append(n)
	_fg.reach = reach


func _plan_f_access(gps: Array) -> void:
	var poly: PackedVector2Array = sections.get("F", PackedVector2Array())
	if poly.is_empty():
		return
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	_fg = {"ox": floor(r.position.x), "oz": floor(r.position.y), "nx": int(ceil(r.size.x)) + 2, "nz": int(ceil(r.size.y)) + 2}
	var n: int = int(_fg.nx) * int(_fg.nz)
	var inpoly := PackedByteArray()
	var bld := PackedByteArray()
	var open := PackedByteArray()
	inpoly.resize(n)
	bld.resize(n)
	open.resize(n)
	for k in n:
		var c := _fc(k)
		inpoly[k] = 1 if Geometry2D.is_point_in_polygon(c, poly) else 0
		var kind := building_kind_at(c, 0.3) if inpoly[k] else ""
		# 1 = Gebäude (durchtunnelbar), 2 = Mauer/Bauwerk (nicht)
		bld[k] = 0 if kind == "" else (2 if kind in ["wall", "structure"] else 1)
		open[k] = 1 if inpoly[k] and not bld[k] else 0
	_fg.inpoly = inpoly
	_fg.bld = bld
	_fg.open = open
	for e in gps:
		_mark_corridor(e[0], e[1])
	# Start: freie Zelle in F nahe dem Quermauer-Tor E|F
	var start := -1
	for d in dividers:
		if String(d.name) == "E|F":
			var bd := INF
			for k in n:
				if _fg.open[k] and _fc(k).distance_to(d.gate) < bd:
					bd = _fc(k).distance_to(d.gate)
					start = k
	if start < 0:
		return
	_flood_f(start)
	var added := 0
	var skip := PackedByteArray()     # Flächen ohne möglichen Durchgang (z. B. hinter LoD2-Mauern) überspringen
	skip.resize(n)
	for _iter in 10:
		# größte nicht erreichte freie Fläche
		var label := PackedInt32Array()
		label.resize(n)
		var best_comp: Array = []
		var nx: int = int(_fg.nx)
		for k in n:
			if not _fg.open[k] or _fg.reach[k] or label[k] or skip[k]:
				continue
			var comp: Array = [k]
			label[k] = 1
			var qi := 0
			while qi < comp.size():
				var c: int = comp[qi]
				qi += 1
				for o in [1, -1, nx, -nx]:
					var m2: int = c + o
					if m2 >= 0 and m2 < n and not label[m2] and _fg.open[m2] and not _fg.reach[m2] \
							and not ((o == 1 or o == -1) and m2 / nx != c / nx):
						label[m2] = 1
						comp.append(m2)
			if comp.size() > best_comp.size():
				best_comp = comp
		if best_comp.size() < 60:
			break
		# kürzester gerader Weg durch Gebäude zur erreichten Fläche
		var best_len := INF
		var best_mid := Vector2.ZERO
		var best_dir := Vector2.ZERO
		for idx in range(0, best_comp.size(), 3):
			var cp := _fc(best_comp[idx])
			for a in 16:
				var dv := Vector2.from_angle(a * TAU / 16.0)
				var s := 1.0
				var sol0 := -1.0
				var sol1 := -1.0
				while s < 30.0 and s < best_len:
					var k := _fi(cp + dv * s)
					if k < 0 or not _fg.inpoly[k] or _fg.bld[k] == 2:
						break
					if _fg.bld[k] == 1 and not _fg.open[k]:
						if sol0 < 0.0:
							sol0 = s
						sol1 = s
					elif _fg.reach[k]:
						var q := cp + dv * s
						if sol0 > 0.0 and s < best_len and absf(terrain.height(q.x, q.y) - terrain.height(cp.x, cp.y)) < 2.0:
							best_len = s
							best_mid = cp + dv * ((sol0 + sol1) * 0.5)
							best_dir = dv
						break
					elif sol0 > 0.0:
						break     # andere abgeschlossene Fläche
					s += 0.5
		if best_len == INF:
			for k in best_comp:
				skip[k] = 1
			continue
		gps.append([best_mid, best_dir])
		_mark_corridor(best_mid, best_dir)
		_flood_f(start)
		added += 1
	var reached := 0
	var free := 0
	for k in n:
		if _fg.open[k]:
			free += 1
			reached += int(_fg.reach[k])
	print("CASTLE_F: %d zusätzliche Durchgänge, erreichbar %d von %d m² freier Hoffläche" % [added, reached, free])
	if Game.cli.has("castle_fdebug"):
		# Prüfbild: schwarz außerhalb, grau Gebäude, dunkelrot Mauer, weiß frei/unerreicht, grün erreicht
		var img := Image.create(int(_fg.nx), int(_fg.nz), false, Image.FORMAT_RGB8)
		for k in n:
			var col := Color.BLACK
			if _fg.inpoly[k]:
				col = Color(0.55, 0.55, 0.55) if _fg.bld[k] == 1 else (Color(0.5, 0.1, 0.1) if _fg.bld[k] == 2 else Color.WHITE)
				if _fg.open[k] and _fg.bld[k]:
					col = Color(0.3, 0.4, 1.0)
				if _fg.reach[k]:
					col = Color(0.2, 0.75, 0.25)
			img.set_pixel(k % int(_fg.nx), k / int(_fg.nx), col)
		img.resize(int(_fg.nx) * 4, int(_fg.nz) * 4, Image.INTERPOLATE_NEAREST)
		img.save_png(ProjectSettings.globalize_path("res://test_output/castle_f_grid.png"))


func _reachable_f(p: Vector2) -> bool:
	if _fg.is_empty() or not _fg.has("reach"):
		return true
	var k := _fi(p)
	return k >= 0 and _fg.reach[k] == 1


## Größter Gebäudeblock der Hauptburg (≥ 1500 m², mehrere Planpunkte) → benannte Teile je Planpunkt
func _split_main_block(list: Array) -> void:
	var poly: PackedVector2Array = sections.get("F", PackedVector2Array())
	for b in list:
		if float(b.get("footprint_area_m2", 0.0)) < 1500.0 or not Geometry2D.is_point_in_polygon(_v2(b.centroid), poly):
			continue
		var fp := BuildingsScript.fp_of(b)
		var seeds: Array = []
		for key in features.get("plan_points", {}):
			var pp: Dictionary = features.plan_points[key]
			if String(key).begins_with("f") and String(pp.get("kind", "")) in ["building", "tower", "gate", "wall"]:
				var p := _v2(pp.position)
				if BuildingsScript.dist_to_poly(p, fp) < 6.0:
					var lbl = pp.get("label_local")
					var chapel: bool = lbl is String and (lbl as String).to_lower().contains("kapelle")
					seeds.append([String(key), p, String(pp.kind), chapel])
		if seeds.size() >= 2:
			buildings.split_building(String(b.id), seeds)


## Kandidaten für freie Plätze (Raster step) in den Abschnitten secs mit Abstand margin zum Bering
func _candidates(secs: Array, step: float, margin: float) -> Array:
	var out: Array = []
	for sec in secs:
		var poly: PackedVector2Array = sections.get(sec, PackedVector2Array())
		if poly.is_empty():
			continue
		var r := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			r = r.expand(p)
		var x := r.position.x + step * 0.5
		while x < r.end.x:
			var z := r.position.y + step * 0.5
			while z < r.end.y:
				var p := Vector2(x, z)
				if Geometry2D.is_point_in_polygon(p, poly) and Geometry2D.is_point_in_polygon(p, boundary) \
						and boundary_dist(p) > margin and not in_building(p, 3.0) and not blocked(p) \
						and not dividers.any(func(d): return Geometry2D.get_closest_point_to_segment(p, d.a, d.b).distance_to(p) < 5.0) \
						and _flat(p) and (sec != "F" or _reachable_f(p)):
					out.append(p)
				z += step
			x += step
	return out


func _flat(p: Vector2) -> bool:
	var h := terrain.height(p.x, p.y)
	for o in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		if absf(terrain.height(p.x + o.x, p.y + o.y) - h) > 0.45:
			return false
	# kein Graben: Umgebung in 8 m nicht deutlich höher
	var rim := -INF
	for o in [Vector2(8, 0), Vector2(-8, 0), Vector2(0, 8), Vector2(0, -8)]:
		rim = maxf(rim, minf(terrain.height(p.x + o.x, p.y + o.y), terrain.height(p.x - o.x, p.y - o.y)))
	return h > rim - 1.5


## Zonennamen (neutral, nach Lage/Ausstattung des Hofs)
const ZONE_NAMES := {"A": "A – Nordhof", "B": "B – Gartenhof", "C": "C – Mittelhof", "D": "D – Grabenhof",
	"E": "E – Torhof", "F": "F – Hauptburg"}
## Zonenquader [Länge entlang des Hofs, Breite quer], größte Fläche zuerst
const ZONE_SIZES := [[44.0, 30.0], [40.0, 28.0], [44.0, 22.0], [36.0, 26.0], [40.0, 20.0], [32.0, 24.0], [34.0, 18.0],
	[28.0, 22.0], [30.0, 16.0], [24.0, 18.0], [24.0, 14.0], [20.0, 14.0], [16.0, 12.0]]
const ZONE_HEIGHT := 10.0          # Quaderhöhe (Net.zone_contains: ±H/2 + 2 m um die Mitte 1 m über dem Boden)
const ZONE_SLOTS := 8              # Spawnplätze je Zone (castle.gd behält nach der Netz-/Sichtprüfung bis 6, mind. 4)
const SPAWNS_PER_SET := 8


static func centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


## Liegt p in der Spielfläche der aktuellen Spielart? (Eroberung: ganze Burg; DM/TDM: Höfe D, E, F bzw. Südseite C|D)
func in_play(p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, boundary):
		return false
	if not restricted:
		return true
	var sec := section_of(p)
	if sec != "":
		return sec in PLAY_SECTIONS
	# außerhalb aller Abschnittspolygone (Mauern, Ränder): Seite der Quermauer C|D wie die Mitte von D
	for d in dividers:
		if String(d.name) == INNER_DIVIDER:
			var ab: Vector2 = (d.b as Vector2) - (d.a as Vector2)
			var dc := centroid(sections.get("D", PackedVector2Array())) - (d.a as Vector2)
			return signf(ab.cross(p - (d.a as Vector2))) == signf(ab.cross(dc))
	return true


## Quader (Länge L entlang axis, Breite W) liegt mit Rand ganz im Abschnitt und im Bering
func _box_fits(poly: PackedVector2Array, c: Vector2, axis: Vector2, L: float, W: float) -> bool:
	var side := axis.orthogonal()
	for i in 9:
		var u := -0.5 + float(i) / 8.0
		for v in [-0.5, 0.5]:
			for q in [c + axis * (u * L) + side * (v * W), c + axis * (v * L) + side * (u * W)]:
				if not Geometry2D.is_point_in_polygon(q, poly) or not Geometry2D.is_point_in_polygon(q, boundary):
					return false
	return true


## Anteil der Quaderfläche ohne Gebäude (Raster 7 × 5)
func _free_frac(c: Vector2, axis: Vector2, L: float, W: float) -> float:
	var side := axis.orthogonal()
	var free := 0
	for i in 7:
		for j in 5:
			if not in_building(c + axis * ((i / 6.0 - 0.5) * L) + side * ((j / 4.0 - 0.5) * W)):
				free += 1
	return free / 35.0


## Zone eines Hofs: Mittelpunkt auf freiem, ebenem (in F erreichbarem) Boden nahe der Hofmitte, Quader entlang des Hauptwegs
## so groß, wie der Hof es zulässt (überwiegend frei); Spawnplätze im/am Quader abseits der Sichtachse Weg/Tore
func _zone_for(sec: String) -> Dictionary:
	var poly: PackedVector2Array = sections.get(sec, PackedVector2Array())
	if poly.is_empty():
		return {}
	var cen := centroid(poly)
	var cands := _candidates([sec], 2.0, 4.0)
	cands.sort_custom(func(a, b): return a.distance_to(cen) < b.distance_to(cen))
	var best := {}
	var best_s := -INF
	for k in mini(cands.size(), 80):
		var c: Vector2 = cands[k]
		var axis: Vector2 = path_info(c)[1]
		for sz in ZONE_SIZES:
			if not _box_fits(poly, c, axis, sz[0], sz[1]):
				continue
			var free := _free_frac(c, axis, sz[0], sz[1])
			if free < 0.55:
				continue
			var sc: float = float(sz[0]) * float(sz[1]) * free - 3.0 * c.distance_to(cen)
			if sc > best_s:
				best_s = sc
				best = {"c": c, "axis": axis, "L": float(sz[0]), "W": float(sz[1]), "free": free}
			break      # größter passender Quader an diesem Punkt
	if best.is_empty():
		# Rückfall: kleiner Kreis am hofnächsten freien Punkt
		if cands.is_empty():
			return {}
		best = {"c": cands[0], "axis": path_info(cands[0])[1], "L": 0.0, "W": 0.0, "free": 1.0}
	var c: Vector2 = best.c
	var axis: Vector2 = best.axis
	var z := {"id": "zone_" + sec.to_lower(), "name": ZONE_NAMES.get(sec, sec), "section": sec, "pos": [c.x, c.y],
		"y": terrain.height(c.x, c.y) + 1.0, "capture_time_s": 15, "axis": [axis.x, axis.y]}
	if float(best.L) > 0.0:
		z["box"] = [best.W, ZONE_HEIGHT, best.L]
		z["radius"] = minf(best.W, best.L) * 0.5
	else:
		z["radius"] = 10.0
	_blocked.append([c, 3.5])           # Fahnenmast an der Zonenmitte
	# Spawnplätze: im Hof, ≤ halbe Quaderdiagonale + 8 m um die Mitte, nicht am Mast, abseits des Hauptwegs (der durch die
	# Tore läuft = Sichtachse zur Nachbarzone), untereinander ≥ 3,5 m
	var reach := Vector2(float(best.L), float(best.W)).length() * 0.5 + 8.0 if float(best.L) > 0.0 else 18.0
	var pool: Array = []
	for q in cands:
		var d := (q as Vector2).distance_to(c)
		if d < 4.0 or d > reach or in_building(q, 1.5) or blocked(q, 1.2):
			continue
		var pd: float = path_info(q)[0]
		if pd < 2.5:
			continue
		pool.append([minf(pd, 14.0) - d * 0.2, q])
	pool.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var slots: Array = []
	for e in pool:
		var q: Vector2 = e[1]
		if slots.any(func(s): return Vector2(s[0], s[1]).distance_to(q) < 3.5):
			continue
		slots.append([q.x, q.y])
		if slots.size() >= ZONE_SLOTS:
			break
	for s in slots:
		_blocked.append([Vector2(s[0], s[1]), 1.6])
	z["slots"] = slots
	print("CASTLE_ZONE %s %s Mitte (%.1f, %.1f) Quader %.0f × %.0f m (frei %.0f %%), %d Plätze" % [z.id, sec, c.x, c.y,
		float(best.L), float(best.W), float(best.free) * 100.0, slots.size()])
	return z


## Liegt p (2D) in einer der Zonen (Quader bzw. Kreis), mit Rand margin?
static func _in_zone_2d(zones: Array, p: Vector2, margin: float) -> bool:
	for z in zones:
		var c := Vector2(float(z.pos[0]), float(z.pos[1]))
		if z.has("box"):
			var ax := Vector2(float(z.axis[0]), float(z.axis[1]))
			var l := p - c
			if absf(l.dot(ax)) <= float(z.box[2]) * 0.5 + margin and absf(l.dot(ax.orthogonal())) <= float(z.box[0]) * 0.5 + margin:
				return true
		elif p.distance_to(c) <= float(z.radius) + margin:
			return true
	return false


## n Starts in den Abschnitten secs (weit gestreut: jeweils der Punkt mit dem größten Abstand zu den gewählten),
## abseits des Hauptwegs und der Zonen; Blick entlang des Wegs zur Gegenseite (Team 0 nach Süden, 1 nach Norden)
func _pick_spawns(secs: Array, n: int, team: int, zones: Array) -> Array:
	var cands := _candidates(secs, 3.0, 6.0).filter(func(p): return path_info(p)[0] > 1.5 and not blocked(p, 1.0) \
		and not _in_zone_2d(zones, p, 2.0))
	var cen := Vector2.ZERO
	for s in secs:
		cen += centroid(sections.get(s, PackedVector2Array()))
	cen /= maxf(secs.size(), 1)
	var chosen: Array = []
	if not cands.is_empty():
		var first: Vector2 = cands[0]
		for p in cands:
			if (p as Vector2).distance_to(cen) < first.distance_to(cen):
				first = p
		chosen.append(first)
	while chosen.size() < n and chosen.size() < cands.size():
		var far := Vector2.ZERO
		var fd := -1.0
		for p in cands:
			var md := INF
			for q in chosen:
				md = minf(md, (p as Vector2).distance_to(q))
			if md > fd:
				fd = md
				far = p
		if fd < 3.0:
			break
		chosen.append(far)
	var out: Array = []
	for p in chosen:
		var d: Vector2 = path_info(p)[1]
		if team == 1:
			d = -d
		elif team < 0:
			d = (cen - p).normalized() if cen.distance_to(p) > 1.0 else d
		out.append({"pos": [p.x, p.y], "team": team, "yaw": atan2(-d.x, -d.y)})
		_blocked.append([p, 1.6])
	return out


## Zonen je Hof A–F (Reihenfolge = FRONTLINE-Nachbarschaft; Alliierte besitzen A im Norden, Achse F), Startsätze:
## DM = D (Team 0) + E (beide) + F (Team 1), TDM = D gegen F, Eroberung (Rückfall ohne eigene Zone) = A gegen F
func _spawns_and_zones() -> Dictionary:
	var zones: Array = []
	for si in COURT_SECTIONS.size():
		var z := _zone_for(COURT_SECTIONS[si])
		if z.is_empty():
			push_warning("Castle: keine Zone im Hof %s" % COURT_SECTIONS[si])
			continue
		z["owner"] = 0 if si == 0 else (1 if si == COURT_SECTIONS.size() - 1 else -1)
		zones.append(z)
	var d_set := _pick_spawns(["D"], SPAWNS_PER_SET, 0, zones)
	var f_set := _pick_spawns(["F"], SPAWNS_PER_SET, 1, zones)
	var e_set := _pick_spawns(["E"], SPAWNS_PER_SET, -1, zones)
	var a_set := _pick_spawns(["A"], SPAWNS_PER_SET, 0, zones)
	spawn_sets = {"dm": d_set + e_set + f_set, "tdm": d_set + f_set, "occupation": a_set + f_set}
	var key := "occupation" if play_mode == 2 else ("tdm" if play_mode == 1 else "dm")
	print("CASTLE_SPAWNS dm %d (D %d, E %d, F %d), tdm %d, occupation %d (A %d) – aktiv %s" % [spawn_sets.dm.size(), d_set.size(),
		e_set.size(), f_set.size(), spawn_sets.tdm.size(), spawn_sets.occupation.size(), a_set.size(), key])
	var bnd: Array = []
	for p in boundary:
		bnd.append([p.x, p.y])
	return {"format": 1, "real": true, "boundary": bnd, "spawns": spawn_sets[key], "occupation_zones": zones}


## DM/TDM: innere Grenze entlang der Quermauer C|D (Bewegungssperre Ebene 5 unter static_root → schneidet auch das
## Navmesh, Sicht/Schüsse frei; 12 m über den Bering hinaus, deckt Wehrgang und Außengrenze ab) und sichtbar
## verrammeltes Tor im Durchgang (Torflügel mit Kollision auf der Seite D, davor Sperre und Drahtrolle), Drahtrollen
## auf dem Wehrgang, wo die Grenze ihn kreuzt.
func _build_inner_boundary(m: Node) -> void:
	var div = null
	for d in dividers:
		if String(d.name) == INNER_DIVIDER:
			div = d
	if div == null:
		push_warning("Castle: Quermauer %s fehlt – keine innere Grenze" % INNER_DIVIDER)
		return
	var a: Vector2 = div.a
	var b: Vector2 = div.b
	var ab := (b - a).normalized()
	var chain: Array = []
	for p in sections.get("C", PackedVector2Array()):
		for q in sections.get("D", PackedVector2Array()):
			if p.distance_to(q) < 0.05 and not chain.any(func(c): return (c as Vector2).distance_to(p) < 0.05):
				chain.append(p)
	if chain.size() < 2:
		chain = [a, b]
	chain.sort_custom(func(x, y): return (x - a).dot(ab) < (y - a).dot(ab))
	var ends := [chain[0], chain[chain.size() - 1]]
	# Abschnittslinie endet nicht immer am Bering: bis zum Schnitt mit der Beringlinie verlängern, dann 12 m darüber hinaus
	for k in [0, chain.size() - 1]:
		var e: Vector2 = chain[k]
		var dir2: Vector2 = -ab if k == 0 else ab
		var far := e + dir2 * 400.0
		var hit := Vector2.INF
		for i in boundary.size():
			var h = Geometry2D.segment_intersects_segment(e - dir2 * 0.5, far, boundary[i], boundary[(i + 1) % boundary.size()])
			if h != null and (hit == Vector2.INF or e.distance_to(h) < e.distance_to(hit)):
				hit = h
		chain[k] = (hit if hit != Vector2.INF else e) + dir2 * 12.0
		ends[0 if k == 0 else 1] = hit if hit != Vector2.INF else e
	inner_ends = ends
	for i in chain.size() - 1:
		var p: Vector2 = chain[i]
		var q: Vector2 = chain[i + 1]
		var dir := q - p
		var lo := INF
		var hi := -INF
		for k in 13:
			var s := p.lerp(q, k / 12.0)
			for o in [-3.0, 0.0, 3.0]:
				var h := terrain.height(s.x + dir.orthogonal().normalized().x * o, s.y + dir.orthogonal().normalized().y * o)
				lo = minf(lo, h)
				hi = maxf(hi, h)
		lo -= 6.0
		hi += 28.0
		var mid := (p + q) * 0.5
		var body := StaticBody3D.new()
		body.name = "InnerBoundary_%d" % i
		body.collision_layer = LevelBuilder.FENCE_LAYER
		body.collision_mask = 0
		# Vier dünne Scheiben (je 0,3 m, Abstand 0,3 m) statt einer Wand: Recast rastert Kollider als Flächen – im
		# Inneren eines dicken Körpers bliebe der Tunnelboden begehbar; Streifen ≤ 2 Zellen zwischen den Scheiben erodiert
		# der Agentenradius. Netzkanten beidseits ≈ 2,5 m auseinander > Inselbrücke (1,2 m) / Kletterstelle (1,6 m) – eine
		# einzelne 0,3-m-Wand ließ eine Inselbrücke durch (Kapsel startet in der Wand, cast_motion übersieht das).
		for off in [-0.9, -0.3, 0.3, 0.9]:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(dir.length() + 0.6, hi - lo, 0.3)
			cs.shape = box
			cs.position = Vector3(0, 0, off)
			body.add_child(cs)
		m.static_root.add_child(body)
		body.position = Vector3(mid.x, (lo + hi) * 0.5, mid.y)
		body.rotation.y = atan2(-dir.y, dir.x)
		body.add_to_group("castle_inner_boundary")
		inner_lines.append([p, q])
	# Wehrgang: Drahtrolle quer über den Gang am Kreuzungspunkt
	var nrm := ab.orthogonal()
	for e in ends:
		var best = null
		var bd := 6.0
		for w in kit.walk_points:
			var wp: Vector3 = w
			var d := Vector2(wp.x, wp.z).distance_to(e)
			if d < bd:
				bd = d
				best = wp
		if best != null:
			var wp: Vector3 = best
			var on := Geometry2D.get_closest_point_to_segment(Vector2(wp.x, wp.z), (e as Vector2) - ab * 20.0, (e as Vector2) + ab * 20.0)
			# auf der Seite D (Spielfläche) knapp vor der Grenze
			var sd := nrm if in_play(on + nrm * 2.0) else -nrm
			var pos := on + sd * 2.0
			kit.prop("stacheldrahtrolle_3m", Transform3D(Basis(Vector3.UP, -nrm.angle()), Vector3(pos.x, wp.y - 0.03, pos.y)))
	# verrammeltes Tor im Durchgang (Gebäude) bzw. geschlossenes Bausatztor
	var done := false
	for pas in buildings.passages:
		if (pas.center as Vector2).distance_to(div.gate) > 0.1:
			continue
		var c: Vector2 = pas.center
		var dv: Vector2 = pas.dir
		var fl: Array = pas.floor
		var t: float = pas.t1
		var fy: float = fl[fl.size() - 1]
		var out := dv
		if not in_play(c + dv * (float(pas.t1) + 3.0)):
			t = pas.t0
			fy = fl[0]
			out = -dv
		var gp := c + dv * t - out * 0.6        # 0,6 m innerhalb der Tunnelöffnung auf der Seite D
		_barricade(m, gp, out, fy)
		done = true
		break
	if not done:
		var g: Vector2 = div.gate
		var pdir: Vector2 = path_info(g)[1]
		var out2 := pdir if in_play(g + pdir * 4.0) else -pdir
		_barricade(m, g + out2 * 1.0, out2, terrain.height(g.x, g.y))
	print("CASTLE_INNER: %d Grenzabschnitte an %s, Tor %s" % [inner_lines.size(), INNER_DIVIDER, str(inner_gate.get("pos", "-"))])


## Torflügel (Kollision Ebene 1, sichtbar, Eichenholz mit Querriegeln) quer im Durchgang an gp, Blick out = zur Spielfläche;
## davor (Seite out) Spanischer Reiter und Drahtrolle
func _barricade(m: Node, gp: Vector2, out: Vector2, fy: float) -> void:
	var z := Vector3(out.x, 0, out.y).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var bs := Basis(x, Vector3.UP, z)
	var o := Vector3(gp.x, fy, gp.y)
	kit.col.box(Transform3D(bs, o + Vector3.UP * 1.75), Vector3(4.6, 3.5, 0.24), "c_wood", true, true)
	for hy in [0.7, 1.75, 2.8]:
		kit.col.box(Transform3D(bs, o + Vector3.UP * hy + z * 0.15), Vector3(4.5, 0.18, 0.08), "c_wood", true, false)
	# Diagonalstrebe
	kit.col.box(Transform3D(bs * Basis(Vector3.FORWARD, deg_to_rad(36.0)), o + Vector3.UP * 1.75 + z * 0.2), Vector3(4.6, 0.16, 0.08), "c_wood", true, false)
	kit.closed_gates.append(o)
	kit.stats.closed_gates += 1
	inner_gate = {"pos": o, "out": z}
	var p1 := gp + out * 3.4
	var p2 := gp + out * 6.2 + out.orthogonal() * 1.2
	kit.prop("spanischer_reiter_holz_4m", Transform3D(Basis(Vector3.UP, -out.orthogonal().angle()), Vector3(p1.x, terrain.height(p1.x, p1.y) - 0.03, p1.y)))
	kit.prop("stacheldrahtrolle_3m", Transform3D(Basis(Vector3.UP, -out.orthogonal().angle()), Vector3(p2.x, terrain.height(p2.x, p2.y) - 0.03, p2.y)))
	_blocked.append([gp + out * 4.0, 5.0])


## Kartengrenze: Bewegungsbarriere Ebene 5, 1,5 m außerhalb der Beringlinie, Höhe über das Gelände der Kante
func build_border(m: Node) -> void:
	var n := boundary.size()
	var area := 0.0
	for i in n:
		area += boundary[i].cross(boundary[(i + 1) % n])
	var ccw := area > 0.0
	for i in n:
		var a := boundary[i]
		var b := boundary[(i + 1) % n]
		var dir := b - a
		var out := -_inward(a, b)
		var lo := INF
		var hi := -INF
		for k in 9:
			var p := a.lerp(b, k / 8.0) + out * 1.5
			var h := terrain.height(p.x, p.y)
			lo = minf(lo, h)
			hi = maxf(hi, maxf(h, terrain.height(p.x - out.x * 4.0, p.y - out.y * 4.0)))
		lo -= 4.0
		hi += 30.0
		# Gehrung: an Außenecken verlängern (Lücke zwischen den Scheiben), an Innenecken kürzen (sonst ragten die
		# Scheiben bis 2,6 m außerhalb der Linie über die Ecke hinaus in den Hof, z. B. vor eine Wehrgangtreppe)
		var dn := dir.normalized()
		var ext_a := _corner_ext((a - boundary[(i - 1 + n) % n]).normalized(), dn, ccw)
		var ext_b := _corner_ext(dn, (boundary[(i + 2) % n] - b).normalized(), ccw)
		var length := maxf(dir.length() + ext_a + ext_b, 0.3)
		var mid := (a + b) * 0.5 + out * 1.5 + dn * (ext_b - ext_a) * 0.5
		var body := StaticBody3D.new()
		body.name = "MapBoundary_%d" % i
		body.collision_layer = LevelBuilder.FENCE_LAYER
		body.collision_mask = 0
		# Unter static_root und als vier dünne Scheiben (wie die innere Grenze): schneidet das Navmesh am Bering, sonst
		# führten KI-Wege über Kletterstellen/Inselbrücken außen am Hang um Quermauern herum (und blieben an der
		# Bewegungssperre hängen)
		for off in [-0.9, -0.3, 0.3, 0.9]:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(length, hi - lo, 0.3)
			cs.shape = box
			cs.position = Vector3(0, 0, off)
			body.add_child(cs)
		m.static_root.add_child(body)
		body.position = Vector3(mid.x, (lo + hi) * 0.5, mid.y)
		body.rotation.y = atan2(-dir.y, dir.x)
		body.add_to_group("castle_boundaries")


## Gehrungsmaß einer Ecke für Scheiben bis 2,6 m außerhalb der Linie: d_in = Richtung bis zur Ecke, d_out = danach.
## > 0 verlängern (Außenecke: Knick in Umlaufrichtung des Polygons), < 0 kürzen (Innenecke); Winkel bis 150°
static func _corner_ext(d_in: Vector2, d_out: Vector2, ccw: bool) -> float:
	var th := absf(d_in.angle_to(d_out))
	var t := tan(minf(th, deg_to_rad(150.0)) * 0.5) * 2.6 + 0.15
	return t if (d_in.cross(d_out) > 0.0) == ccw else -(t - 0.3)
