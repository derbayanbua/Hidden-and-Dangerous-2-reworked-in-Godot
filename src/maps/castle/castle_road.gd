extends RefCounted
## Castle: Hauptweg als eigene Bänder über dem Gelände (nur Darstellung, ohne Kollision, unter dynamic_root → nicht im
## Navmesh). Vorher wurde das Wegmaterial je 2-m-Geländezelle vergeben (treppige Ränder). Jetzt:
## - Wegachse mit abgerundeten Knicken (Chaikin, Schnitt ≤ 4 m je Ecke → Abweichung vom Datenweg < 0,6 m)
## - Abgleich 3D-Rundgang: innere Vorhöfe Flusskieselpflaster ±2,4 m mit zwei Reihen Randsteinen, äußere Vorhöfe heller
##   Sandweg ±2,6 m mit einer Reihe; außen ein schmaler Sandsaum, der über 0,85 m weich ins Gras ausläuft
##   (Alpha-Hash über Vertexfarbe, Texturen weiter weltbezogen triplanar → nahtlos zum Gelände)
## Unterbrochen über Gräben (Brücken), in Gebäuden/Durchgängen und im ganz gepflasterten Hof F.
## Castle: main road as smoothed ribbons (cobbles, kerbs, gravel shoulder with soft edge), visual only.

const STEP := 1.0                     # Abtastung entlang der Achse [m]
const COBBLE_HALF := 2.4             # Kieselpflaster ±2,4 m
const SAND_HALF := 2.6                # Sandweg ±2,6 m
const KERB_W := 0.22                  # eine Reihe Granit-Randsteine
const PEBBLE_SECTIONS := ["D", "E"]   # innere Vorhöfe gepflastert (Rundgang 2. Vorhof; E Annahme), A–C Sandweg
const LIFT_COBBLE := 0.055
const LIFT_KERB := 0.075
const LIFT_GRAVEL := 0.035

var road := PackedVector2Array()
var stats := {"samples": 0, "runs": 0, "length_m": 0.0, "max_dev": 0.0}


## Knicke runden: Chaikin mit begrenztem Eckschnitt (Endpunkte bleiben)
static func smooth(pts: PackedVector2Array, iterations := 3, max_cut := 4.0) -> PackedVector2Array:
	var cur := pts
	for _it in iterations:
		if cur.size() < 3:
			return cur
		var out := PackedVector2Array([cur[0]])
		for i in range(1, cur.size() - 1):
			var a := cur[i - 1]
			var b := cur[i]
			var c := cur[i + 1]
			var ca := minf(a.distance_to(b) * 0.25, max_cut)
			var cc := minf(b.distance_to(c) * 0.25, max_cut)
			out.append(b + (a - b).normalized() * ca)
			out.append(b + (c - b).normalized() * cc)
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


## Gleichmäßig abtasten: [Punkt, Tangente]
static func resample(pts: PackedVector2Array, step: float) -> Array:
	var out: Array = []
	if pts.size() < 2:
		return out
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		if L < 1e-4:
			continue
		var t := acc
		while t < L:
			out.append(a.lerp(b, t / L))
			t += step
		acc = t - L
	out.append(pts[pts.size() - 1])
	var res: Array = []
	for k in out.size():
		var p: Vector2 = out[k]
		var d: Vector2 = (out[mini(k + 1, out.size() - 1)] - out[maxi(k - 1, 0)])
		res.append([p, d.normalized() if d.length() > 1e-5 else Vector2(0, 1)])
	return res


var _used := {}                       # SurfaceTool → Dreiecke (leere Werkzeuge nicht übernehmen)


func _gravel_material(r) -> Material:
	var base: Material = r._lb_mats.get("c_sand", r._lb_mats.get("c_gravel"))
	if base == null:
		return null
	var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	m.alpha_hash_scale = 1.0
	return m


