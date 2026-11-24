extends Node
## Kontrollbilder Tageszyklus (Fenster): --mission=bavaria --autoplay=screenshots_bavaria_daynight
## → test_output/bavaria_daynight/{tag,daemmerung,nacht}_*.png, OG-Blick nach draußen, Laternen nachts.
const DIR := "res://test_output/bavaria_daynight/"
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
	camera.far = preload("res://src/world/view_distance.gd").camera_far()   # Kartenkamera-far (Bavaria ≤ 800 m)
	if "--waldrand=1" in OS.get_cmdline_user_args():
		# Doppelter Waldrand: erhöhter Blick von innen über Randsaum + äußeren Gürtel
		m.day_night.set_hour(12.0, 0.0)
		var a: Vector2 = m.boundary[0]
		var b: Vector2 = m.boundary[1]
		var c := Vector2.ZERO
		for q in m.boundary:
			c += q
		c /= m.boundary.size()
		var mid := a.lerp(b, 0.5)
		var out := (mid - c).normalized()
		var eye := mid - out * 10.0
		camera.global_position = Vector3(eye.x, 14.0, eye.y)
		camera.look_at(Vector3(mid.x + out.x * 18.0, 2.0, mid.y + out.y * 18.0))
		await _save("waldrand_dicht")
		get_tree().quit()
		return
	if "--sued_neu=1" in OS.get_cmdline_user_args():
		# Südstreifen des Panoramarings: Süd bei Tag/Dämmerung/Nacht + Südwest mit dem Dorf (Blickfang), Wiese, Augenhöhe
		var s: Vector3 = m.scene_details.south
		var sw := (s + Vector3(-s.z, 0, s.x)).normalized()
		var stand: Vector3 = m.pixel(m.layout["occupation_zones"][2]["pixel"]) + Vector3.UP * 1.7
		var lm = m.get("landmark")
		if lm != null:
			var d: Vector3 = (lm as Node3D).global_position - stand
			sw = Vector3(d.x, 0, d.z).normalized()
		for v in [["tag", 12.0, s], ["daemmerung", 19.35, s], ["nacht", 0.5, s], ["sw_dorf_tag", 12.0, sw]]:
			m.day_night.set_hour(v[1], 0.0)
			camera.global_position = stand
			camera.look_at(stand + (v[2] as Vector3) * 10.0 + Vector3.UP * 0.9)
			await _save("sued_neu_" + v[0])
		get_tree().quit()
		return
	if "--eztree_shots=1" in OS.get_cmdline_user_args():
		await _eztree_shots()
		get_tree().quit()
		return
	if Game.cli.has("hart_shots"):
		# Bibliotheks-/Wetter-Kontrollbilder: --hart_shots=<präfix> → test_output/<präfix>_*.png
		# (--weather=<zustand> fest; --hart_weather=1 nimmt alle Wetterzustände nacheinander auf)
		await _hart_shots(String(Game.cli["hart_shots"]))
		get_tree().quit()
		return
	var cam_arg := String(Game.cli.get("cam", ""))
	if cam_arg != "":
		# Freie Kontrollansicht: --cam=x,y,z;bx,by,bz [--hour=19.35] [--tag=name] (y = Fußhöhe, Auge +1,7 m)
		var parts := cam_arg.split(";")
		var pv := parts[0].split_floats(",")
		var dv := parts[1].split_floats(",")
		m.day_night.set_hour(float(Game.cli.get("hour", "19.35")), 0.0)
		camera.global_position = Vector3(pv[0], pv[1] + 1.7, pv[2])
		camera.look_at(camera.global_position + Vector3(dv[0], dv[1], dv[2]))
		_report_near(Vector3(pv[0], pv[1], pv[2]), 12.0)
		await _save(String(Game.cli.get("tag", "kamera")))
		get_tree().quit()
		return
	var h16 := m.static_root.get_node("haus_16") as Node3D
	var og: Array = h16.get_meta("og_shooting_windows", [])
	var road: Array = m.layout["paths"][0]["points"]
	var r0: Vector3 = m.pixel(road[0])
	var r1: Vector3 = m.pixel(road[1])
	var poles: Array = m.street_lamps.lamps.filter(func(l): return l.get_meta("kind") == "pole")
	for phase in [["tag", 12.0], ["daemmerung", 19.35], ["nacht", 0.5]]:
		m.day_night.set_hour(phase[1], 0.0)
		var tag: String = phase[0]
		# Dorfweg auf Augenhöhe
		camera.global_position = r0.lerp(r1, 0.15) + Vector3.UP * 1.7
		camera.look_at(r0.lerp(r1, 0.6) + Vector3.UP * 1.5)
		await _save(tag + "_dorfweg")
		# Fernkulisse je Himmelsrichtung (vom Antennenturm-Stand, über die Randkulisse hinweg)
		var s: Vector3 = m.scene_details.south
		var dirs := {"sued": s, "nord": -s, "ost": Vector3(s.z, 0, -s.x), "west": Vector3(-s.z, 0, s.x)}
		# erhöhter freier Blickpunkt über der Wiese (wie ein Beobachter auf dem Aststand/Dach)
		var stand: Vector3 = m.pixel(m.layout["occupation_zones"][2]["pixel"]) + Vector3.UP * 7.0
		for dname in dirs:
			if tag == "nacht" and dname != "sued":
				continue
			camera.global_position = stand + Vector3.UP * 1.7
			camera.look_at(camera.global_position + dirs[dname] * 10.0 + Vector3.UP * 0.6)
			await _save(tag + "_fernsicht_" + dname)
		# OG Haus 16: Blick von innen nach draußen
		if not og.is_empty():
			var w: Vector3 = og[0]
			var side := signf(w.z)
			camera.global_position = h16.to_global(Vector3(w.x + 0.25, w.y + 1.6, w.z - side * 2.2))
			camera.look_at(h16.to_global(Vector3(w.x, w.y + 1.35, w.z + side * 6.0)))
			await _save(tag + "_og_haus16_blick_nach_draussen")
			# von außen hinein
			camera.global_position = h16.to_global(Vector3(w.x - 1.5, w.y + 2.0, w.z + side * 5.0))
			camera.look_at(h16.to_global(Vector3(w.x, w.y + 1.6, w.z)))
			await _save(tag + "_og_haus16_von_aussen")
		# Laterne
		if not poles.is_empty():
			var p: Node3D = poles[0]
			camera.global_position = p.to_global(Vector3(3.5, 1.7, -5.0))
			camera.look_at(p.to_global(Vector3(0, 2.4, -0.4)))
			await _save(tag + "_laterne")
	# Nacht: Laternenreihe von weiter weg
	m.day_night.set_hour(23.0, 0.0)
	camera.global_position = r0.lerp(r1, 0.05) + Vector3.UP * 2.2
	camera.look_at(r1 + Vector3.UP * 1.0)
	await _save("nacht_laternenreihe")
	get_tree().quit()

