extends Node
## Kontrollbilder Panoramaring (Fenster): --mission=bavaria --autoplay=shots_pano_ring [--prefix=pano_ring_]
## → test_output/bavaria_daynight/<prefix>{tag_nord,tag_ost,tag_sued,tag_west,daemmerung_*,nacht_*,boden_*}.png
## Blickpunkt wie tag_fernsicht_* (screenshots_bavaria_daynight.gd: Wiese, 7 m erhöht) zum direkten Vergleich.
const DIR := "res://test_output/bavaria_daynight/"
var m: Mission
var camera: Camera3D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	while m == null or not m.nav_ready:
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
	camera.far = preload("res://src/world/view_distance.gd").camera_far()
	var pre := String(Game.cli.get("prefix", "pano_ring_"))
	var s: Vector3 = m.scene_details.south
	var dirs := {"nord": -s, "ost": Vector3(s.z, 0, -s.x), "sued": s, "west": Vector3(-s.z, 0, s.x)}
	var stand: Vector3 = m.pixel(m.layout["occupation_zones"][2]["pixel"]) + Vector3.UP * 7.0
	var ground: Vector3 = m.pixel(m.layout["occupation_zones"][2]["pixel"])
	for phase in [["tag", 12.0, dirs.keys()], ["daemmerung", 19.35, ["west", "sued"]], ["nacht", 0.5, ["sued", "ost"]]]:
		m.day_night.set_hour(phase[1], 0.0)
		for dname in phase[2]:
			camera.global_position = stand + Vector3.UP * 1.7
			camera.look_at(camera.global_position + dirs[dname] * 10.0 + Vector3.UP * 0.6)
			await _save(pre + phase[0] + "_" + dname)
	# Augenhöhe am Boden (Anschluss Unterkante/Randwald)
	m.day_night.set_hour(12.0, 0.0)
	for dname in ["sued", "nord"]:
		camera.global_position = ground + Vector3.UP * 1.7
		camera.look_at(camera.global_position + dirs[dname] * 10.0 + Vector3.UP * 0.4)
		await _save(pre + "boden_" + dname)
	# Außenbereich: Draufsicht der ganzen Karte bis zum Ring, Blick Südwest aufs Dorf, Blick Nordost aufs Werk (Augenhöhe)
	var c := Vector2.ZERO
	for q in m.boundary:
		c += q
	c /= m.boundary.size()
	var far0 := camera.far
	camera.far = 2000.0
	camera.global_position = Vector3(c.x, 230.0, c.y) - Vector3(s.x, 0, s.z) * 120.0
	camera.look_at(Vector3(c.x, 0, c.y) + Vector3(s.x, 0, s.z) * 40.0)
	camera.fov = 85
	await _save("aussen_draufsicht")
	camera.far = far0
	camera.fov = 70
	var mid: Vector3 = m.pixel(m.layout["occupation_zones"][2]["pixel"]) + Vector3.UP * 1.7
	var lm = m.get("landmark")
	if lm:
		var apex: Vector2 = m.scene_details.vista_apex     # Wiesenmitte = Spitze der Blickschneise
		camera.global_position = Vector3(apex.x, 1.7, apex.y)
		camera.look_at(Vector3(lm.tower_top.x, 8.0, lm.tower_top.z))
		await _save("aussen_dorf_sw")
	var fw = m.get("factory_landmark")
	if fw:
		camera.global_position = mid
		camera.look_at(Vector3(fw.factory_center.x, mid.y + 4.0, fw.factory_center.y))
		await _save("aussen_werk_no")
	get_tree().quit()

func _save(id: String) -> void:
	camera.reset_physics_interpolation()
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(DIR + id + ".png")
	print("BILD ", DIR + id + ".png")
