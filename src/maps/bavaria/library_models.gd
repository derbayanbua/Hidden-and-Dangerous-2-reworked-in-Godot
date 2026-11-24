extends RefCounted
## Bavaria: projekteigene Low-Poly-Modelle (res://assets/maps/bavaria/library/models/, frei nutzbar).
## 1) REPLACE: Original-Requisiten (orig_cache) mit passender Größe/Funktion werden in Templates.prop ersetzt.
##    Ersetzt wird nur, wenn der Grundriss des Bibliotheksmodells höchstens ±35 % vom Original abweicht.
## 2) Zusätzliche Dorfausstattung setzt war_decoration.gd (EXTRAS). Feld/Wiese nicht: dort liegen schon Trichter,
##    Wagen und Erdwälle aus field_trenches.gd, deren Plätze sonst belegt würden.
## Schalter: --lib_models=0 = alles wie vorher (Originalmodelle, keine Zusätze).
const DIR := "res://assets/maps/bavaria/library/models/"
## Wert = Modell oder Kandidatenliste (erstes, das die Grundrissregel erfüllt, gilt für alle Aufrufe des Schlüssels).
const REPLACE := {
	"e_wcase": "holzschrank",          # Kleiderschrank 1,66 × 2,0 × 0,91 → 1,58 × 2,14 × 0,86
	"e_ktable": "esstisch_mit_decke",  # Küchentisch 2,2 × 1,0 × 1,2 → 1,45 × 1,07 × 0,78 (kleiner, Durchgänge bleiben frei)
	# Gap-Fill (Pack 10)
	"e_chair": "holzstuhl_bauern",
	"e_armch2": "sessel_polster_1930",
	"m_af5_umyv01": "waschbecken_wand",
	"m_af5_zachod01": "abort_holzsitz",
	"e_covrlt": "decke_gefaltet",
	"e_flaska1": "glasflasche_gruen",
	"e_flaska2": "krug_steingut",
	"e_kicpot": "kochtopf_emaille_gross",
	"w_pliers": "zange_werkzeug",
	# vorhandene Bibliothek (Packs 04–07)
	"e_shelvs": "oelregal",
	# Eigenmodelle 0.12.3 in Originalgröße (Grundriss und Höhe höchstens wie das Original, damit jeder Platz passt)
	"e_boiler": "boiler_badeofen",           # Badeofen mit Kupferkessel und Rauchrohr
	"e_bucket": "eimer_zink_gross",
	"e_hanger": "garderobe_staender",
	"e_repbox": "schubladenkommode_klein",
	"ja_vobraz07": "wandbild_quadrat",       # eigenes Landschaftsmotiv, beidseitig
	"k_g_kamna": "kanonenofen_rund",
	"m_af5_vana01": "badewanne_guss_lang",
	"e_kacbnt": "kuechenanrichte_niedrig",   # bleibt unter der Fensterbrüstung (Einrichtungsprüfung)
	"e_gstove": "herd_klein",                # Herdplatte auf Originalhöhe (Topf), kleinerer Grundriss
	"e_matrce": "matratze_drell",            # nur Matratze, das Holzgestell bleibt
	"e_pbx1": "holzkiste_gross",
	"ja_klada2": "rundholz_stamm",
	"ja_drevo": "brennholzstapel_lang",
	"k_barelmir3": "fass_eiche",
	"e_wuchar": "holzbottich_hoch",
}
## Direkt geladene Wracks/Aggregat/Flugzeuge (war_decoration._asset, meadow_cover._aircraft); gleiche Grundrissregel.
## Eigenmodelle 0.12.3 im Originalgrundriss: PKW mit offenen Fensterflächen (Mesh-Kollision, durchschießbar),
## Jäger- und Transporterwrack (gleicher Platz, Seitenroute und Turmsicht frei).
const WRECKS := {
	"la_hakl_vrak01": "halbkettenfahrzeug_3d",
	"la_tiger_vrak01": "panzerwrack_3d",
	"la_agreg01": "feldgenerator",
	"la_citr_vrak01": "pkw_wrack_offen",
	"la_spitfire": "jaeger_wrack",
	"cutletadlo_af2": "transporter_wrack",
}
## Heckenstrauch mit eigenem Stamm-Mesh „tree“ (Stammerdung wie die Originalsträucher), scene_details._hedge.
const HEDGE := "lib:heckenstrauch"
## Laufzeitbericht: Schlüssel → Bibliotheksmodell bzw. "" (Grundrissregel verworfen)
static var report := {}
## [Name, Modell, Referenzpixel (Layout), Drehung, Kollision]
const EXTRAS := [
	["Pumpe_Hof", "wasserpumpe_hand", [565, 940], 0.3, true],
	["Wegkreuz_Dorfrand", "wegkreuz", [300, 880], 0.6, true],
	["Brennholz_Sued", "brennholz_unterstand", [700, 1125], 0.5, true],
	["Schutt_Zeilen", "ziegelschutt", [930, 800], 0.2, true],
	# Pack 07: Dorftechnik und Hofausstattung (Platz über die Schutzregeln von war_decoration._site)
	["Telegrafenmast_Mitte", "telegrafenmast_dorf", [800, 690], 0.0, true],
	["Telegrafenmast_Ost", "telegrafenmast_dorf", [900, 820], 0.0, true],
	["Wegweiser_Dorfrand", "wegweiser_alt_holz", [330, 900], 0.8, true],
	["Bienenstoecke_Garten", "bienenstoecke_3", [700, 1100], 0.5, true],
	["Milchkannen_Hof", "milchkannen_regal", [590, 960], 1.2, true],
]
## Verworfen (Pack 07): Telegrafenmast am Nordfeld, Handpflug am Feldrand und Heutrockengestell auf der Wiese – belegten Plätze der
## Erdwälle/Sandsacknester aus field_trenches.gd (test_bavaria_clipping rot).

