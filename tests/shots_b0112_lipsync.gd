extends "res://tests/test_systems.gd"
## B-052 Kontrollbilder (FENSTER): sprechende Figur in der Zwischensequenz, Nahaufnahme des Gesichts.
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_b0112_lipsync
## -> test_output/b0112_lip_*.png (Szene + Nahaufnahme je erkanntem Satz, höchstens 4 Sätze)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var tag := String(Game.cli.get("tag", ""))     # 0.11.7: --tag=<mission> trennt die Bilder je Mission
	img.save_png(ProjectSettings.globalize_path("res://test_output/b0112_lip_%s%s.png" % [(tag + "_") if tag != "" else "", name]))
	print("BILD ", name)


func _head(who: Node3D) -> Vector3:
	# 0.11.7: zuerst das animierte Skelett (statische Darsteller haben zusätzlich ausgeblendete Frames „f“ in Ruhelage)
	for n in who.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		var b := sk.find_bone("f")
		if b >= 0:
			return sk.global_transform * sk.get_bone_global_pose(b).origin
	for n in who.find_children("f", "", true, false):
		if n is Node3D:
			return (n as Node3D).global_position
	return who.global_position + Vector3.UP * 1.65


func _run() -> void:
	var done := 0
	var seen := {}
	var t0 := Time.get_ticks_msec()
	var god_done := false
	while done < 4 and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().process_frame
		if not god_done and mission() and mission().squad:      # Trupp unverwundbar (Testregel)
			for sm in mission().squad.members:
				sm.max_health = 100000.0
				sm.health = sm.max_health
			god_done = not mission().squad.members.is_empty()
		for ls in get_tree().root.find_children("LipSync", "Node", true, false):
			var who := ls.get_parent() as Node3D
			if who == null or seen.has(ls.get_instance_id()):
				continue
			seen[ls.get_instance_id()] = true
			# Mund offen abwarten (bis 1,5 s)
			for i in 90:
				await get_tree().process_frame
				if not is_instance_valid(ls):
					break
				var w: Dictionary = ls.last_weights
				if float(w.get("m0_1", 0.0)) + float(w.get("m0_2", 0.0)) > 0.4:
					break
			if not is_instance_valid(who):
				continue
			await _shot("%d_szene" % done)
			var old := get_viewport().get_camera_3d()
			var cam := Camera3D.new()
			cam.fov = 30.0
			get_tree().root.add_child(cam)
			var h := _head(who)
			var fwd := -who.global_transform.basis.z.normalized()
			if old:      # 0.11.7: von der Seite der Szenenkamera auf das Gesicht (Blickrichtung des Darstellers unsicher)
				var to_cam := old.global_position - h
				to_cam.y = 0.0
				if to_cam.length() > 0.3:
					fwd = to_cam.normalized()
			cam.global_position = h + fwd * 0.9 + Vector3.UP * 0.05
			cam.look_at(h, Vector3.UP)
			cam.make_current()
			await _shot("%d_gesicht_%s" % [done, who.name])
			cam.queue_free()
			if old:
				old.make_current()
			done += 1
	check(done > 0, "Sprechende Figur aufgenommen", str(done))
	_finish()
