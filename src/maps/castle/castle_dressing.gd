extends RefCounted
## Castle (echte Burg): Hofausstattung nach dem Abgleich mit Referenzansichten der Höfe (0.12.2).
## - Laubbäume in den Rasenhöfen (Torhof E als Park, je 1–4 in A–D) und ein Hausbaum im Hof der Hauptburg F
## - Hecken entlang des Hauptwegs (C, B, A), Straßenlaternen (A, B, C), Holzbänke (E, F, B)
## - Hauptburg: überdachte Holzaußentreppen an Hofwänden (begehbar, Podest auf 2,7 m), Kanonenkugelpyramide
## - Holzzaun an der Grabenkante (Halsgraben) außerhalb von Wegen und Gebäuden
## Alles deterministisch (gleiche Geometrie auf allen Rechnern). Bäume: EZ-Tree-Vorlagen (Bavaria), sichtbar unter
## dynamic_root (nicht in der Navmesh-Quelle), Stamm als Kollisionskiste im Bausatz. Fehlende Modelle entfallen.
## Castle courtyard dressing after comparison with reference views (trees, hedges, lanterns, benches, covered
## wooden stairs, cannonballs, ditch fence).

const EzTree := preload("res://src/maps/bavaria/eztree.gd")
const MeshBatch := preload("res://src/maps/castle/castle_mesh.gd")
const LibraryModels := preload("res://src/maps/bavaria/library_models.gd")

## Bäume je Hof: [Anzahl, Arten (Kontext für EzTree.pick-ähnliche Wahl), Mindestabstand untereinander]
const TREES := {"E": [7, ["beech", "oak"], 13.0], "A": [4, ["beech", "oak"], 14.0], "B": [2, ["beech"], 14.0],
	"C": [3, ["oak", "beech"], 14.0], "D": [2, ["beech"], 16.0], "F": [1, ["beech"], 0.0]}
## Hecken je Hof: höchstens so viele 4-m-Stücke (Referenz: niedrige Hecken säumen den Weg in C und B, in A einzelne)
const HEDGE_SECTIONS := {"C": 22, "B": 16, "A": 8}
const LANTERN_SECTIONS := ["A", "B", "C"]
const BENCHES := {"E": 4, "F": 2, "B": 2}
## Überdachte Außentreppe: Lauf entlang der Wand, Podest oben an der Wand
const STAIR_RISE := 2.7
const STAIR_STEPS := 15
const STAIR_RUN := 0.3
const STAIR_W := 1.2
const LANDING := Vector2(2.0, 1.6)      # Länge entlang der Wand, Tiefe

var stats := {"trees": 0, "hedges": 0, "lanterns": 0, "benches": 0, "stairs": 0, "cannonballs": 0, "fence_m": 0.0}
var trees: Array = []          # Vector3 Stammfuß
var stairs: Array = []         # {foot: Vector3, top: Vector3}
var fence: Array = []          # [Vector3, Vector3] Zaunabschnitte
var stair_reject := {}         # Ablehnungsgründe der Außentreppen-Plätze (Bericht)


static func _h(p: Vector2, salt: int) -> float:
	var v := absf(sin(p.x * 12.9898 + p.y * 78.233 + salt * 37.719) * 43758.5453)
	return v - floorf(v)


func build(r, m: Node) -> void:
	_trees(r, m)
	_stairs(r, m)
	_cannonballs(r, m)
	_hedges(r, m)
	_lanterns(r)
	_benches(r)
	_ditch_fence(r, m)
	print("CASTLE_DRESSING ", stats, " Treppenplätze abgelehnt ", stair_reject)


# ---------------------------------------------------------------- Bäume

