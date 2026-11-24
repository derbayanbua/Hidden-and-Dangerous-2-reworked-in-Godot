extends RefCounted
## Bäume aus dem Baumgenerator EZ-Tree (MIT, Copyright (c) 2024 Daniel Greenheck) für Bavaria.
## GLBs/Texturen: assets/maps/bavaria/trees_eztree/ (Erzeugung und Lizenzen siehe SOURCES.txt dort).
## Je GLB: Knoten „tree“ (Rinde) + „leaves“ (Laubkarten) in voller Stufe, dazu „tree_lod1..3“ + „leaves_lod1..3“
## (EZ-Tree-LOD: weniger Ringe/Segmente, jede 2./3./9. Laubkarte). Die LOD-Meshes hängen als Meta „ez_lod1..3“ am
## Vollmesh. Verwendung: Kartenbäume (MultiMesh) LOD1, Randsaum/Gürtel LOD2, dichter Außenwald LOD3; volle Stufe
## nur bei Einzelaufstellung (Godot-Mesh-LOD greift dort zusätzlich).
## Schalter `--eztree=0`: alte Originalbäume (Vergleich).

const DIR := "res://assets/maps/bavaria/trees_eztree/"
const SHADER := preload("res://src/maps/bavaria/eztree_wind.gdshader")

## Modellhöhe [m] je Variante (wie in der Erzeugung normiert, Stammfuß im Ursprung).
const HEIGHTS := {
	"ez_spruce_s": 10.0, "ez_spruce_m": 13.0, "ez_spruce_l": 16.0,
	"ez_beech_s": 8.0, "ez_beech_m": 11.0, "ez_beech_l": 14.0,
	"ez_oak_s": 8.0, "ez_oak_m": 11.0, "ez_oak_l": 14.0,
	"ez_birch_s": 8.0, "ez_birch_m": 11.0, "ez_birch_l": 14.0,
	"ez_fruit_s": 5.0, "ez_fruit_m": 6.5,
}
## Zielhöhe [m] je Art bei Platzierungsmaßstab 1 (Originalbaum l_tree ≈ 10 m).
const REF := {"spruce": 14.0, "beech": 12.0, "oak": 11.0, "birch": 12.5, "fruit": 6.5}
## Mischung je Ort: Waldsaum innen Laub/Birke mit Fichten, Höfe/Gärten Obstbäume.
## Birke (lichte Krone, wenige Laubkarten) nur noch als Beimischung; Höfe/Gärten Obstbäume mit Buche/Eiche (Hausbaum).
const MIX := {
	"wood": [["spruce", 35], ["beech", 25], ["oak", 25], ["birch", 15]],
	"garden": [["fruit", 60], ["beech", 20], ["oak", 20]],
	"vista": [["spruce", 60], ["birch", 40]],
}
## Laubfarbe (11/2026): gedecktes Sommer-Olivgrün statt Neon-Grün der Laubkarten; Fichte dunkel-blaugrün.
const LEAF_TINT := {"spruce": Color(0.6, 0.7, 0.56), "beech": Color(0.82, 0.9, 0.64), "oak": Color(0.76, 0.84, 0.58),
	"birch": Color(0.9, 0.96, 0.68), "fruit": Color(0.8, 0.9, 0.62)}
## Tönung, mit der die Impostor-Atlanten gerendert wurden (Impostor = neue/alte Tönung → gleiche Farbe beim Übergang).
const IMPOSTOR_RENDER_TINT := {"spruce": Color(0.78, 0.86, 0.74), "beech": Color(0.92, 0.98, 0.86), "oak": Color(0.9, 0.95, 0.85),
	"birch": Color(1.0, 1.05, 0.92), "fruit": Color(0.95, 1.0, 0.9)}
const LEAF_SATURATION := 0.82
## Krone je Art (Anteile der Modellhöhe tree_height): Mitte, Halbmesser – für Kronen-Normalen und Verschattung.
const CROWN := {"spruce": [0.45, 0.3], "beech": [0.62, 0.3], "oak": [0.58, 0.34], "birch": [0.66, 0.22], "fruit": [0.62, 0.38]}
const BARK_TINT := {"birch": Color(0.88, 0.86, 0.82), "spruce": Color(0.8, 0.76, 0.72)}

static var _enabled := -1
static var _mats := {}

static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 1 if String(Game.cli.get("eztree", "1")) != "0" and ResourceLoader.exists(DIR + "ez_spruce_m.glb") else 0
	return _enabled == 1