static var _cache := {}

static func enabled() -> bool:
	return String(Game.cli.get("lib_models", "1")) != "0"

static func load_model(name: String) -> Node3D:
	if not _cache.has(name):
		var path := DIR + name + ".glb"
		var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
		_cache[name] = scene
	var s: PackedScene = _cache[name]
	if s == null:
		return null
	var root := s.instantiate() as Node3D
	if FLAT_NORMALS.has(name):
		_flat_normals(root)
	# Die meisten Teile sind nur über Vertexfarben (COLOR_0) eingefärbt und haben kein Material:
	# ohne eigenes Material zeigt Godot sie weiß.
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			var has_color := mesh is ArrayMesh and ((mesh as ArrayMesh).surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0
			var untextured := mat == null or (mat.albedo_texture == null and not mat.vertex_color_use_as_albedo)
			if has_color and untextured:
				(mi as MeshInstance3D).set_surface_override_material(i, _vertex_color_material())
	return root

## Modelle aus Quadern mit geteilten Eckpunkten und ohne Normalen: der Import mittelt die Normalen diagonal über die
## Ecken → verschmierte Schattierung und Schattenakne (feines Korn auf den Flächen). Hier flach neu berechnet.
const FLAT_NORMALS := ["bienenstoecke_3"]
static var _flat_cache := {}

static func _flat_normals(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var src: Mesh = (mi as MeshInstance3D).mesh
		if src == null:
			continue
		if not _flat_cache.has(src):
			var out := ArrayMesh.new()
			for i in src.get_surface_count():
				var arr := src.surface_get_arrays(i)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var cols = arr[Mesh.ARRAY_COLOR]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
				var nv := PackedVector3Array()
				var nn := PackedVector3Array()
				var nc := PackedColorArray()
				for t in range(0, idx.size(), 3):
					var a := verts[idx[t]]
					var b := verts[idx[t + 1]]
					var c := verts[idx[t + 2]]
					var n := (c - a).cross(b - a).normalized()   # Godot: Vorderseite im Uhrzeigersinn
					for k in 3:
						nv.append(verts[idx[t + k]])
						nn.append(n)
						if cols != null:
							nc.append((cols as PackedColorArray)[idx[t + k]])
				var na := []
				na.resize(Mesh.ARRAY_MAX)
				na[Mesh.ARRAY_VERTEX] = nv
				na[Mesh.ARRAY_NORMAL] = nn
				if cols != null:
					na[Mesh.ARRAY_COLOR] = nc
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
				out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(i))
			_flat_cache[src] = out
		(mi as MeshInstance3D).mesh = _flat_cache[src]

static var _vc_mat: StandardMaterial3D
static func _vertex_color_material() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.vertex_color_is_srgb = true
		_vc_mat.roughness = 0.9
	return _vc_mat

## Ersatz für ein Original-Template: null = Original behalten.
static func replacement(key: String, original: Node3D, bounds_fn: Callable, table: Dictionary = REPLACE) -> Node3D:
	if not enabled() or not table.has(key):
		return null
	var cands: Array = table[key] if table[key] is Array else [table[key]]
	for name in cands:
		var lib := load_model(name)
		if lib == null:
			continue
		if original != null:
			var a: AABB = bounds_fn.call(original, Transform3D.IDENTITY)
			var b: AABB = bounds_fn.call(lib, Transform3D.IDENTITY)
			var fa := maxf(a.size.x, a.size.z)
			var fb := maxf(b.size.x, b.size.z)
			if fa <= 0.0 or fb / fa > 1.35 or fb / fa < 0.65:
				print("BAVARIA_LIBRARY_MODEL verworfen ", key, " → ", name, " Grundriss %.2f → %.2f m" % [fa, fb])
				lib.free()
				continue
		lib.set_meta("library_model", name)
		report[key] = name
		print("BAVARIA_LIBRARY_MODEL ", key, " → ", name)
		return lib
	report[key] = ""
	return null

## Bibliotheksvegetation/-requisite ohne Original (Templates.prop-Schlüssel „lib:<modell>“).
static func is_lib_key(key: String) -> bool:
	return key.begins_with("lib:")
