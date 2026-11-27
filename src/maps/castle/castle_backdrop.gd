extends RefCounted
## Kulisse der Testkarte Castle (AP 3): Häuser rund um die Burg als vereinfachte Blöcke mit Sattel-/Walm-/Pult-/Zeltdach
## (Putz, Ziegel, Stand 1944/45), See und Fluss als Wasserflächen, Hangwald (EZ-Tree-Impostor, nah 3D), Ferngelände
## außerhalb des Datenrasters, Fernhügel als Horizont. Rein optisch: keine Kollision, nicht in der Navmesh-Quelle (Kind der
## Mission, nicht static_root; Navmesh liest nur statische Kollider), ohne Schatten, je Block ein Zeichenaufruf.
## Daten aus den Castle-Kartendaten (castle_real.gd `data_dir()`). Fehlen sie, entsteht nichts.
## Backdrop of the Castle test map (houses, lake/river, forest, far terrain, far hills). Visual only: no collision, not
## part of the navmesh source, no shadows. Data from the Castle map data; without it nothing is built.
##
## Aufruf / call: `Backdrop.build(mission)` nach dem Burgbau. Schalter `--castle_backdrop=0` = aus.
## Baut die Mission das Gelände des Datenrasters selbst (`mission.real.terrain`), entsteht hier nur das Ferngelände
## außerhalb; Höhen dann über `mission.ground_y`. Optionale Missionsmethode `backdrop_exclude_polygons()` ->
## Array[PackedVector2Array] (x/z): zusätzlich zu Abschnittspolygonen + Halsgraben + Kartengrenze keine Häuser/Bäume.

const RealData := preload("res://src/maps/castle/castle_real.gd")
const EzTree := preload("res://src/maps/bavaria/eztree.gd")

## Ergebnis des letzten Aufbaus (Tests/Messung)
static var stats := {}


static func build(m: Node) -> void:
	stats = {}
	if m == null or String(Game.cli.get("castle_backdrop", "1")) == "0":
		return
	if m.get_node_or_null("CastleBackdrop") != null:
		return
	if not FileAccess.file_exists(RealData.data_dir() + "terrain.json"):
		print("CASTLE_BACKDROP: keine Kartendaten – übersprungen / no map data, skipped")
		return
	var b := Builder.new()
	b.run(m)
	stats = b.st


class Acc:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	## Dreieck mit Vorderseite in Richtung nrm (Godot: Uhrzeigersinn = vorn)
	func tri(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, col: Color, ta: Vector2, tb: Vector2, tc: Vector2, k: Vector2) -> void:
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			var t := b
			b = cc
			cc = t
			var tt := tb
			tb = tc
			tc = tt
		v.append(a)
		v.append(b)
		v.append(cc)
		uv.append(ta)
		uv.append(tb)
		uv.append(tc)
		for i in 3:
			n.append(nrm)
			c.append(col)
			uv2.append(k)

	func mesh(mat: Material) -> ArrayMesh:
		if v.is_empty():
			return null
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, mat)
		return am