func _trees(r, m: Node) -> void:
	if not EzTree.enabled():
		return
	var holder := Node3D.new()
	holder.name = "CastleCourtTrees"
	m.dynamic_root.add_child(holder)
	var templates := {}
	for sec in TREES:
		var spec: Array = TREES[sec]
		var cands: Array = r._candidates([sec], 3.0, 5.0)
		# Platz für eine Krone: Weg ≥ 6 m, Gebäude ≥ 5 m, Tore/Durchgänge ≥ 9 m, keine Sperrfläche in 4 m
		cands = cands.filter(func(q): return r.path_info(q)[0] > 6.0 and not r.in_building(q, 5.0) and not r.blocked(q, 4.0) \
			and not r.near_passage(q, 9.0) and not r.dividers.any(func(d): return (d.gate as Vector2).distance_to(q) < 12.0))
		if sec == "F":
			# Hausbaum: freiester Punkt (größter Abstand zu Gebäuden in 4 Richtungen)
			cands.sort_custom(func(a, b): return _clearance(r, a) > _clearance(r, b))
		else:
			cands.sort_custom(func(a, b): return _h(a, 3) < _h(b, 3))
		var placed: Array = []
		for q in cands:
			if placed.size() >= int(spec[0]):
				break
			if placed.any(func(o): return (o as Vector2).distance_to(q) < float(spec[2])):
				continue
			var sp: String = spec[1][int(_h(q, 7) * 997.0) % (spec[1] as Array).size()]
			var key := "ez_%s_l" % sp if _h(q, 11) > 0.35 or sec == "F" else "ez_%s_m" % sp
			if not templates.has(key):
				# flache Laubkarten (volle Stufe): die Volumen-Büschel erschienen hier als weiße Kartenflächen (Kontrollbild baumpark)
				var prev_clumps: int = EzTree._clumps
				EzTree._clumps = 0
				templates[key] = EzTree.load_template(key)
				EzTree._clumps = prev_clumps
			var tmpl: Node3D = templates[key]
			if tmpl == null:
				continue
			var y: float = r.terrain.height(q.x, q.y)
			var s := EzTree.model_scale(key, (1.05 if sec == "F" else 0.85) + 0.3 * _h(q, 13))
			var t: Node3D = tmpl.duplicate()
			holder.add_child(t)
			t.transform = Transform3D(Basis(Vector3.UP, _h(q, 17) * TAU).scaled(Vector3.ONE * s), Vector3(q.x, y - 0.1, q.y))
			# Stamm als Kollision (Kugeln/Bewegung), Krone ohne
			r.kit.col.box(Transform3D(Basis(), Vector3(q.x, y + 1.5, q.y)), Vector3(0.6, 3.0, 0.6), "c_wood", false, true)
			r._blocked.append([q, 2.2])
			placed.append(q)
			trees.append(Vector3(q.x, y, q.y))
			stats.trees += 1
	for k in templates:
		if templates[k] != null:
			(templates[k] as Node3D).free()


func _clearance(r, p: Vector2) -> float:
	var best := 0.0
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]:
		var s := 1.0
		while s < 20.0 and not r.in_building(p + d * s, 0.0) and Geometry2D.is_point_in_polygon(p + d * s, r.boundary):
			s += 1.0
		best += minf(s, 14.0)
	return best


# ---------------------------------------------------------------- Hecken, Laternen, Bänke entlang des Wegs

## Punkte entlang des Hauptwegs im Abschnitt sec alle step Meter: [Punkt, Richtung]
func _path_samples(r, sec: String, step: float) -> Array:
	var out: Array = []
	var acc := 0.0
	for i in r.path.size() - 1:
		var a: Vector2 = r.path[i]
		var b: Vector2 = r.path[i + 1]
		var L := a.distance_to(b)
		var d := (b - a) / maxf(L, 0.01)
		var t := step - acc
		while t < L:
			var p := a + d * t
			if r.section_of(p) == sec:
				out.append([p, d])
			t += step
		acc = fmod(acc + L, step)
	return out


func _side_ok(r, q: Vector2, clear: float) -> bool:
	return Geometry2D.is_point_in_polygon(q, r.boundary) and r.boundary_dist(q) > 2.0 and not r.in_building(q, clear) \
		and not r.blocked(q, clear) and not r.near_passage(q, 6.0) \
		and not r.dividers.any(func(dv): return (dv.gate as Vector2).distance_to(q) < 10.0) \
		and absf(r.terrain.height(q.x, q.y) - r.terrain.height(q.x + 1.5, q.y)) < 0.5 \
		and absf(r.terrain.height(q.x, q.y) - r.terrain.height(q.x, q.y + 1.5)) < 0.5


