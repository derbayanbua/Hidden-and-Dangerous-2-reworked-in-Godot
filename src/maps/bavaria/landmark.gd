extends Node3D
## Bavaria – Blickfang außerhalb der Karte (nur aus der Ferne sichtbar, nicht erreichbar).
## Dorf auf einer Anhöhe: Kirche mit Zwiebelturm, Höfe mit Ziegeldächern, ein brennendes Gehöft mit Rauchsäule,
## nachts glimmt das Feuer. Low-Poly, ein gemeinsames Vertexfarben-Material (1 Fläche) + 2 Partikelsysteme.
## Ohne Kollision, ohne Schatten, nicht in der Navmesh-Quelle (Kind der Mission, nicht static_root/nav_region).
## Rauch/Feuer sind rein lokale Kosmetik (fester Partikel-Seed, keine Netznachricht; Protokoll unverändert).
## Tageszeit: liest `mission.day_night.state()` (daylight/night/lamp) alle 0,5 s; Nebel/Dunst bettet ein.

const AZIMUTH_DEG := 95.0         ## Richtung ab Kartenmitte (Vector2.from_angle, Welt x/z): Südwesten, Rand des Alpensektors
const EDGE_OFFSET := 108.0        ## Abstand Kuppe ↔ Spielgrenze entlang dieser Richtung [m] (vor dem Panoramaring)
## Modellmeter → Weltmeter: das Dorf steht nah (≈ 175 m ab Kartenmitte) und ist verkleinert gebaut → gleicher Sehwinkel
## wie ein Dorf in ≈ 350 m. Alle Maße unten (Hügel, Höfe, Kirche, Bäume) sind Modellmeter.
const K := 0.5
const HILL_H := 36.0              ## sanfte Kuppe (Modell 36 m = 18 m Welt), Turmspitze ≈ 46 m über dem Umland
const HILL_R := 150.0             ## Fußradius (quer zur Blickrichtung ×1,35), flache Flanken
const PLATEAU_R := 42.0
const VIS_BEGIN := 40.0           ## näher als das → ausgeblendet (weich über VIS_MARGIN); Spielfläche liegt weiter weg
const VIS_MARGIN := 15.0
var fx_k := 1.0                   ## Maßstab für Rauch/Feuer (Dorf: K)
const GROUND_Y := -0.3            ## Umland „DistantCountryside“

var mission: Node
var hill_center := Vector2.ZERO   ## Welt x/z der Kuppe
var tower_top := Vector3.ZERO     ## Welt: Spitze des Zwiebelturms
var mesh_instance: MeshInstance3D
var smoke: GPUParticles3D
var fire: GPUParticles3D
var _smoke_mat: StandardMaterial3D
var _fire_mat: StandardMaterial3D
var _st: SurfaceTool
var _t := 0.0
var _yaw := 0.0

