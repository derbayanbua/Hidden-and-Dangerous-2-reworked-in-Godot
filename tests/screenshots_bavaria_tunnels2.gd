extends Node
## Kontrollbilder Stollenausbau 2 (Fenster): --mission=bavaria --autoplay=screenshots_bavaria_tunnels2 [--set=bee|neu|all] [--tag=vorher]
## → test_output/hart_tunnel2_*.png (MG-Nest außen/innen, Einsturzgang von außen, Luke mit Treppe, Bienenstöcke am Zugang)
const DIR := "res://test_output/"
var m: Mission
var camera: Camera3D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	while m == null or not m.nav_ready or not m.room_lighting.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	m.controller.input_enabled = false
	m.rig.set_process(false)
	m.rig.set_physics_process(false)
	m.hud.visible = false
	camera = Camera3D.new()
	m.add_child(camera)
	camera.current = true
	camera.fov = 70
	camera.near = 0.05
	camera.far = preload("res://src/world/view_distance.gd").camera_far()
	var t = m.tunnels
	var park: Vector2 = t.nodes["antennenhaus"]
	for s in get_tree().get_nodes_in_group("soldiers"):
		s.global_position = Vector3(park.x, t.FLOOR_Y + 0.1, park.y)
		s.process_mode = Node.PROCESS_MODE_DISABLED
		s.visible = false
	m.day_night.set_hour(14.0, 0.0)
	var set := String(Game.cli.get("set", "all"))
	var tag := String(Game.cli.get("tag", "nachher"))
	if set in ["bee", "all"]:
		var bee: Node3D = null
		for n in get_tree().get_nodes_in_group("bavaria_decorations"):
			if String(n.name).contains("Bienen"):
				bee = n
		if bee:
			var p := bee.global_position
			var e: Dictionary = t.entrances["reihenhaus"]
			var to_e: Vector3 = (Vector3(e.top.x, 0, e.top.z) - p)
			to_e.y = 0
			to_e = to_e.normalized()
			var side := Vector3(-to_e.z, 0, to_e.x)
			await _shot("hart_tunnel2_bienen_%s_1" % tag, p - to_e * 4.5 + side * 1.5 + Vector3.UP * 1.7, p + Vector3.UP * 0.6)
			await _shot("hart_tunnel2_bienen_%s_2" % tag, p + side * 4.0 + Vector3.UP * 1.4, p + Vector3.UP * 0.5)
			await _shot("hart_tunnel2_bienen_%s_nah" % tag, p - side * 2.2 + to_e * 0.8 + Vector3.UP * 1.2, p + Vector3.UP * 0.4)
			print("BIENEN ", p, " Kinder ", bee.get_child_count())
	if set in ["neu", "all"] and "extra" in t:
		for id in t.extra:
			var x: Dictionary = t.extra[id]
			var top: Vector3 = x.top
			var u: Vector3 = x.u3
			match String(x.kind):
				"nest":
					await _shot("hart_tunnel2_mg_nest_aussen", top - u * 8.0 + Vector3(u.z, 0, -u.x) * 3.0 + Vector3.UP * 2.6, top - u * 2.0 + Vector3.UP * 0.6)
					await _shot("hart_tunnel2_mg_nest_hinten", top + u * 0.6 + Vector3(u.z, 0, -u.x) * 2.5 + Vector3.UP * 2.4, top - u * 3.0 + Vector3.UP * 0.8)
					m.day_night.set_hour(23.0, 0.0)
					var b: Vector3 = x.bottom
					await _shot("hart_tunnel2_mg_nest_innen", b + u * 1.8 + Vector3.UP * 1.6, top + Vector3.UP * 0.8)
					m.day_night.set_hour(14.0, 0.0)
				"rubble":
					await _shot("hart_tunnel2_einsturz_aussen", top - u * 5.0 + Vector3(u.z, 0, -u.x) * 2.5 + Vector3.UP * 3.0, top + u * 3.5 + Vector3.DOWN * 1.8)
					await _shot("hart_tunnel2_einsturz_oben", top + u * 3.0 + Vector3(u.z, 0, -u.x) * 4.0 + Vector3.UP * 4.5, top + u * 4.5 + Vector3.DOWN * 2.5)
					m.day_night.set_hour(23.0, 0.0)
					var b2: Vector3 = x.bottom
					await _shot("hart_tunnel2_einsturz_innen", b2 + u * 0.6 + Vector3.UP * 1.5, top + Vector3.UP * 0.5)
					m.day_night.set_hour(14.0, 0.0)
				"hatch":
					await _shot("hart_tunnel2_luke_aussen", top - u * 3.5 + Vector3(u.z, 0, -u.x) * 1.8 + Vector3.UP * 2.0, top + u * 1.5 + Vector3.DOWN * 0.8)
					m.day_night.set_hour(23.0, 0.0)
					var b3: Vector3 = x.bottom
					await _shot("hart_tunnel2_luke_treppe_innen", b3 + u * 1.6 + Vector3.UP * 1.6, top + Vector3.UP * 0.4)
					m.day_night.set_hour(14.0, 0.0)
	get_tree().quit()

func _shot(id: String, eye: Vector3, at: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(at, Vector3.UP)
	camera.reset_physics_interpolation()
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + id + ".png")
	print("BILD ", DIR + id + ".png")