func _hedges(r, m: Node) -> void:
	# Sichtbar: Heckensträucher mit Laubkarten (Bibliothek, wie die Hecken der Testkarte Bavaria); der 4-m-Bausatzblock
	# (glatter grüner Körper) nur noch als Rückfall ohne Bibliotheksmodell
	# Sommerstrauch mit Laubkarten (Alpha-Maske, wie der dichte Randsaum der Testkarte); der Bibliotheks-Heckenstrauch ist
	# nur facettierte Vertexfarbe (Kontrollbild hof_c) und bleibt Rückfall
	var tmpl: Node3D = null
	if LibraryModels.enabled():
		tmpl = LibraryModels.load_model("strauch_sommer_2")
		if tmpl == null:
			tmpl = LibraryModels.load_model(LibraryModels.HEDGE.trim_prefix("lib:"))
	var box := AABB()
	if tmpl:
		var first := true
		for mi in tmpl.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D()
			var nd: Node = mi
			while nd != tmpl and nd != null:
				xf = (nd as Node3D).transform * xf
				nd = nd.get_parent()
			var bb: AABB = xf * (mi as MeshInstance3D).get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		if box.size.x < 0.05 or box.size.y < 0.05 or box.size.z < 0.05:
			tmpl.free()
			tmpl = null
	if tmpl == null and r.kit.model_aabb("hecke_sommer_4m").size.is_zero_approx():
		return
	var holder := Node3D.new()
	holder.name = "CastleHedges"
	m.dynamic_root.add_child(holder)
	for sec in HEDGE_SECTIONS:
		# Heckenreihen beidseits des Wegs, 4,2 m von der Wegmitte, je 3 Stücke, dann 4 m Lücke (Durchgänge);
		# abwechselnd links/rechts gefüllt, bis die Höchstzahl des Hofs erreicht ist
		var samples := _path_samples(r, sec, 4.0)
		var cap := int(HEDGE_SECTIONS[sec])
		var count := 0
		for side in [-1.0, 1.0]:
			var run := 0
			for k in samples.size():
				if count >= cap:
					break
				var p: Vector2 = samples[k][0]
				var d: Vector2 = samples[k][1]
				var q: Vector2 = p + d.orthogonal() * 4.2 * side
				if run >= 3:
					run = 0
					continue
				if r.path_info(q)[0] < 3.6 or not _side_ok(r, q, 1.5):
					run = 0
					continue
				var y: float = r.terrain.height(q.x, q.y)
				if tmpl:
					# zwei Sträucher je 4-m-Stück, Längsachse (lokal z) entlang des Wegs, Höhe 1,2–1,5 m
					var yaw := atan2(d.x, d.y)
					for part in 2:
						var c: Vector2 = q + d * (float(part) - 0.5) * 2.0
						var sc := Vector3(1.6 / box.size.x, (1.2 + 0.3 * _h(c, 5)) / box.size.y, 2.4 / box.size.z)
						var b := Basis(Vector3.UP, yaw + (PI if _h(c, 9) > 0.5 else 0.0)) * Basis.from_scale(sc)
						var off := Vector3(box.get_center().x, box.position.y, box.get_center().z)
						var t: Node3D = tmpl.duplicate()
						holder.add_child(t)
						t.transform = Transform3D(b, Vector3(c.x, r.terrain.height(c.x, c.y) - 0.06, c.y) - b * off)
					r.kit.col.box(Transform3D(Basis(Vector3.UP, -d.angle()), Vector3(q.x, y + 0.6, q.y)), Vector3(4.0, 1.2, 1.3),
						"c_wood", false, true)
				else:
					r.kit.prop("hecke_sommer_4m", Transform3D(Basis(Vector3.UP, -d.angle()), Vector3(q.x, y - 0.03, q.y)))
				r._blocked.append([q, 2.2])
				run += 1
				count += 1
				stats.hedges += 1
	if tmpl:
		tmpl.free()


