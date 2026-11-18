extends "res://src/maps/bavaria/landmark.gd"
## Bavaria – zweiter Fern-Blickfang im Nordosten: Werk am Waldrand auf einem Hang über einer Talsenke.
## Schlote mit Rauchfahnen, lange Hallen mit Satteldach, zwei Silos, mehrstöckiges Werksgebäude mit Türmchen,
## Werkswohnhäuser, Bahndamm mit Gleis, Nadelwald dahinter, unten Kirche und geschwungene Straße.
## Technik wie das Dorf (landmark.gd, Bauteile/Material/Partikel geerbt): ein Vertexfarben-Mesh + ein Fenster-Mesh
## (nachts erleuchtet) + 2 Partikelsysteme (Rauch, Glimmen; je ein Emitter für alle Schlote) = 4 Zeichenaufrufe.
## Ohne Kollision/Schatten, nicht im Navmesh (Kind der Mission), weich eingeblendet (visibility_range).
## Entfernung: Das Werk steht ≈ 180 m vor der Kartenmitte (vor dem Panoramaring, panorama_ring.gd) und ist mit
## SCALE = 0,12 (≈ 180/1500) verkleinert gebaut → gleicher Sehwinkel wie ein Werk in 1,5 km. Geländefuß auf Umlandhöhe,
## damit Hangfuß/Talsohle knapp unter dem Horizont des Himmel-Shaders liegen; Kartennebel + leichte Dunstfärbung.
## Rauch/Glimmen rein lokal (fester Seed, keine Netznachricht; Protokoll unverändert).

const F_AZIMUTH_DEG := 260.0     ## Richtung ab Kartenmitte (Vector2.from_angle, Welt x/z): Nordosten (Himmel-Shader: Süd = (0,817; 0,576))
const F_EDGE_OFFSET := 120.0     ## Abstand Werk ↔ Spielgrenze [m] (vor dem Panoramaring)
const SCALE := 0.12              ## Modellmeter → Weltmeter (≈ 180 m / 1500 m)
const PLATEAU_Y := 60.0          ## Hanghöhe über der Talsohle [Modellmeter]
const HAZE := Color(0.62, 0.66, 0.72)
const HAZE_K := 0.10

var factory_center := Vector2.ZERO        ## Welt x/z
var chimney_tops: Array[Vector3] = []     ## Welt
var windows_instance: MeshInstance3D
var glow: GPUParticles3D
var _win_mat: StandardMaterial3D
var _top_local: Array[Vector3] = []       ## Modellraum
var _lit_st: SurfaceTool

