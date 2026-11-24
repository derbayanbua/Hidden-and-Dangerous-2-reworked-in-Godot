extends RefCounted
## Ersetzt auf der Karte Bavaria Original-Spieltexturen (orig_cache) durch projekteigene, frei nutzbare Texturen
## aus res://assets/maps/bavaria/library/. Aufruf aus ground_surfaces.gd. Abschalten: --lib_tex=0 (1 = nur Schritt 1).
## Fehlt eine Textur, bleibt das bisherige Material.
const DIR := "res://assets/maps/bavaria/library/"
## [LevelBuilder-Materialschlüssel, Albedo, Normal ("" = keine), Rauheit ("" = keine), UV-Skala (Kacheln je m)]
const SPECS := [
	["plaster", "putz_hell_alt.png", "", "", 0.45],          # ersetzt 2e_v8w1
	["damaged", "putz_abgeplatzt.png", "", "", 0.45],        # ersetzt 2e_v8w1b
	["stone", "stein_trockenmauer.png", "", "", 0.5],        # ersetzt 2e_sw1
	["roof", "dach_ziegel_alt_albedo.png", "dach_ziegel_alt_normal.png", "dach_ziegel_alt_roughness.png", 0.4],  # ersetzt 2e_v8rf
	["slate", "dach_schiefer_albedo.png", "dach_schiefer_normal.png", "dach_schiefer_roughness.png", 0.45],     # ersetzt 2e_dosk
	["wood", "wand_holzvertikal_albedo.png", "wand_holzvertikal_normal.png", "wand_holzvertikal_roughness.png", 0.5],  # ersetzt 2e_vwoo2
	# Schritt 2: Ruinenboden und dunkles Holz
	["rubble", "kies_erdgemisch.png", "", "", 0.35],         # ersetzt 2e_wdmg2
	["darkwood", "wand_holzvertikal_albedo.png", "wand_holzvertikal_normal.png", "wand_holzvertikal_roughness.png", 0.5, Color(0.55, 0.45, 0.38)],  # ersetzt 2e_vwoo2 (dunkel)
	# Schritt 3: Ziegel und Boden-Ersatz (bei vorhandenen Bodenfotos übernimmt ground_surfaces.gd die Materialien,
	# tauscht die Albedo und schaltet Normal/Rauheit der Bibliothek wieder ab)
	["brick", "ziegelmauer_abgewittert_albedo.png", "ziegelmauer_abgewittert_normal.png", "ziegelmauer_abgewittert_roughness.png", 0.6],  # ersetzt 2e_v8w2
	["earth", "lehm_schlamm_pfuetzen_albedo.png", "lehm_schlamm_pfuetzen_normal.png", "lehm_schlamm_pfuetzen_roughness.png", 0.25],      # ersetzt 2e_wgr2
	["grass", "wiese_kies_mischung_albedo.png", "wiese_kies_mischung_normal.png", "wiese_kies_mischung_roughness.png", 0.25, Color(0.82, 0.9, 0.78)],  # ersetzt 2e_wgr1l
	["meadow", "wiese_kies_mischung_albedo.png", "wiese_kies_mischung_normal.png", "wiese_kies_mischung_roughness.png", 0.2],        # ersetzt g_al1_012
]

static func apply(lb: LevelBuilder) -> int:
	var level := int(String(Game.cli.get("lib_tex", "9")))   # 0 = aus, 1 = nur Schritt 1, sonst alles
	if level == 0:
		return 0
	var n := 0
	for i in SPECS.size():
		if level == 1 and i >= 6:
			break
		var s: Array = SPECS[i]
		var alb := _tex(s[1])
		if alb == null:
			continue
		var m := StandardMaterial3D.new()
		m.albedo_texture = alb
		if s.size() > 5:
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
	print("BAVARIA_LIBRARY ersetzt=", n)
	return n

static func _tex(file: String) -> Texture2D:
	if file == "" or not ResourceLoader.exists(DIR + file):
		return null
	return load(DIR + file) as Texture2D