func _lanterns(r) -> void:
	if r.kit.model_aabb("strassenlampe_guss").size.is_zero_approx():
		return
	for sec in LANTERN_SECTIONS:
		var samples := _path_samples(r, sec, 22.0)
		var k := 0
		for e in samples:
			var p: Vector2 = e[0]
			var d: Vector2 = e[1]
			var side := 1.0 if k % 2 == 0 else -1.0
			k += 1
			var q: Vector2 = p + d.orthogonal() * 3.1 * side
			if not _side_ok(r, q, 0.8):
				q = p - d.orthogonal() * 3.1 * side
				if not _side_ok(r, q, 0.8):
					continue
			var y: float = r.terrain.height(q.x, q.y)
			# Arm zum Weg: Modell-Ausleger zeigt nach +X (Hüllquader 1,54 × 4 × 0,86)
			var to_path := (p - q).normalized()
			r.kit.place("strassenlampe_guss", Transform3D(Basis(Vector3.UP, -to_path.angle()), Vector3(q.x, y - 0.05, q.y)))
			r.kit.col.box(Transform3D(Basis(), Vector3(q.x, y + 1.5, q.y)), Vector3(0.25, 3.0, 0.25), "c_wood", false, true)
			r._blocked.append([q, 1.2])
			stats.lanterns += 1


func _benches(r) -> void:
	if r.kit.model_aabb("holzbank_3d").size.is_zero_approx():
		return
	for sec in BENCHES:
		var samples := _path_samples(r, sec, 9.0)
		samples.sort_custom(func(a, b): return _h(a[0], 23) < _h(b[0], 23))
		var n := 0
		for e in samples:
			if n >= int(BENCHES[sec]):
				break
			var p: Vector2 = e[0]
			var d: Vector2 = e[1]
			var side := 1.0 if _h(p, 29) > 0.5 else -1.0
			var q: Vector2 = p + d.orthogonal() * 3.6 * side
			if not _side_ok(r, q, 1.4) or (sec == "F" and not r._reachable_f(q)):
				continue
			var y: float = r.terrain.height(q.x, q.y)
			# Sitzfläche zum Weg (Modellfront +Z)
			var face := (p - q).normalized()
			var b := Basis(Vector3.UP, atan2(face.x, face.y))
			r.kit.prop("holzbank_3d", Transform3D(b, Vector3(q.x, y - 0.02, q.y)))
			r._blocked.append([q, 1.6])
			n += 1
			stats.benches += 1


# ---------------------------------------------------------------- Hauptburg: Außentreppen, Kanonenkugeln

## Wandstellen der Gebäude im Abschnitt sec: je Gebäudekante ≥ min_len alle 1 m ein Punkt auf der Kante mit
## [Punkt, Richtung entlang der Kante, Normale zum Hof (nach außen), Kantenlänge, Lage t auf der Kante]
func _wall_spots(r, sec: String, min_len: float) -> Array:
	var out: Array = []
	for e in r._fp_boxes:
		if String(e[2]) != "building":
			continue
		var fp: PackedVector2Array = e[1]
		for i in fp.size():
			var a := fp[i]
			var b := fp[(i + 1) % fp.size()]
			var L := a.distance_to(b)
			if L < min_len:
				continue
			var along := (b - a) / L
			var n := along.orthogonal()
			var mid := (a + b) * 0.5
			if Geometry2D.is_point_in_polygon(mid + n * 0.3, fp):
				n = -n
			if r.section_of(mid + n * 2.0) != sec:
				continue
			var t := 0.5
			while t < L:
				out.append([a + along * t, along, n, L, t])
				t += 1.0
	out.sort_custom(func(x, y): return _h(x[0], 41) < _h(y[0], 41))
	return out