class Builder:
	extends RefCounted

	const FINE_STEP := 2               ## Datenraster 2 m → eigenes Kulissengelände 4 m (nur ohne Missionsgelände)
	const CHUNK := 48                  ## Feinzellen je Geländeblock (192 m)
	const SINK := 0.25                 ## eigenes Gelände knapp unter dem Datenniveau
	const WATER_DEPTH := 2.5           ## eigener Boden unter See/Fluss
	const WATER_LIFT := 0.12           ## Wasserfläche knapp über dem Datenspiegel (Gelände der Mission liegt dort auf Spiegelhöhe)
	const WALL_FOOT := 2.0             ## Hauswände so weit unter die Fußhöhe ziehen (Hang)
	const HOUSE_CHUNK := 384.0
	const COARSE := 40.0               ## Ferngelände-Raster
	const R_FAR := 2400.0              ## Ferngelände-Radius um die Burgmitte
	const HAZE := Color(0.50, 0.56, 0.60)
	## Kulissen-Bauteile (Pack 18, s. assets/maps/castle/backdrop/SOURCES.txt)
	const KIT := "res://assets/maps/castle/backdrop/"
	const FACADE_DIST := 230.0         ## Häuser bis zu diesem Abstand zur Burg bekommen eine Schaufassade zur Burg hin
	const SHORE_DIST := 420.0          ## Seeufer-Ausstattung bis zu diesem Abstand zur Burg
	const TREE_KEYS := ["ez_spruce_l", "ez_beech_l"]
	const NEAR_BAND := 90.0            ## Bäume so nah an der Burg bekommen zusätzlich 3D-LOD3
	const NEAR_CHUNK := 64.0           ## 3D-Blöcke (Sichtweite je Blockmitte)
	const FAR_CHUNK := 800.0           ## Impostor-Blöcke (alle Bäume)
	const NEAR_3D_END := 85.0         ## 3D-Block sichtbar bis zu diesem Abstand der Blockmitte
	## Impostor eines Nahbaums je Instanz unter diesem Kameraabstand weg. Muss ≤ NEAR_3D_END − halbe Blockdiagonale (45 m)
	## sein, sonst Lücke; dazwischen kurz beide (deckungsgleich).
	const IMP_HIDE := 40.0
	## Flusslauf über die Datenenden hinaus verlängern (bis hinter den Horizont)
	const RIVER_EXT := 2600.0

	var m: Node
	var root: Node3D
	var st := {}
	var ext_terrain := false           ## Mission baut das Datenraster-Gelände selbst
	var cols := 0
	var rows := 0
	var cell := 2.0
	var ox := 0.0
	var oz := 0.0
	var H := PackedFloat32Array()
	var C := PackedByteArray()
	var fcols := 0
	var frows := 0
	var lake := PackedVector2Array()
	var river := PackedVector2Array()
	var lake_y := 0.0
	var river_y := 0.0
	var excl: Array = []               ## Burgflächen (kein eigenes Gelände)
	var excl_tree: Array = []          ## Burgflächen + Rand (keine Bäume/Häuser)
	var castle_pts := PackedVector2Array()   ## Randpunkte der Burgflächen (≤ 20 m Abstand) für Richtung/Abstand zur Burg
	var castle_box := Rect2()
	var facades := Acc.new()           ## Schaufassaden (ein Atlas, ein Zeichenaufruf)
	var facade_cells: Array = []       ## Seitenverhältnis je Atlaszelle
	var tower_xf: Array = []           ## Kirchtürme (Pack-Modell) als Transformationen
	var near_polys: Array = []         ## Nahband (3D-Bäume)
	var center := Vector2.ZERO
	var mask := PackedByteArray()      ## Feinzelle: 1 = Burgfläche
	var tmask := PackedByteArray()     ## Feinzelle: Bit0 Burg+Rand, Bit1 Haus, Bit2 Ortslage, Bit3 Nahband
	var houses_out: Array = []         ## Fußpunkte außerhalb des Datenrasters (Vector3 x, y, z)
	var far_occ := {}                  ## 20-m-Zellen mit Häusern außerhalb des Rasters
	var river_ext: Array = []          ## [Kappenmitte, Richtung] je verlängertem Flussende
	var noise := FastNoiseLite.new()
	var hills := FastNoiseLite.new()
	var hedge := FastNoiseLite.new()
	var mat_terrain: StandardMaterial3D
	var mat_house: ShaderMaterial
	var CH := PackedFloat32Array()     ## Ferngelände-Höhen
	var cn := 0
	var corg := Vector2.ZERO

	func run(mission: Node) -> void:
		m = mission
		var t0 := Time.get_ticks_msec()
		var terr := _json("terrain.json")
		var feat := _json("castle_features.json")
		var sur := _json("surroundings.json")
		if terr.is_empty():
			print("CASTLE_BACKDROP: terrain.json unlesbar – übersprungen")
			return
		var real = m.get("real")
		ext_terrain = real != null and real.get("terrain") != null and m.has_method("ground_y")
		root = Node3D.new()
		root.name = "CastleBackdrop"
		root.add_to_group("castle_backdrop")
		m.add_child(root)
		noise.seed = 4711
		noise.frequency = 1.0 / 170.0
		noise.fractal_octaves = 3
		hills.seed = 1944
		hills.frequency = 1.0 / 900.0
		hills.fractal_octaves = 4
		hedge.seed = 45
		hedge.frequency = 1.0 / 240.0
		hedge.fractal_octaves = 1
		_load_terrain(terr)
		_load_features(feat)
		var t1 := Time.get_ticks_msec()
		_materials()
		_rasters(sur.get("buildings", []) if not sur.is_empty() else [])
		var t2 := Time.get_ticks_msec()
		if not ext_terrain:
			_fine_terrain()
		_coarse_terrain()
		_horizon()
		var t3 := Time.get_ticks_msec()
		_water()
		_shore()
		_houses(sur.get("buildings", []) if not sur.is_empty() else [])
		var t4 := Time.get_ticks_msec()
		_trees()
		var t5 := Time.get_ticks_msec()
		st["ext_terrain"] = ext_terrain
		st["ms"] = {"load": t1 - t0, "raster": t2 - t1, "terrain": t3 - t2, "houses": t4 - t3, "trees": t5 - t4, "total": t5 - t0}
		var geo := 0
		var verts := 0
		for gi in root.find_children("*", "GeometryInstance3D", true, false):
			geo += 1
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
				var mm := (gi as MeshInstance3D).mesh
				for s in mm.get_surface_count():
					verts += mm.surface_get_array_len(s)
		st["nodes"] = geo
		st["mesh_verts"] = verts
		m.set_meta("castle_backdrop_stats", st)
		print("CASTLE_BACKDROP: %s" % JSON.stringify(st))

	# ------------------------------------------------------------------ Daten
	func _json(f: String) -> Dictionary:
		if not FileAccess.file_exists(RealData.data_dir() + f):
			return {}
		var d = JSON.parse_string(FileAccess.get_file_as_string(RealData.data_dir() + f))
		return d if d is Dictionary else {}

	func _load_terrain(t: Dictionary) -> void:
		cell = float(t.get("cell_m", 2.0))
		cols = int(t.cols)
		rows = int(t.rows)
		ox = float(t.origin_xz[0])
		oz = float(t.origin_xz[1])
		H.resize(cols * rows)
		C.resize(cols * rows)
		var hs: Array = t.heights
		var cs: Array = t.get("source", [])
		for j in rows:
			var r: Array = hs[j]
			var rc: Array = cs[j] if j < cs.size() else []
			for i in cols:
				H[j * cols + i] = float(r[i])
				C[j * cols + i] = int(rc[i]) if i < rc.size() else 0
		fcols = (cols - 1) / FINE_STEP + 1
		frows = (rows - 1) / FINE_STEP + 1

	func _load_features(f: Dictionary) -> void:
		if f.has("lake"):
			lake = _poly(f.lake.polygon)
			lake_y = float(f.lake.water_y)
		if f.has("river"):
			river = _extend_ends(_poly(f.river.polygon))
			river_y = float(f.river.water_y)
		for s in f.get("sections", []):
			excl.append(_poly(s.polygon))
		if f.has("halsgraben"):
			excl.append(_poly(f.halsgraben.polygon))
		if m.has_method("backdrop_exclude_polygons"):       # zusätzliche Flächen der Mission (Türme, Brücken …)
			for p in m.call("backdrop_exclude_polygons"):
				excl.append(p if p is PackedVector2Array else _poly(p))
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in excl:
			for q in p:
				lo = lo.min(q)
				hi = hi.max(q)
			for g in Geometry2D.offset_polygon(p, 4.0):
				excl_tree.append(g)
			for g in Geometry2D.offset_polygon(p, NEAR_BAND):
				near_polys.append(g)
		for p in excl:
			for i in p.size():
				var a: Vector2 = p[i]
				var b: Vector2 = p[(i + 1) % p.size()]
				var k := maxi(int(a.distance_to(b) / 20.0), 1)
				for s in k:
					castle_pts.append(a.lerp(b, float(s) / k))
		if not castle_pts.is_empty():
			castle_box = Rect2(castle_pts[0], Vector2.ZERO)
			for q in castle_pts:
				castle_box = castle_box.expand(q)
		var bnd = m.get("boundary")
		if bnd is PackedVector2Array and (bnd as PackedVector2Array).size() > 2:
			for g in Geometry2D.offset_polygon(bnd, 3.0):
				excl_tree.append(g)
		center = (lo + hi) * 0.5 if lo.x < INF else Vector2(ox + cols * cell * 0.5, oz + rows * cell * 0.5)
		st["exclude_polygons"] = excl.size()

	## Flusspolygon: nördliche und südliche Endkappe (kürzeste Kante am z-Extrem) in Laufrichtung um RIVER_EXT
	## verlängern, damit der Fluss nicht abrupt endet; Richtung aus Kappenmitte und Mitte drei Punkte flussaufwärts.
	func _extend_ends(p: PackedVector2Array) -> PackedVector2Array:
		if p.size() < 8:
			return p
		var cen := Vector2.ZERO
		for q in p:
			cen += q
		cen /= p.size()
		for north in [true, false]:
			var n := p.size()
			var a := 0
			for i in n:
				if (p[i].y < p[a].y) if north else (p[i].y > p[a].y):
					a = i
			var prv := (a - 1 + n) % n
			var nxt := (a + 1) % n
			var b_is_prev: bool = (p[prv].y < p[nxt].y) == north
			var b := prv if b_is_prev else nxt
			var ai := (a + (3 if b_is_prev else -3) + n) % n
			var bi := (b + (-3 if b_is_prev else 3) + n) % n
			var cap := (p[a] + p[b]) * 0.5
			var dir := (cap - (p[ai] + p[bi]) * 0.5).normalized()
			if dir.dot(cap - cen) < 0.0:
				dir = -dir
			river_ext.append([cap, dir])
			var ea := p[a] + dir * RIVER_EXT
			var eb := p[b] + dir * RIVER_EXT
			if b_is_prev:
				p.insert(a, ea)          # … b, eb, ea, a …
				p.insert(a, eb)
			else:
				p.insert(a + 1, eb)      # … a, ea, eb, b …
				p.insert(a + 1, ea)
		return p

	## Abstand zur verlängerten Flussachse außerhalb der Daten (Hügel dort flach halten)
	func _river_ext_dist(p: Vector2) -> float:
		var d := INF
		for e in river_ext:
			var c: Vector2 = e[0]
			var q := Geometry2D.get_closest_point_to_segment(p, c, c + (e[1] as Vector2) * (RIVER_EXT + 2000.0))
			d = minf(d, q.distance_to(p))
		return d

	static func _poly(a) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in a:
			var p := Vector2(float(q[0]), float(q[1]))
			if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.05:
				out.append(p)
		if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 0.05:
			out.remove_at(out.size() - 1)
		return out

	func hd(x: float, z: float) -> float:
		var fx := clampf((x - ox) / cell, 0.0, cols - 1.001)
		var fz := clampf((z - oz) / cell, 0.0, rows - 1.001)
		var i := int(fx)
		var j := int(fz)
		var tx := fx - i
		var tz := fz - j
		var k := j * cols + i
		return lerpf(lerpf(H[k], H[k + 1], tx), lerpf(H[k + cols], H[k + cols + 1], tx), tz)

	## Bodenhöhe für Kulissenobjekte im Datenraster: Missionsgelände, sonst eigenes (abgesenktes) Gelände
	func gy(x: float, z: float) -> float:
		if ext_terrain:
			return float(m.call("ground_y", x, z))
		return hd(x, z) - SINK

	func in_data(x: float, z: float, inset := 0.0) -> bool:
		return x >= ox + inset and z >= oz + inset and x <= ox + (cols - 1) * cell - inset and z <= oz + (rows - 1) * cell - inset

	func fpos(i: int, j: int) -> Vector2:
		return Vector2(ox + i * cell * FINE_STEP, oz + j * cell * FINE_STEP)

	func in_water(p: Vector2) -> int:
		if lake.size() > 2 and Geometry2D.is_point_in_polygon(p, lake):
			return 1
		if river.size() > 2 and Geometry2D.is_point_in_polygon(p, river):
			return 2
		return 0

	## Polygon in ein Feinzellen-Raster (Zellmitte) schreiben
	func _raster(arr: PackedByteArray, p: PackedVector2Array, bit: int) -> void:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q in p:
			lo = lo.min(q)
			hi = hi.max(q)
		var s := cell * FINE_STEP
		var i0 := maxi(int(floor((lo.x - ox) / s - 0.5)), 0)
		var i1 := mini(int(ceil((hi.x - ox) / s)), fcols - 2)
		var j0 := maxi(int(floor((lo.y - oz) / s - 0.5)), 0)
		var j1 := mini(int(ceil((hi.y - oz) / s)), frows - 2)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				if Geometry2D.is_point_in_polygon(fpos(i, j) + Vector2(s, s) * 0.5, p):
					arr[j * fcols + i] |= bit

	func _rasters(houses: Array) -> void:
		mask.resize(fcols * frows)
		tmask.resize(fcols * frows)
		for p in excl:
			_raster(mask, p, 1)
		for p in excl_tree:
			_raster(tmask, p, 1)
		for p in near_polys:
			_raster(tmask, p, 8)
		var s := cell * FINE_STEP
		for b in houses:
			var fp := _poly(b.footprint)
			if fp.size() < 3:
				continue
			var lo := Vector2(INF, INF)
			var hi := -lo
			for q in fp:
				lo = lo.min(q)
				hi = hi.max(q)
			var cen := (lo + hi) * 0.5
			if not in_data(cen.x, cen.y):
				houses_out.append(Vector3(cen.x, float(b.ground_y), cen.y))
				far_occ[Vector2i(floori(cen.x / 20.0), floori(cen.y / 20.0))] = true
				continue
			for g in Geometry2D.offset_polygon(fp, 2.5):
				_raster(tmask, g, 2)
			# Ortslage: Hülle + 12 m (Gärten, Gassen)
			var i0 := maxi(int((lo.x - 12.0 - ox) / s), 0)
			var i1 := mini(int((hi.x + 12.0 - ox) / s), fcols - 1)
			var j0 := maxi(int((lo.y - 12.0 - oz) / s), 0)
			var j1 := mini(int((hi.y + 12.0 - oz) / s), frows - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					tmask[j * fcols + i] |= 4

	# ------------------------------------------------------------------ Materialien
	func _materials() -> void:
		mat_terrain = StandardMaterial3D.new()
		mat_terrain.resource_name = "castle_backdrop_ground"
		mat_terrain.vertex_color_use_as_albedo = true
		mat_terrain.roughness = 1.0
		mat_terrain.metallic_specular = 0.15
		var nt := NoiseTexture2D.new()
		var nz := FastNoiseLite.new()
		nz.frequency = 0.02
		nz.fractal_octaves = 4
		nt.noise = nz
		nt.seamless = true
		nt.width = 256
		nt.height = 256
		var gr := Gradient.new()
		gr.set_color(0, Color(0.72, 0.72, 0.68))
		gr.set_color(1, Color(0.95, 0.95, 0.9))
		nt.color_ramp = gr
		mat_terrain.albedo_texture = nt
		mat_terrain.uv1_triplanar = true
		mat_terrain.uv1_world_triplanar = true
		mat_terrain.uv1_scale = Vector3(0.025, 0.025, 0.025)
		mat_house = ShaderMaterial.new()
		mat_house.resource_name = "castle_backdrop_houses"
		var sh := Shader.new()
		sh.code = HOUSE_SHADER
		mat_house.shader = sh

	const HOUSE_SHADER := """
shader_type spatial;
render_mode cull_back;
// UV = Meter (Wand: entlang/über Fuß, Dach: quer/Fallinie), UV2.x = Art (0 Wand, 1 Ziegel, 2 Flachdach), UV2.y = Fenster
void fragment() {
	vec3 base = COLOR.rgb;
	float rough = 0.95;
	if (UV2.x < 0.5) {
		vec2 g = UV / vec2(3.2, 3.0);
		vec2 f = fract(g);
		vec2 fw = fwidth(g);
		float wx = smoothstep(0.33 - fw.x, 0.33 + fw.x, f.x) * (1.0 - smoothstep(0.67 - fw.x, 0.67 + fw.x, f.x));
		float wy = smoothstep(0.30 - fw.y, 0.30 + fw.y, f.y) * (1.0 - smoothstep(0.76 - fw.y, 0.76 + fw.y, f.y));
		float fade = clamp(max(fw.x, fw.y) * 3.0 - 0.4, 0.0, 1.0);
		float win = mix(wx * wy, 0.15, fade) * UV2.y * step(0.0, UV.y);
		float dirt = 1.0 - 0.2 * (1.0 - smoothstep(-0.5, 1.5, UV.y));
		base = mix(base * dirt, vec3(0.06, 0.07, 0.08), win);
		rough = mix(0.95, 0.3, win);
	} else if (UV2.x < 1.5) {
		float r = UV.y / 0.36;
		float fv = fwidth(r);
		float fade = clamp(fv * 2.0 - 0.3, 0.0, 1.0);
		float line = mix(smoothstep(0.7, 0.95, fract(r)), 0.2, fade);
		float h = fract(sin(dot(floor(vec2(UV.x / 0.28 + floor(r) * 0.5, r)), vec2(12.9898, 78.233))) * 43758.5453);
		base *= (1.0 - 0.35 * line) * (0.86 + 0.28 * mix(h, 0.5, fade));
		rough = 0.85;
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
"""

	func _ground_color(p: Vector2, slope: float, flags: int, wet: bool) -> Color:
		var nv := noise.get_noise_2dv(p)
		var c := Color(0.19, 0.24, 0.12).lerp(Color(0.25, 0.28, 0.15), clampf(nv * 1.5 + 0.5, 0.0, 1.0))
		if noise.get_noise_2dv(p * 0.8) > 0.2 or slope > 0.3:
			c = c.lerp(Color(0.12, 0.16, 0.08), 0.8)                 # Waldboden (gleiches Rauschen wie die Waldflecken)
		if flags & 4:
			c = c.lerp(Color(0.43, 0.41, 0.36), 0.45)                # Ortslage (Wege, Höfe)
		if slope > 0.85:
			c = c.lerp(Color(0.45, 0.41, 0.35), clampf((slope - 0.85) * 2.0, 0.0, 0.8))   # Fels/Erde
		if wet:
			c = Color(0.30, 0.29, 0.22)
		return c

	func _add_mesh(am: Mesh, nm: String) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = am
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mi)
		return mi

	static func _grid_mesh(verts: PackedVector3Array, nrms: PackedVector3Array, colr: PackedColorArray, idx: PackedInt32Array, mat: Material) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = nrms
		arr[Mesh.ARRAY_COLOR] = colr
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, mat)
		return am

	# ------------------------------------------------------------------ Gelände
	## Eigenes Gelände im Datenraster (nur wenn die Mission keines baut), 4 m, ohne Burgflächen.
	func _fine_terrain() -> void:
		var s := cell * FINE_STEP
		var n := fcols * frows
		var fy := PackedFloat32Array()
		fy.resize(n)
		var wet := PackedByteArray()
		wet.resize(n)
		for j in frows:
			for i in fcols:
				var k := (j * FINE_STEP) * cols + i * FINE_STEP
				var y := H[k] - SINK
				var w := in_water(fpos(i, j))
				var code := C[k]
				if code == 2 or w == 1:
					y = minf(y, lake_y - WATER_DEPTH)
					wet[j * fcols + i] = 1
				elif code == 3 or w == 2:
					y = minf(y, river_y - WATER_DEPTH)
					wet[j * fcols + i] = 1
				fy[j * fcols + i] = y
		var count := 0
		var tris := 0
		var cj := 0
		while cj < frows - 1:
			var ci := 0
			while ci < fcols - 1:
				var i1 := mini(ci + CHUNK, fcols - 1)
				var j1 := mini(cj + CHUNK, frows - 1)
				var w := i1 - ci + 1
				var verts := PackedVector3Array()
				var nrms := PackedVector3Array()
				var colr := PackedColorArray()
				var idx := PackedInt32Array()
				for j in range(cj, j1 + 1):
					for i in range(ci, i1 + 1):
						var k := j * fcols + i
						var p := fpos(i, j)
						var hx := fy[j * fcols + mini(i + 1, fcols - 1)] - fy[j * fcols + maxi(i - 1, 0)]
						var hz := fy[mini(j + 1, frows - 1) * fcols + i] - fy[maxi(j - 1, 0) * fcols + i]
						verts.append(Vector3(p.x, fy[k], p.y))
						nrms.append(Vector3(-hx / (2.0 * s), 1.0, -hz / (2.0 * s)).normalized())
						colr.append(_ground_color(p, Vector2(hx, hz).length() / (2.0 * s), tmask[k], wet[k] == 1))
				for j in range(cj, j1):
					for i in range(ci, i1):
						if mask[j * fcols + i] & 1:
							continue
						var a := (j - cj) * w + (i - ci)
						idx.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
				if not idx.is_empty():
					_add_mesh(_grid_mesh(verts, nrms, colr, idx, mat_terrain), "Gelaende_%d_%d" % [ci, cj])
					count += 1
					tris += idx.size() / 3
				ci += CHUNK
			cj += CHUNK
		st["terrain_chunks"] = count
		st["terrain_tris"] = tris

	## Ferngelände: grobes Raster um die Burgmitte bis R_FAR, Quads im Datenraster entfallen. Außerhalb Relaxation zwischen
	## Rasterkante, Hausfußhöhen und Wasser, dazu Hügel mit wachsendem Abstand.
	func coarse_h(p: Vector2) -> float:
		var fx := clampf((p.x - corg.x) / COARSE, 0.0, cn - 1.001)
		var fz := clampf((p.y - corg.y) / COARSE, 0.0, cn - 1.001)
		var i := int(fx)
		var j := int(fz)
		var k := j * cn + i
		return lerpf(lerpf(CH[k], CH[k + 1], fx - i), lerpf(CH[k + cn], CH[k + cn + 1], fx - i), fz - j)

	func _outside_dist(p: Vector2) -> float:
		var q := Vector2(clampf(p.x, ox, ox + (cols - 1) * cell), clampf(p.y, oz, oz + (rows - 1) * cell))
		return q.distance_to(p)

	func _coarse_terrain() -> void:
		cn = int(2.0 * R_FAR / COARSE) + 1
		corg = center - Vector2(R_FAR, R_FAR)
		CH.resize(cn * cn)
		var fixed := PackedByteArray()
		fixed.resize(cn * cn)
		for j in cn:
			for i in cn:
				var p := corg + Vector2(i, j) * COARSE
				var k := j * cn + i
				var w := in_water(p)
				if in_data(p.x, p.y):
					CH[k] = hd(p.x, p.y) - 1.5
					fixed[k] = 1
				elif w > 0:
					CH[k] = (lake_y if w == 1 else river_y) - WATER_DEPTH
					fixed[k] = 1
				else:
					# Talboden entlang der Flussverlängerung, sonst Rasterkante
					CH[k] = lerpf(river_y + 1.5, hd(p.x, p.y), smoothstep(40.0, 450.0, _river_ext_dist(p)))
		var hb := {}
		for hp in houses_out:
			var key := Vector2i(roundi((hp.x - corg.x) / COARSE), roundi((hp.z - corg.y) / COARSE))
			hb[key] = minf(float(hb.get(key, INF)), hp.y - 0.4)
		for key in hb:
			if key.x >= 0 and key.y >= 0 and key.x < cn and key.y < cn and fixed[key.y * cn + key.x] == 0:
				CH[key.y * cn + key.x] = hb[key]
				fixed[key.y * cn + key.x] = 2
		# Gauß-Seidel nur im Bereich bis 700 m außerhalb des Rasters (weiter draußen trägt das Hügelrauschen)
		var free: PackedInt32Array = PackedInt32Array()
		for j in range(1, cn - 1):
			for i in range(1, cn - 1):
				var k := j * cn + i
				if fixed[k] == 0 and _outside_dist(corg + Vector2(i, j) * COARSE) < 700.0:
					free.append(k)
		for it in 40:
			for k in free:
				CH[k] = (CH[k - 1] + CH[k + 1] + CH[k - cn] + CH[k + cn]) * 0.25
		for j in cn:
			for i in cn:
				var k := j * cn + i
				if fixed[k] != 0:
					continue
				var p := corg + Vector2(i, j) * COARSE
				var a := smoothstep(320.0, 1900.0, _outside_dist(p)) * smoothstep(60.0, 450.0, _river_ext_dist(p))
				CH[k] += a * (25.0 + 85.0 * (0.5 + 0.5 * hills.get_noise_2dv(p)))
		var blocks := 4
		var per := int(ceil(float(cn - 1) / blocks))
		var count := 0
		var tris := 0
		for bj in blocks:
			for bi in blocks:
				var i0 := bi * per
				var j0 := bj * per
				var i1 := mini(i0 + per, cn - 1)
				var j1 := mini(j0 + per, cn - 1)
				if i0 >= i1 or j0 >= j1:
					continue
				var w := i1 - i0 + 1
				var verts := PackedVector3Array()
				var nrms := PackedVector3Array()
				var colr := PackedColorArray()
				var idx := PackedInt32Array()
				for j in range(j0, j1 + 1):
					for i in range(i0, i1 + 1):
						var p := corg + Vector2(i, j) * COARSE
						var hx := CH[j * cn + mini(i + 1, cn - 1)] - CH[j * cn + maxi(i - 1, 0)]
						var hz := CH[mini(j + 1, cn - 1) * cn + i] - CH[maxi(j - 1, 0) * cn + i]
						verts.append(Vector3(p.x, CH[j * cn + i], p.y))
						nrms.append(Vector3(-hx / (2.0 * COARSE), 1.0, -hz / (2.0 * COARSE)).normalized())
						var c := _ground_color(p, Vector2(hx, hz).length() / (2.0 * COARSE), 0, in_water(p) > 0)
						colr.append(c.lerp(HAZE, smoothstep(900.0, 2600.0, p.distance_to(center)) * 0.3))
				for j in range(j0, j1):
					for i in range(i0, i1):
						var pc := corg + (Vector2(i, j) + Vector2(0.5, 0.5)) * COARSE
						if pc.distance_to(center) > R_FAR + COARSE:
							continue
						if in_data(pc.x, pc.y, COARSE * 0.75):
							continue
						var a := (j - j0) * w + (i - i0)
						idx.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
				if idx.is_empty():
					continue
				_add_mesh(_grid_mesh(verts, nrms, colr, idx, mat_terrain), "Ferngelaende_%d_%d" % [bi, bj])
				count += 1
				tris += idx.size() / 3
		st["far_chunks"] = count
		st["far_tris"] = tris

	## Horizont: Hügelkranz in Polarkoordinaten ab R_FAR (Anschluss an das Ferngelände), zunehmend im Dunst.
	func _horizon() -> void:
		var seg := 192
		var radii := [R_FAR - 30.0, R_FAR + 350.0, R_FAR + 850.0, R_FAR + 1400.0]
		var haze := [0.22, 0.3, 0.38, 0.46]
		var rise := [0.0, 90.0, 170.0, 120.0]
		var amp := [0.0, 80.0, 170.0, 230.0]
		## Flusstal: vorderer Kranz abgesenkt, dahinter niedrigere Fernhügel (keine Lücke im Horizont)
		var valley := [0.0, 0.4, 0.7, 0.85]
		var verts := PackedVector3Array()
		var nrms := PackedVector3Array()
		var colr := PackedColorArray()
		var idx := PackedInt32Array()
		var base := (lake_y + river_y) * 0.5
		for r in radii.size():
			for s in seg:
				var a := TAU * s / seg
				var p := center + Vector2(cos(a), sin(a)) * float(radii[r])
				var y := coarse_h(p) - 1.0
				if r > 0:
					var nv := 0.5 + 0.5 * hills.get_noise_2d(cos(a) * 900.0 * r, sin(a) * 900.0 * r)
					var dip := lerpf(float(valley[r]), 1.0, smoothstep(80.0, 900.0, _river_ext_dist(p)))
					y = base + (float(rise[r]) + float(amp[r]) * nv) * dip
				verts.append(Vector3(p.x, y, p.y))
				nrms.append(Vector3.UP)
				colr.append(Color(0.17, 0.23, 0.13).lerp(HAZE, haze[r]))
		# Normalen aus der Geometrie (vorher pauschal aufwärts → sonnige Hänge leuchteten weiß)
		for r in radii.size():
			for s in seg:
				var k := r * seg + s
				var along := verts[r * seg + (s + 1) % seg] - verts[r * seg + (s - 1 + seg) % seg]
				var radial := verts[mini(r + 1, radii.size() - 1) * seg + s] - verts[maxi(r - 1, 0) * seg + s]
				var nn := radial.cross(along).normalized()
				nrms[k] = nn if nn.y > 0.0 else -nn
		for r in radii.size() - 1:
			for s in seg:
				var a0 := r * seg + s
				var a1 := r * seg + (s + 1) % seg
				idx.append_array([a0, a0 + seg, a1, a1, a0 + seg, a1 + seg])
		var mat := StandardMaterial3D.new()
		mat.resource_name = "castle_backdrop_horizon"
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		mat.metallic_specular = 0.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := _add_mesh(_grid_mesh(verts, nrms, colr, idx, mat), "Horizont")
		mi.extra_cull_margin = 64.0

	# ------------------------------------------------------------------ Wasser
	## Kulissenwasser (eigener, deckender Shader): Farbe je Gewässer, weiche Kräuselung aus wenigen Sinuswellen, die mit
	## der Bildschirmgröße zur glatten Fläche ausblenden (kein Kachelmuster/Flimmern aus der Vogelperspektive).
	const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 shallow : source_color = vec3(0.16, 0.36, 0.33);
