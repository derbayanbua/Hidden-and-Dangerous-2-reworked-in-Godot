extends SceneTree
## Packt res://custom_maps/<id>/ als <id>.pck (aufgerufen von tools/export_custom_map.ps1).
## Packs res://custom_maps/<id>/ into <id>.pck (called by tools/export_custom_map.ps1).
##   godot --headless -s res://tools/pack_custom_map.gd -- --map=<id> --out=<pfad> [--install_user=1]


func _initialize() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var id := String(a.get("map", ""))
	var out := String(a.get("out", ""))
	var packer := load("res://src/mission/custom_map_packer.gd")
	var cm := load("res://src/mission/custom_maps.gd")
	var err := "Aufruf / usage: --map=<id> --out=<datei.pck>" if id == "" or out == "" else ""
	if err == "":
		err = packer.pack("res://custom_maps/" + id, id, out)
	if err == "":
		var listing: Dictionary = cm.read_pck_listing(out)
		err = String(listing.get("error", ""))
		if err == "":
			err = cm.check_listing(listing["files"], id)
	if err == "" and a.has("install_user"):
		DirAccess.make_dir_recursive_absolute("user://maps")
		var dst := ProjectSettings.globalize_path("user://maps").path_join(id + ".pck")
		if DirAccess.copy_absolute(out, dst) != OK:
			err = "Kopieren nach user://maps fehlgeschlagen / copy failed"
		else:
			print("PACK_USER ", dst)
	if err != "":
		printerr("PACK_FEHLER / PACK_ERROR: ", err)
		quit(1)
		return
	print("PACK_OK ", out, " sha256=", FileAccess.get_sha256(out))
	quit(0)