## Welt x/z der Kuppe aus der Spielgrenze (auch für die Blickschneise in scene_details, vor dem Bau des Blickfangs).
static func hill_center_for(b: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in b:
		c += q
	c /= b.size()
	var dir := Vector2.from_angle(deg_to_rad(AZIMUTH_DEG))
	var edge := c
	for i in b.size():
		var hit = Geometry2D.segment_intersects_segment(c, c + dir * 3000.0, b[i], b[(i + 1) % b.size()])
		if hit != null:
			edge = hit
	return edge + dir * EDGE_OFFSET

## Welt x/z des Zwiebelturms (Turmachse lokal −15/−6, wie _village).
static func tower_xz_for(b: PackedVector2Array) -> Vector2:
	var dir := Vector2.from_angle(deg_to_rad(AZIMUTH_DEG))
	var o := Basis(Vector3.UP, atan2(dir.x, dir.y)) * Vector3(-15.0, 0.0, -6.0) * K
	return hill_center_for(b) + Vector2(o.x, o.z)

## Lage aus Grenze + Richtung bestimmen und alles bauen.
func build(m: Node) -> void:
	mission = m
	name = "Blickfang"
	var dir := Vector2.from_angle(deg_to_rad(AZIMUTH_DEG))
	hill_center = hill_center_for(m.boundary)
	position = Vector3(hill_center.x, GROUND_Y, hill_center.y)
	# lokales −Z zeigt zur Karte: Kirche steht breitseitig zum Betrachter
	_yaw = atan2(dir.x, dir.y)
	rotation.y = _yaw
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_hill()
	_village()
	_trees()
	var mesh := _st.commit()
	_st = null
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Dorf"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _solid_material()
	mesh_instance.scale = Vector3.ONE * K
	_far_only(mesh_instance)
	add_child(mesh_instance)
	fx_k = K
	var burn := Vector3(-30.0, _h(-30.0, 8.0) + 5.0, 8.0) * K  # brennendes Gehöft (lokal, Mauerkrone)
	smoke = _smoke(burn)
	add_child(smoke)
	fire = _fire(burn)
	add_child(fire)
	add_to_group("bavaria_landmark")
	set_process(true)

func _ready() -> void:
	tower_top = to_global(_tower_top_local * K)
	_update(true)

func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_update(false)

## Tageszeit → Rauchfarbe, Feuerglut
func _update(_full: bool) -> void:
	var st: Dictionary = {}
	var dn = mission.get("day_night") if mission else null
	if dn and dn.has_method("state"):
		st = dn.state()
	var day := float(st.get("daylight", 0.3))
	var night := float(st.get("night", 0.0))
	var lamp := float(st.get("lamp", 1.0))
	if _smoke_mat:
		var col := Color(0.30, 0.29, 0.28).lerp(Color(0.40, 0.39, 0.38), day).lerp(Color(0.05, 0.05, 0.06), night)
		col.a = lerpf(1.0, 0.6, night)
		_smoke_mat.albedo_color = col
	if _fire_mat:
		var k := lerpf(0.35, 2.4, lamp)          # additiv: tagsüber kaum, nachts glimmend (HDR-Albedo)
		_fire_mat.albedo_color = Color(1.0 * k, 0.45 * k, 0.12 * k, lerpf(0.3, 0.9, lamp))

# ---------------------------------------------------------------- Gelände
## Höhe der Anhöhe im lokalen Raum (0 = Umland)
## Unregelmäßiger Umriss der Kuppe (Faktor auf den Radius je Richtung, deterministisch)
static func _irr(a: float) -> float:
	return 1.0 + 0.11 * sin(3.0 * a + 0.7) + 0.06 * sin(5.0 * a + 2.1) + 0.035 * sin(8.0 * a + 0.3)

## Sanfte Moränenkuppe: fast ebene Hochfläche fürs Dorf, flache, nach außen auslaufende Flanken (kein Kegel),
## Umriss unregelmäßig, leichte Wellen am Hang.
func _h(x: float, z: float) -> float:
	var a := atan2(z, x / 1.35)
	var r := Vector2(x / 1.35, z).length() / _irr(a)
	var top := HILL_H - minf(r, PLATEAU_R) * 0.03
	if r <= PLATEAU_R:
		return top
	if r >= HILL_R:
		return 0.0
	var t := (r - PLATEAU_R) / (HILL_R - PLATEAU_R)
	var w := 1.0 + 0.06 * sin(r * 0.09 + a * 2.0) * sin(PI * t)     # sanfte Hangwellen
	return top * pow(0.5 * (1.0 + cos(PI * t)), 1.25) * w

func _hill() -> void:
	var seg := 48
	var rings := [0.0, 20.0, PLATEAU_R, 60.0, 78.0, 96.0, 114.0, 130.0, 142.0, HILL_R + 6.0]
	var pts: Array = []
	for ri in rings.size():
		var row: Array[Vector3] = []
		for s in seg:
			var a := TAU * s / seg
			var r: float = rings[ri] * _irr(a)
			var x := cos(a) * r * 1.35
			var z := sin(a) * r
			row.append(Vector3(x, _h(x, z) - (0.6 if ri == rings.size() - 1 else 0.0), z))
		pts.append(row)
	for ri in rings.size() - 1:
		for s in seg:
			var s2 := (s + 1) % seg
			var a: Vector3 = pts[ri][s]
			var b: Vector3 = pts[ri][s2]
			var c2: Vector3 = pts[ri + 1][s2]
			var d: Vector3 = pts[ri + 1][s]
			var g := Color(0.24, 0.31, 0.13).lerp(Color(0.17, 0.24, 0.10), float(ri) / rings.size())
			g = g.lerp(Color(0.38, 0.33, 0.16), 0.3 * float((s * 7 + ri * 3) % 4) / 3.0)   # Feld-/Wiesenwechsel
			_quad(a, d, c2, b, g)

# ---------------------------------------------------------------- Dorf
var _tower_top_local := Vector3.ZERO

func _village() -> void:
	var plaster := Color(0.90, 0.89, 0.84)
	var roof := Color(0.52, 0.17, 0.09)
	var dark := Color(0.07, 0.08, 0.07)
	# Kirche: Langhaus (x = Länge, breitseitig zur Karte), Chor im Osten, Turm im Westen, Zwiebelhelm
	var cz := -6.0
	var gy := _h(0.0, cz) - 0.5
	_box(Vector3(-2.0, gy, cz), Vector3(20.0, 10.0, 11.0), plaster)
	_gable_roof(Vector3(-2.0, gy + 10.0, cz), 20.6, 11.8, 5.6, roof, plaster)
	_box(Vector3(11.5, gy, cz), Vector3(7.0, 8.5, 8.0), plaster)                 # Chor
	_hip_cap(Vector3(11.5, gy + 8.5, cz), 7.4, 8.4, 3.6, roof)
	var tx := -15.0
	var th := 46.0                    # hoher Kirchturm: bleibt über Dächern und Bäumen der Karte sichtbar
	_box(Vector3(tx, gy, cz), Vector3(6.4, th, 6.4), plaster)                    # Turm
	_box(Vector3(tx, gy + th - 0.6, cz), Vector3(7.0, 0.6, 7.0), plaster)        # Gesims
	for k in 4:                                                                   # Schallöffnungen
		var ang := k * PI * 0.5
		var n := Vector3(sin(ang), 0, cos(ang))
		var t := Vector3(n.z, 0, -n.x)
		var o := Vector3(tx, gy + th - 5.0, cz) + n * 3.22
		_quad(o - t * 0.7, o + t * 0.7, o + t * 0.7 + Vector3.UP * 2.6, o - t * 0.7 + Vector3.UP * 2.6, dark)
		var o2 := Vector3(tx, gy + th - 9.5, cz) + n * 3.22                   # Uhr
		_quad(o2 - t * 0.9, o2 + t * 0.9, o2 + t * 0.9 + Vector3.UP * 1.8, o2 - t * 0.9 + Vector3.UP * 1.8, Color(0.25, 0.22, 0.16))
	# Zwiebelhelm: Profil (Radius, Höhe über Gesims)
	var prof := [[3.1, 0.0], [3.3, 0.6], [3.9, 1.8], [4.0, 2.6], [3.6, 3.7], [2.4, 4.7], [1.0, 5.4], [0.9, 6.6],
		[1.3, 7.1], [1.45, 7.6], [1.0, 8.3], [0.25, 8.8], [0.12, 10.6], [0.0, 10.8]]
	_lathe(Vector3(tx, gy + th, cz), prof, 12, dark)
	_tower_top_local = Vector3(tx, gy + th + 10.8, cz)
	_box(Vector3(tx, gy + th + 10.6, cz), Vector3(0.12, 1.6, 0.12), dark)        # Kreuz
	_box(Vector3(tx, gy + th + 11.6, cz), Vector3(0.9, 0.12, 0.12), dark)
	# Höfe: [x, z, Länge, Tiefe, Wandhöhe, Drehung, Putzfarbe]
	var farms := [
		[22.0, -24.0, 15.0, 10.0, 6.0, 0.15, plaster], [34.0, 6.0, 13.0, 9.0, 5.5, -0.35, Color(0.86, 0.80, 0.66)],
		[12.0, 20.0, 17.0, 10.0, 6.5, 0.05, plaster], [-12.0, 26.0, 14.0, 9.5, 5.5, 0.4, Color(0.84, 0.82, 0.76)],
		[-48.0, -16.0, 14.0, 10.0, 6.0, -0.2, plaster], [-52.0, 22.0, 16.0, 10.0, 5.5, 0.3, Color(0.88, 0.83, 0.70)],
		[46.0, -14.0, 12.0, 9.0, 5.0, 0.6, plaster], [-28.0, -32.0, 13.0, 9.0, 5.5, -0.5, Color(0.85, 0.84, 0.80)],
		[52.0, 24.0, 15.0, 10.0, 6.0, -0.1, plaster]]
	for f in farms:
		_farm(f[0], f[1], f[2], f[3], f[4], f[5], f[6], roof)
	# brennendes Gehöft: geschwärzte Mauern, halb eingestürztes Dach
	var bx := -30.0
	var bz := 8.0
	var by := _h(bx, bz) - 0.5
	var soot := Color(0.20, 0.18, 0.16)
	_box(Vector3(bx, by, bz), Vector3(15.0, 4.2, 10.0), Color(0.55, 0.52, 0.47))
	_box(Vector3(bx, by + 4.2, bz), Vector3(15.0, 1.6, 10.0), soot)
	_gable_roof(Vector3(bx + 4.5, by + 5.8, bz), 6.0, 10.8, 4.0, Color(0.16, 0.12, 0.10), soot)
	for k in 4:                                                                 # stehengebliebene Sparren
		var px := bx - 6.0 + k * 1.8
		_box(Vector3(px, by + 5.8, bz), Vector3(0.3, 3.6 - k * 0.6, 0.3), Color(0.08, 0.07, 0.06))

func _farm(x: float, z: float, l: float, d: float, wall: float, rot: float, col: Color, roof: Color) -> void:
	var y := _h(x, z) - 0.6
	var bs := Basis(Vector3.UP, rot)
	var o := Vector3(x, y, z)
	_box(o, Vector3(l, wall, d), col, bs)
	# Stadel-Hälfte: Holz im Obergeschoss
	_box(o + bs * Vector3(l * 0.25, wall * 0.55, 0), Vector3(l * 0.5 + 0.08, wall * 0.45, d + 0.08), Color(0.36, 0.26, 0.18), bs)
	_gable_roof(o + Vector3.UP * wall, l + 1.2, d + 1.6, d * 0.42, roof.lerp(Color(0.38, 0.24, 0.18), fposmod(x * 0.37, 1.0) * 0.6), col, bs)

func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4511
	for i in 44:                      # Waldstücke an den Flanken (Gruppen um wenige Richtungen)
		var a := float(i % 5) * 1.3 + 0.7 + rng.randf_range(-0.35, 0.35)
		var r := rng.randf_range(PLATEAU_R + 6.0, 125.0)
		var x := cos(a) * r * 1.35
		var z := sin(a) * r
		if z < -40.0 and absf(x) < 70.0:
			continue                      # Hang zur Karte frei: Kirche bleibt sichtbar
		var y := _h(x, z) - 0.5
		var hgt := rng.randf_range(9.0, 15.0)
		var rad := hgt * rng.randf_range(0.28, 0.4)
		var c := Color(0.13, 0.20, 0.11).lerp(Color(0.20, 0.25, 0.12), rng.randf())
		_lathe(Vector3(x, y, z), [[0.25, 0.0], [rad, hgt * 0.25], [rad * 0.85, hgt * 0.6], [0.0, hgt]], 6, c)

# ---------------------------------------------------------------- Bauteile
func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		_st.set_color(col)
		_st.set_normal(n)
		_st.add_vertex(v)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(a, c, b, col)
	_tri(a, d, c, col)

## Quader: Fußmitte o, Größe s (x Länge, y Höhe, z Tiefe), gedreht um bs
func _box(o: Vector3, s: Vector3, col: Color, bs := Basis()) -> void:
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return o + bs * Vector3(x, y, z)
	var a: Vector3 = p.call(-hx, 0, -hz)
	var b: Vector3 = p.call(hx, 0, -hz)
	var c: Vector3 = p.call(hx, 0, hz)
	var d: Vector3 = p.call(-hx, 0, hz)
	var up := bs * Vector3(0, s.y, 0)
	_quad(a, b, b + up, a + up, col)
	_quad(b, c, c + up, b + up, col.darkened(0.06))
	_quad(c, d, d + up, c + up, col)
	_quad(d, a, a + up, d + up, col.darkened(0.06))
	_quad(a + up, b + up, c + up, d + up, col)

## Satteldach (First entlang x) mit Giebeldreiecken in Wandfarbe
func _gable_roof(o: Vector3, l: float, d: float, h: float, col: Color, wall: Color, bs := Basis()) -> void:
	var hx := l * 0.5
	var hz := d * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return o + bs * Vector3(x, y, z)
	var r0: Vector3 = p.call(-hx, h, 0)
	var r1: Vector3 = p.call(hx, h, 0)
	var e0: Vector3 = p.call(-hx, -0.3, -hz)
	var e1: Vector3 = p.call(hx, -0.3, -hz)
	var f0: Vector3 = p.call(-hx, -0.3, hz)
	var f1: Vector3 = p.call(hx, -0.3, hz)
	_quad(e0, e1, r1, r0, col)
	_quad(f1, f0, r0, r1, col.darkened(0.12))
	var gx := hx - 0.6
	_tri(p.call(-gx, 0, -hz + 0.6), p.call(-gx, 0, hz - 0.6), p.call(-gx, h - 0.3, 0), wall)
	_tri(p.call(gx, 0, hz - 0.6), p.call(gx, 0, -hz + 0.6), p.call(gx, h - 0.3, 0), wall)

## Walmkappe (Pyramide) über Rechteck l × d
func _hip_cap(o: Vector3, l: float, d: float, h: float, col: Color) -> void:
	var a := o + Vector3(-l * 0.5, 0, -d * 0.5)
	var b := o + Vector3(l * 0.5, 0, -d * 0.5)
	var c := o + Vector3(l * 0.5, 0, d * 0.5)
	var e := o + Vector3(-l * 0.5, 0, d * 0.5)
	var t := o + Vector3(0, h, 0)
	_tri(a, b, t, col)
	_tri(b, c, t, col.darkened(0.1))
	_tri(c, e, t, col)
	_tri(e, a, t, col.darkened(0.1))

## Drehkörper aus Profil [[r, y], …]
func _lathe(o: Vector3, prof: Array, seg: int, col: Color) -> void:
	for i in prof.size() - 1:
		var r0: float = prof[i][0]
		var y0: float = prof[i][1]
		var r1: float = prof[i + 1][0]
		var y1: float = prof[i + 1][1]
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var p00 := o + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := o + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := o + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := o + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var shade := col.darkened(0.08 * float(s % 2))
			if r1 > 0.001:
				_quad(p00, p10, p11, p01, shade)
			else:
				_tri(p00, p10, p01, shade)

# ---------------------------------------------------------------- Material, Rauch, Feuer
func _solid_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _far_only(g: GeometryInstance3D) -> void:
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	g.visibility_range_begin = VIS_BEGIN
	g.visibility_range_begin_margin = VIS_MARGIN
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func _soft_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t

func _particles(at: Vector3, amount: int, life: float, pm: ParticleProcessMaterial, mat: StandardMaterial3D, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.fixed_fps = 15
	p.local_coords = false
	p.process_material = pm
	if "use_fixed_seed" in p:
		p.set("use_fixed_seed", true)
		p.set("seed", 1945)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-120, -10, -120) * fx_k, Vector3(240, 220, 240) * fx_k)
	_far_only(p)
	return p

