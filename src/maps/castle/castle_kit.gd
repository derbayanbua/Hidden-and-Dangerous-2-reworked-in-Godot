extends RefCounted
## Castle: Burgbaukasten (eigene freie Module, assets/maps/castle/kit/, Herkunft SOURCES.txt). Sichtbares als
## MultiMesh je Modellteil, Kollision als eigene Kisten nach den Modulmaßen (Wand 4 × 4 × 0,85 m, Wehrgang auf der
## Innenseite +Z in 3,7–3,9 m, Turm 8 × 8 m mit Tür auf −Z, Tor 8 m mit 4,4 m Durchlass).
## Castle modular kit placement: walls with wall-walk, towers with ladder to the top platform, gates, stairs.

const MeshBatch := preload("res://src/maps/castle/castle_mesh.gd")
const DIR := "res://assets/maps/castle/kit/models/"
const WALK_Y := 3.9
const TOWER_TOP := 12.0

class CastleLadder extends OrigInteractive.OrigLadder:
	# Erst senkrecht am Fuß hinauf, dann auf die Plattform (wie die Leitern der Testkarte Bavaria)
	func climb(s: Soldier) -> void:
		if s.is_climbing():
			return
		var dest := bottom if at_top else top
		var corner := Vector3(bottom.x, top.y + 0.25, bottom.z)
		s.start_path_climb(s.global_position, corner, dest, absf(top.y - bottom.y) / 1.2 + 0.6)
		_rung_sounds(s, absf(top.y - bottom.y) / 1.2)
		used.emit(s)

var _parts := {}        # Modell → Array von [Mesh, lokale Transform]
var _xf := {}           # Modell → Array[Transform3D]
var stats := {"walls": 0, "walk": 0, "cross": 0, "towers": 0, "gates": 0, "closed_gates": 0, "stairs": 0, "tower_stairs": 0,
	"ladders": 0, "missing": []}
var closed_gates: Array = []    # Vector3 geschlossene Tore
var found_mat := "c_wall"       # Fundamente/Sockel unter Bausatzteilen (Stützmauer-Material, wenn vorhanden)
var gate_axes: Array = []       # Vector3 Durchgangsachse je gate_points-Eintrag des Bausatzes
var col := MeshBatch.new()      # Kollision + eigene Ergänzungen (Fundamente, Treppen, Leitern)
var towers: Array = []          # {pos: Vector3, top: Vector3, id}
var stairs_at: Array = []       # Vector3 oberer Austritt
var walk_points: Array = []     # Vector3 Wehrgangpunkte (Prüfung/Bilder)
var gate_points: Array = []     # Vector3 Tordurchgänge


func _model(name: String) -> Array:
	if _parts.has(name):
		return _parts[name]
	var out: Array = []
	var path := DIR + name + ".glb"
	if ResourceLoader.exists(path):
		var root := (load(path) as PackedScene).instantiate()
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var t: Transform3D = (mi as MeshInstance3D).transform
			var p := mi.get_parent()
			while p != null and p != root:
				if p is Node3D:
					t = (p as Node3D).transform * t
				p = p.get_parent()
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			# Flächen ohne Material, nur mit Vertexfarben (Packs 17/18: Kaminkörper, Torrahmen, Kriegsdeko …) →
			# Vertexfarb-Material je Fläche (Kopie des Meshes; texturierte Flächen bleiben unverändert)
			var name_key := String(mi.name) + "|" + (mesh.resource_name if mesh else "")
			if mesh is ArrayMesh:
				var dup: ArrayMesh = null
				for si in mesh.get_surface_count():
					# der glTF-Import setzt für Flächen ohne Material ein untexturiertes Standardmaterial (weiß) → wie „ohne“
					var mat := mesh.surface_get_material(si) as BaseMaterial3D
					var plain: bool = mat == null or (mat.albedo_texture == null and not mat.vertex_color_use_as_albedo)
					if plain and ((mesh as ArrayMesh).surface_get_format(si) & Mesh.ARRAY_FORMAT_COLOR) != 0:
						if dup == null:
							dup = mesh.duplicate() as ArrayMesh
						dup.surface_set_material(si, _vc_material())
				if dup != null:
					mesh = dup
			out.append([mesh, t, name_key])
		root.free()
	else:
		stats.missing.append(path)
	_parts[name] = out
	return out


