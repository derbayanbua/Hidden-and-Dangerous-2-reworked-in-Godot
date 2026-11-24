extends RefCounted
## Hilfsfunktionen der Testkarte Castle: Layout laden, Gelände, Materialien.
## Helpers for the Castle test map: layout loading, terrain, materials.
## Materialien nur aus projekteigenen freien Texturen (assets/maps/bavaria/library/); fehlt eine Datei,
## bleibt das prozedurale LevelBuilder-Material. Keine Originalspieldaten.

const LIB := "res://assets/maps/bavaria/library/"
## [LevelBuilder-Schlüssel, Albedo, Normal, Rauheit, Kacheln je m, Farbton]
const MATERIALS := [
	["grass", "wiese_kies_mischung_albedo.png", "wiese_kies_mischung_normal.png", "wiese_kies_mischung_roughness.png", 0.2, Color(0.82, 0.9, 0.78)],
	["stone", "stein_trockenmauer.png", "", "", 0.4, Color(0.8, 0.8, 0.8)],
	["plaster", "putz_hell_alt.png", "", "", 0.45, Color.WHITE],
	["wood", "wand_holzvertikal_albedo.png", "wand_holzvertikal_normal.png", "wand_holzvertikal_roughness.png", 0.5, Color.WHITE],
	["darkwood", "wand_holzvertikal_albedo.png", "", "", 0.5, Color(0.55, 0.45, 0.38)],
]