func _hart_shots(pre: String) -> void:
	m.day_night.set_hour(float(Game.cli.get("hour", "12.0")), 0.0)
	var views := []
	if Game.cli.has("hart_graben"):
		# Nacht: Gräben/Boden direkt über Stollenlampen (Lichtdurchgriff durch die Decke?)
		var space := m.get_world_3d().direct_space_state
		# Grabensohle (≈ −1,3 m, Freiluft) im Umkreis von 4 m um eine Stollenlampe
		for l in get_tree().get_nodes_in_group("bavaria_tunnel_lamps"):
			var lp: Vector3 = (l as Node3D).global_position
			var found := Vector3.INF
			for ox in [0.0, -2.0, 2.0, -4.0, 4.0]:
				for oz in [0.0, -2.0, 2.0, -4.0, 4.0]:
					if found.is_finite():
						break
					var q := Vector3(lp.x + ox, 6.0, lp.z + oz)
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q, q + Vector3.DOWN * 9.0, 1))
					if not hit.is_empty() and hit.position.y < -1.1 and hit.position.y > -1.5:
						found = hit.position
			if found.is_finite():
				views.append(["graben_%d" % views.size(), found + Vector3(1.4, 2.4, 1.4), found])
			if views.size() >= 3:
				break
	elif Game.cli.has("hart_tunnel"):
		# Stollen: in Gangmitte auf Augenhöhe entlang der Gangachse (Gänge 0–2)
		var T = m.tunnels
		for ci in mini(T.chains.size(), 3):
			var pts: PackedVector2Array = T.chains[ci]
			var L: float = T.chain_length(pts)
			var a2: Vector2 = T.chain_at(pts, L * 0.35)[0]
			var b2: Vector2 = T.chain_at(pts, minf(L * 0.35 + 5.0, L - 0.3))[0]
			var a := Vector3(a2.x, T.floor_at(a2) + 1.55, a2.y)
			var b := Vector3(b2.x, T.floor_at(b2) + 1.3, b2.y)
			views.append(["stollen_%d" % ci, a, b])
	else:
		var road: Array = m.layout["paths"][0]["points"]
		var r0: Vector3 = m.pixel(road[0])
		var r1: Vector3 = m.pixel(road[1])
		views.append(["dorfweg", r0.lerp(r1, 0.15) + Vector3.UP * 1.7, r0.lerp(r1, 0.6) + Vector3.UP * 1.5])
		var h16 := m.static_root.get_node_or_null("haus_16") as Node3D
		if h16:
			views.append(["haus16", h16.to_global(Vector3(0, 2.2, 16.0)), h16.global_position + Vector3.UP * 3.0])
		var meadow: Vector3 = m.pixel(m.layout["occupation_zones"][2]["pixel"])
		views.append(["wiese", meadow + Vector3.UP * 2.5 - m.scene_details.south * 12.0, meadow + m.scene_details.south * 30.0])
		for n in get_tree().get_nodes_in_group("bavaria_library_props"):
			var nm := String(n.name)
			if nm in ["Telegrafenmast_Mitte", "Bienenstoecke_Garten", "Milchkannen_Hof", "Wegweiser_Dorfrand"]:
				var p: Vector3 = (n as Node3D).global_position
				views.append(["deko_" + nm.to_lower(), p + Vector3(4.5, 2.0, 4.5), p + Vector3.UP * 1.0])
		# Einrichtung (Gap-Fill): Stuhl, Badewanne, Strauch
		for g in ["bavaria_furniture"]:
			var seen := {}
			for n in get_tree().get_nodes_in_group(g):
				var lm := ""
				for c in (n as Node).find_children("*", "Node3D", true, false):
					if c.has_meta("library_model"):
						lm = String(c.get_meta("library_model"))
						break
				if lm in ["holzstuhl_bauern", "badewanne_guss", "kuechenherd_alt"] and not seen.has(lm):
					seen[lm] = true
					var p: Vector3 = (n as Node3D).global_position
					views.append(["innen_" + lm, p + Vector3(1.4, 1.5, 1.4), p + Vector3.UP * 0.4])
	var states: Array = ["klar", "bewoelkt", "regen", "gewitter"] if Game.cli.has("hart_weather") else [""]
	for st in states:
		if st != "" and m.get("weather") and m.weather.enabled:
			m.weather.set_weather(st, true)
		for v in views:
			camera.global_position = v[1]
			camera.look_at(v[2])
			await get_tree().create_timer(0.4).timeout
			var id: String = pre + ("_" + st if st != "" else "") + "_" + v[0]
			camera.reset_physics_interpolation()
			for i in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://test_output/" + id + ".png")
			print("BILD ", id)
			_frame_stats(id)