static func is_key(key: String) -> bool:
	return key.begins_with("ez_")

static func species_of(key: String) -> String:
	return key.get_slice("_", 1)

## Deterministische Wahl aus Lage und Maßstab (kein RandomNumberGenerator → Zufallsmuster der Karte unverändert).
static func pick(context: String, pos: Vector3, scale_value: float) -> String:
	var h := absf(sin(pos.x * 12.9898 + pos.z * 78.233) * 43758.5453)
	h -= floorf(h)
	var mix: Array = MIX.get(context, MIX["wood"])
	var total := 0.0
	for e in mix:
		total += float(e[1])
	var x := h * total
	var sp: String = mix[0][0]
	for e in mix:
		x -= float(e[1])
		if x < 0.0:
			sp = e[0]
			break
	# Größenstufe nur nach Maßstab, ohne Streuung (wenige MultiMesh-Gruppen = wenige Zeichenaufrufe).
	var v := "s" if scale_value < 0.8 else ("m" if scale_value < 1.15 or sp == "fruit" else "l")
	return "ez_%s_%s" % [sp, v]

## Maßstab des Modells, damit die Endhöhe = Platzierungsmaßstab × Arthöhe ist.
static func model_scale(key: String, scale_value: float) -> float:
	return scale_value * float(REF[species_of(key)]) / float(HEIGHTS[key])

## Vorlage laden: nur volle Stufe als Knoten, LOD-Meshes als Meta am Vollmesh, Materialien gesetzt.
static func load_template(key: String) -> Node3D:
	var path := DIR + key + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate() as Node3D
	var by_name := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		by_name[String(mi.name)] = mi
	var sp := species_of(key)
	for part in ["tree", "leaves"]:
		var full: MeshInstance3D = by_name.get(part)
		if full == null:
			continue
		var mat := material(sp, part == "leaves", float(HEIGHTS[key]))
		_prepare(full.mesh, mat, key + "_" + part)
		for lod in [1, 2, 3]:
			var lmi: MeshInstance3D = by_name.get("%s_lod%d" % [part, lod])
			if lmi == null:
				continue
			_prepare(lmi.mesh, mat, "%s_%s_lod%d" % [key, part, lod])
			full.mesh.set_meta("ez_lod%d" % lod, lmi.mesh)
			lmi.get_parent().remove_child(lmi)
			lmi.free()
		full.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if part == "leaves" and clumps_enabled():
			# Volumen-Laub (11/2026): je Laubkarte der gröberen Stufe ein räumlicher Büschel aus drei gekreuzten Karten
			# (zufällig gedreht, Normalen kugelförmig von der Kronenmitte). Nah: Büschel aus LOD1, fern: aus LOD2;
			# LOD2/LOD3 (Randgürtel, Außenwald, Schatten) bleiben flache Karten.
			var src: Mesh = full.mesh
			var l1: Mesh = src.get_meta("ez_lod1", src)
			var l2: Mesh = src.get_meta("ez_lod2", l1)
			var l3: Mesh = src.get_meta("ez_lod3", l2)
			var crown: Array = CROWN.get(sp, [0.6, 0.3])
			var c := Vector3(0, float(crown[0]) * float(HEIGHTS[key]), 0)
			var leaf_mat := material(sp, true, float(HEIGHTS[key]))
			# Dreiecksbudget: Büschel aus LOD2-Karten (≈ 1/3 der Karten, dafür größer) nah, aus LOD3 fern
			# Kronenhülle (Runde 3): nah aus LOD1 (je Karte 2 Hüllkarten ≈ Budget vorher 3 × LOD2), fern aus LOD2
			var dim := 0.8 if sp in ["birch", "fruit"] else 0.92    # helle Arten wirkten von oben grellgelb
			var near := clump_mesh(l1, c, 1.15, false, leaf_mat, dim)
			near.resource_name = src.resource_name
			near.set_meta("ez_lod1", clump_mesh(l2, c, 1.45, false, leaf_mat, dim))
			(near.get_meta("ez_lod1") as Mesh).resource_name = src.resource_name + "_lod1"
			near.set_meta("ez_lod2", l2)
			near.set_meta("ez_lod3", src.get_meta("ez_lod3", l2))
			full.mesh = near
	# Doppelte LOD-Knoten im GLB (gleicher Name an anderer Stelle) entfernen: sie blieben sonst als zusätzliche, immer
	# sichtbare Laubkarten mit dem unvorbereiteten glTF-Material stehen (weiße/grelle Kartenflächen in der Krone).
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if is_instance_valid(mi) and String(mi.name) not in ["tree", "leaves"]:
			mi.get_parent().remove_child(mi)
			mi.free()
	root.name = key
	return root

