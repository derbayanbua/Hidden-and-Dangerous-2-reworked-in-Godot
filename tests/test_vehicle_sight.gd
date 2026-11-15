extends "res://tests/test_gameplay.gd"
## Visiersicht im Fahrzeug (0.11.6): Maske außerhalb des 4:3-Sichtfelds je Seitenverhältnis, Fadenkreuz = Bildmitte =
## Schussrichtung, FOV vertikal wie Original (65° horizontal bei 4:3). AFRICA1 Panzer III „panzer01“, Kanone + Bug-MG.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_vehicle_sight [--shots=1 (Fenster)]

const ASPECTS := {"4x3": Vector2(1440, 1080), "16x9": Vector2(1920, 1080), "16x10": Vector2(1728, 1080), "21x9": Vector2(2520, 1080)}


func _covered(vp: Vector2) -> bool:
	# Abtastraster: jeder Punkt liegt im 4:3-Sichtfeld oder in einem Balken
	var r: Dictionary = load("res://src/ui/hud.gd").sight_mask_rects(vp)
	var rects: Array = [r["view"]] + r["bars"]
	for iy in 41:
		for ix in 81:
			var p := Vector2(vp.x * ix / 80.0, vp.y * iy / 40.0) * 0.9999
			var ok := false
			for rc in rects:
				if (rc as Rect2).grow(0.5).has_point(p):
					ok = true
					break
			if not ok:
				return false
	return true


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or not Game.cli.has("shots"):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/vehicle_sight"))
	img.save_png(ProjectSettings.globalize_path("res://test_output/vehicle_sight/%s.png" % name))
	print("BILD test_output/vehicle_sight/%s.png" % name)


func _run() -> void:
	var hs = load("res://src/ui/hud.gd")
	# --- Geometrie je Seitenverhältnis ---
	for k in ASPECTS:
		var vp: Vector2 = ASPECTS[k]
		var r: Dictionary = hs.sight_mask_rects(vp)
		var view: Rect2 = r["view"]
		check(is_equal_approx(view.size.x / view.size.y, 4.0 / 3.0) and is_equal_approx(view.size.y, vp.y),
			"%s: Sichtfeld 4:3 über volle Höhe" % k, str(view))
		check(view.get_center().distance_to(vp * 0.5) < 0.5, "%s: Sichtfeldmitte = Bildmitte" % k)
		check(_covered(vp), "%s: Sichtfeld + Maske decken das ganze Bild" % k)
	var r43: Dictionary = hs.sight_mask_rects(ASPECTS["4x3"])
	check((r43["bars"][0] as Rect2).size == Vector2.ZERO, "4:3: keine Balken")
	var r219: Dictionary = hs.sight_mask_rects(ASPECTS["21x9"])
	check((r219["bars"][0] as Rect2).size.x > 300.0, "21:9: Seitenbalken", str(r219["bars"][0]))
	check(_covered(Vector2(1280, 1024)), "5:4: Balken oben/unten decken das Bild")

	# --- Im Spiel: Kanonensitz des Panzers ---
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m = mission()
	check(m != null and m.runtime != null, "AFRICA1 geladen")
	if m == null:
		_finish()
		return
	var rt: LsRuntime = m.runtime
	rt.auto_skip = true
	await seconds(2.0)
	if rt.in_cutscene:
		rt.end_cutscene()
	var tank := rt.find_frame("panzer01") as Vehicle
	check(tank != null, "Panzer III gefunden")
	if tank == null:
		_finish()
		return
	for o in tank.occupants.duplicate():
		if is_instance_valid(o):
			tank.leave(o)
			(o as Soldier).global_position += Vector3(40, 0, 0)
			if (o as Soldier).has_node("EnemyBrain"):
				(o as Soldier).get_node("EnemyBrain").enabled = false
	var hale: Soldier = m.squad.leader()
	hale.max_health = 99999.0     # Unverwundbar (Testregel)
	hale.health = 99999.0
	var hud = m.hud if "hud" in m else null
	var rig: CameraRig = m.rig
	for seat in tank.turrets:
		hale.global_position = tank.global_position + tank.global_basis.x * 3.0
		if not tank.board(hale, false, seat):
			check(false, "Sitz %d besetzt" % seat)
			continue
		rig.vehicle_fpv = true
		# Blick auf die aktuelle Rohrrichtung, Turm einschwingen lassen
		for i in 60:
			var d := tank.turret_dir(seat)
			hale.look_yaw = atan2(-d.x, -d.z)
			hale.look_pitch = asin(clampf(d.y, -1.0, 1.0))
			await get_tree().physics_frame
		await frames(3)
		check(rig.vehicle_sight_active(), "Sitz %d: Visiersicht aktiv" % seat)
		var mask: Control = hud.find_child("VehicleSightMask", true, false) if hud else null
		check(mask != null and mask.visible, "Sitz %d: Maske sichtbar" % seat)
		check(absf(rig.camera.fov - rig.base_fov()) < 0.5 or hale.aiming, "Sitz %d: vertikales FOV = Original (%.1f°)" % [seat, rig.base_fov()],
			"%.1f" % rig.camera.fov)
		var vp := get_viewport().get_visible_rect().size
		if hud and hud.has_method("_vehicle_aim_offset"):
			var off: Vector2 = hud._vehicle_aim_offset(hale, rig.camera)
			check(off.length() <= vp.y * 0.08, "Sitz %d: Fadenkreuz/Schussrichtung = Bildmitte" % seat, "%.1f px bei %s" % [off.length(), str(vp)])
		# Kameraachse = Schussrichtung
		var cam_fwd := -rig.camera.global_basis.z
		var ang := rad_to_deg(cam_fwd.angle_to(tank.turret_dir(seat)))
		check(ang < 3.0, "Sitz %d: Kamerablick = Rohrrichtung" % seat, "%.2f°" % ang)
		if DisplayServer.get_name() != "headless" and Game.cli.has("shots"):
			for k in ASPECTS:
				get_window().size = Vector2i(ASPECTS[k] / 1.5)
				await frames(8)
				await shot("seat%d_%s" % [seat, k])
		rig.vehicle_fpv = false
		for i in 60:
			await get_tree().process_frame
			if mask == null or not mask.visible:
				break
		check(not rig.vehicle_sight_active() and (not mask.visible if mask else true), "Sitz %d: Verfolgerkamera ohne Maske" % seat,
			"rig %s, Maske %s, aktiv %s" % [rig.vehicle_sight_active(), mask.visible if mask else null, m.controller.active == hale])
		rig.vehicle_fpv = true
		tank.leave(hale)
		await frames(3)
		check(mask == null or not mask.visible, "Sitz %d: nach Aussteigen keine Maske" % seat)
	_finish()