uniform vec3 deep : source_color = vec3(0.05, 0.19, 0.18);
uniform vec2 flow = vec2(0.03, 0.01);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wp.xz;
	float t = TIME;
	vec2 q1 = p * 0.31 + flow * t * 3.0;
	vec2 q2 = p * 0.73 + vec2(-flow.y, flow.x) * t * 4.0 + 3.1;
	vec2 slope = vec2(cos(q1.x + 0.7 * sin(q1.y * 1.3)), sin(q1.y + 0.6 * cos(q1.x * 1.1))) * 0.06
		+ vec2(cos(q2.y * 1.7 + q2.x), sin(q2.x * 1.9 - q2.y * 0.4)) * 0.035;
	float fw = length(fwidth(p));
	slope *= 1.0 - smoothstep(0.15, 0.9, fw);       // ferne Pixel: glatte Fläche statt Rauschen
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float var_ = 0.5 + 0.5 * sin(p.x * 0.011 + 1.3 * sin(p.y * 0.008));
	ALBEDO = mix(deep, shallow, 0.35 + 0.3 * var_);
	ROUGHNESS = 0.32;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
"""

	func _water() -> void:
		var sh := Shader.new()
		sh.code = WATER_SHADER
		var n := 0
		# See grün-türkis, Fluss grau-grün (Gletscherfluss), Strömung nach Norden
		for w in [[lake, lake_y, "See", Vector2(0.02, 0.01), Color(0.17, 0.37, 0.33), Color(0.05, 0.19, 0.17)],
				[river, river_y, "Fluss", Vector2(0.0, -0.12), Color(0.36, 0.41, 0.35), Color(0.17, 0.22, 0.18)]]:
			var poly: PackedVector2Array = w[0]
			if poly.size() < 3:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("flow", w[3])
			mat.set_shader_parameter("shallow", w[4])
			mat.set_shader_parameter("deep", w[5])
			var idx := Geometry2D.triangulate_polygon(poly)
			if idx.is_empty():
				var cleaned := Geometry2D.offset_polygon(poly, 0.05)
				if not cleaned.is_empty():
					poly = cleaned[0]
					idx = Geometry2D.triangulate_polygon(poly)
			if idx.is_empty():
				push_warning("CASTLE_BACKDROP: Wasserpolygon %s nicht zerlegbar" % w[2])
				continue
			var acc := Acc.new()
			var y := float(w[1]) + (WATER_LIFT if ext_terrain else 0.0)
			for t in range(0, idx.size(), 3):
				var a := poly[idx[t]]
				var b := poly[idx[t + 1]]
				var c := poly[idx[t + 2]]
				acc.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, Color.WHITE, a, b, c, Vector2.ZERO)
			var mi := _add_mesh(acc.mesh(mat), "Wasser_" + String(w[2]))
			mi.set_meta("castle_backdrop_water", true)
			n += 1
		st["water"] = n

	# ------------------------------------------------------------------ Häuser
	## gedeckter, gealterter Putz: Ocker, Grau, Altrosa, Creme, Sand, Graugrün
	const WALLS := [Color(0.62, 0.53, 0.38), Color(0.55, 0.54, 0.50), Color(0.63, 0.52, 0.48), Color(0.66, 0.62, 0.52),
		Color(0.58, 0.51, 0.41), Color(0.52, 0.53, 0.47), Color(0.60, 0.47, 0.37), Color(0.57, 0.56, 0.52)]
	## gealterte Biberschwanz-/Falzziegel, dunkler, einzelne Schieferdächer
	const ROOFS := [Color(0.37, 0.19, 0.14), Color(0.32, 0.18, 0.14), Color(0.41, 0.23, 0.16), Color(0.30, 0.21, 0.17),
		Color(0.35, 0.24, 0.19), Color(0.27, 0.26, 0.26)]
	const TOWER_WALL := Color(0.60, 0.58, 0.53)
	const SPIRE := Color(0.24, 0.25, 0.26)

	func _houses(list: Array) -> void:
		var accs := {}
		var built := 0
		var skipped := 0
		if FileAccess.file_exists(KIT + "fassaden_atlas.json") and ResourceLoader.exists(KIT + "fassaden_atlas.png"):
			var fj = JSON.parse_string(FileAccess.get_file_as_string(KIT + "fassaden_atlas.json"))
			if fj is Dictionary:
				for c in fj.get("cells", []):
					facade_cells.append(float(c.aspect))
		for b in list:
			var fp := _poly(b.footprint)
			if fp.size() < 3 or absf(_area(fp)) < 6.0:
				skipped += 1
				continue
			var cen := Vector2.ZERO
			for q in fp:
				cen += q
			cen /= fp.size()
			var hidden := not in_data(cen.x, cen.y) and in_water(cen) > 0     # in der Flussverlängerung
			for p in excl_tree:
				if Geometry2D.is_point_in_polygon(cen, p):
					hidden = true
					break
			if hidden:
				skipped += 1
				continue
			var key := Vector2i(floori(cen.x / HOUSE_CHUNK), floori(cen.y / HOUSE_CHUNK))
			if not accs.has(key):
				accs[key] = Acc.new()
			var hsh := absi(String(b.get("gml_id", str(cen))).hash())
			_house(accs[key], fp, cen, b, hsh)
			built += 1
		var verts := 0
		for key in accs:
			var acc: Acc = accs[key]
			verts += acc.v.size()
			_add_mesh(acc.mesh(mat_house), "Haeuser_%d_%d" % [key.x, key.y])
		if not facades.v.is_empty():
			var fm := StandardMaterial3D.new()
			fm.resource_name = "castle_backdrop_facades"
			fm.albedo_texture = load(KIT + "fassaden_atlas.png")
			fm.albedo_color = Color(0.72, 0.70, 0.66)        # gedämpft wie der übrige Putz
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			fm.alpha_scissor_threshold = 0.5
			fm.roughness = 0.95
			fm.metallic_specular = 0.2
			fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_add_mesh(facades.mesh(fm), "Haeuser_Fassaden")
			st["facades"] = facades.v.size() / 6
		_towers()
		st["houses"] = built
		st["houses_skipped"] = skipped
		st["house_chunks"] = accs.size()
		st["house_verts"] = verts

	static func _area(p: PackedVector2Array) -> float:
		var a := 0.0
		for i in p.size():
			var q := p[(i + 1) % p.size()]
			a += p[i].x * q.y - q.x * p[i].y
		return a * 0.5

	## Dachebenen h = a·x + b·z + c (lokal, Ursprung = Grundrissmitte); Dach = Minimum aller Ebenen.
	func _planes(fp: PackedVector2Array, b: Dictionary, cen: Vector2, eave: float, ridge: float) -> Array:
		var kind := String(b.get("roof_type", "flat"))
		var dh := ridge - eave
		if kind == "flat" or dh < 0.4:
			return [Vector3(0, 0, eave)]
		var rl = b.get("ridge_line")
		var r1 := Vector2.ZERO
		var r2 := Vector2.ZERO
		var has_line := false
		var has_pts := rl is Array and (rl as Array).size() >= 2
		if has_pts:
			r1 = Vector2(float(rl[0][0]), float(rl[0][2])) - cen
			r2 = Vector2(float(rl[rl.size() - 1][0]), float(rl[rl.size() - 1][2])) - cen
			has_line = r1.distance_to(r2) >= 0.5
		var planes: Array = []
		if kind in ["pyramid", "cone", "tower"] or not has_line:
			var apex := (r1 + r2) * 0.5 if has_pts else Vector2.ZERO
			var u := Vector2.RIGHT
			var best := 0.0
			for i in fp.size():
				var e := fp[(i + 1) % fp.size()] - fp[i]
				if e.length() > best:
					best = e.length()
					u = e.normalized()
			var dirs: Array = [u, -u, u.orthogonal(), -u.orthogonal()]
			if kind in ["cone", "tower"]:
				for k in 4:
					dirs.append(u.rotated(PI * 0.25 + PI * 0.5 * k))
			for e in dirs:
				var ev: Vector2 = e
				var tmax := 0.0
				for q in fp:
					tmax = maxf(tmax, ev.dot(q - apex))
				if tmax < 0.3:
					continue
				var k := dh / tmax
				planes.append(Vector3(-k * ev.x, -k * ev.y, ridge + k * ev.dot(apex)))
			return planes if not planes.is_empty() else [Vector3(0, 0, eave)]
		var d := (r2 - r1).normalized()
		var nn := d.orthogonal()
		var wp := 0.0
		var wn := 0.0
		for q in fp:
			var s := nn.dot(q - r1)
			wp = maxf(wp, s)
			wn = maxf(wn, -s)
		if kind == "shed":
			# Firstlinie = hohe Traufseite; Fläche fällt zur weiteren Seite
			var e := nn if wp >= wn else -nn
			var w := maxf(wp, wn)
			if w < 0.3:
				return [Vector3(0, 0, eave)]
			var k := dh / w
			return [Vector3(-k * e.x, -k * e.y, ridge + k * e.dot(r1))]
		for side in [[nn, wp], [-nn, wn]]:
			var e: Vector2 = side[0]
			if float(side[1]) < 0.3:
				continue
			var k := dh / float(side[1])
			planes.append(Vector3(-k * e.x, -k * e.y, ridge + k * e.dot(r1)))
		if kind in ["hip", "mansard"]:
			for end in [[d, r2], [-d, r1]]:
				var e: Vector2 = end[0]
				var o: Vector2 = end[1]
				var tmax := 0.0
				for q in fp:
					tmax = maxf(tmax, e.dot(q - o))
				if tmax < 0.5:
					continue
				var k := dh / tmax
				planes.append(Vector3(-k * e.x, -k * e.y, ridge + k * e.dot(o)))
		return planes if not planes.is_empty() else [Vector3(0, 0, eave)]

	static func _halfplane(g: Vector2, k: float) -> PackedVector2Array:
		# Bereich g·p + k ≤ 0 als großes Viereck (lokale Koordinaten)
		var l := g.length()
		var gn := g / l
		var p0 := gn * (-k / l)
		var t := gn.orthogonal()
		var big := 400.0
		return PackedVector2Array([p0 + t * big, p0 - t * big, p0 - t * big - gn * big * 2.0, p0 + t * big - gn * big * 2.0])

	static func _ph(pl: Vector3, p: Vector2) -> float:
		return pl.x * p.x + pl.y * p.y + pl.z

	func _house(acc: Acc, fpw: PackedVector2Array, cen: Vector2, b: Dictionary, hsh: int) -> void:
		var g := float(b.ground_y)
		var eave := maxf(float(b.eave_y), g + 2.2)
		var ridge := maxf(float(b.ridge_y), eave)
		var wall_c: Color = WALLS[hsh % WALLS.size()]
		wall_c = wall_c * (0.64 + 0.12 * float((hsh >> 4) % 7) / 6.0)
		wall_c.a = 1.0
		var roof_c: Color = ROOFS[(hsh >> 8) % ROOFS.size()]
		roof_c = roof_c * (0.85 + 0.2 * float((hsh >> 12) % 5) / 4.0)
		roof_c.a = 1.0
		var kind := String(b.get("roof_type", "flat"))
		var rl = b.get("ridge_line")
		var has_line := rl is Array and (rl as Array).size() >= 2 \
			and Vector2(float(rl[0][0]), float(rl[0][2])).distance_to(Vector2(float(rl[-1][0]), float(rl[-1][2]))) >= 0.5
		# Kirche: die Gebäudedaten fassen Schiff + Turm zusammen (Traufe fast am Boden, First = Turmspitze, keine Firstlinie)
		# → Schiff mit Satteldach + quadratischer Turm mit Spitzhelm am Westende.
		if not has_line and not (kind in ["pyramid", "cone", "tower"]) and ridge - eave > 15.0:
			_church(acc, fpw, cen, g, ridge, roof_c)
			st["churches"] = int(st.get("churches", 0)) + 1
			return
		_body(acc, fpw, cen, b, g, eave, ridge, wall_c, roof_c, 1.0)
		_facade(fpw, cen, g, eave, hsh)

	## Nächster Punkt der Burgflächen (Richtung/Abstand zur Burg)
	func _castle_near(p: Vector2) -> Vector2:
		var best := Vector2(INF, INF)
		var bd := INF
		for q in castle_pts:
			var d := q.distance_squared_to(p)
			if d < bd:
				bd = d
				best = q
		return best

	## Schaufassade (Atlas-Motiv aus Pack 18) an der zur Burg gewandten Hauswand naher Häuser. Das Motiv steht 7 cm vor
	## der Wand; Giebel/Attika ragen wie bei Inn-Salzach-Fassaden über die Traufe und verdecken das Dach.
	func _facade(fpw: PackedVector2Array, cen: Vector2, g: float, eave: float, hsh: int) -> void:
		if facade_cells.is_empty() or eave - g < 6.0 or not castle_box.grow(FACADE_DIST).has_point(cen):
			return
		var cp := _castle_near(cen)
		if cp.distance_to(cen) > FACADE_DIST:
			return
		var best := -1
		var score := 0.55
		var nrm := Vector2.ZERO
		for i in fpw.size():
			var a := fpw[i]
			var b := fpw[(i + 1) % fpw.size()]
			var ln := a.distance_to(b)
			if ln < 5.5 or ln > 18.0:
				continue
			var o := (b - a).orthogonal().normalized()
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + o * 0.05, fpw):
				o = -o
			var s := o.dot((cp - (a + b) * 0.5).normalized())
			if s > score:
				score = s
				best = i
				nrm = o
		if best < 0:
			return
		var a := fpw[best]
		var b := fpw[(best + 1) % fpw.size()]
		var cell := hsh % facade_cells.size()
		var w := a.distance_to(b) * 0.97
		var h := clampf(w * float(facade_cells[cell]), (eave - g) * 0.9, (eave - g) * 1.45)
		var n3 := Vector3(nrm.x, 0.0, nrm.y)
		var right := (-n3).cross(Vector3.UP)
		var mid := (a + b) * 0.5 + nrm * 0.07
		var base := Vector3(mid.x, g - 0.3, mid.y)
		var l0 := base - right * w * 0.5
		var r0 := base + right * w * 0.5
		var l1 := l0 + Vector3.UP * (h + 0.3)
		var r1 := r0 + Vector3.UP * (h + 0.3)
		var cx := cell % 4
		var cy := cell / 4
		var u0 := cx / 4.0 + 0.002
		var u1 := (cx + 1) / 4.0 - 0.002
		var v0 := cy / 2.0 + 0.002
		var v1 := (cy + 1) / 2.0 - 0.002
		facades.tri(l0, r0, r1, n3, Color.WHITE, Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2.ZERO)
		facades.tri(l0, r1, l1, n3, Color.WHITE, Vector2(u0, v1), Vector2(u1, v0), Vector2(u0, v0), Vector2.ZERO)

	func _church(acc: Acc, fpw: PackedVector2Array, cen: Vector2, g: float, top: float, roof_c: Color) -> void:
		var u := Vector2.RIGHT
		var best := 0.0
		for i in fpw.size():
			var e := fpw[(i + 1) % fpw.size()] - fpw[i]
			if e.length() > best:
				best = e.length()
				u = e.normalized()
		var w := u.orthogonal()
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q in fpw:
			var d := q - cen
			lo = lo.min(Vector2(u.dot(d), w.dot(d)))
			hi = hi.max(Vector2(u.dot(d), w.dot(d)))
		var ln := hi.x - lo.x
		var wd := hi.y - lo.y
		if wd > ln:                      # Längsachse = längere Ausdehnung
			var t := u
			u = w
			w = -t
			lo = Vector2(INF, INF)
			hi = -lo
			for q in fpw:
				var d := q - cen
				lo = lo.min(Vector2(u.dot(d), w.dot(d)))
				hi = hi.max(Vector2(u.dot(d), w.dot(d)))
			ln = hi.x - lo.x
			wd = hi.y - lo.y
		var mid_w := (lo.y + hi.y) * 0.5
		var nave_eave := g + clampf(0.3 * ln, 8.0, 15.0)
		var nave_ridge := nave_eave + clampf(0.42 * wd, 4.0, 13.0)
		var r1 := cen + u * (lo.x + 0.5) + w * mid_w
		var r2 := cen + u * (hi.x - 0.5) + w * mid_w
		var nave := {"roof_type": "gable", "ridge_line": [[r1.x, nave_ridge, r1.y], [r2.x, nave_ridge, r2.y]]}
		_body(acc, fpw, cen, nave, g, nave_eave, nave_ridge, TOWER_WALL * 1.05, roof_c, 0.0)
		# Turm: Seite ~30 % der Schiffsbreite, am westlicheren Ende, Schaft ~62 % der Gesamthöhe, darüber Spitzhelm
		var s := clampf(0.32 * wd, 6.0, 11.0)
		var end_lo := cen + u * lo.x
		var end_hi := cen + u * hi.x
		var along := (lo.x + s * 0.5) if end_lo.x <= end_hi.x else (hi.x - s * 0.5)
		var tc := cen + u * along + w * mid_w
		var shaft := maxf(g + 0.62 * (top - g), nave_ridge + 4.0)
		var spire := maxf(top, shaft + 6.0)
		var sq := PackedVector2Array()
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			sq.append(tc + u * c.x * s * 0.5 + w * c.y * s * 0.5)
		if ResourceLoader.exists(KIT + "kirchturm.glb"):
			# Pack-Modell (5,8 × 22 × 6 m, Fuß im Ursprung) auf Seite s und Gesamthöhe skaliert
			var ux := Vector3(u.x, 0, u.y)
			var bs := Basis(ux * (s / 5.8), Vector3.UP * ((spire - g + 0.6) / 22.0), ux.cross(Vector3.UP) * (s / 5.98))
			tower_xf.append(Transform3D(bs, Vector3(tc.x, g - 0.6, tc.y)))
		else:
			_body(acc, sq, tc, {"roof_type": "pyramid"}, g, shaft, spire, TOWER_WALL, SPIRE, 0.0)

	## Die Pack-Modelle bestehen aus vielen Einzelknoten mit je eigenem Material. Zusammenfassung je Albedo-Textur und
	## Transparenzart; die Materialfarbe wandert in die Eckenfarbe → 1–3 Flächen je Modell (wenige Zeichenaufrufe).
	static var _merged_cache := {}
	static func merged(path: String) -> ArrayMesh:
		if _merged_cache.has(path):
			return _merged_cache[path]
		if not ResourceLoader.exists(path):
			return null
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		var groups := {}
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D()
			var nd: Node = mi
			while nd != scene and nd != null:
				xf = (nd as Node3D).transform * xf
				nd = nd.get_parent()
			var nb := xf.basis.inverse().transposed()
			var mesh := (mi as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var mat: Material = (mi as MeshInstance3D).get_active_material(s)
				var tex: Texture2D = null
				var col := Color.WHITE
				var tr := 0
				if mat is BaseMaterial3D:
					tex = (mat as BaseMaterial3D).albedo_texture
					col = (mat as BaseMaterial3D).albedo_color
					tr = (mat as BaseMaterial3D).transparency
				var key := "%s|%d" % [str(tex.get_rid().get_id()) if tex else "-", tr]
				if not groups.has(key):
					groups[key] = {"mat": mat, "v": PackedVector3Array(), "n": PackedVector3Array(),
						"uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
				var g: Dictionary = groups[key]
				var arr := mesh.surface_get_arrays(s)
				var av: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var an = arr[Mesh.ARRAY_NORMAL]
				var auv = arr[Mesh.ARRAY_TEX_UV]
				var ac = arr[Mesh.ARRAY_COLOR]
				var ai = arr[Mesh.ARRAY_INDEX]
				var v: PackedVector3Array = g.v
				var n: PackedVector3Array = g.n
				var uv: PackedVector2Array = g.uv
				var c: PackedColorArray = g.c
				var ii: PackedInt32Array = g.i
				var base := v.size()
				for k in av.size():
					v.append(xf * av[k])
					n.append((nb * an[k]).normalized() if an != null and k < (an as PackedVector3Array).size() else Vector3.UP)
					uv.append(auv[k] if auv != null and k < (auv as PackedVector2Array).size() else Vector2.ZERO)
					c.append(col * (ac[k] if ac != null and k < (ac as PackedColorArray).size() else Color.WHITE))
				if ai != null and (ai as PackedInt32Array).size() > 0:
					for k in (ai as PackedInt32Array):
						ii.append(base + k)
				else:
					for k in av.size():
						ii.append(base + k)
				g.v = v
				g.n = n
				g.uv = uv
				g.c = c
				g.i = ii
		scene.free()
		var out := ArrayMesh.new()
		for key in groups:
			var g: Dictionary = groups[key]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = g.v
			arr[Mesh.ARRAY_NORMAL] = g.n
			arr[Mesh.ARRAY_TEX_UV] = g.uv
			arr[Mesh.ARRAY_COLOR] = g.c
			arr[Mesh.ARRAY_INDEX] = g.i
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var m0: Material = g.mat
			if m0 is BaseMaterial3D:
				var m1 := (m0 as BaseMaterial3D).duplicate() as BaseMaterial3D
				m1.albedo_color = Color.WHITE
				m1.vertex_color_use_as_albedo = true
				m1.vertex_color_is_srgb = true
				m0 = m1
			out.surface_set_material(out.get_surface_count() - 1, m0)
		out.resource_name = path.get_file().get_basename()
		_merged_cache[path] = out
		return out

	func _towers() -> void:
		if tower_xf.is_empty():
			return
		var mesh := merged(KIT + "kirchturm.glb")
		if mesh:
			_mm(mesh, tower_xf, Transform3D(), "Kirchtuerme")
		st["church_towers"] = tower_xf.size()

	## Seeufer: Uferkante (4 m) und Steine am burgnahen Ufer, Schilfgruppen im Flachwasser, zwei Bootsstege.
	## Nur Optik; je Bauteil und 160-m-Block ein MultiMesh mit Sichtweite.
	func _shore() -> void:
		if lake.size() < 3 or castle_pts.is_empty():
			return
		var lists := {}       # "teil|cx|cz" -> Array[Transform3D]
		var steg_cands: Array = []
		var walked := 0.0
		var next_reed := 0.0
		var next_stone := 10.0
		for i in lake.size():
			var a := lake[i]
			var b := lake[(i + 1) % lake.size()]
			var ln := a.distance_to(b)
			if ln < 0.5:
				continue
			var t := (b - a) / ln
			var nl := t.orthogonal()                # Richtung Land
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nl * 2.0, lake):
				nl = -nl
			var d := 0.0
			while d < ln:
				var p := a + t * d
				var s := walked + d
				d += 4.0
				var cd := _castle_near(p).distance_to(p)
				if cd > SHORE_DIST or _in_excl_tree(p):
					continue
				var r := _rnd(int(p.x * 3.0), int(p.y * 3.0))
				# Modell-x entlang des Ufers, Modell-z zum Land
				var bx := Vector3(t.x, 0, t.y)
				var bz := Vector3(nl.x, 0, nl.y)
				var basis := Basis(bx, Vector3.UP, bz)
				if basis.determinant() < 0.0:
					basis = Basis(-bx, Vector3.UP, bz)
				if cd < 110.0:
					_shore_put(lists, "kante", Transform3D(basis, Vector3(p.x, lake_y - 0.12, p.y)))
				if s >= next_reed and r.z < 0.55:
					next_reed = s + 14.0 + r.x * 18.0
					var q := p - nl * (1.5 + r.y * 3.0)
					var sc := 0.8 + 0.5 * r.w
					_shore_put(lists, "schilf", Transform3D(Basis(Vector3.UP, r.w * TAU).scaled(Vector3(sc, sc, sc)), Vector3(q.x, lake_y - 0.25, q.y)))
				if s >= next_stone:
					next_stone = s + 22.0 + r.y * 25.0
					var q2 := p + nl * 0.6
					_shore_put(lists, "steine", Transform3D(Basis(Vector3.UP, r.x * TAU), Vector3(q2.x, lake_y - 0.15, q2.y)))
				steg_cands.append([cd, p, nl])
			walked += ln
		# Stege: an der burgnächsten Uferstelle und einer zweiten ≥ 120 m davon
		steg_cands.sort_custom(func(x, y): return x[0] < y[0])
		var stege: Array = []
		for c in steg_cands:
			var far_enough := true
			for s2 in stege:
				if (s2[1] as Vector2).distance_to(c[1]) < 120.0:
					far_enough = false
			if far_enough:
				stege.append(c)
			if stege.size() >= 2:
				break
		for c in stege:
			var p: Vector2 = c[1]
			var nl: Vector2 = c[2]
			# Modell-z (Steglänge) Richtung Wasser, Landende am Ufer
			var bz := Vector3(-nl.x, 0, -nl.y)
			var bx := Vector3.UP.cross(bz)
			var q := p - nl * 2.6
			_shore_put(lists, "steg", Transform3D(Basis(bx, Vector3.UP, bz), Vector3(q.x, lake_y - 0.9, q.y)))
		var parts := {"kante": ["see_uferkante_4m.glb", 200.0], "schilf": ["see_schilf.glb", 180.0],
			"steine": ["see_ufersteine.glb", 260.0], "steg": ["see_steg_6m.glb", 700.0]}
		var counts := {}
		for lk in lists:
			var part := String(lk).get_slice("|", 0)
			var mesh := merged(KIT + String(parts[part][0]))
			if mesh == null:
				continue
			var mi := _mm(mesh, lists[lk], Transform3D(), "Ufer_" + String(lk).replace("|", "_"))
			mi.visibility_range_end = float(parts[part][1])
			mi.visibility_range_end_margin = 30.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			counts[part] = int(counts.get(part, 0)) + (lists[lk] as Array).size()
		st["shore"] = counts

	func _shore_put(lists: Dictionary, part: String, xf: Transform3D) -> void:
		var lk := "%s|%d|%d" % [part, floori(xf.origin.x / 160.0), floori(xf.origin.z / 160.0)]
		if not lists.has(lk):
			lists[lk] = []
		(lists[lk] as Array).append(xf)

	func _in_excl_tree(p: Vector2) -> bool:
		for poly in excl_tree:
			if Geometry2D.is_point_in_polygon(p, poly):
				return true
		return false

	## Ein Baukörper: Grundriss (Welt), Dachebenen aus Typ/Firstlinie, Wände bis unter die Dachkante
	func _body(acc: Acc, fpw: PackedVector2Array, cen: Vector2, b: Dictionary, g: float, eave: float, ridge: float,
			wall_c: Color, roof_c: Color, win: float) -> void:
		var fp := PackedVector2Array()
		for q in fpw:
			fp.append(q - cen)
		var planes := _planes(fp, b, cen, eave, ridge)
		var pieces: Array = []      # [poly, plane]
		if planes.size() == 1:
			pieces.append([fp, planes[0]])
		else:
			for i in planes.size():
				var cur: Array = [fp]
				for j in planes.size():
					if i == j or cur.is_empty():
						continue
					var diff: Vector3 = planes[i] - planes[j]
					var gv := Vector2(diff.x, diff.y)
					if gv.length() < 1e-5:
						if diff.z > 1e-4 or (absf(diff.z) <= 1e-4 and j < i):
							cur = []
						continue
					var hp := _halfplane(gv, diff.z)
					var nxt: Array = []
					for poly in cur:
						for r in Geometry2D.intersect_polygons(poly, hp):
							if absf(_area(r)) > 0.05:
								nxt.append(r)
					cur = nxt
				for poly in cur:
					pieces.append([poly, planes[i]])
		var flat_c := Color(0.27, 0.26, 0.25)
		var foot := g - WALL_FOOT
		var windows := win if eave - g > 2.6 else 0.0
		wall_c.a = 1.0
		for pc in pieces:
			var poly: PackedVector2Array = pc[0]
			var pl: Vector3 = pc[1]
			var gr := Vector2(pl.x, pl.y)
			var sl := gr.length()
			var gd := gr / sl if sl > 1e-3 else Vector2.RIGHT
			var stretch := sqrt(1.0 + sl * sl)
			var nrm := Vector3(-pl.x, 1.0, -pl.y).normalized()
			var kind := Vector2(1.0 if sl > 0.05 else 2.0, 0.0)
			var col := roof_c if sl > 0.05 else flat_c
			var idx := Geometry2D.triangulate_polygon(poly)
			for t in range(0, idx.size(), 3):
				var pts: Array = []
				var uvs: Array = []
				for o in 3:
					var q := poly[idx[t + o]]
					pts.append(Vector3(q.x + cen.x, _ph(pl, q), q.y + cen.y))
					uvs.append(Vector2(gd.orthogonal().dot(q), -gd.dot(q) * stretch))
				acc.tri(pts[0], pts[1], pts[2], nrm, col, uvs[0], uvs[1], uvs[2], kind)
			# Wände unter den Rändern dieses Dachstücks, die auf dem Grundriss liegen
			for i in poly.size():
				var pa := poly[i]
				var pb := poly[(i + 1) % poly.size()]
				var e := pb - pa
				var len := e.length()
				if len < 0.05 or not _on_outline(pa, pb, fp):
					continue
				var o2 := e.orthogonal().normalized()
				if Geometry2D.is_point_in_polygon((pa + pb) * 0.5 + o2 * 0.05, fp):
					o2 = -o2
				var n3 := Vector3(o2.x, 0.0, o2.y)
				var ya := _ph(pl, pa)
				var yb := _ph(pl, pb)
				var wa := Vector3(pa.x + cen.x, foot, pa.y + cen.y)
				var wb := Vector3(pb.x + cen.x, foot, pb.y + cen.y)
				var wc := Vector3(pb.x + cen.x, yb, pb.y + cen.y)
				var wd := Vector3(pa.x + cen.x, ya, pa.y + cen.y)
				# Fenster mittig je Wandstück (Raster 3,2 m)
				var u0 := -fposmod(len, 3.2) * 0.5
				var k2 := Vector2(0.0, windows if len > 2.4 else 0.0)
				var ua := Vector2(u0, foot - g)
				var ub := Vector2(u0 + len, foot - g)
				acc.tri(wa, wb, wc, n3, wall_c, ua, ub, Vector2(u0 + len, yb - g), k2)
				acc.tri(wa, wc, wd, n3, wall_c, ua, Vector2(u0 + len, yb - g), Vector2(u0, ya - g), k2)

	static func _on_outline(pa: Vector2, pb: Vector2, fp: PackedVector2Array) -> bool:
		var mid := (pa + pb) * 0.5
		var e := (pb - pa).normalized()
		for i in fp.size():
			var a := fp[i]
			var b := fp[(i + 1) % fp.size()]
			var q := Geometry2D.get_closest_point_to_segment(mid, a, b)
			if q.distance_to(mid) < 0.06 and absf(e.cross((b - a).normalized())) < 0.05:
				return true
		return false

	# ------------------------------------------------------------------ Bäume
	## Kopie des EZ-Tree-Kreuzbillboards (eztree_impostor.gdshader) mit Ausblenden je Instanz: Nahbäume
	## (INSTANCE_CUSTOM.r = 1) verschwinden unter hide_dist Kameraabstand, dort steht der 3D-Baum (LOD3).
	const IMPOSTOR_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_cut = 0.5;
uniform float translucency = 0.3;
uniform float hide_dist = 52.0;
varying vec2 quad_uv;
void vertex() {
	quad_uv = UV2;
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	if (INSTANCE_CUSTOM.r > 0.5 && distance(org.xz, cam.xz) < hide_dist) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb * mix(0.75, 1.0, clamp(quad_uv.y * 1.4, 0.0, 1.0));
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	vec3 n = NORMAL;
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec3 side = normalize(cross(n, up));
	NORMAL = normalize(n + side * (quad_uv.x - 0.5) * 1.6 + up * max((quad_uv.y - 0.45) * 1.2, 0.0) * 0.8);
	BACKLIGHT = c.rgb * translucency;
}
"""

	func _trees() -> void:
		var keys: Array = []
		for k in TREE_KEYS:
			if EzTree.has_impostor(k):
				keys.append(k)
		if keys.is_empty():
			st["trees"] = 0
			print("CASTLE_BACKDROP: keine Baum-Impostoren vorhanden – Wald entfällt")
			return
		var imp := {}              # "cx|cz|key" -> [Array[Transform3D], PackedByteArray Nahbaum]
		var near3d := {}           # "cx|cz|key" -> Array[Transform3D]
		var count := 0
		var near := 0
		# 1) Datenraster: Hangwald, Waldflecken, Hecken-/Baumreihen; offene Wiesen bleiben frei. Raster 6 m mit Streuung.
		var step := 3
		for j in range(0, rows - 1, step):
			for i in range(0, cols - 1, step):
				var r := _rnd(i, j)
				var p := Vector2(ox + (i + r.x * 2.6) * cell, oz + (j + r.y * 2.6) * cell)
				var fi := clampi(int((p.x - ox) / (cell * FINE_STEP)), 0, fcols - 1)
				var fj := clampi(int((p.y - oz) / (cell * FINE_STEP)), 0, frows - 1)
				var flags := tmask[fj * fcols + fi]
				if flags & 3 or mask[fj * fcols + fi]:
					continue
				var k := j * cols + i
				if C[k] == 2 or C[k] == 3 or in_water(p) > 0:
					continue
				var hx := hd(p.x + 2.0, p.y) - hd(p.x - 2.0, p.y)
				var hz := hd(p.x, p.y + 2.0) - hd(p.x, p.y - 2.0)
				var prob := _tree_prob(p, Vector2(hx, hz).length() / 4.0, (flags & 4) != 0)
				if r.z > prob:
					continue
				var is_near := (flags & 8) != 0
				var key: String = keys[int(r.w * 997.0) % keys.size()]
				_put(imp, near3d, key, Vector3(p.x, gy(p.x, p.y) - 0.15, p.y), r, is_near)
				count += 1
				if is_near:
					near += 1
		# 2) Ferngelände: Waldflecken und Baumreihen auf den Hügeln (nur Impostor), 15 m Raster
		var fstep := 13.0
		var nn := int(2.0 * (R_FAR - 100.0) / fstep)
		for j in nn:
			for i in nn:
				var r := _rnd(i + 5000, j + 5000)
				var p := center - Vector2(R_FAR - 100.0, R_FAR - 100.0) + (Vector2(i, j) + Vector2(r.x, r.y)) * fstep
				if in_data(p.x, p.y) or p.distance_to(center) > R_FAR - 60.0:
					continue
				if r.z > _tree_prob(p, 0.0, false, false):
					continue
				if far_occ.has(Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))) or in_water(p) > 0:
					continue
				var key: String = keys[int(r.w * 997.0) % keys.size()]
				_put(imp, near3d, key, Vector3(p.x, coarse_h(p) - 0.3, p.y), r, false, 1.35)
				count += 1
		# 3) MultiMeshes
		var imp_mats := {}
		var lod := {}
		for key in keys:
			var src := EzTree.impostor_mesh(key)
			var mat := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = IMPOSTOR_SHADER
			mat.shader = sh
			var om := src.surface_get_material(0) as ShaderMaterial if src else null
			if om:
				mat.set_shader_parameter("atlas", om.get_shader_parameter("atlas"))
			mat.set_shader_parameter("hide_dist", IMP_HIDE)
			imp_mats[key] = [src, mat]
			var tmpl := EzTree.load_template(key)
			var parts: Array = []
			if tmpl:
				for mi in tmpl.find_children("*", "MeshInstance3D", true, false):
					var xf := Transform3D()
					var nd: Node = mi
					while nd != tmpl and nd != null:
						xf = (nd as Node3D).transform * xf
						nd = nd.get_parent()
					parts.append([EzTree.lod_mesh((mi as MeshInstance3D).mesh, 3), xf])
				tmpl.free()
			lod[key] = parts
		var batches := 0
		for lk in imp:
			var key := String(lk).get_slice("|", 2)
			var e: Array = imp[lk]
			var mi := _mm(imp_mats[key][0], e[0], Transform3D(), "Wald_" + String(lk).replace("|", "_"), e[1])
			mi.material_override = imp_mats[key][1]
			batches += 1
		for lk in near3d:
			var key := String(lk).get_slice("|", 2)
			for part in lod[key]:
				var g := _mm(part[0], near3d[lk], part[1], "Wald3D_" + String(lk).replace("|", "_"))
				g.visibility_range_end = NEAR_3D_END
				g.visibility_range_end_margin = 10.0
				g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				batches += 1
		st["trees"] = count
		st["trees_near"] = near
		st["tree_batches"] = batches

	## Baumdichte: Hänge bewaldet, Waldflecken, schmale Hecken-/Baumreihen (Rauschen-Isolinie), sonst offen.
	func _tree_prob(p: Vector2, slope: float, town: bool, hedges := true) -> float:
		var prob := 0.0
		if slope > 0.3:
			prob = 0.85
		elif noise.get_noise_2dv(p * 0.8) > 0.2:
			prob = 0.8
		elif hedges and absf(hedge.get_noise_2dv(p)) < 0.022 and not town:
			prob = 0.6
		if town and slope <= 0.3:
			prob = minf(prob, 0.05)
		return prob

	func _put(imp: Dictionary, near3d: Dictionary, key: String, pos: Vector3, r: Vector4, is_near: bool, sk := 1.0) -> void:
		var s := EzTree.model_scale(key, (0.85 + 0.4 * fposmod(r.w * 7.13, 1.0)) * sk)
		var xf := Transform3D(Basis(Vector3.UP, r.w * TAU * 13.0).scaled(Vector3(s, s, s)), pos)
		var lk := "%d|%d|%s" % [floori(pos.x / FAR_CHUNK), floori(pos.z / FAR_CHUNK), key]
		if not imp.has(lk):
			imp[lk] = [[], []]
		(imp[lk][0] as Array).append(xf)
		(imp[lk][1] as Array).append(1 if is_near else 0)
		if is_near:
			var nk := "%d|%d|%s" % [floori(pos.x / NEAR_CHUNK), floori(pos.z / NEAR_CHUNK), key]
			if not near3d.has(nk):
				near3d[nk] = []
			(near3d[nk] as Array).append(xf)

	func _mm(mesh: Mesh, list: Array, part: Transform3D, nm: String, near_flags: Array = []) -> MultiMeshInstance3D:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = not near_flags.is_empty()
		mm.mesh = mesh
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, (list[k] as Transform3D) * part)
			if mm.use_custom_data:
				mm.set_instance_custom_data(k, Color(float(near_flags[k]), 0, 0, 0))
		var mi := MultiMeshInstance3D.new()
		mi.name = nm
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mi)
		return mi

	## Deterministische Zufallswerte je Rasterpunkt (x, z Versatz, Wahrscheinlichkeit, Art/Drehung)
	static func _rnd(i: int, j: int) -> Vector4:
		var out := Vector4()
		for c in 4:
			var h := absf(sin(i * 12.9898 + j * 78.233 + c * 37.719) * 43758.5453)
			out[c] = h - floorf(h)
		return out