static func factory_center_for(b: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in b:
		c += q
	c /= b.size()
	var dir := Vector2.from_angle(deg_to_rad(F_AZIMUTH_DEG))
	var edge := c
	for i in b.size():
		var hit = Geometry2D.segment_intersects_segment(c, c + dir * 3000.0, b[i], b[(i + 1) % b.size()])
		if hit != null:
			edge = hit
	return edge + dir * F_EDGE_OFFSET

func build(m: Node) -> void:
	mission = m
	name = "Werk"
	var dir := Vector2.from_angle(deg_to_rad(F_AZIMUTH_DEG))
	factory_center = factory_center_for(m.boundary)
	position = Vector3(factory_center.x, GROUND_Y, factory_center.y)
	_yaw = atan2(dir.x, dir.y)       # lokales −Z zeigt zur Karte, Betrachter-rechts = lokales −X
	rotation.y = _yaw
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lit_st = SurfaceTool.new()
	_lit_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_terrain()
	_valley()
	_works()
	_forest()
	mesh_instance = _instance("Fabrik", _st.commit(), _solid_material())
	_win_mat = StandardMaterial3D.new()
	_win_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_win_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	windows_instance = _instance("Fenster", _lit_st.commit(), _win_mat)
	_st = null
	_lit_st = null
	fx_k = SCALE / 0.31            # Rauch/Glimmen im selben Verhältnis wie das Modell verkleinert
	smoke = _chimney_smoke()
	add_child(smoke)
	glow = _chimney_glow()
	add_child(glow)
	add_to_group("bavaria_factory")
	set_process(true)

func _instance(n: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	mi.scale = Vector3.ONE * SCALE
	_far_only(mi)
	add_child(mi)
	return mi

func _ready() -> void:
	chimney_tops.clear()
	for t in _top_local:
		chimney_tops.append(to_global(t * SCALE))
	_update(true)

## Tageszeit wie landmark.gd: daylight/night/lamp aus mission.day_night.state()
func _update(_full: bool) -> void:
	var st: Dictionary = {}
	var dn = mission.get("day_night") if mission else null
	if dn and dn.has_method("state"):
		st = dn.state()
	var day := float(st.get("daylight", 0.3))
	var night := float(st.get("night", 0.0))
	var lamp := float(st.get("lamp", 1.0))
	if _smoke_mat:
		var col := Color(0.42, 0.42, 0.42).lerp(Color(0.80, 0.80, 0.79), day).lerp(Color(0.05, 0.05, 0.06), night)
		col.a = lerpf(0.85, 0.55, night)
		_smoke_mat.albedo_color = col
	if _fire_mat:
		var k := lerpf(0.0, 2.2, lamp)
		_fire_mat.albedo_color = Color(1.0 * k, 0.42 * k, 0.12 * k, lerpf(0.0, 0.85, lamp))
	if _win_mat:
		_win_mat.albedo_color = Color(0.11, 0.12, 0.13).lerp(Color(1.9, 1.35, 0.7), lamp)

# ---------------------------------------------------------------- Gelände
## Hanghöhe (Modellraum, 0 = Talsohle): Talsenke vorn (−Z), Hang, Hochfläche mit Werk und Wald; seitlich auslaufend.
func _y(x: float, z: float) -> float:
	var t := smoothstep(-190.0, -70.0, z)
	var side := 1.0 - smoothstep(520.0, 760.0, absf(x))
	return PLATEAU_Y * t * side + 4.0 * sin(x * 0.011) * t

func _haze(c: Color) -> Color:
	return c.lerp(HAZE, HAZE_K)

func _terrain() -> void:
	var xs: Array[float] = []
	var x := -800.0
	while x <= 800.0:
		xs.append(x)
		x += 80.0
	var zs: Array[float] = [-420.0, -330.0, -260.0, -210.0, -175.0, -150.0, -125.0, -100.0, -80.0, -60.0, -20.0, 40.0, 120.0, 220.0, 340.0, 460.0]
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var p := [Vector3(xs[i], 0, zs[j]), Vector3(xs[i + 1], 0, zs[j]), Vector3(xs[i + 1], 0, zs[j + 1]), Vector3(xs[i], 0, zs[j + 1])]
			for k in 4:
				p[k].y = _y(p[k].x, p[k].z) - 1.0
			var zc := (zs[j] + zs[j + 1]) * 0.5
			var g := Color(0.30, 0.36, 0.18).lerp(Color(0.40, 0.38, 0.22), 0.4 * float((i * 5 + j * 3) % 3) / 2.0)
			if zc > -200.0 and zc < -70.0:
				g = g.darkened(0.12)                       # Hang
			_quad(p[0], p[1], p[2], p[3], _haze(g))

# ---------------------------------------------------------------- Tal: Straße, Kirche
func _valley() -> void:
	var road := _haze(Color(0.55, 0.52, 0.46))
	var prev := Vector3.ZERO
	var x := -760.0
	while x <= 760.0:
		var z := -300.0 + 45.0 * sin(x * 0.006)
		var p := Vector3(x, _y(x, z) + 0.3, z)
		if x > -760.0:
			var n := Vector3(0, 0, 4.0)
			_quad(prev - n, p - n, p + n, prev + n, road)
		prev = p
		x += 40.0
	# Kirche (links unten): Langhaus, Turm mit Spitzhelm
	var plaster := _haze(Color(0.88, 0.86, 0.80))
	var roof := _haze(Color(0.30, 0.20, 0.17))
	var cx := 220.0
	var cz := -255.0
	var gy := _y(cx, cz) - 0.5
	_box(Vector3(cx, gy, cz), Vector3(26.0, 11.0, 13.0), plaster)
	_gable_roof(Vector3(cx, gy + 11.0, cz), 27.0, 14.0, 7.0, roof, plaster)
	_box(Vector3(cx - 17.0, gy, cz), Vector3(7.0, 30.0, 7.0), plaster)
	_hip_cap(Vector3(cx - 17.0, gy + 30.0, cz), 7.4, 7.4, 13.0, roof)
	# einige Häuser an der Straße
	var rng := RandomNumberGenerator.new()
	rng.seed = 4407
	for i in 7:
		var hx := rng.randf_range(-500.0, 520.0)
		var hz := -300.0 + 45.0 * sin(hx * 0.006) + (22.0 if i % 2 == 0 else -22.0)
		var hy := _y(hx, hz) - 0.5
		var l := rng.randf_range(12.0, 18.0)
		_box(Vector3(hx, hy, hz), Vector3(l, 8.0, 10.0), plaster)
		_gable_roof(Vector3(hx, hy + 8.0, hz), l + 1.0, 11.0, 4.5, roof, plaster)

# ---------------------------------------------------------------- Werk
func _works() -> void:
	var concrete := _haze(Color(0.80, 0.78, 0.72))
	var concrete2 := _haze(Color(0.70, 0.69, 0.65))
	var roof := _haze(Color(0.20, 0.20, 0.22))
	var brick := _haze(Color(0.50, 0.27, 0.19))
	var dark := Color(0.09, 0.10, 0.11)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1943
	# Bahndamm mit Gleis vor dem Werk (quer zum Blick)
	var bz := -95.0
	var ballast := _haze(Color(0.42, 0.38, 0.33))
	var x0 := -560.0
	var x1 := 420.0
	var crest := _y(0.0, bz) + 9.0
	_quad(Vector3(x0, _y(x0, bz - 22.0), bz - 22.0), Vector3(x1, _y(x1, bz - 22.0), bz - 22.0), Vector3(x1, crest, bz - 4.0), Vector3(x0, crest, bz - 4.0), ballast)
	_quad(Vector3(x0, crest, bz - 4.0), Vector3(x1, crest, bz - 4.0), Vector3(x1, crest, bz + 4.0), Vector3(x0, crest, bz + 4.0), ballast.darkened(0.1))
	_quad(Vector3(x0, crest, bz + 4.0), Vector3(x1, crest, bz + 4.0), Vector3(x1, _y(x1, bz + 20.0), bz + 20.0), Vector3(x0, _y(x0, bz + 20.0), bz + 20.0), ballast)
	for rz in [-1.5, 1.5]:
		_box(Vector3((x0 + x1) * 0.5, crest, bz + rz), Vector3(x1 - x0, 0.6, 0.5), Color(0.15, 0.13, 0.12))
	for i in 5:                                          # abgestellte Güterwagen
		var wx := -380.0 + i * 13.5
		_box(Vector3(wx, crest + 0.6, bz), Vector3(12.0, 4.2, 3.2), _haze(Color(0.33, 0.22, 0.17)))
	var py := PLATEAU_Y - 0.5
	# lange Hallen mit Satteldach (First quer zum Blick)
	var halls := [[-60.0, -35.0, 150.0], [40.0, -5.0, 170.0], [-30.0, 28.0, 190.0], [150.0, 52.0, 120.0]]
	for h in halls:
		var hx: float = h[0]
		var hz: float = h[1]
		var l: float = h[2]
		_box(Vector3(hx, py, hz), Vector3(l, 13.0, 24.0), concrete if int(hz) % 2 == 0 else concrete2)
		_gable_roof(Vector3(hx, py + 13.0, hz), l + 1.5, 25.5, 7.5, roof, concrete)
		_window_row(hx, py + 4.0, hz - 12.1, l - 8.0, 9, 3.0, 4.0, rng)
		_window_row(hx, py + 8.6, hz - 12.1, l - 8.0, 9, 3.0, 2.2, rng)
	# zwei Silos nebeneinander (links)
	for sx in [205.0, 226.0]:
		var sz := -20.0
		_lathe(Vector3(sx, py, sz), [[10.0, 0.0], [10.0, 42.0], [6.0, 46.0], [0.0, 47.0]], 10, concrete)
	_box(Vector3(215.5, py + 42.0, -20.0), Vector3(12.0, 3.0, 3.0), concrete2)
	# mehrstöckiges Werksgebäude rechts mit kleinem Turm
	var wx2 := -250.0
	var wz2 := -20.0
	_box(Vector3(wx2, py, wz2), Vector3(70.0, 30.0, 24.0), concrete)
	_hip_cap(Vector3(wx2, py + 30.0, wz2), 71.0, 25.0, 7.0, roof)
	_box(Vector3(wx2 + 18.0, py + 30.0, wz2), Vector3(8.0, 14.0, 8.0), concrete)
	_hip_cap(Vector3(wx2 + 18.0, py + 44.0, wz2), 9.0, 9.0, 6.0, roof)
	for fl in 5:
		_window_row(wx2, py + 3.0 + fl * 5.6, wz2 - 12.1, 62.0, 12, 2.4, 3.0, rng)
	# Werkswohnhäuser vor dem Werksgebäude (Hangkante)
	for i in 6:
		var hx := -330.0 + i * 28.0
		var hz := -62.0 - float(i % 2) * 6.0
		var hy := _y(hx, hz) - 0.5
		_box(Vector3(hx, hy, hz), Vector3(18.0, 8.0, 10.0), concrete2)
		_gable_roof(Vector3(hx, hy + 8.0, hz), 19.0, 11.0, 4.5, _haze(Color(0.36, 0.20, 0.15)), concrete2)
		_window_row(hx, hy + 2.0, hz - 5.1, 14.0, 3, 1.4, 1.8, rng)
		_window_row(hx, hy + 5.2, hz - 5.1, 14.0, 3, 1.4, 1.6, rng)
	# Schlote (Backstein), schlank und hoch; dunkle Kopfbänder
	var tops := [[-170.0, 40.0, 175.0], [-105.0, 62.0, 195.0], [-25.0, 48.0, 165.0], [55.0, 70.0, 200.0], [120.0, 30.0, 180.0], [175.0, 75.0, 160.0]]
	for t in tops:
		var tx: float = t[0]
		var tz: float = t[1]
		var th: float = t[2]
		_lathe(Vector3(tx, py - 1.0, tz), [[5.0, 0.0], [4.2, th * 0.35], [3.0, th]], 8, brick)
		_lathe(Vector3(tx, py - 1.0 + th - 6.0, tz), [[2.95, 0.0], [2.85, 4.0], [2.85, 6.0]], 8, dark)
		_top_local.append(Vector3(tx, py - 1.0 + th, tz))

## Fensterreihe auf der Fassade zum Betrachter (z = Fassadenebene); ≈ 18 % landen im nachts leuchtenden Fenster-Mesh.
func _window_row(cx: float, y: float, z: float, width: float, n: int, w: float, h: float, rng: RandomNumberGenerator) -> void:
	for i in n:
		var x := cx - width * 0.5 + width * (i + 0.5) / n
		var a := Vector3(x - w * 0.5, y, z)
		var b := Vector3(x + w * 0.5, y, z)
		if rng.randf() < 0.18:
			var keep := _st
			_st = _lit_st
			_quad(a, b, b + Vector3.UP * h, a + Vector3.UP * h, Color.WHITE)
			_st = keep
		else:
			_quad(a, b, b + Vector3.UP * h, a + Vector3.UP * h, Color(0.12, 0.13, 0.14))

# ---------------------------------------------------------------- Nadelwald hinter und neben dem Werk
func _forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6119
	var n := 0
	while n < 300:
		var x := rng.randf_range(-720.0, 720.0)
		var z := rng.randf_range(-80.0, 420.0)
		if z < 105.0 and x > -330.0 and x < 260.0:
			continue                                     # Werksgelände frei
		if z < -40.0 and absf(x) < 560.0:
			continue
		n += 1
		var y := _y(x, z) - 0.8
		var hgt := rng.randf_range(24.0, 36.0)
		var rad := hgt * rng.randf_range(0.18, 0.24)
		var c := _haze(Color(0.10, 0.17, 0.11).lerp(Color(0.15, 0.21, 0.12), rng.randf()))
		_lathe(Vector3(x, y, z), [[rad, hgt * 0.12], [rad * 0.6, hgt * 0.55], [0.0, hgt]], 5, c)

# ---------------------------------------------------------------- Rauch und Glimmen (je ein Emitter für alle Schlote)
func _points_texture(center: Vector3) -> ImageTexture:
	var data := PackedFloat32Array()
	for t in _top_local:
		var p := t * SCALE - center
		data.append_array([p.x, p.y, p.z])
	var img := Image.create_from_data(_top_local.size(), 1, false, Image.FORMAT_RGBF, data.to_byte_array())
	return ImageTexture.create_from_image(img)

func _tops_center() -> Vector3:
	var c := Vector3.ZERO
	for t in _top_local:
		c += t * SCALE
	return c / maxf(_top_local.size(), 1)

func _chimney_smoke() -> GPUParticles3D:
	var c := _tops_center()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _points_texture(c)
	pm.emission_point_count = _top_local.size()
	pm.direction = Vector3.UP
	pm.spread = 6.0
	pm.initial_velocity_min = 1.6 * fx_k
	pm.initial_velocity_max = 2.2 * fx_k
	pm.gravity = Vector3(0.11, -0.01, 0.03)          # Wind: Fahnen neigen sich zur Seite
	pm.damping_min = 0.01
	pm.damping_max = 0.03
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.25))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 1, 1, 0))
	cr.set_color(1, Color(1, 1, 1, 0))
	cr.add_point(0.05, Color(0.9, 0.9, 0.9, 0.9))
	cr.add_point(0.55, Color(1, 1, 1, 0.5))
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
	var p := _particles(c, 16 * _top_local.size(), 36.0, pm, _smoke_mat, 14.0 * fx_k)
	p.name = "Rauch"
	return p

func _chimney_glow() -> GPUParticles3D:
	var c := _tops_center()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _points_texture(c)
	pm.emission_point_count = _top_local.size()
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.3 * fx_k
	pm.initial_velocity_max = 0.8 * fx_k
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 0.8, 0.4, 0))
	cr.set_color(1, Color(0.8, 0.2, 0.05, 0))
	cr.add_point(0.3, Color(1, 0.55, 0.2, 1))
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
	var p := _particles(c, 3 * _top_local.size(), 1.4, pm, _fire_mat, 3.2 * fx_k)
	p.name = "Glimmen"
	return p
