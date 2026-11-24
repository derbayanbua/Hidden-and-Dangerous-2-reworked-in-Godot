extends RefCounted
## Baut eine eigene Karte als .pck (PCKPacker). Genutzt von tools/pack_custom_map.gd (Exportskript) und test_custom_maps.
## Builds a custom map .pck. Ziel im Paket: res://custom_maps/<id>/<relativer Pfad>; zu jeder .import-Datei werden die
## importierten Daten (res://.godot/imported/…) mitgenommen. Platzhalter __MAP_ID__ in Textdateien wird ersetzt.

const TEXT_EXT := ["json", "tscn", "tres", "gd", "md", "txt", "cfg"]
const SKIP := [".gdignore", "Thumbs.db", ".DS_Store"]


static func _walk(abs_dir: String, rel: String, out: Array[String]) -> void:
	var d := DirAccess.open(abs_dir.path_join(rel))
	if d == null:
		return
	for f in d.get_files():
		if SKIP.has(f) or f.ends_with(".tmp"):
			continue
		out.append(rel.path_join(f) if rel != "" else f)
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_walk(abs_dir, rel.path_join(sub) if rel != "" else sub, out)


## src_dir: Ordner der Karte (res:// oder absolut). Rückgabe "" = OK, sonst Fehlertext.
static func pack(src_dir: String, id: String, out_path: String) -> String:
	var cm := preload("res://src/mission/custom_maps.gd")
	if not cm.valid_id(id):
		return "ungültige ID / invalid id (a-z, 0-9, _): " + id
	var abs_src := ProjectSettings.globalize_path(src_dir)
	var files: Array[String] = []
	_walk(abs_src, "", files)
	if not files.has("map.json"):
		return "map.json fehlt in / missing in " + src_dir
	var man_txt := FileAccess.get_file_as_string(abs_src.path_join("map.json")).replace("__MAP_ID__", id)
	var info: Dictionary = cm.validate_manifest(JSON.parse_string(man_txt), id)
	if info.has("error"):
		return "Manifest: " + String(info["error"])
	var tmp := ProjectSettings.globalize_path("user://custom_map_pack_tmp")
	DirAccess.make_dir_recursive_absolute(tmp)
	var pk := PCKPacker.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
	if pk.pck_start(ProjectSettings.globalize_path(out_path)) != OK:
		return "Ausgabe nicht schreibbar / output not writable: " + out_path
	var added := {}
	var re := RegEx.new()
	re.compile("\"(res://\\.godot/imported/[^\"]+)\"")
	var n := 0
	for rel in files:
		var src := abs_src.path_join(rel)
		var target := "%s/%s/%s" % [cm.MANIFEST_ROOT, id, rel]
		if TEXT_EXT.has(rel.get_extension().to_lower()):
			var txt := FileAccess.get_file_as_string(src)
			if txt.contains("__MAP_ID__"):
				src = tmp.path_join("f%d.%s" % [n, rel.get_extension()])
				n += 1
				var w := FileAccess.open(src, FileAccess.WRITE)
				w.store_string(txt.replace("__MAP_ID__", id))
				w.close()
		if pk.add_file(target, src) != OK:
			return "Datei nicht aufnehmbar / cannot add: " + rel
		if rel.ends_with(".import"):
			for m in re.search_all(FileAccess.get_file_as_string(abs_src.path_join(rel))):
				var imp := m.get_string(1)
				if added.has(imp):
					continue
				var imp_abs := ProjectSettings.globalize_path(imp)
				if not FileAccess.file_exists(imp_abs):
					return "importierte Datei fehlt (vorher --import ausführen) / imported file missing: " + imp
				if pk.add_file(imp, imp_abs) != OK:
					return "Datei nicht aufnehmbar / cannot add: " + imp
				added[imp] = true
	if pk.flush() != OK:
		return "Schreiben fehlgeschlagen / flush failed"
	return ""
