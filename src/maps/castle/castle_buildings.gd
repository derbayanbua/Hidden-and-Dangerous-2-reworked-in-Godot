extends RefCounted
## Castle: Gebäude aus den Gebäudedaten der Karte (Wandpolygone + echte Dachpolygone, geschlossen, nicht
## begehbar). Liegt ein Tor-/Wegpunkt in einem Gebäude, wird ein Durchgang (Tunnel mit Boden/Wänden/Decke) durch das
## Gebäude geschnitten. Sichtbares je Material zusammengefasst, Kollision als ein Trimesh je Bereich.
## Castle buildings from the map building data; optional gate passages cut through buildings.

const MeshBatch := preload("res://src/maps/castle/castle_mesh.gd")
const LayoutScript := preload("res://src/maps/castle/castle_layout.gd")
const PASS_HALF := 2.2      # halbe Durchgangsbreite [m]
const PASS_HEIGHT := 3.6    # lichte Höhe über dem höheren Ende [m]

var footprints: Array[PackedVector2Array] = []
var passages: Array = []      # {center: Vector2, dir: Vector2, t0, t1, h0, h1, building}
var count := 0


static func fp_of(b: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in b.footprint:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


## Triangulierung eines ebenen Polygons → Liste von Dreiecken [a, b, c]
static func _tris(p: PackedVector3Array, n: Vector3) -> Array:
	var out: Array = []
	if p.size() < 3:
		return out
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var p2 := PackedVector2Array()
	for q in p:
		p2.append(Vector2(q.dot(u), q.dot(v)))
	var idx := Geometry2D.triangulate_polygon(p2)
	if idx.is_empty():
		for i in range(1, p.size() - 1):
			out.append([p[0], p[i], p[i + 1]])
	else:
		for i in range(0, idx.size(), 3):
			out.append([p[idx[i]], p[idx[i + 1]], p[idx[i + 2]]])
	return out


static func _clip(poly: PackedVector3Array, pl: Plane) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var da := pl.distance_to(a)
		var db := pl.distance_to(b)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


static func _half(n: Vector3, c3: Vector3, k: float) -> Plane:
	# behält n·(p − c3) ≥ k
	return Plane(n, n.dot(c3) + k)


var _lb: LevelBuilder
var helmets: Array = []        # {pos: Vector3 (Traufmitte), width, height, onion: bool} – Turmhelme statt Daten-Kegeldach
var onion_id := ""             # Gebäude-ID, das den Zwiebelhelm bekommt (Uhrturm, falls plausibel)
var helmets_recentered := 0    # Helme, deren Daten-Schwerpunkt außerhalb des Grundrisses lag
var stats := {"facade": {}, "roof": {}}


func _has(key: String) -> bool:
	return _lb != null and _lb._mats.has(key)


static func is_tower(b: Dictionary) -> bool:
	var rt := String(b.get("roof_type", ""))
	var area := float(b.get("footprint_area_m2", 0.0))
	return rt in ["cone", "pyramid", "tower"] or (area < 160.0 and float(b.ridge_y) - float(b.ground_y) > 2.2 * sqrt(maxf(area, 1.0)))


## Fassadenart (Burgfassaden-Pack): Mauern/Bauwerke = Stützmauer, Türme = Tuff mit Scharten, Kapellen = gotisch,
## sonst Kalkputz nach Geschosszahl (4 m je Geschoss, Traufe − Fuß). Ohne Pack-Texturen: bisherige Materialien.
func _wall_material(b: Dictionary) -> String:
	var kind := String(b.get("kind", ""))
	if kind == "wall" or kind == "bridge" or kind == "structure":
		return "f_retain" if _has("f_retain") else "c_wall"
	if is_tower(b):
		return "f_tuff" if _has("f_tuff") else "c_stone"
	var label = b.get("label_local")
	if String(b.id).contains("kapelle") or (label is String and (label as String).to_lower().contains("kapelle")):
		if _has("f_gothic"):
			return "f_gothic"
	var storeys := clampi(roundi((float(b.eave_y) - float(b.ground_y)) / 4.0), 1, 4)
	if _has("f_kalk%d" % storeys):
		return "f_kalk%d" % storeys
	return "c_plaster" if hash(String(b.id)) % 3 != 0 else "c_plaster2"


func _roof_material(b: Dictionary) -> String:
	var rt := String(b.get("roof_type", ""))
	if rt == "flat":
		return "c_wall"
	var k: String = LayoutScript.ROOF_MATS[hash(String(b.id)) % LayoutScript.ROOF_MATS.size()]
	if _has(k):
		return k
	return "c_roof" if hash(String(b.id)) % 2 == 0 else "c_roof2"


## Wand-UV je 4-m-Geschoss: u waagerecht ab der linken Wandkante, v von der Gebäudefußhöhe aufwärts
static func wall_uv(n: Vector3, p: PackedVector3Array, ground: float, mat: String) -> Array:
	var sz: Vector2 = LayoutScript.FACADE_SIZE.get(mat, Vector2.ZERO)
	if sz == Vector2.ZERO:
		return []
	var u := Vector3(n.z, 0, -n.x)
	u = u.normalized() if u.length() > 0.05 else Vector3.RIGHT
	var umin := INF
	for q in p:
		umin = minf(umin, q.dot(u))
	return [u, Vector3.UP, 1.0 / sz.x, -1.0 / sz.y, -umin / sz.x, 1.0 + ground / sz.y]


## Durchgang suchen: Torpunkt g in/≤ 3 m am Grundriss, Achse dir. Ergebnis {t0, t1} entlang dir (relativ zu g):
## Innenintervall an g bzw. das nächste, mit Nachbarintervallen zusammengefasst, wenn die Lücke < 4 m ist
## (Nischen/Vorsprünge des Grundrisses dürfen den Durchgang nicht wieder schließen).
static func passage_interval(fp: PackedVector2Array, g: Vector2, dir: Vector2) -> Dictionary:
	if dist_to_poly(g, fp) > 3.0:
		return {}
	var ts: Array[float] = []
	var far := 200.0
	var a := g - dir * far
	var b := g + dir * far
	for i in fp.size():
		var hit = Geometry2D.segment_intersects_segment(a, b, fp[i], fp[(i + 1) % fp.size()])
		if hit != null:
			ts.append((hit as Vector2 - g).dot(dir))
	ts.sort()
	if ts.size() < 2:
		return {}
	var iv: Array = []
	for k in range(0, ts.size() - 1, 2):
		iv.append([ts[k], ts[k + 1]])
	var bi := -1
	var best_d := INF
	for k in iv.size():
		var d := 0.0 if (iv[k][0] <= 0.0 and iv[k][1] >= 0.0) else minf(absf(iv[k][0]), absf(iv[k][1]))
		if d < best_d:
			best_d = d
			bi = k
	var lo: int = bi
	var hi: int = bi
	while lo > 0 and float(iv[lo][0]) - float(iv[lo - 1][1]) < 4.0:
		lo -= 1
	while hi < iv.size() - 1 and float(iv[hi + 1][0]) - float(iv[hi][1]) < 4.0:
		hi += 1
	var r := {"t0": float(iv[lo][0]), "t1": float(iv[hi][1])}
	if r.t1 - r.t0 > 70.0:
		return {}
	return r


var _h_fn: Callable


var ids: Array[String] = []        # parallel zu footprints
var split_parts := {}              # Gebäude-ID → {Teilname: Anzahl Flächen} (aufgeteilte Großblöcke)
var _split := {}                   # Gebäude-ID → Array [Teilname, Vector2 Planpunkt]


## Großen zusammengefassten Block nach Planpunkten in benannte Teilgebäude aufteilen (je Fläche nächster Planpunkt;
## eigene Fassaden-/Dachmaterialien je Teil). seeds: Array [Name, Vector2].
func split_building(id: String, seeds: Array) -> void:
	_split[id] = seeds


func _seed_entry(id: String, p: Vector2) -> Array:
	var best: Array = []
	var bd := INF
	for s in _split[id]:
		var d := p.distance_to(s[1])
		if d < bd:
			bd = d
			best = s
	return best


## Dach-UV: u waagerecht entlang der Traufe, v die Neigung hinab (Meter × Maßstab)
static func roof_uv(n: Vector3) -> Array:
	var u := Vector3(n.z, 0, -n.x)
	u = u.normalized() if u.length() > 0.05 else Vector3.RIGHT
	return [u, n.cross(u).normalized(), 0.4]


## gate_points: Vector2 (Achse aus dir_fn) oder [Vector2, Vector2 Achse].
## h_fn(Vector2) -> float: Bodenhöhe an den Durchgangsenden (Brückendeck oder Gelände)
func build(m: Node, list: Array, terrain, gate_points: Array, dir_fn: Callable, play_rect: Rect2, h_fn := Callable()) -> void:
	_h_fn = h_fn if h_fn.is_valid() else func(p: Vector2): return terrain.height(p.x, p.y)
	_lb = m.lb
	var inside := MeshBatch.new()
	var outside := MeshBatch.new()
	for b in list:
		if String(b.get("kind", "")) == "bridge":
			continue   # Gräben überbrückt castle.gd entlang des Hauptwegs (Deck), Daten-Brückenblöcke entfallen
		var fp := fp_of(b)
		if fp.size() < 3:
			continue
		var in_play := play_rect.has_point(Vector2(float(b.centroid[0]), float(b.centroid[1])))
		var mb: MeshBatch = inside if in_play else outside
		footprints.append(fp)
		ids.append(String(b.id))
		count += 1
		var mine: Array = []        # Durchgänge dieses Gebäudes (mehrere möglich)
		var pieces: Array = []      # je Durchgang eine Liste konvexer Teilbereiche
		if in_play:
			for ge in gate_points:
				var g: Vector2 = ge[0] if ge is Array else ge
				var dir: Vector2 = ge[1] if ge is Array else dir_fn.call(g)
				var r := passage_interval(fp, g, dir)
				if not r.is_empty():
					r.center = g
					r.dir = dir
					r = _make_passage(m, b, r, terrain, mb)
					mine.append(r)
					pieces.append(r.pieces)
					passages.append(r)
			_emit_passage_walls(mine, mb)
		var wm := _wall_material(b)
		var rm := _roof_material(b)
		var ground := float(b.ground_y)
		var split: bool = _split.has(String(b.id))
		if split:
			split_parts[String(b.id)] = {}
		# kleine Türme mit Kegel-/Zeltdach: Turmhelm aus dem Pack statt Daten-Dachfläche (Dach bleibt als Kollision)
		var helm := false
		if not split and String(b.get("roof_type", "")) in ["cone", "pyramid"] and float(b.get("footprint_area_m2", 0.0)) < 200.0 \
				and float(b.ridge_y) - float(b.eave_y) > 1.5:
			var r := Rect2(fp[0], Vector2.ZERO)
			for q2 in fp:
				r = r.expand(q2)
			# Schwerpunkt aus den Daten liegt nicht immer im Grundriss (Uhrturm: 21 m davor) → dann Grundrissmitte
			var cpos := Vector2(float(b.centroid[0]), float(b.centroid[1]))
			if not Geometry2D.is_point_in_polygon(cpos, fp):
				cpos = r.get_center()
				helmets_recentered += 1
			helmets.append({"pos": Vector3(cpos.x, float(b.eave_y), cpos.y),
				"width": maxf(r.size.x, r.size.y), "height": float(b.ridge_y) - float(b.eave_y), "onion": String(b.id) == onion_id,
				"fp": fp, "ground": ground, "area": float(b.get("footprint_area_m2", 0.0))})
			helm = true
		for kind in ["wall_polygons", "roof_polygons"]:
			for poly in b.get(kind, []):
				var p := PackedVector3Array()
				for q in poly:
					p.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
				var n := MeshBatch.newell(p)
				if n == Vector3.ZERO:
					continue
				var is_roof: bool = kind == "roof_polygons" and absf(n.y) > 0.25
				if is_roof or absf(n.y) > 0.85:
					if n.y < 0.0:
						n = -n
				else:
					var c := Vector3.ZERO
					for q in p:
						c += q
					c /= p.size()
					var hz := Vector2(n.x, n.z).normalized()
					if Geometry2D.is_point_in_polygon(Vector2(c.x, c.z) + hz * 0.3, fp):
						n = -n
				var mat := rm if is_roof else wm
				if split:
					# Teilgebäude je Planpunkt: Türme/Tore/Mauern Tuff mit Scharten, Kapelle gotisch, sonst Palasfenster;
					# Dachziegelsorte je Teil
					var cc := Vector3.ZERO
					for q in p:
						cc += q
					cc /= p.size()
					var sd: Array = _seed_entry(String(b.id), Vector2(cc.x, cc.z))
					var part: String = sd[0]
					var hv := hash(part)
					if is_roof:
						mat = LayoutScript.ROOF_MATS[hv % 4] if _has("r_bib1") else (["c_roof", "c_roof2"][hv % 2])
					elif _has("f_palas"):
						var pk: String = sd[2] if sd.size() > 2 else "building"
						# Gestaltung (Innerer Hof): Hauptburg = grober Bruch-/Tuffstein mit kleinen Fenstern, keine
						# regelmäßigen Palastfenster → Tuffwand mit Kleinfenstern (Rückfall Palasfenster)
						var plain := "f_tuffwin" if _has("f_tuffwin") else "f_palas"
						mat = "f_tuff" if pk in ["tower", "gate", "wall"] else ("f_gothic" if sd.size() > 3 and sd[3] else plain)
					else:
						mat = ["c_plaster", "c_plaster2", "c_stone"][hv % 3]
					split_parts[String(b.id)][part] = int(split_parts[String(b.id)].get(part, 0)) + 1
				var uvb: Array = []
				if is_roof and (mat.begins_with("r_") or mat.begins_with("c_roof")):
					uvb = roof_uv(n)
					if mat.begins_with("r_"):
						uvb[2] = 0.25
				elif mat.begins_with("f_"):
					uvb = wall_uv(n, p, ground, mat)
				if not is_roof and not uvb.is_empty():
					stats.facade[mat] = int(stats.facade.get(mat, 0)) + 1
				elif is_roof:
					stats.roof[mat] = int(stats.roof.get(mat, 0)) + 1
				var vis: bool = not (helm and kind == "roof_polygons")
				for t in _tris(p, n):
					_emit(mb, t, n, mat, pieces, uvb, vis)
		# Sockel unter dem Grundriss (verdeckt Geländefugen am Hang)
		for i in fp.size():
			var a := fp[i]
			var e := fp[(i + 1) % fp.size()]
			if a.distance_to(e) < 0.05:
				continue
			var mid := (a + e) * 0.5
			var out2 := Vector2(e.y - a.y, a.x - e.x).normalized()
			if Geometry2D.is_point_in_polygon(mid + out2 * 0.2, fp):
				out2 = -out2
			var n3 := Vector3(out2.x, 0, out2.y)
			var top := ground + 0.05
			var bot := minf(ground, minf(terrain.height(a.x, a.y), terrain.height(e.x, e.y))) - 2.5
			var q := PackedVector3Array([Vector3(a.x, bot, a.y), Vector3(e.x, bot, e.y), Vector3(e.x, top, e.y), Vector3(a.x, top, a.y)])
			var sm := wm
			if wm.begins_with("f_"):
				sm = "c_retain" if _has("c_retain") else "c_stone"   # Sockel triplanar (Fassaden-UV gilt nur für Wände)
			for t in _tris(q, n3):
				_emit(mb, t, n3, sm, pieces)
		if in_play:
			_nav_cut(m, b, fp, mine)
	var n1: Node3D = inside.commit(m.static_root, "CastleBuildings", m.lb, true)
	n1.add_to_group("castle_buildings")
	var n2: Node3D = outside.commit(m.dynamic_root, "CastleBuildingsFar", m.lb, true)
	n2.add_to_group("castle_buildings")


func _emit(mb: MeshBatch, t: Array, n: Vector3, mat: String, pieces: Array, uvb: Array = [], vis := true) -> void:
	if pieces.is_empty():
		mb.tri(t[0], t[1], t[2], n, mat, vis, true, uvb)
		return
	# nacheinander je Durchgang: nur die Teile außerhalb des Durchgangsquaders behalten
	var polys: Array = [PackedVector3Array([t[0], t[1], t[2]])]
	for pass_pieces in pieces:
		var next: Array = []
		for src in polys:
			for planes in pass_pieces:
				var poly: PackedVector3Array = src
				for pl in planes:
					poly = _clip(poly, pl)
					if poly.size() < 3:
						break
				if poly.size() >= 3:
					next.append(poly)
		polys = next
	for poly in polys:
		for i in range(1, poly.size() - 1):
			if (poly[i] - poly[0]).cross(poly[i + 1] - poly[0]).length() > 1e-5:
				mb.tri(poly[0], poly[i], poly[i + 1], n, mat, vis, true, uvb)


## Tunnel: Schnittbereiche (5 konvexe Teile außerhalb des Durchgangsquaders), Seitenwände, Decke, Boden
func _make_passage(_m: Node, b: Dictionary, pas: Dictionary, terrain, mb: MeshBatch) -> Dictionary:
	var c: Vector2 = pas.center
	var d: Vector2 = pas.dir
	var s := Vector2(-d.y, d.x)
	var t0: float = pas.t0 - 0.3
	var t1: float = pas.t1 + 0.3
	var pa := c + d * (t0 - 1.5)
	var pb := c + d * (t1 + 1.5)
	var h0: float = _h_fn.call(pa)
	var h1: float = _h_fn.call(pb)
	# Bodenprofil: linear zwischen den Enden, nie unter dem Gelände im Gebäude (Gelände würde sonst durchstoßen)
	var steps := maxi(int((t1 - t0) / 2.0), 1)
	var ys: Array[float] = []
	for k in steps + 1:
		var tk := lerpf(t0, t1, float(k) / steps)
		var y := lerpf(h0, h1, float(k) / steps)
		for w in [-PASS_HALF, -PASS_HALF * 0.5, 0.0, PASS_HALF * 0.5, PASS_HALF]:
			var q: Vector2 = c + d * tk + s * w
			y = maxf(y, terrain.height(q.x, q.y) + 0.03)
		ys.append(y)
	var top := maxf(maxf(h0, h1) + PASS_HEIGHT, (ys.max() as float) + 2.8)
	var open := float(b.eave_y) < top + 0.4
	var cut_top := float(b.ridge_y) + 50.0 if open else top
	var c3 := Vector3(c.x, 0, c.y)
	var D := Vector3(d.x, 0, d.y)
	var S := Vector3(s.x, 0, s.y)
	var hw := PASS_HALF
	pas.pieces = [
		[_half(-S, c3, hw)],
		[_half(S, c3, hw)],
		[_half(S, c3, -hw), _half(-S, c3, -hw), _half(-D, c3, -t0)],
		[_half(S, c3, -hw), _half(-S, c3, -hw), _half(D, c3, t1)],
		[_half(S, c3, -hw), _half(-S, c3, -hw), _half(D, c3, t0), _half(-D, c3, -t1), Plane(Vector3.UP, cut_top)],
	]
	pas.t0 = t0
	pas.t1 = t1
	pas.h0 = h0
	pas.h1 = h1
	pas.building = String(b.id)
	pas.open = open
	var liner_top := top if not open else maxf(float(b.eave_y), (ys.max() as float) + 2.5)
	pas.floor = ys
	pas.walls = []
	# Anlauframpen vor beiden Enden (Boden im Durchgang liegt über dem Gelände an der Hauswand)
	for e in [[t0, ys[0], t0 - 1.8, h0], [t1, ys[steps], t1 + 1.8, h1]]:
		var pi: Vector2 = c + d * float(e[0])
		var po: Vector2 = c + d * float(e[2])
		var yi: float = e[1]
		var yo: float = minf(float(e[3]), yi)
		if yi - yo < 0.05:
			continue
		var ri1 := pi - s * hw
		var ri2 := pi + s * hw
		var ro1 := po - s * hw
		var ro2 := po + s * hw
		mb.quad(Vector3(ri1.x, yi, ri1.y), Vector3(ri2.x, yi, ri2.y), Vector3(ro2.x, yo - 0.05, ro2.y), Vector3(ro1.x, yo - 0.05, ro1.y), Vector3.UP, "c_paving")
	for k in steps:
		var ta := lerpf(t0, t1, float(k) / steps)
		var tb := lerpf(t0, t1, float(k + 1) / steps)
		var ya: float = ys[k]
		var yb: float = ys[k + 1]
		var la := c + d * ta
		var lb2 := c + d * tb
		# Boden
		var fa1 := la - s * hw
		var fa2 := la + s * hw
		var fb1 := lb2 - s * hw
		var fb2 := lb2 + s * hw
		mb.quad(Vector3(fa1.x, ya, fa1.y), Vector3(fa2.x, ya, fa2.y), Vector3(fb2.x, yb, fb2.y), Vector3(fb1.x, yb, fb1.y), Vector3.UP, "c_paving")
		# Seitenwände (zur Mitte gerichtet): erst nach allen Durchgängen des Gebäudes (_emit_passage_walls), damit sich
		# kreuzende Durchgänge einander nicht zumauern
		for side in [-1.0, 1.0]:
			var wa: Vector2 = la + s * hw * side
			var wb: Vector2 = lb2 + s * hw * side
			pas.walls.append([wa, wb, ya, yb, Vector3(-s.x * side, 0, -s.y * side), liner_top])
		if not open:
			mb.quad(Vector3(fa1.x, top, fa1.y), Vector3(fa2.x, top, fa2.y), Vector3(fb2.x, top, fb2.y), Vector3(fb1.x, top, fb1.y), Vector3.DOWN, "c_stone")
	return pas


## Seitenwände der Durchgänge eines Gebäudes in 0,5-m-Stücken; Stücke im Lichtraum eines anderen Durchgangs desselben
## Gebäudes entfallen (Kreuzung zweier offener Durchgänge in der Hauptburg ließ sonst nur einen 0,6-m-Spalt)
func _emit_passage_walls(mine: Array, mb: MeshBatch) -> void:
	for pas in mine:
		for w in pas.walls:
			var wa: Vector2 = w[0]
			var wb: Vector2 = w[1]
			var n := maxi(int(ceil(wa.distance_to(wb) / 0.5)), 1)
			for k in n:
				var f0 := float(k) / n
				var f1 := float(k + 1) / n
				var mid := wa.lerp(wb, (f0 + f1) * 0.5)
				var inside_other := false
				for o in mine:
					if o == pas:
						continue
					var l: Vector2 = mid - (o.center as Vector2)
					var od: Vector2 = o.dir
					var tt := l.dot(od)
					if tt > float(o.t0) - 0.1 and tt < float(o.t1) + 0.1 and absf(l.dot(od.orthogonal())) < PASS_HALF - 0.05:
						inside_other = true
						break
				if inside_other:
					continue
				var p0 := wa.lerp(wb, f0)
				var p1 := wa.lerp(wb, f1)
				var y0 := lerpf(float(w[2]), float(w[3]), f0)
				var y1 := lerpf(float(w[2]), float(w[3]), f1)
				var top: float = w[5]
				mb.quad(Vector3(p0.x, y0 - 1.0, p0.y), Vector3(p1.x, y1 - 1.0, p1.y), Vector3(p1.x, top, p1.y), Vector3(p0.x, top, p0.y), w[4], "c_stone")


## Navmesh: Grundriss (ohne Durchgang) per Hindernis ausschneiden – das Gelände läuft unter dem Gebäude durch
func _nav_cut(m: Node, b: Dictionary, fp: PackedVector2Array, list: Array) -> void:
	var polys: Array = [fp]
	var cw := Geometry2D.is_polygon_clockwise(fp)
	for pas in list:
		var c: Vector2 = pas.center
		var d: Vector2 = pas.dir
		var s := Vector2(-d.y, d.x)
		var w := PASS_HALF + 0.1
		var rect := PackedVector2Array([c + d * (pas.t0 - 3.0) - s * w, c + d * (pas.t1 + 3.0) - s * w,
			c + d * (pas.t1 + 3.0) + s * w, c + d * (pas.t0 - 3.0) + s * w])
		var next: Array = []
		for src in polys:
			for q in Geometry2D.clip_polygons(src, rect):
				if Geometry2D.is_polygon_clockwise(q) == cw:
					next.append(q)
		polys = next
	var base := float(b.ground_y) - 3.0
	for q in polys:
		var ob := NavigationObstacle3D.new()
		ob.name = String(b.id) + "_NavCut"
		ob.avoidance_enabled = false
		ob.affect_navigation_mesh = true
		ob.height = float(b.ridge_y) - base + 3.0
		var c0 := Vector2.ZERO
		for p in q:
			c0 += p
		c0 /= q.size()
		var verts := PackedVector3Array()
		for p in q:
			verts.append(Vector3(p.x - c0.x, 0, p.y - c0.y))
		ob.vertices = verts
		m.static_root.add_child(ob)
		ob.position = Vector3(c0.x, base, c0.y)