static func load_layout(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		push_error("Castle: Layout %s nicht lesbar" % path)
		return {}
	return d


static func polygon(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func height(t: Dictionary, x: float, z: float) -> float:
	var amp := float(t.get("amplitude", 0.0))
	if amp == 0.0:
		return 0.0
	var wx := maxf(float(t.get("wavelength_x", 46.0)), 1.0)
	var wz := maxf(float(t.get("wavelength_z", 62.0)), 1.0)
	return amp * sin(x / wx * TAU * 0.5) * cos(z / wz * TAU * 0.5)


## Regelmäßiges Dreiecksgitter über rect (x/z), Höhe aus height()
static func ground_mesh(t: Dictionary, rect: Rect2) -> ArrayMesh:
	var step := maxf(float(t.get("grid_step", 2.0)), 0.5)
	var nx := int(ceil(rect.size.x / step))
	var nz := int(ceil(rect.size.y / step))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz + 1:
		for ix in nx + 1:
			var x := rect.position.x + ix * step
			var z := rect.position.y + iz * step
			st.set_uv(Vector2(x, z) * 0.12)
			st.add_vertex(Vector3(x, height(t, x, z), z))
	for iz in nz:
		for ix in nx:
			var i := iz * (nx + 1) + ix
			# Vorderseite oben (Godot: im Uhrzeigersinn von oben gesehen)
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + nx + 1)
			st.add_index(i + 1)
			st.add_index(i + nx + 2)
			st.add_index(i + nx + 1)
	st.generate_normals()
	return st.commit()


static func apply_materials(lb: LevelBuilder) -> int:
	var n := 0
	for s in MATERIALS:
		var alb := _tex(s[1])
		if alb == null:
			continue
		var m := StandardMaterial3D.new()
		m.albedo_texture = alb
		m.albedo_color = s[5]
		m.roughness = 0.92
		var nrm := _tex(s[2])
		if nrm:
			m.normal_enabled = true
			m.normal_texture = nrm
			m.normal_scale = 0.6
		var rgh := _tex(s[3])
		if rgh:
			m.roughness = 1.0
			m.roughness_texture = rgh
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * float(s[4])
		lb._mats[String(s[0])] = m
		n += 1
	return n


static func _tex(file: String) -> Texture2D:
	if file == "" or not ResourceLoader.exists(LIB + file):
		return null
	return load(LIB + file)


const KIT_TEX := "res://assets/maps/castle/kit/textures/"
## Materialien der echten Burg aus dem Burgbaukasten: [Schlüssel, Set, Kacheln je m, Farbton]
const KIT_MATERIALS := [
	["c_wall", "tuffmauer_moertel", 0.25, Color.WHITE],
	["c_stone", "stein_bruchmauer", 0.3, Color.WHITE],
	["c_plaster", "kalkputz_abgewittert", 0.25, Color.WHITE],
	["c_plaster2", "putz_creme", 0.3, Color(0.95, 0.93, 0.88)],
	["c_roof", "dachziegel_rot", 0.35, Color(0.85, 0.8, 0.78)],
	["c_roof2", "dachpfanne_braun_alt", 0.3, Color.WHITE],
	["c_paving", "tuffstein_moosig", 0.3, Color(0.82, 0.82, 0.8)],
	["c_steps", "treppenstein_abgelaufen", 0.5, Color.WHITE],
	["c_earth", "keller_erdreich", 0.2, Color(0.9, 0.85, 0.78)],
	["c_moss", "tuffstein_moosig", 0.25, Color.WHITE],
	["c_wood", "holz_eiche_altert", 0.5, Color.WHITE],
	# Abgleich mit Referenzansichten (0.12.2): Hauptweg und Hof der Hauptburg mit Katzenkopfpflaster, Gehstreifen Kies
	["c_cobble", "katzenkopfpflaster", 0.9, Color(0.92, 0.92, 0.9)],
	["c_gravel", "erdweg_kies", 0.35, Color(0.95, 0.93, 0.9)],
	# Abgleich 3D-Rundgang (0.12.2): Flusskieselpflaster (innere Höfe) und heller Sandweg (äußere Höfe), eigene prozedurale
	# Texturen aus tools/gen_castle_ground.py (Kachel 1,2 m bzw. 2,0 m)
	["c_pebble", "flusskiesel_pflaster", 0.83, Color.WHITE],
	["c_sand", "sandweg_hell", 0.5, Color(0.88, 0.86, 0.82)],
	["c_hedge", "schnitthecke", 1.0, Color.WHITE],
]


static func apply_kit_materials(lb: LevelBuilder) -> void:
	for s in KIT_MATERIALS:
		var alb := _kit_tex(s[1] + "_albedo.png")
		var m := StandardMaterial3D.new()
		m.albedo_color = s[3]
		m.roughness = 0.95
		if alb:
			m.albedo_texture = alb
			var nrm := _kit_tex(s[1] + "_normal.png")
			if nrm:
				m.normal_enabled = true
				m.normal_texture = nrm
				m.normal_scale = 0.7
			var rgh := _kit_tex(s[1] + "_roughness.png")
			if rgh:
				m.roughness = 1.0
				m.roughness_texture = rgh
				m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		else:
			m.albedo_color = Color(0.6, 0.58, 0.55)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if String(s[0]).begins_with("c_roof"):
			# Dächer: UV entlang der Dachneigung (castle_buildings), Ziegelreihen parallel zur Traufe
			m.uv1_scale = Vector3.ONE
			m.normal_scale = 0.4
		else:
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE * float(s[2])
		lb._mats[String(s[0])] = m
	# Gras im Hof (Bibliothek „grass“) und dunklere Hänge
	var g: StandardMaterial3D = lb.mat("grass")
	lb._mats["c_grass"] = g
	var sl := g.duplicate() as StandardMaterial3D
	sl.albedo_color = g.albedo_color * Color(0.8, 0.85, 0.75)
	lb._mats["c_slope"] = sl


## Fassaden/Dächer/Gelände aus dem Burgfassaden-Pack (kit/textures): [Schlüssel, Set, triplanar (Kacheln je m) oder 0 = UV]
## Fassaden-UV: Breite/Höhe der Textur in Metern (FACADE_SIZE), 4-m-Geschosse.
const PACK17 := [
	["f_kalk1", "kalkputz_geschoss_8m", 0.0], ["f_kalk2", "kalkputz_fenster_2g_8m", 0.0],
	["f_kalk3", "kalkputz_fenster_3g_8m", 0.0], ["f_kalk4", "kalkputz_fenster_4g_8m", 0.0],
	["f_gothic", "kapelle_spitzbogen_8m", 0.0], ["f_palas", "palas_fenster_8m", 0.0],
	["f_tuff", "tuffwand_schiessscharten_8m", 0.0], ["f_tuffwin", "tuffwand_kleinfenster_8m", 0.0],
	["f_retain", "hang_stuetzmauer_alt", 0.0],
	["r_bib1", "dach_biberschwanz_alt", 0.0], ["r_bib2", "dach_biberschwanz_verwittert", 0.0],
	["r_mn1", "dach_moench_nonne_alt", 0.0], ["r_mn2", "dach_moench_nonne_verwittert", 0.0],
	["c_rock", "nagelfluh_konglomerat", 0.18], ["c_rock2", "nagelfluh_moosig", 0.18],
	["c_ditch", "graben_erde_gras", 0.2], ["c_retain", "hang_stuetzmauer_alt", 0.25],
]
const FACADE_SIZE := {"f_kalk1": Vector2(8, 4), "f_kalk2": Vector2(8, 8), "f_kalk3": Vector2(8, 12), "f_kalk4": Vector2(8, 16),
	"f_gothic": Vector2(8, 8), "f_palas": Vector2(8, 8), "f_tuff": Vector2(8, 4), "f_tuffwin": Vector2(8, 4), "f_retain": Vector2(4, 4)}
const ROOF_MATS := ["r_bib1", "r_bib2", "r_mn1", "r_mn2"]


static func apply_pack17_materials(lb: LevelBuilder) -> void:
	for s in PACK17:
		var alb := _kit_tex(s[1] + "_albedo.png")
		if alb == null:
			continue    # Datei fehlt: bisheriges Material bleibt (Schlüssel fällt in castle_buildings zurück)
		var m := StandardMaterial3D.new()
		m.albedo_texture = alb
		m.roughness = 1.0
		var nrm := _kit_tex(s[1] + "_normal.png")
		if nrm:
			m.normal_enabled = true
			m.normal_texture = nrm
			m.normal_scale = 0.6
		var rgh := _kit_tex(s[1] + "_roughness.png")
		if rgh:
			m.roughness_texture = rgh
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if float(s[2]) > 0.0:
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE * float(s[2])
		else:
			# LoD2-Wand-/Dachflächen beidseitig: einzelne verdreht orientierte Teilflächen ließen sonst Himmelsstreifen durch
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		lb._mats[String(s[0])] = m


static func has_mat(lb: LevelBuilder, key: String) -> bool:
	return lb._mats.has(key)


static func _kit_tex(file: String) -> Texture2D:
	return load(KIT_TEX + file) if ResourceLoader.exists(KIT_TEX + file) else null