func _smoke(at: Vector3) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 3.0 * fx_k
	pm.direction = Vector3.UP
	pm.spread = 7.0
	pm.initial_velocity_min = 2.6 * fx_k
	pm.initial_velocity_max = 3.4 * fx_k
	# Wind quer zur Blickrichtung → die Säule neigt sich sichtbar
	pm.gravity = Vector3(0.09, -0.012, 0.02) * fx_k
	pm.damping_min = 0.01
	pm.damping_max = 0.03
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 1, 1, 0))
	cr.set_color(1, Color(1, 1, 1, 0))
	cr.add_point(0.06, Color(0.7, 0.7, 0.7, 0.95))
	cr.add_point(0.6, Color(1, 1, 1, 0.6))
	var crt := GradientTexture1D.new()
	crt.gradient = cr
	pm.color_ramp = crt
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.albedo_texture = _soft_tex()
	_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var p := _particles(at, 56, 42.0, pm, _smoke_mat, 30.0 * fx_k)
	p.name = "Rauch"
	return p

func _fire(at: Vector3) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(5.0, 0.5, 3.0) * fx_k
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 1.0 * fx_k
	pm.initial_velocity_max = 2.2 * fx_k
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 0.8, 0.4, 0))
	cr.set_color(1, Color(0.8, 0.2, 0.05, 0))
	cr.add_point(0.25, Color(1, 0.6, 0.25, 1))
	var crt := GradientTexture1D.new()
	crt.gradient = cr
	pm.color_ramp = crt
	_fire_mat = StandardMaterial3D.new()
	_fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_fire_mat.vertex_color_use_as_albedo = true
	_fire_mat.albedo_texture = _soft_tex()
	_fire_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var p := _particles(at + Vector3(0, 0.3, 0), 14, 1.6, pm, _fire_mat, 5.0 * fx_k)
	p.name = "Feuer"
	return p
