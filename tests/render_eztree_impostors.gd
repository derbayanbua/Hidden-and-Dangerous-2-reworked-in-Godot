extends Node
## Impostor-Bilder der EZ-Tree-Bäume rendern (FENSTER, kein Kopflos-Lauf):
##   tools\godot.cmd -- --autoplay=render_eztree_impostors
## → assets/maps/bavaria/trees_eztree/impostor/<art>.png (Atlas 2048×1024: links Ansicht von vorn, rechts von der Seite,
## Albedo + Alpha, ungeschattet) und impostors.json (Kantenlänge S des quadratischen Ausschnitts je Art).
## Ausschnitt: S = max(Höhe, 2·max|x|, 2·max|z|)·1,04, Stammfuß bei y = 0, unten 2 % Rand (wie eztree.gd impostor_mesh).
const EzTree := preload("res://src/maps/bavaria/eztree.gd")
const OUT := "res://assets/maps/bavaria/trees_eztree/impostor/"
const RES := 1024

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.current = true
	var sizes := {}
	for key in EzTree.HEIGHTS:
		var tree := EzTree.load_template(key)
		if tree == null:
			push_error("fehlt: " + key)
			continue
		vp.add_child(tree)
		var s := EzTree.impostor_size(tree)
		sizes[key] = s
		cam.size = s
		var atlas := Image.create(RES * 2, RES, false, Image.FORMAT_RGBA8)
		for view in 2:
			var c := Vector3(0, s * 0.48, 0)
			var eye := c + (Vector3(0, 0, 100) if view == 0 else Vector3(100, 0, 0))
			cam.look_at_from_position(eye, c, Vector3.UP)
			cam.far = 300.0
			for f in 4:
				await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(0, 0, RES, RES), Vector2i(view * RES, 0))
		atlas.fix_alpha_edges()      # Farbe in transparente Säume (keine dunklen Ränder in den Mipmaps)
		atlas.save_png(OUT + key + ".png")
		print("IMPOSTOR ", key, " S=", s)
		tree.queue_free()
		await get_tree().process_frame
	var f := FileAccess.open(OUT + "impostors.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(sizes, "\t"))
	f.close()
	print("ERGEBNIS render_eztree_impostors: %d Impostoren, 0 fehlgeschlagen" % sizes.size())
	get_tree().quit(0)
