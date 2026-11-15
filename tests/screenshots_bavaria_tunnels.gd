extends Node
## Kontrollbilder Stollen + Suchturm (Fenster): --mission=bavaria --autoplay=screenshots_bavaria_tunnels
## → test_output/bavaria_daynight/tunnel_*.png, turm_*.png
const DIR := "res://test_output/bavaria_daynight/"
const Tunnels := preload("res://src/maps/bavaria/tunnels.gd")
var m: Mission
var camera: Camera3D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	while m == null or not m.nav_ready or not m.room_lighting.initialized:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
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
	var t: RefCounted = m.tunnels
	var tw = m.searchlight_tower
	# Trupp aus dem Bild (in den Stollen am Antennenhaus-Ansatz)
	var park: Vector2 = t.nodes["antennenhaus"]
	for s in get_tree().get_nodes_in_group("soldiers"):
		s.global_position = Vector3(park.x, Tunnels.FLOOR_Y + 0.1, park.y)
		s.process_mode = Node.PROCESS_MODE_DISABLED
		s.visible = false
	var mg: Dictionary = t.entrances["mg42"]
	var u: Vector3 = (Vector3(mg.bottom.x, 0, mg.bottom.z) - Vector3(mg.top.x, 0, mg.top.z)).normalized()
	m.day_night.set_hour(14.0, 0.0)
	await _shot("tunnel_einstieg_mg42_tag", mg.approach - u * 2.5 + Vector3.UP * 2.6, mg.top + u * 2.0 + Vector3.DOWN * 1.0)
	m.day_night.set_hour(23.0, 0.0)
	await _shot("tunnel_einstieg_mg42_von_unten", mg.bottom + Vector3.UP * 1.6 - u * -0.3, mg.top + Vector3.UP * 1.0)
	var a: Vector2 = t.nodes["mg42"]
	var j: Vector2 = t.nodes["abzweig"]
	var p := a.lerp(j, 0.12)
	var q := a.lerp(j, 0.4)
	await _shot("tunnel_innen_stollen", Vector3(p.x, Tunnels.FLOOR_Y + 1.6, p.y), Vector3(q.x, Tunnels.FLOOR_Y + 1.3, q.y))
	var jb := j.lerp(a, 0.06)
	var r: Vector2 = t.nodes["reihenhaus"]
	await _shot("tunnel_abzweig", Vector3(jb.x, Tunnels.FLOOR_Y + 1.6, jb.y), Vector3(r.x, Tunnels.FLOOR_Y + 1.2, r.y))
	for id in ["antennenhaus", "reihenhaus"]:
		var e: Dictionary = t.entrances[id]
		var node: Vector2 = t.nodes[id]
		await _shot("tunnel_treppe_" + id + "_von_unten", Vector3(node.x, Tunnels.FLOOR_Y + 1.6, node.y), e.top + Vector3.UP * 0.6)
		var eu: Vector3 = (Vector3(e.bottom.x, 0, e.bottom.z) - Vector3(e.top.x, 0, e.top.z)).normalized()
		await _shot("tunnel_ausgang_" + id + "_im_haus", e.approach - eu * 0.2 + Vector3.UP * 1.65, e.top + eu * 1.2 + Vector3.DOWN * 0.8)
	# Suchturm
	var site: Vector3 = tw.site
	var view := site + Vector3(26, 0, 22)
	var g := view
	m.day_night.set_hour(13.0, 0.0)
	await _shot("turm_tag", g + Vector3.UP * 1.7, site + Vector3.UP * 5.0)
	m.day_night.set_hour(23.5, 0.0)
	for i in 30:
		await get_tree().physics_frame
	await _shot("turm_nacht_suchen", g + Vector3.UP * 1.7, site + Vector3.UP * 4.0)
	# Ziel auf offener Wiese, Scheinwerfer erfasst und verfolgt
	var soldier := Soldier.new()
	soldier.name = "SuchturmZiel"
	m.actors_root.add_child(soldier)
	var target := site + Vector3(-14, 0, 12)
	soldier.global_position = target + Vector3.UP * 0.2
	var h = tw.heads[0]
	h.target = soldier
	h.mode = 1
	h.unseen = -100.0
	for i in 120:
		await get_tree().physics_frame
	await _shot("turm_nacht_verfolgt", target + Vector3(10, 1.7, -14), target + Vector3.UP * 1.0)
	await _shot("turm_nacht_verfolgt_totale", site + Vector3(30, 6.0, 30), target + Vector3.UP * 1.0)
	get_tree().quit()

func _shot(id: String, eye: Vector3, at: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(at, Vector3.UP)
	await _save(id)

func _save(id: String) -> void:
	camera.reset_physics_interpolation()
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + id + ".png")
	print("BILD ", DIR + id + ".png")