static var _clumps := -1
## Schalter `--leaf_clumps=0`: flache Original-Laubkarten (Vergleich).
static func clumps_enabled() -> bool:
	if _clumps < 0:
		_clumps = 0 if String(Game.cli.get("leaf_clumps", "1")) == "0" else 1
	return _clumps == 1

## Laubkarten → räumliche Büschel. Je Karte (Dreieckspaar) drei senkrecht zueinander stehende Karten gleicher Fläche
## (size_k × Kartenkante) um den Kartenmittelpunkt, Drehung deterministisch je Karte; UV = UV-Ausschnitt der Karte.
## Normalen zeigen von `center` (Kronenmitte, Modellraum) nach außen → die Krone wird als Masse beleuchtet.
## only_alpha: nur Oberflächen mit Alpha-Material umbauen (Bibliotheksmodelle), übrige unverändert übernehmen.
static func clump_mesh(src: Mesh, center: Vector3, size_k := 0.9, only_alpha := false, override: Material = null, dim := 1.0) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.set_meta("no_auto_lod", true)     # PerfTuning._generate_lods würde die Büschel zu UV-verschmierten Flächen verschmelzen
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var mat: Material = override if override else src.surface_get_material(s)
		var prim := Mesh.PRIMITIVE_TRIANGLES
		if src is ArrayMesh:
			prim = (src as ArrayMesh).surface_get_primitive_type(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		if prim != Mesh.PRIMITIVE_TRIANGLES or uvs == null or (only_alpha and not _is_alpha(mat)):
			out.add_surface_from_arrays(prim, arr)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			continue
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var pv := PackedVector3Array()
		var pn := PackedVector3Array()
		var pu := PackedVector2Array()
		var pc := PackedColorArray()
		var pi := PackedInt32Array()
		var card := 0
		var t := 0
		while t + 5 < idx.size():
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			var uv_lo := Vector2(INF, INF)
			var uv_hi := -uv_lo
			var mid := Vector3.ZERO
			for k in 6:
				var v: Vector3 = verts[idx[t + k]]
				var u: Vector2 = uvs[idx[t + k]]
				lo = lo.min(v)
				hi = hi.max(v)
				uv_lo = uv_lo.min(u)
				uv_hi = uv_hi.max(u)
				mid += v
			mid /= 6.0
			var diag := 0.0
			for a in 6:
				for b in range(a + 1, 6):
					diag = maxf(diag, (verts[idx[t + a]] as Vector3).distance_to(verts[idx[t + b]]))
			t += 6
			var half := diag * 0.7071 * size_k * 0.5
			if half <= 0.0001:
				continue
			var h1 := fposmod(sin(float(card) * 12.9898 + mid.x) * 43758.5453, 1.0)
			var h2 := fposmod(sin(float(card) * 78.233 + mid.z) * 24634.6345, 1.0)
			var h3 := fposmod(sin(float(card) * 39.425 + mid.y) * 17431.123, 1.0)
			card += 1
			var nrm := (mid - center)
			var dist := nrm.length()
			nrm = nrm / dist if dist > 0.01 else Vector3.UP
			# Kronenhülle (Runde 3): Karten liegen tangential zur Krone (Normale radial, Neigung ≤ ~40°, Drehung frei)
			# → schuppige, geschlossene Oberfläche statt sternförmiger Kreuzkarten. Zwei versetzte Lagen je Karte,
			# innere Lage dunkler (Vertexfarbe: Tiefe + Streuung je Karte).
			var side := nrm.cross(Vector3.UP if absf(nrm.y) < 0.95 else Vector3.RIGHT).normalized()
			for q in 2:
				var tilt := Basis(side, (h1 - 0.5) * 1.4).rotated(nrm, (h2 + float(q) * 0.37) * TAU)
				var n0: Vector3 = (tilt * nrm).normalized()
				var ax: Vector3 = n0.cross(side).normalized()
				if ax.length() < 0.1:
					ax = n0.cross(Vector3.FORWARD).normalized()
				ax = ax.rotated(n0, (h3 + float(q) * 0.5) * TAU)
				var ay: Vector3 = n0.cross(ax).normalized()
				var off := nrm * (0.18 if q == 0 else -0.28) * half + ax * (h2 - 0.5) * half * 0.6
				var hq := half * (1.0 if q == 0 else 0.85)
				var shade := clampf(0.78 + 0.22 * (dist / maxf(dist + half, 0.01)) + (h3 - 0.5) * 0.16, 0.6, 1.08) * (1.0 if q == 0 else 0.8) * dim
				var col := Color(shade * (0.97 + h1 * 0.06), shade, shade * (0.94 + h2 * 0.08))
				var base := pv.size()
				for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var p: Vector3 = mid + off + (ax * corner.x + ay * corner.y) * hq
					pv.append(p)
					var n: Vector3 = p - center
					pn.append((n.normalized() if n.length() > 0.01 else nrm).lerp(nrm, 0.5).normalized())
					pc.append(col)
					pu.append(Vector2(lerpf(uv_lo.x, uv_hi.x, corner.x * 0.5 + 0.5), lerpf(uv_hi.y, uv_lo.y, corner.y * 0.5 + 0.5)))
				pi.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		if pv.is_empty():
			continue
		var na := []
		na.resize(Mesh.ARRAY_MAX)
		na[Mesh.ARRAY_VERTEX] = pv
		na[Mesh.ARRAY_NORMAL] = pn
		na[Mesh.ARRAY_TEX_UV] = pu
		na[Mesh.ARRAY_COLOR] = pc
		na[Mesh.ARRAY_INDEX] = pi
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
		var m2 := mat
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_DISABLED:
			m2 = mat.duplicate()
			(m2 as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		out.surface_set_material(out.get_surface_count() - 1, m2)
	return out

static func _is_alpha(mat: Material) -> bool:
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	return mat is ShaderMaterial

static func _prepare(mesh: Mesh, mat: Material, res_name: String) -> void:
	if mesh == null:
		return
	mesh.resource_name = res_name
	for s in mesh.get_surface_count():
		mesh.surface_set_material(s, mat)

## Gemeinsames Material je Art/Teil (ein Material je Art → wenige Zeichenaufrufe).
static func material(sp: String, leaf: bool, height: float) -> ShaderMaterial:
	var k := "%s|%s" % [sp, leaf]
	if _mats.has(k):
		return _mats[k]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = ("leaves_" if leaf else "bark_") + sp
	if leaf:
		m.set_shader_parameter("albedo_tex", load(DIR + "leaves_%s.png" % sp))
		m.set_shader_parameter("use_normal", false)
		m.set_shader_parameter("is_leaf", true)
		m.set_shader_parameter("tint", LEAF_TINT.get(sp, Color.WHITE))
		m.set_shader_parameter("roughness_value", 0.85)
		m.set_shader_parameter("alpha_cut", 0.4 if sp == "spruce" else 0.45)
		var crown: Array = CROWN.get(sp, [0.6, 0.3])
		m.set_shader_parameter("crown_center", crown[0])
		m.set_shader_parameter("crown_radius", crown[1])
		m.set_shader_parameter("crown_normal", 0.75)
		m.set_shader_parameter("crown_ao", 1.0)
		m.set_shader_parameter("color_vary", 0.18)
		m.set_shader_parameter("saturation", LEAF_SATURATION)
		m.set_shader_parameter("edge_fade", 0.4)
		m.set_shader_parameter("translucency", 0.4)
	else:
		m.set_shader_parameter("albedo_tex", load(DIR + "bark_%s_albedo.jpg" % sp))
		m.set_shader_parameter("normal_tex", load(DIR + "bark_%s_normal.png" % sp))
		m.set_shader_parameter("roughness_value", 0.95)
		m.set_shader_parameter("tint", BARK_TINT.get(sp, Color(0.85, 0.82, 0.78)))
		m.set_shader_parameter("color_vary", 0.14)
		m.set_shader_parameter("saturation", 0.9)
		m.set_shader_parameter("base_dark", 1.0)
		m.set_shader_parameter("base_height", 0.7)
	# Gleiche Biegung für Rinde und Laub derselben Art (Laub bleibt an den Ästen).
	m.set_shader_parameter("tree_height", 12.0 if sp != "fruit" else 6.0)
	m.set_shader_parameter("sway", 0.012 if sp == "spruce" else 0.018)
	m.set_shader_parameter("flutter", 0.0 if sp == "spruce" else 0.03)
	_mats[k] = m
	return m

## ---- Impostor (ferne Bäume als Kreuz-Billboard) ----
const IMPOSTOR_DIR := DIR + "impostor/"
const IMPOSTOR_SHADER := preload("res://src/maps/bavaria/eztree_impostor.gdshader")
## Ab dieser Kamera-Entfernung [m] (Blockmitte) Impostor statt 3D; weicher Übergang über IMPOSTOR_FADE.
const IMPOSTOR_DIST := 70.0
const IMPOSTOR_FADE := 12.0
static var _imp_sizes := {}
static var _imp_meshes := {}

## Kantenlänge des quadratischen Ausschnitts (gleiche Formel beim Rendern und beim Quad).
static func impostor_size(tree: Node3D) -> float:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi in tree.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).mesh.get_aabb()
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	var r := maxf(maxf(absf(lo.x), absf(hi.x)), maxf(absf(lo.z), absf(hi.z)))
	return maxf(hi.y, 2.0 * r) * 1.04

static func has_impostor(key: String) -> bool:
	return is_key(key) and ResourceLoader.exists(IMPOSTOR_DIR + key + ".png")

## Zwei gekreuzte Quads im Modellraum des Baums (Stammfuß im Ursprung), Atlas links vorn (+Z), rechts Seite (+X).
static func impostor_mesh(key: String) -> Mesh:
	if _imp_meshes.has(key):
		return _imp_meshes[key]
	if _imp_sizes.is_empty() and FileAccess.file_exists(IMPOSTOR_DIR + "impostors.json"):
		_imp_sizes = JSON.parse_string(FileAccess.get_file_as_string(IMPOSTOR_DIR + "impostors.json"))
	if not _imp_sizes.has(key) or not has_impostor(key):
		return null
	var s := float(_imp_sizes[key])
	var y0 := -0.02 * s
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for view in 2:
		# vorn: u → +X, Normale +Z; Seite (Kamera bei +X): u → −Z, Normale +X
		var right := Vector3(1, 0, 0) if view == 0 else Vector3(0, 0, -1)
		var nrm := Vector3(0, 0, 1) if view == 0 else Vector3(1, 0, 0)
		var u0 := 0.5 * view
		var corners := [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]
		for idx in [0, 1, 2, 0, 2, 3]:
			var c: Array = corners[idx]
			st.set_normal(nrm)
			st.set_tangent(Plane(right, 1.0))
			st.set_uv(Vector2(u0 + 0.5 * c[0], 1.0 - c[1]))
			st.set_uv2(Vector2(c[0], c[1]))
			st.add_vertex(right * (c[0] - 0.5) * s + Vector3(0, y0 + c[1] * s, 0))
	var mesh := st.commit()
	mesh.resource_name = key + "_impostor"
	# Begrenzung = echte Baumbox (die Quads sind quadratisch und außen durchsichtig): Culling/Sichtprüfungen wie beim 3D-Baum
	var tmpl := load_template(key)
	if tmpl:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for mi in tmpl.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = lod_mesh((mi as MeshInstance3D).mesh, 3).get_aabb()     # wie die bisherige LOD3-Ferngeometrie
			lo = lo.min(b.position)
			hi = hi.max(b.end)
		tmpl.free()
		mesh.custom_aabb = AABB(lo, hi - lo)
	var m := ShaderMaterial.new()
	m.shader = IMPOSTOR_SHADER
	m.resource_name = "impostor_" + key
	m.set_shader_parameter("atlas", load(IMPOSTOR_DIR + key + ".png"))
	var sp := species_of(key)
	var now: Color = LEAF_TINT.get(sp, Color.WHITE)
	var was: Color = IMPOSTOR_RENDER_TINT.get(sp, Color.WHITE)
	# Atlas enthält Rinde + Laub; mittlere Abdunklung wie beim Laub (Rinde ist im Fernbild klein)
	m.set_shader_parameter("tint", Color(now.r / was.r, now.g / was.g, now.b / was.b) * 0.92)
	m.set_shader_parameter("saturation", LEAF_SATURATION)
	mesh.surface_set_material(0, m)
	_imp_meshes[key] = mesh
	return mesh

## LOD-Mesh zu einem Vollmesh (EZ-Tree), sonst das Mesh selbst.
static func lod_mesh(mesh: Mesh, level: int) -> Mesh:
	if mesh != null and mesh.has_meta("ez_lod%d" % level):
		return mesh.get_meta("ez_lod%d" % level)
	return mesh
