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
	if String(Game.cli.get("set", "")) == "bunker2":
		await _bunker2(t, tw)
		get_tree().quit()
		return
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

## Ausbau 11/2026 (--set=bunker2): Gang, Räume, Tür, Geheimraum, Ziffern-Fundorte, Turmschalter, Sicherungskasten
func _bunker2(t: RefCounted, tw) -> void:
	var bx = m.bunker_extras
	while bx.fuse_box == null:
		await get_tree().physics_frame
	bx.clock = 1000.0          # ruhige Flackerphase für die Aufnahmen
	bx.set_process(false)
	for l in t.lamps:
		l.light_energy = l.get_meta("base_energy")
	m.day_night.set_hour(23.0, 0.0)
	var c0: PackedVector2Array = t.chains[0]
	var l0: float = Tunnels.chain_length(c0)
	var g0: Vector2 = Tunnels.chain_at(c0, l0 * 0.22)[0]
	var g1: Vector2 = Tunnels.chain_at(c0, l0 * 0.34)[0]
	await _shot("bunker2_gang", Vector3(g0.x, t.floor_at(g0) + 1.6, g0.y), Vector3(g1.x, t.floor_at(g1) + 1.2, g1.y))
	var c1: PackedVector2Array = t.chains[1]
	var l1: float = Tunnels.chain_length(c1)
	var g2: Vector2 = Tunnels.chain_at(c1, l1 * 0.25)[0]
	var g3: Vector2 = Tunnels.chain_at(c1, l1 * 0.42)[0]
	await _shot("bunker2_gang_ausbruch", Vector3(g2.x, t.floor_at(g2) + 1.6, g2.y), Vector3(g3.x, t.floor_at(g3) + 1.1, g3.y))
	for rm in t.rooms:
		var eye: Vector2 = (rm.junction as Vector2) + (rm.n as Vector2) * 0.6
		var at: Vector2 = (rm.c as Vector2) + (rm.n as Vector2) * (float(rm.d) * 0.5)
		await _shot("bunker2_raum_" + String(rm.id), Vector3(eye.x, t.floor_at(eye) + 1.65, eye.y), Vector3(at.x, t.floor_at(at) + 0.8, at.y))
	var sc: Dictionary = t.secret
	var dl: Vector2 = sc.dir
	var e2: Vector2 = (sc.end as Vector2) - dl * 1.1 + (sc.side as Vector2) * 0.15
	var d2: Vector2 = sc.door
	await _shot("bunker2_tuer", Vector3(e2.x, t.floor_at(e2) + 1.6, e2.y), Vector3(d2.x, t.floor_at(d2) + 1.2, d2.y))
	var kp: Vector2 = sc.keypad
	await _shot("bunker2_tuer_zahlenschloss", Vector3(kp.x, t.floor_at(kp) + 1.4, kp.y) - Vector3(dl.x, 0, dl.y) * 0.55, Vector3(kp.x, t.floor_at(kp) + 1.35, kp.y))
	bx._door_state(true, true)
	await get_tree().create_timer(0.3).timeout
	var in2: Vector2 = d2 + dl * 0.7 + (sc.side as Vector2) * 0.25
	await _shot("bunker2_geheimraum", Vector3(in2.x, t.floor_at(in2) + 1.65, in2.y), Vector3(sc.c.x, t.floor_at(sc.c) + 0.9, sc.c.y) + Vector3(dl.x, 0, dl.y) * 0.8)
	var egg: Vector3 = bx.egg.global_position
	var to_c: Vector3 = (Vector3(sc.c.x, egg.y, sc.c.y) - egg).normalized()
	await _shot("bunker2_geheimraum_ei", egg + to_c * 0.9 + Vector3.UP * 0.25, egg)
	var btn: Vector3 = bx.nuke.global_position
	var tt := Vector3(sc.t.x, 0, sc.t.y)
	await _shot("bunker2_geheimraum_knopf", btn - tt * 1.0 + Vector3.UP * 0.3, btn + Vector3.DOWN * 0.35)
	for sp in bx.digit_spots:
		var p: Vector3 = sp.pos
		var nrm: Vector3 = sp.normal
		if p.y > -0.2:
			m.day_night.set_hour(14.0, 0.0)
		else:
			m.day_night.set_hour(23.0, 0.0)
		await _shot("bunker2_ziffer_%s_%s" % [sp.order, sp.digit], p + nrm * 1.1 + Vector3.UP * 0.15, p)
	m.day_night.set_hour(14.0, 0.0)
	var sw: Vector3 = bx.tower_switch.global_position
	await _shot("bunker2_turmschalter", sw + Vector3(0.6, 0.2, 1.5), sw)
	var fz: Vector3 = bx.fuse_box.global_position
	var fn: Vector3 = (fz - bx.fuse_box.get_parent().get_node("Sicherungskasten").global_position).normalized()
	await _shot("bunker2_sicherungskasten", fz + fn * 1.0 + Vector3.UP * 0.2, fz - fn * 0.25)

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