## Modell → Materialschlüssel (LevelBuilder._mats) statt der flachen Vertexfarbe (Torrahmen aus Pack 17: Quader ohne UV)
const MAT_OVERRIDE := {"erdgeschoss_tor_durchgang_8m": "c_wall"}


## skip: Teile, deren Knoten-/Meshname eine dieser Zeichenfolgen enthält, entfallen (z. B. Geschossboden)
func place(name: String, xf: Transform3D, skip: Array = []) -> void:
	var parts := _model(name)
	for k in parts.size():
		if skip.any(func(s): return String(parts[k][2]).contains(s)):
			continue
		var key := "%s#%d" % [name, k]
		if not _xf.has(key):
			_xf[key] = []
		_xf[key].append(xf)


func commit(parent: Node3D, lb: LevelBuilder) -> void:
	for key in _xf:
		var name: String = String(key).get_slice("#", 0)
		var k := int(String(key).get_slice("#", 1))
		var part: Array = _parts[name][k]
		var list: Array = _xf[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, (list[i] as Transform3D) * (part[1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kit_%s_%d" % [name, k]
		mmi.multimesh = mm
		# Modelle ohne Textur/UV (nur eine Vertexfarbe je Teil) wirken als flache Farbfläche → Burgmaterial (Welt-Triplanar)
		var ov: String = MAT_OVERRIDE.get(name, "")
		if ov != "" and lb._mats.has(ov):
			mmi.material_override = lb._mats[ov]
		parent.add_child(mmi)
	var n := col.commit(parent, "KitCollision", lb, true)
	n.add_to_group("castle_kit")


var _aabb := {}

## Hüllquader eines Modells (Modellkoordinaten), leer wenn das Modell fehlt
func model_aabb(name: String) -> AABB:
	if _aabb.has(name):
		return _aabb[name]
	var box := AABB()
	var first := true
	for part in _model(name):
		if part[0] == null:
			continue
		var bb: AABB = (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	_aabb[name] = box
	return box


## Requisit mit einfacher Kistenkollision (Hüllquader × shrink); false wenn das Modell fehlt
func prop(name: String, xf: Transform3D, collide := true, shrink := 0.85) -> bool:
	if _model(name).is_empty():
		return false
	place(name, xf)
	if collide:
		var bb := model_aabb(name)
		var size := bb.size * Vector3(shrink, 1.0, shrink)
		var sc := xf.basis.get_scale()
		col.box(Transform3D(xf.basis.orthonormalized(), xf * bb.get_center()), size * sc, "c_wood", false, true)
	stats.props = int(stats.get("props", 0)) + 1
	return true


## Wendeltreppe (Pack 18, 24 Stufen à 18°, eine Umdrehung ≈ 3,1 m) auf Geschossboden y0 (lokal) mit Höhe h:
## sichtbares Modell + eigene Kollision (dünne Stufenplatten, Mittelsäule, Austrittsstufe 25 auf Geschosshöhe)
func _spiral(b: Basis, o: Vector3, y0: float, h: float) -> void:
	var sy := h / 4.0
	place("turm_wendeltreppe_stein", Transform3D(b * Basis.from_scale(Vector3(1, sy, 1)), o + b * Vector3(0, y0, 0)))
	for i in range(1, 26):
		var a := -deg_to_rad(18.0) * (i - 1)
		var top := y0 + (0.32 + (i - 1) * 0.1563) * sy
		var dir := Vector3(cos(a), 0, sin(a))
		var lb := Basis(Vector3.UP, -a)
		col.box(Transform3D(b * lb, o + b * (dir * 1.1 + Vector3(0, top - 0.3, 0))), Vector3(1.9, 0.6, 0.62), "c_steps", i == 25, true)
	col.box(Transform3D(b, o + b * Vector3(0, y0 + h * 0.5, 0)), Vector3(0.48, h, 0.48), "c_stone", false, true)


## Turmausstattung (Pack 18) im Erdgeschoss: Tisch, Bank, Waffenständer, Strohsack, angelehnte Leiter; Balken
func _furnish(b: Basis, o: Vector3, spiral: bool) -> void:
	# Wendeltreppe belegt r ≤ 2,05 m um die Mitte, Zugang von +x; Möbel in den Ecken (≥ 2,4 m von der Mitte)
	var items: Array = [["turm_tisch_bauer", Vector3(-2.55, 0.16, -2.2), PI * 0.5], ["turm_holzbank", Vector3(2.25, 0.16, -2.75), 0.0],
		["turm_waffenstaender", Vector3(2.7, 0.16, 2.0), PI * 0.5], ["turm_strohsack", Vector3(-2.4, 0.16, 2.2), PI * 0.5]]
	if not spiral:
		# gerade Läufe: Lauf 1 im Band z 2,0–3,1; Weg Tür → Laufanfang (x −2,6) bleibt frei
		items = [["turm_tisch_bauer", Vector3(1.6, 0.16, -0.2), PI * 0.5], ["turm_holzbank", Vector3(2.6, 0.16, -0.2), PI * 0.5],
			["turm_waffenstaender", Vector3(2.75, 0.16, -2.0), -PI * 0.5], ["turm_strohsack", Vector3(-2.4, 0.16, -0.5), 0.0],
			["turm_holzleiter_3m", Vector3(-2.7, 4.16, -2.7), PI * 0.25]]
		prop("turm_deckenbalken_4m", Transform3D(b, o + b * Vector3(0, 0.85, -0.6)), false)
	for it in items:
		prop(String(it[0]), Transform3D(b * Basis(Vector3.UP, float(it[2])), o + b * (it[1] as Vector3)))


var _vc: StandardMaterial3D

func _vc_material() -> StandardMaterial3D:
	if _vc == null:
		_vc = StandardMaterial3D.new()
		_vc.vertex_color_use_as_albedo = true
		_vc.vertex_color_is_srgb = true
		_vc.roughness = 0.9
	return _vc


static func frame(center: Vector3, along: Vector2, inward: Vector2) -> Basis:
	var z := Vector3(inward.x, 0, inward.y).normalized()
	var x := Vector3.UP.cross(z).normalized()
	if x.dot(Vector3(along.x, 0, along.y)) < 0.0:
		pass   # Laufrichtung egal, Rechtssystem hat Vorrang
	return Basis(x, Vector3.UP, z)


func _cbox(b: Basis, origin: Vector3, local_center: Vector3, size: Vector3, mat := "", visual := false) -> void:
	col.box(Transform3D(b, origin + b * local_center), size, mat if mat != "" else "c_wall", visual, true)


## Mauermodul (Länge len ≈ 4 m) mit Fundament bis bottom_y; walk = Wehrgang auf der Innenseite
func wall(c2: Vector2, along: Vector2, inward: Vector2, len: float, base_y: float, bottom_y: float, walk: bool) -> void:
	var b := frame(Vector3.ZERO, along, inward)
	var o := Vector3(c2.x, base_y, c2.y)
	var sx := len / 4.0
	place("mauer_wehrgang_4m" if walk else "mauer_zinnen_4m", Transform3D(Basis(b.x * sx, b.y, b.z), o))
	_cbox(b, o, Vector3(0, 2.0, 0), Vector3(len, 4.0, 0.85))
	for mx in [-1.5, 0.5]:
		_cbox(b, o, Vector3(mx * sx, 4.78, 0), Vector3(0.8 * sx, 1.15, 0.92))
	if walk:
		_cbox(b, o, Vector3(0, 3.8, 1.25), Vector3(len, 0.2, 2.4))
		walk_points.append(o + b.z * 1.25 + Vector3.UP * WALK_Y)
		stats.walk += 1
	if bottom_y < base_y - 0.05:
		var hgt := base_y - bottom_y + 0.02
		col.box(Transform3D(b, o + Vector3.DOWN * hgt * 0.5 + Vector3.UP * 0.01), Vector3(len + 0.02, hgt, 0.9), found_mat, true, true)
	stats.walls += 1


## Eckpfeiler an Polygonknicken (füllt Lücken zwischen Modulen, oben auf Wehrganghöhe)
func pillar(p: Vector3, bottom_y: float) -> void:
	var hgt := p.y + WALK_Y - bottom_y
	col.box(Transform3D(Basis(), Vector3(p.x, bottom_y + hgt * 0.5, p.z)), Vector3(2.4, hgt, 2.4), found_mat, true, true)


## Treppe zum Wehrgang: läuft parallel zur Mauer am Wehrgangrand (lokal z 2,5–3,8), x von −2 bis +6 m
func stair(c2: Vector2, along: Vector2, inward: Vector2, base_y: float, bottom_y: float) -> void:
	var b := frame(Vector3.ZERO, along, inward)
	var o := Vector3(c2.x, base_y, c2.y)
	var n := 16
	for i in n:
		var top := (i + 1) * WALK_Y / n
		var hgt := top - (bottom_y - base_y)
		var lc := Vector3(-2.0 + (i + 0.5) * 0.5, top - hgt * 0.5, 3.15)
		col.box(Transform3D(b, o + b * lc), Vector3(0.5, hgt, 1.3), "c_steps", true, true)
	stairs_at.append(o + b * Vector3(5.75, WALK_Y, 3.15))
	stats.stairs += 1


## Tor (8 m): Durchlass 4,4 × 3,2 m quer zur Achse along; closed = schweres Tor mit geschlossenem Holzflügel
## (Kollision im Durchlass, z. B. Außentor an der Kartengrenze)
func gate(c2: Vector2, along: Vector2, base_y: float, bottom_y: float, closed := false) -> void:
	var inward := Vector2(-along.y, along.x)
	var b := frame(Vector3.ZERO, along, inward)
	var o := Vector3(c2.x, base_y, c2.y)
	place("toranlage_schwer_8m" if closed else "toranlage_offen_8m", Transform3D(b, o))
	if closed:
		# geschlossener Torflügel: Kollision + sichtbare Holzfläche auch von der Hofseite (Bausatzflügel ist einseitig)
		_cbox(b, o, Vector3(0, 1.6, -0.2), Vector3(4.45, 3.2, 0.9), "c_wood", true)
		closed_gates.append(o)
		stats.closed_gates += 1
	for sx in [-3.1, 3.1]:
		_cbox(b, o, Vector3(sx, 2.0, 0), Vector3(1.8, 4.0, 1.4))
		if bottom_y < base_y - 0.05:
			var hgt := base_y - bottom_y
			col.box(Transform3D(b, o + b * Vector3(sx, -hgt * 0.5, 0)), Vector3(1.8, hgt, 1.4), found_mat, true, true)
	_cbox(b, o, Vector3(0, 3.6, 0), Vector3(4.4, 0.8, 1.4))
	if closed:
		return
	gate_points.append(o)
	gate_axes.append(Vector3(inward.x, 0, inward.y))
	stats.gates += 1


## Geschossboden mit Treppenloch (Innenmaß ±3,14 m), Oberkante y_top (lokal), Loch x hx0–hx1, z hz0–hz1
func _hatch_floor(b: Basis, o: Vector3, y_top: float, hx0: float, hx1: float, hz0: float, hz1: float) -> void:
	var w := 3.14
	var th := 0.16
	var rects := [[-w, w, -w, hz0], [-w, w, hz1, w], [-w, hx0, hz0, hz1], [hx1, w, hz0, hz1]]
	for r in rects:
		var sx: float = r[1] - r[0]
		var sz: float = r[3] - r[2]
		if sx < 0.05 or sz < 0.05:
			continue
		var lc := Vector3((r[0] + r[1]) * 0.5, y_top - th * 0.5, (r[2] + r[3]) * 0.5)
		col.box(Transform3D(b, o + b * lc), Vector3(sx, th, sz), "c_wood", true, true)


## Treppenlauf im Turm entlang lokal ±x (dir), Band z zc ± 0,55 m, von y0 nach y1, 16 Stufen über 5,2 m
func _flight(b: Basis, o: Vector3, zc: float, dir: float, y0: float, y1: float) -> void:
	var n := 16
	var run := 5.2 / n
	for i in n:
		var top := y0 + (i + 1) * (y1 - y0) / n
		var x := (-2.6 + (i + 0.5) * run) * dir
		var hgt := top - y0 + 0.02
		col.box(Transform3D(b, o + b * Vector3(x, y0 - 0.02 + hgt * 0.5, zc)), Vector3(run, hgt, 1.1), "c_steps", true, true)


## Quadratischer Turm (8 × 8 m, 3 Geschosse, Tür auf −Z = Hofseite) mit Leiter außen zur Plattform auf 12 m;
## stairs = zusätzlich innen Treppenläufe Erdgeschoss → 1. OG → 2. OG → Plattform (eigene Böden mit Treppenloch)
## spiral = Wendeltreppen (Pack 18) statt gerader Läufe; beide Arten mit Böden mit Treppenloch
func tower(m: Node, id: String, c2: Vector2, inward: Vector2, base_y: float, bottom_y: float, ground_fn: Callable, stairs := false, spiral := false) -> void:
	var b := frame(Vector3.ZERO, Vector2(inward.y, -inward.x), -inward)   # −Z zeigt in den Hof
	var o := Vector3(c2.x, base_y, c2.y)
	var own_floors := stairs or spiral
	place("turm_quadratisch_sockel_8m", Transform3D(b, o))
	place("turm_quadratisch_geschoss_8m", Transform3D(b, o + Vector3.UP * 4.0), ["treppenstein"] if own_floors else [])
	place("turm_quadratisch_zinnen_8m", Transform3D(b, o + Vector3.UP * 8.0), ["treppenstein", "holz"] if own_floors else [])
	if spiral and not _model("turm_wendeltreppe_stein").is_empty():
		_spiral(b, o, 0.16, 4.0)
		_hatch_floor(b, o, 4.16, -1.3, 2.2, -1.2, 2.2)
		_spiral(b, o, 4.16, 4.0)
		_hatch_floor(b, o, 8.16, -1.3, 2.2, -1.2, 2.2)
		_spiral(b, o, 8.16, 3.84)
		_hatch_floor(b, o, 12.0, -1.3, 2.2, -1.2, 2.2)
		stats.tower_spirals = int(stats.get("tower_spirals", 0)) + 1
		stairs = true      # gleiche Bodenbehandlung wie bei geraden Läufen
	elif spiral:
		spiral = false
		stairs = true
	_furnish(b, o, spiral)
	if stairs and not spiral:
		_flight(b, o, 2.55, 1.0, 0.16, 4.16)
		_hatch_floor(b, o, 4.16, -0.6, 3.14, 1.9, 3.14)
		_flight(b, o, -2.55, -1.0, 4.16, 8.16)
		_hatch_floor(b, o, 8.16, -3.14, 0.6, -3.14, -1.9)
		_flight(b, o, 2.55, 1.0, 8.16, 12.0)
		_hatch_floor(b, o, 12.0, -0.6, 3.14, 1.9, 3.14)
		stats.tower_stairs += 1
	for lv in [0.0, 4.0, 8.0]:
		_cbox(b, o, Vector3(-3.57, lv + 2.0, 0), Vector3(0.86, 4.0, 8.0))
		_cbox(b, o, Vector3(3.57, lv + 2.0, 0), Vector3(0.86, 4.0, 8.0))
		_cbox(b, o, Vector3(0, lv + 2.0, 3.57), Vector3(6.28, 4.0, 0.86))
		if lv == 0.0:
			_cbox(b, o, Vector3(-2.55, 2.0, -3.57), Vector3(2.28, 4.0, 0.86))
			_cbox(b, o, Vector3(2.55, 2.0, -3.57), Vector3(2.28, 4.0, 0.86))
			_cbox(b, o, Vector3(0, 3.5, -3.57), Vector3(2.83, 1.0, 0.86))
		else:
			_cbox(b, o, Vector3(0, lv + 2.0, -3.57), Vector3(6.28, 4.0, 0.86))
		if lv == 0.0 or not stairs:
			_cbox(b, o, Vector3(0, lv + 0.08, 0), Vector3(6.8, 0.16, 6.8))
	if not stairs:
		_cbox(b, o, Vector3(0, 11.92, 0), Vector3(6.65, 0.15, 6.65))
	# Brüstung (Kollision) mit Lücke für die Leiter bei x 2,2–3,4 auf −Z
	_cbox(b, o, Vector3(0, 12.55, 3.7), Vector3(8.0, 1.1, 0.6))
	_cbox(b, o, Vector3(-3.7, 12.55, 0), Vector3(0.6, 1.1, 8.0))
	_cbox(b, o, Vector3(3.7, 12.55, 0.6), Vector3(0.6, 1.1, 6.8))
	_cbox(b, o, Vector3(-0.9, 12.55, -3.7), Vector3(6.2, 1.1, 0.6))
	if bottom_y < base_y - 0.05:
		var hgt := base_y - bottom_y
		col.box(Transform3D(b, o + Vector3.DOWN * hgt * 0.5), Vector3(8.0, hgt, 8.0), found_mat, true, true)
	# Leiter
	var lx := 2.8
	var foot2 := o + b * Vector3(lx, 0, -4.7)
	var foot_y: float = ground_fn.call(foot2.x, foot2.z)
	var bottom := Vector3(foot2.x, foot_y, foot2.z)
	var top := o + b * Vector3(lx, TOWER_TOP, -2.9)
	var rail_bot := foot_y - 0.2
	for zx in [-0.25, 0.25]:
		var p := o + b * Vector3(lx + zx, 0, -4.15)
		var hgt := o.y + TOWER_TOP + 1.0 - rail_bot
		col.box(Transform3D(b, Vector3(p.x, rail_bot + hgt * 0.5, p.z)), Vector3(0.07, hgt, 0.07), "c_wood", true, false)
	var y := rail_bot + 0.3
	while y < o.y + TOWER_TOP:
		var p := o + b * Vector3(lx, 0, -4.15)
		col.box(Transform3D(b, Vector3(p.x, y, p.z)), Vector3(0.5, 0.05, 0.05), "c_wood", true, false)
		y += 0.3
	for upper in [false, true]:
		var l := CastleLadder.new()
		l.name = "%s_leiter_%s" % [id, "oben" if upper else "unten"]
		l.persistent_id = "castle_" + l.name
		l.bottom = bottom
		l.top = top
		l.at_top = upper
		l.prompt = "Hinunterklettern" if upper else "Hinaufklettern"
		m.dynamic_root.add_child(l)
		l.global_position = top if upper else bottom
		l.add_to_group("castle_ladders")
		stats.ladders += 1
	towers.append({"id": id, "pos": o, "top": top, "door": o + b * Vector3(0, 0, -5.0), "ladder": bottom, "stairs": stairs,
		"stair_foot": o + b * Vector3(-2.0, 0.16, 1.0), "stair_top": o + b * Vector3(-2.2, 12.0, -2.2), "basis": b, "spiral": spiral})
	stats.towers += 1