func _stairs(r, m: Node) -> void:
	if r.sections.get("F", PackedVector2Array()).is_empty():
		return
	var run := STAIR_STEPS * STAIR_RUN
	var total := run + LANDING.x
	var spots := _wall_spots(r, "F", total + 2.0)
	stair_reject["stellen"] = spots.size()
	for e in spots:
		if stairs.size() >= 2:
			break
		var q: Vector2 = e[0]
		var along: Vector2 = e[1]
		var n: Vector2 = e[2]
		var t0: float = e[4]
		if t0 < 1.0 or t0 + total > float(e[3]) - 1.0:
			continue
		if stairs.any(func(s): return Vector2(s.foot.x, s.foot.z).distance_to(q) < 25.0):
			continue
		# Fläche frei: Streifen 0–2,6 m vor der Wand über die ganze Länge, eben (±0,4 m), im Hof erreichbar
		var y0: float = r.terrain.height(q.x + n.x * 0.8, q.y + n.y * 0.8)
		var why := ""
		var s := -1.0
		while why == "" and s <= total + 1.0:
			for dd in [0.6, 1.4, 2.4, 3.4]:
				var c: Vector2 = q + along * s + n * dd
				if r.in_building(c, 0.1):
					why = "gebaeude"
				elif r.blocked(c, 0.3):
					why = "belegt"
				elif r.path_info(c)[0] < 3.0:
					why = "weg"
				elif r.near_passage(c, 3.0):
					why = "durchgang"
				elif absf(r.terrain.height(c.x, c.y) - y0) > 0.4:
					why = "uneben"
				elif dd > 1.0 and not r._reachable_f(c):    # 1-m-Raster: Zellen an der Wand zählen als Gebäude
					why = "unerreichbar"
				if why != "":
					break
			s += 0.5
		if why != "":
			stair_reject[why] = int(stair_reject.get(why, 0)) + 1
			continue
		_build_stair(r, q, along, n, y0)
		for k in range(0, int(total) + 2, 2):
			r._blocked.append([q + along * k + n * 1.2, 1.8])