func _frame_stats(id: String) -> void:
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var ob := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	print("STAT %s draw_calls=%d objects=%d fps=%.1f" % [id, dc, ob, Engine.get_frames_per_second()])

## EZ-Tree-Bäume (Fenster): --eztree_shots=1 → eztree_*.png; mit --eztree=0 Vergleich eztree_alt_*.png.
## Nahaufnahme je Art (Probebäume auf der Wiese), Waldrand, Wiesenmitte, Kartenblick Tag/Dämmerung.
func _eztree_shots() -> void:
	var ez := String(Game.cli.get("eztree", "1")) != "0"
	var pre := "eztree_" if ez else "eztree_alt_"
	if Game.cli.has("shot_prefix"):
		pre = String(Game.cli["shot_prefix"])
		ez = false      # nur Wald-/Kartenansichten, keine Probebäume
	var meadow: Vector3 = m.pixel(m.layout["occupation_zones"][2]["pixel"])
	var s: Vector3 = m.scene_details.south
	var side := Vector3(s.z, 0, -s.x)
	m.day_night.set_hour(12.0, 0.0)
	if ez:
		var probes: Array[Node3D] = []
		var arten := [["fichte", "ez_spruce_l", 1.0], ["buche", "ez_beech_m", 1.0], ["eiche", "ez_oak_m", 1.0],
			["birke", "ez_birch_m", 1.0], ["obstbaum", "ez_fruit_m", 1.0]]
		for i in arten.size():
			var base := meadow + s * 22.0 + side * (float(i) - 2.0) * 16.0
			var n: Node3D = m._templates.prop(arten[i][1], base, 0.4, float(arten[i][2]))
			probes.append(n)
		await get_tree().create_timer(0.5).timeout
		for i in arten.size():
			var base := meadow + s * 22.0 + side * (float(i) - 2.0) * 16.0
			var h: float = preload("res://src/maps/bavaria/eztree.gd").HEIGHTS[arten[i][1]]
			camera.global_position = base - s * (h * 0.9 + 3.0) + Vector3.UP * 1.7
			camera.look_at(base + Vector3.UP * h * 0.45)
			await _save(pre + "art_" + arten[i][0])
		# alle Arten nebeneinander
		camera.global_position = meadow + s * 22.0 - s * 45.0 + Vector3.UP * 3.0
		camera.look_at(meadow + s * 22.0 + Vector3.UP * 5.0)
		await _save(pre + "arten_reihe")
		for n in probes:
			n.queue_free()
		await get_tree().process_frame
	# Waldrand: Augenhöhe innen an der ersten Grenzkante, Blick nach außen
	var a: Vector2 = m.boundary[0]
	var b: Vector2 = m.boundary[1]
	var c := Vector2.ZERO
	for q in m.boundary:
		c += q
	c /= m.boundary.size()
	var mid := a.lerp(b, 0.5)
	var out := (mid - c).normalized()
	var eye := mid - out * 14.0
	camera.global_position = Vector3(eye.x, 1.7, eye.y)
	camera.look_at(Vector3(mid.x + out.x * 20.0, 4.0, mid.y + out.y * 20.0))
	await _save(pre + "waldrand")
	# Übergang 3D → Impostor: erhöht am Rand, Blick flach hinaus über den dichten Außenwald
	var edge_eye := mid - out * 2.0
	camera.global_position = Vector3(edge_eye.x, 7.0, edge_eye.y)
	camera.look_at(Vector3(mid.x + out.x * 120.0, 3.0, mid.y + out.y * 120.0))
	await _save(pre + "uebergang")
	# Wiesenmitte, Augenhöhe, Blick zum Wald
	camera.global_position = meadow + Vector3.UP * 1.7
	camera.look_at(meadow + Vector3(out.x, 0, out.y) * 30.0 + Vector3.UP * 3.0)
	await _save(pre + "wiesenmitte")
	# Blick über die Karte bei Tag und in der Dämmerung
	for v in [["tag", 12.0], ["daemmerung", 19.35]]:
		m.day_night.set_hour(v[1], 0.0)
		camera.global_position = Vector3(c.x, 0, c.y) - Vector3(out.x, 0, out.y) * 60.0 + Vector3.UP * 38.0
		camera.look_at(Vector3(c.x, 0, c.y) + Vector3(out.x, 0, out.y) * 60.0)
		await _save(pre + "karte_" + v[0])

## Listet sichtbare Geometrie, deren Weltbox näher als r (waagrecht) an p liegt (Fehlersuche).
func _report_near(p: Vector3, r: float) -> void:
	for gi in m.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var boxes: Array[AABB] = []
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			for k in mm.instance_count:
				boxes.append(g.global_transform * mm.get_instance_transform(k) * mm.mesh.get_aabb())
		else:
			boxes.append(g.global_transform * g.get_aabb())
		for k in boxes.size():
			var b: AABB = boxes[k]
			var c := Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.z, b.position.z, b.end.z))
			if c.distance_to(Vector2(p.x, p.z)) < r and b.size.length() > 1.0:
				print("NAH %s [%d] box=%s" % [g.get_path(), k, b])

func _save(id: String) -> void:
	camera.reset_physics_interpolation()
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var sfx := String(Game.cli.get("suffix", ""))   # z. B. --suffix=_opt (Vergleichsbilder neben dem alten Stand)
	get_viewport().get_texture().get_image().save_png(DIR + id + sfx + ".png")
	print("BILD ", DIR + id + sfx + ".png")
