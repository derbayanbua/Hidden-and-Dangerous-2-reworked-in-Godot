extends "res://tests/shots_graphics.gd"
## 0.11.7 Lichtstimmung je Grafikstufe vergleichen (FENSTER, nicht headless). Gleiche Kameralage, Stufen 0..4,
## Bilder + mittlere Helligkeit/Farbe je Bild, Abweichung gegen Stufe 2 (Hoch).
##   tools\godot.cmd -- --mission=a1_blizzard --autoplay=shots_light_quality [--levels=0,1,2,3,4] [--tag=]
## → test_output/light_quality/<mission><tag>_q<n>_{sky,horizon,ground}.png, light_quality_<mission><tag>.txt
## Trupp unverwundbar (Gesundheit wird jedes Bild aufgefüllt), Gegner angehalten.

const VIEWS := {"sky": 30.0, "horizon": 3.0, "ground": -25.0}


func _shot_lq(name: String) -> Vector4:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/light_quality"))
	var mid := String(Game.cli.get("mission", "mission")) + String(Game.cli.get("tag", ""))
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://test_output/light_quality/%s_%s.png" % [mid, name])
	var sm: Image = img.duplicate()
	sm.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var acc := Vector4.ZERO
	for y in sm.get_height():
		for x in sm.get_width():
			var c: Color = sm.get_pixel(x, y)
			acc += Vector4(c.r, c.g, c.b, 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	return acc / float(sm.get_width() * sm.get_height())


func _god(m) -> void:
	while is_inside_tree():
		if m and is_instance_valid(m) and m.squad:
			for s in m.squad.members:
				if is_instance_valid(s) and s.alive:
					s.health = maxf(s.health, 100.0)
		await get_tree().process_frame


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	if m == null:
		check(false, "Mission geladen")
		_finish()
		return
	_god(m)
	await _wait_player_control(m)
	for e in m.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	var levels: Array = []
	for t in String(Game.cli.get("levels", "0,1,2,3,4")).split(","):
		levels.append(int(t))
	var res := {}
	for q in levels:
		Settings.quality = q
		Settings.apply()
		await seconds(2.5)
		for v in VIEWS:
			s.look_pitch = deg_to_rad(VIEWS[v])
			await seconds(1.0)
			res["%d_%s" % [q, v]] = await _shot_lq("q%d_%s" % [q, v])
	var ref := 2 if levels.has(2) else int(levels[0])
	var rep: PackedStringArray = ["Lichtstimmung je Stufe, Mission %s%s, Referenz Stufe %d" % [Game.cli.get("mission", "?"),
		Game.cli.get("tag", ""), ref], "Stufe Ansicht   Hell   R     G     B    dHell%  dFarbe"]
	var worst := 0.0
	for q in levels:
		for v in VIEWS:
			var a: Vector4 = res["%d_%s" % [q, v]]
			var b: Vector4 = res["%d_%s" % [ref, v]]
			var dl := (a.w - b.w) / maxf(b.w, 0.02) * 100.0
			var ca := Vector3(a.x, a.y, a.z) / maxf(a.w, 0.02)
			var cb := Vector3(b.x, b.y, b.z) / maxf(b.w, 0.02)
			var dc := ca.distance_to(cb)
			if v != "sky":
				worst = maxf(worst, absf(dl))
			rep.append("%d     %-8s %.3f %.3f %.3f %.3f %+6.1f  %.3f" % [q, v, a.w, a.x, a.y, a.z, dl, dc])
	rep.append("GROESSTE_ABWEICHUNG_HELL %.1f %% (ohne Himmel)" % worst)
	var f := FileAccess.open("res://test_output/light_quality/light_quality_%s%s.txt" % [Game.cli.get("mission", "x"),
		Game.cli.get("tag", "")], FileAccess.WRITE)
	f.store_string("\n".join(rep) + "\n")
	f.close()
	print("\n".join(rep))
	check(true, "Bilder erstellt")
	_finish()