func _build_stair(r, q: Vector2, along: Vector2, n: Vector2, y0: float) -> void:
	var col = r.kit.col
	var x := Vector3(along.x, 0, along.y)
	var z := Vector3(n.x, 0, n.y)
	var bs := Basis(x, Vector3.UP, z)
	var o := Vector3(q.x, y0, q.y)
	var cz := 0.05 + STAIR_W * 0.5          # Laufmitte vor der Wand
	var rise := STAIR_RISE / STAIR_STEPS
	# Stufen (Blockstufen bis zum Boden, sichtbar + Kollision), steigend in +x
	for i in STAIR_STEPS:
		var top := rise * (i + 1)
		col.box(Transform3D(bs, o + bs * Vector3(STAIR_RUN * (i + 0.5), top * 0.5, cz)), Vector3(STAIR_RUN, top, STAIR_W), "c_wood", true, true)
	var run := STAIR_STEPS * STAIR_RUN
	# Podest an der Wand (oben), getragen von Pfosten
	var lc := Vector3(run + LANDING.x * 0.5, STAIR_RISE - 0.1, 0.05 + LANDING.y * 0.5)
	col.box(Transform3D(bs, o + bs * lc), Vector3(LANDING.x, 0.2, LANDING.y), "c_wood", true, true)
	for px in [run + 0.1, run + LANDING.x - 0.1]:
		col.box(Transform3D(bs, o + bs * Vector3(px, (STAIR_RISE - 0.2) * 0.5, LANDING.y - 0.05)), Vector3(0.16, STAIR_RISE - 0.2, 0.16), "c_wood", true, true)
	# Geländer außen (Lauf schräg + Podest), Kollision als durchgehende dünne Kiste
	var rail_len := Vector2(run, STAIR_RISE).length()
	var ang := atan2(STAIR_RISE, run)
	var rb := bs * Basis(Vector3.BACK, ang)
	col.box(Transform3D(rb, o + bs * Vector3(run * 0.5, STAIR_RISE * 0.5 + 0.95, 0.05 + STAIR_W)), Vector3(rail_len, 0.08, 0.08), "c_wood", true, false)
	col.box(Transform3D(bs, o + bs * Vector3(run + LANDING.x * 0.5, STAIR_RISE + 0.95, 0.05 + LANDING.y)), Vector3(LANDING.x, 0.08, 0.08), "c_wood", true, false)
	col.box(Transform3D(bs, o + bs * Vector3(run + LANDING.x - 0.04, STAIR_RISE + 0.5, 0.05 + LANDING.y * 0.5)), Vector3(0.08, 1.0, LANDING.y), "c_wood", false, true)
	col.box(Transform3D(bs, o + bs * Vector3(run + LANDING.x * 0.5, STAIR_RISE + 0.5, 0.05 + LANDING.y)), Vector3(LANDING.x, 1.0, 0.08), "c_wood", false, true)
	for k in 4:
		var px := run * (k + 0.5) / 4.0
		var py := STAIR_RISE * (k + 0.5) / 4.0
		col.box(Transform3D(bs, o + bs * Vector3(px, py + 0.5, 0.05 + STAIR_W)), Vector3(0.08, 1.0, 0.08), "c_wood", true, false)
	# Dach: Pultdach von der Wand weg geneigt über Lauf und Podest, auf vier Pfosten
	var roof_y := STAIR_RISE + 2.4
	var depth := maxf(STAIR_W, LANDING.y) + 0.5
	var slope := deg_to_rad(18.0)
	# Pfosten außen neben Lauf und Podest (z = depth − 0,3) auf dem Boden bis unter das Dach
	var post_top := roof_y - tan(slope) * (depth - 0.3) - 0.06
	for px in [0.2, run * 0.5, run + 0.1, run + LANDING.x - 0.1]:
		col.box(Transform3D(bs, o + bs * Vector3(px, post_top * 0.5, depth - 0.3)), Vector3(0.14, post_top, 0.14), "c_wood", true, false)
	var rbs := bs * Basis(Vector3.RIGHT, slope)
	var roof_mat := "r_bib1" if r._lb_mats.has("r_bib1") else "c_roof"
	col.box(Transform3D(rbs, o + bs * Vector3(total_len() * 0.5, roof_y - sin(slope) * depth * 0.5, depth * 0.5)),
		Vector3(total_len() + 0.6, 0.12, depth / cos(slope) + 0.3), roof_mat, true, false)
	stairs.append({"foot": o + bs * Vector3(-0.4, 0, cz), "top": o + bs * Vector3(run + LANDING.x * 0.5, STAIR_RISE + 0.1, 0.05 + LANDING.y * 0.5), "n": z,
		"mid": o + bs * Vector3(total_len() * 0.5, 0, 0)})
	stats.stairs += 1


static func total_len() -> float:
	return STAIR_STEPS * STAIR_RUN + LANDING.x


func _cannonballs(r, m: Node) -> void:
	# an einer Hofwand der Hauptburg, 1,2 m davor
	var q := Vector2.INF
	for e in _wall_spots(r, "F", 3.0):
		var c: Vector2 = (e[0] as Vector2) + (e[2] as Vector2) * 1.2
		if not r.in_building(c, 0.6) and not r.blocked(c, 1.5) and r.path_info(c)[0] > 3.0 and not r.near_passage(c, 5.0) \
				and r._reachable_f(c) and r.boundary_dist(c) > 3.0:
			q = c
			break
	if q == Vector2.INF:
		return
	var y: float = r.terrain.height(q.x, q.y)
	var rad := 0.11
	var xfs: Array = []
	for layer in 4:
		var nn := 4 - layer
		for i in nn:
			for j in nn:
				var off := Vector3((i - (nn - 1) * 0.5) * rad * 2.0, rad + layer * rad * 1.414, (j - (nn - 1) * 0.5) * rad * 2.0)
				xfs.append(Transform3D(Basis(), Vector3(q.x, y, q.y) + off))
	var sm := SphereMesh.new()
	sm.radius = rad
	sm.height = rad * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.17)
	mat.metallic = 0.6
	mat.roughness = 0.55
	sm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mi := MultiMeshInstance3D.new()
	mi.name = "Kanonenkugeln"
	mi.multimesh = mm
	m.dynamic_root.add_child(mi)
	r.kit.col.box(Transform3D(Basis(), Vector3(q.x, y + 0.3, q.y)), Vector3(0.9, 0.6, 0.9), "c_wood", false, true)
	r._blocked.append([q, 1.4])
	stats.cannonballs = xfs.size()


