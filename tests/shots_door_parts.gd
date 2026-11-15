extends Node
## Kontrollbilder Türteile (Fenster): Kamera an Konsolen-„pos“-Stellen, Tür nahe der Stelle zu und offen.
##   tools\godot.cmd -- --autoplay=shots_door_parts --maps=mp_arctic2_mp --tag=vorher
##   --views=x,y,z,dx,dy,dz;…  (Standard: die beiden ARCTIC2-Stellen [D])
## Ausgabe test_output/arctic2_doors/<tag>_<n>_{zu,offen}.png

const DEFAULT_VIEWS := "-1.92,-8.71,-60.48,-0.93,-0.06,-0.37;40.58,-16.47,-23.93,0.76,-0.06,0.65"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _shot(path: String) -> void:
	for i in 6:
		await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("BILD ", path)


func _run() -> void:
	var map := String(Game.cli.get("maps", "mp_arctic2_mp"))
	var tag := String(Game.cli.get("tag", "vorher"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/arctic2_doors"))
	Net.host({"name": "Shots", "map": map, "mode": Net.Mode.TEAM_DEATHMATCH, "port": Net.PORT + 64, "max_players": 2,
		"time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0, "password": "", "allow_vehicles": false})
	await _wait(func():
		var mm = Game.current_mission()
		return mm != null and mm.is_node_ready() and Net._soldiers.has(1), 600.0)
	var m: Mission = Game.current_mission()
	await get_tree().create_timer(3.0).timeout
	var s: Soldier = Net._soldiers.get(1)
	if s:
		s.set_meta("god", true)
		s.visible = false
	var hud := m.find_child("HUD", true, false)
	if hud is CanvasItem:
		(hud as CanvasItem).visible = false
	var cam := Camera3D.new()
	cam.fov = 65.0
	m.add_child(cam)
	cam.current = true
	var it: OrigInteractive = m.get("interactive")
	var n := 0
	for v in String(Game.cli.get("views", DEFAULT_VIEWS)).split(";", false):
		n += 1
		var c := v.split(",")
		var eye := Vector3(float(c[0]), float(c[1]) + 1.6, float(c[2]))
		var dir := Vector3(float(c[3]), float(c[4]), float(c[5])).normalized()
		cam.global_position = eye
		cam.look_at(eye + dir, Vector3.UP)
		cam.make_current()
		# Tür vor der Kamera (nächste zum Punkt 4 m voraus)
		var best: OrigInteractive.OrigDoor = null
		var bd := 4.0
		var ahead := eye + dir * 4.0
		for k in it.controls:
			var d = it.controls[k]
			if d is OrigInteractive.OrigDoor and d.global_position.distance_to(ahead) < bd:
				bd = d.global_position.distance_to(ahead)
				best = d
		if best:
			best.amount = 0.0
			best.target = 0.0
			best._apply()
		if Game.cli.has("list"):
			for mi in m.find_children("*", "MeshInstance3D", true, false):
				var me := mi as MeshInstance3D
				if me.mesh == null or not me.is_visible_in_tree():
					continue
				var b := me.global_transform * me.get_aabb()
				var hit = b.grow(0.05).intersects_segment(eye, eye + dir * 9.0)
				if hit != null:
					print("STRAHL %d %.2f %s size=%s c=%s" % [n, eye.distance_to(hit), me.get_path(), b.size, b.get_center()])
		await _shot("res://test_output/arctic2_doors/%s_%d_zu.png" % [tag, n])
		if best:
			print("TÜR %d %s" % [n, best.name])
			best.amount = best.open_amount
			best.target = best.open_amount
			best._apply()
			await _shot("res://test_output/arctic2_doors/%s_%d_offen.png" % [tag, n])
			best.amount = 0.0
			best.target = 0.0
			best._apply()
	get_tree().quit(0)
