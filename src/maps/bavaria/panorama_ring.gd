extends MeshInstance3D
## Umlaufende Fernkulisse als Geometrie: offener Zylinder um die Kartenmitte mit den Panoramabildern
## (Süd = Alpenband, Nord/Ost/West = Landschaftsstreifen) statt Streifen im Himmelsshader. Dadurch Parallaxe,
## Bildwinkel unverzerrt vergrößert (Shader-Uniforms zoom 1,6 bzw. alps_zoom 2,2), damit die Kulisse deutlich sichtbar ist;
## volle Bildschärfe (Mipmaps + anisotrope Filterung, leichtes Nachschärfen) und nur leichter eigener Dunst.
## Bilder, Sektorrichtungen und Abbildungsparameter übernimmt der Ring vom Himmelsmaterial (alps_sky.gdshader,
## gesetzt von scene_details.configure_sky); ohne Bilder entsteht kein Ring und der Himmel bleibt unverändert.
## Liegt hinter beiden Fern-Blickfängen (Dorf SW, Werk NO) und innerhalb der Kamera-far (Bavaria.VIEW_FAR).
## Ohne Schatten, ohne Kollision, nicht in der Navmesh-Quelle; ein Zeichenaufruf.
## [m] waagrecht ab Kartenmitte: knapp hinter Außenwald, Dorf (landmark.gd) und Werk (factory_landmark.gd), nur ein schmaler
## Wiesenstreifen bis zum Ring. Grenze bis 79 m von der Mitte → entferntester Ringpunkt ≈ 344 m < Bavaria.VIEW_FAR.
const RADIUS := 260.0
const EYE_Y := 1.4             ## Bildhorizont = Augenhöhe über dem Außenboden (−0,30 m) + 1,7 m
const BOTTOM_Y := -8.0         ## Unterkante unter dem Außenboden (kein Spalt)
const TOP_ELEV_DEG := 18.5     ## Oberkante [°] über dem Horizont (Südgipfel bis ≈ 17°, übrige Streifen ≈ 7° × zoom 1,6)
## Südstreifen (Alpenkette über Tal, Himmel transparent, Ränder weich; erzeugt aus panorama/source), ersetzt im Ring das
## blasse Alpenband. params = (Augenhöhe als Bildzeile v, v je Radiant, u je Radiant, u der Südrichtung), ohne Zoom:
## 3064×600 px über 120° (±60°), gleicher Maßstab waagrecht/senkrecht; Talboden knapp unter Augenhöhe, Gipfel ≈ 13–17°.
const FAR_SOUTH := "res://assets/maps/bavaria/panorama/panorama_south.png"
const FAR_SOUTH_P := Vector4(0.7667, 2.439, 0.4775, 0.5)
const SEGMENTS := 256
const SKY_S := 0.5
var mission: Node
var center := Vector2.ZERO     ## Welt x/z der Kartenmitte
var material: ShaderMaterial
var _sky_mat: ShaderMaterial
var _t := 0.0

## Baut den Ring, falls der Himmel die Fernkulisse trägt. Rückgabe false = keine Bilder, kein Ring.
func build(m: Node, env: Environment) -> bool:
	mission = m
	name = "Panoramaring"
	_sky_mat = env.sky.sky_material as ShaderMaterial if env and env.sky else null
	if _sky_mat == null or _sky_mat.get_shader_parameter("far_enabled") != true:
		return false
	var b: PackedVector2Array = m.boundary
	for q in b:
		center += q
	center /= b.size()
	position = Vector3(center.x, 0.0, center.y)
	material = ShaderMaterial.new()
	material.shader = load("res://src/maps/bavaria/panorama_ring.gdshader")
	material.render_priority = Material.RENDER_PRIORITY_MIN   # vor Rauch/Partikeln der Blickfänge zeichnen
	for k in ["panorama", "far_north", "far_east", "far_west", "far_north_p", "far_east_p", "far_west_p",
			"south_direction", "panorama_repeats"]:
		var v = _sky_mat.get_shader_parameter(k)
		if v != null:
			material.set_shader_parameter(k, v)
	material.set_shader_parameter("south_enabled", _sky_mat.get_shader_parameter("panorama") != null)
	if ResourceLoader.exists(FAR_SOUTH):
		material.set_shader_parameter("far_south", load(FAR_SOUTH))
		material.set_shader_parameter("far_south_p", FAR_SOUTH_P)
		material.set_shader_parameter("far_south_enabled", true)
	material.set_shader_parameter("ring_center", Vector3(center.x, EYE_Y, center.y))
	material.set_shader_parameter("top_fade", deg_to_rad(TOP_ELEV_DEG))
	mesh = _cylinder()
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 16.0
	add_to_group("bavaria_panorama_ring")
	_sky_mat.set_shader_parameter("ring_active", true)
	_sync()
	return true

func top_y() -> float:
	return EYE_Y + RADIUS * tan(deg_to_rad(TOP_ELEV_DEG))

func _cylinder() -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var top := top_y()
	for i in SEGMENTS + 1:
		var a := TAU * float(i) / SEGMENTS
		var p := Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)
		verts.append(Vector3(p.x, BOTTOM_Y, p.z))
		verts.append(Vector3(p.x, top, p.z))
	for i in SEGMENTS:
		var k := i * 2
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = SKY_S
		_sync()

## Tageslicht/Nacht/Sonne vom Himmelsmaterial (day_night.gd setzt sie alle 0,5 s) übernehmen.
func _sync() -> void:
	if _sky_mat == null or material == null:
		return
	for k in ["daylight", "night", "sun_direction", "overcast", "rain_haze"]:
		var v = _sky_mat.get_shader_parameter(k)
		if v != null:
			material.set_shader_parameter(k, v)
	_sky_mat.set_shader_parameter("ring_active", true)