# ---------------------------------------------------------------- Holzzaun an der Grabenkante

func _ditch_fence(r, m: Node) -> void:
	var hg: Dictionary = r.features.get("halsgraben", {})
	if hg.is_empty() or not hg.has("polygon"):
		return
	var poly := PackedVector2Array()
	for p in hg.polygon:
		poly.append(r._v2(p))
	if poly.size() < 3:
		return
	# Abtastung der Grabenkante alle 2,5 m; Zaunpunkt 0,8 m außerhalb der Kante auf der Seite des Hofs, nur wo der
	# Boden dort > 2,5 m über der Grabensohle liegt (echte Kante), außerhalb von Weg/Brücke, Gebäuden und Mauern
	var pts: Array = []
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var L := a.distance_to(b)
		var n := maxi(int(L / 2.5), 1)
		var nrm := (b - a).normalized().orthogonal()
		var mid := (a + b) * 0.5
		if Geometry2D.is_point_in_polygon(mid + nrm * 1.0, poly):
			nrm = -nrm
		for k in n:
			var p := a.lerp(b, float(k) / n) + nrm * 0.8
			pts.append([p, i])
	var col := MeshBatch.new()
	var body := StaticBody3D.new()
	body.name = "CastleDitchFence"
	body.collision_layer = LevelBuilder.FENCE_LAYER
	body.collision_mask = 0
	var prev = null
	for e in pts:
		var p: Vector2 = e[0]
		var ok: bool = Geometry2D.is_point_in_polygon(p, r.boundary) and r.boundary_dist(p) > 1.5 and r.path_info(p)[0] > 4.5 \
			and not r.in_building(p, 1.0) and not r.near_passage(p, 4.0) and r.section_of(p) != "F"
		if ok:
			var y: float = r.terrain.height(p.x, p.y)
			var low := y
			for o in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
				low = minf(low, r.terrain.height(p.x + o.x, p.y + o.y))
			ok = y - low > 2.0
		if not ok:
			prev = null
			continue
		var cur := Vector3(p.x, r.terrain.height(p.x, p.y), p.y)
		_post(col, cur)
		if prev != null and (prev as Vector3).distance_to(cur) < 3.5:
			_rails(col, body, prev, cur)
		prev = cur
	if body.get_child_count() > 0:
		m.static_root.add_child(body)
		body.add_to_group("castle_ditch_fence")
	else:
		body.free()
	col.commit(m.static_root, "CastleDitchFenceVisual", m.lb, false)


func _post(col, p: Vector3) -> void:
	col.box(Transform3D(Basis(), p + Vector3.UP * 0.5), Vector3(0.14, 1.2, 0.14), "c_wood", true, false)


func _rails(col, body: StaticBody3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	var x := d.normalized()
	var z := Vector3.UP.cross(x).normalized()
	var y := x.cross(z).normalized()
	if y.y < 0.0:
		y = -y
		z = -z
	var bs := Basis(x, y, z)
	for hy in [0.45, 0.95]:
		col.box(Transform3D(bs, (a + b) * 0.5 + Vector3.UP * hy), Vector3(d.length(), 0.1, 0.06), "c_wood", true, false)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(d.length(), 1.1, 0.3)
	cs.shape = box
	cs.transform = Transform3D(bs, (a + b) * 0.5 + Vector3.UP * 0.55)
	body.add_child(cs)
	fence.append([a, b])
	stats.fence_m += L