func build(r, m: Node) -> void:
	if r.path.size() < 2 or not r._lb_mats.has("c_cobble"):
		return
	road = smooth(r.path)
	var samples := resample(road, STEP)
	# Abweichung der Darstellung vom Datenweg (für Bericht/Test)
	for e in samples:
		stats.max_dev = maxf(stats.max_dev, r.path_info(e[0])[0])
	var ok: Array = []
	for e in samples:
		var p: Vector2 = e[0]
		var good: bool = Geometry2D.is_point_in_polygon(p, r.boundary) and r.section_of(p) not in ["F", ""] \
			and not r.in_building(p, 0.6) and not r._in_ditch(p) and not r.near_passage(p, 1.0)
		ok.append(good)
	var peb := SurfaceTool.new()
	peb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var snd := SurfaceTool.new()
	snd.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb := SurfaceTool.new()
	kerb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grav := SurfaceTool.new()
	grav.begin(Mesh.PRIMITIVE_TRIANGLES)
	var in_run := false
	var pebble_ok: bool = r._lb_mats.has("c_pebble")
	var sand_ok: bool = r._lb_mats.has("c_sand")
	for k in samples.size() - 1:
		if not (ok[k] and ok[k + 1]):
			in_run = false
			continue
		if not in_run:
			stats.runs += 1
			in_run = true
		stats.samples += 1
		stats.length_m += (samples[k][0] as Vector2).distance_to(samples[k + 1][0])
		var a: Array = samples[k]
		var b: Array = samples[k + 1]
		# 3D-Rundgang: innere Höfe (D, E) Flusskieselpflaster mit zwei Reihen Granit-Randsteinen,
		# äußere Höfe (A, B, C) heller Sandweg mit einer Reihe Randsteinen; beidseits schmaler, auslaufender Sandsaum
		var pebble: bool = String(r.section_of(a[0])) in PEBBLE_SECTIONS
		var half := COBBLE_HALF if pebble else SAND_HALF
		var kw := KERB_W * (2.0 if pebble else 1.0)
		var center: SurfaceTool = peb if pebble else snd
		var offs: Array = []
		var n := int(ceil(2.0 * half / 0.8))
		for i in n + 1:
			offs.append(-half + 2.0 * half * float(i) / float(n))
		_strip(r, center, a, b, offs, LIFT_COBBLE, [])
		stats[("pebble_m" if pebble else "sand_m")] = float(stats.get("pebble_m" if pebble else "sand_m", 0.0)) \
			+ (a[0] as Vector2).distance_to(b[0])
		for s in [-1.0, 1.0]:
			_strip(r, kerb, a, b, [s * half, s * (half + kw)], LIFT_KERB, [])
			var g0 := half + kw - 0.1
			_strip(r, grav, a, b, [s * g0, s * (g0 + 0.25), s * (g0 + 0.55), s * (g0 + 0.85)], LIFT_GRAVEL,
				[0.85, 0.7, 0.3, 0.0])
	if stats.samples == 0:
		return
	var holder := Node3D.new()
	holder.name = "CastleRoad"
	m.dynamic_root.add_child(holder)
	var cob_m: Material = r._lb_mats.get("c_cobble")
	for e in [[peb, r._lb_mats.get("c_pebble") if pebble_ok else cob_m, "Pebble"],
			[snd, r._lb_mats.get("c_sand") if sand_ok else r._lb_mats.get("c_gravel", cob_m), "Sand"],
			[kerb, cob_m, "Kerb"], [grav, _gravel_material(r), "Fringe"]]:
		var st: SurfaceTool = e[0]
		if e[1] == null or int(_used.get(st.get_instance_id(), 0)) == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = e[2]
		mi.mesh = st.commit()
		mi.material_override = e[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


## Querstreifen zwischen zwei Achsenpunkten; offs = Querabstände (links → rechts), alpha je Abstand (leer = 1)
func _strip(r, st: SurfaceTool, a: Array, b: Array, offs: Array, lift: float, alpha: Array) -> void:
	var rows: Array = []
	for e in [a, b]:
		var p: Vector2 = e[0]
		var n: Vector2 = (e[1] as Vector2).orthogonal()
		var row: Array = []
		for o in offs:
			var q: Vector2 = p + n * float(o)
			row.append(Vector3(q.x, r.terrain.height(q.x, q.y) + lift, q.y))
		rows.append(row)
	_used[st.get_instance_id()] = int(_used.get(st.get_instance_id(), 0)) + 2 * (offs.size() - 1)
	for i in offs.size() - 1:
		var quad := [rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]]
		var al := [1.0, 1.0, 1.0, 1.0]
		if not alpha.is_empty():
			al = [alpha[i], alpha[i + 1], alpha[i + 1], alpha[i]]
		for t in [[0, 1, 2], [0, 2, 3]]:
			var p0: Vector3 = quad[t[0]]
			var p1: Vector3 = quad[t[1]]
			var p2: Vector3 = quad[t[2]]
			var nn := (p1 - p0).cross(p2 - p0)
			var idx: Array = t
			if nn.y < 0.0:
				idx = [t[0], t[2], t[1]]
			# Godot: Vorderseite im Uhrzeigersinn von oben → (b−a)×(c−a) zeigt nach unten
			idx = [idx[0], idx[2], idx[1]]
			for j in idx:
				var v: Vector3 = quad[j]
				st.set_color(Color(1, 1, 1, float(al[j])))
				st.set_normal(_normal(r, v))
				st.add_vertex(v)


func _normal(r, v: Vector3) -> Vector3:
	var t = r.terrain
	var dx: float = t.height(v.x + 0.7, v.z) - t.height(v.x - 0.7, v.z)
	var dz: float = t.height(v.x, v.z + 0.7) - t.height(v.x, v.z - 0.7)
	return Vector3(-dx, 1.4, -dz).normalized()
