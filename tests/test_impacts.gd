extends "res://tests/test_gameplay.gd"
## 0.11.7 Einschusslöcher (Effects.impact/_decal, src/combat/effects.gd): Größe, Kontrast der Textur (fast schwarzer
## Kern, dunkler Rand, Hof), keine Entfernungsausblendung, Ring-Puffer MAX_DECALS, echter Projektiltreffer auf vier
## Oberflächen (Schnee/Holz/Metall/Stein), Loch an der Fläche entlang der Normalen. Netzschuss (Remote): test_mp_minimap.
##   tools\godot.cmd --headless -- --mission=m01_funkfeuer --autoplay=test_impacts --profiles_dir=user://test_impacts
## Kontrollbilder (Fenster, ohne --headless) → test_output/impacts/*.png (nah, 15 m, Zielfernrohr 40 m)

const SURFACES := {"schnee": Color(0.93, 0.94, 0.97), "holz": Color(0.45, 0.3, 0.17), "metall": Color(0.38, 0.4, 0.42),
	"stein": Color(0.55, 0.53, 0.5)}


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _run() -> void:
	for i in 1500:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	Settings.decals = true
	var s: Soldier = m.squad.leader()
	s.set_physics_process(false)
	for mb in m.squad.members:
		if mb != s:
			mb.process_mode = Node.PROCESS_MODE_DISABLED
	for e in m.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.global_position += Vector3(0, -200, 0)
	# --- Textur: Kontrast ---
	var img: Image = Effects._hole_tex.get_image()
	var n := img.get_width()
	var core := img.get_pixel(n / 2, n / 2)
	var rim := img.get_pixel(n / 2 + int(n * 0.18), n / 2)
	var halo := img.get_pixel(n / 2 + int(n * 0.36), n / 2)
	var edge := img.get_pixel(n - 1, n / 2)
	check(n >= 64, "Lochtextur 64 px (vorher 32)", str(n))
	check(core.a > 0.95 and _lum(core) < 0.03, "Kern deckend, fast schwarz", str(core))
	check(rim.a > 0.85 and _lum(rim) < 0.12, "Rand dunkel und deckend", str(rim))
	check(halo.a > 0.05 and halo.a < 0.6, "Schmauch-/Staubhof halbtransparent", str(halo))
	check(edge.a < 0.05, "Hof läuft zum Rand aus (keine harte Kante)", str(edge))
	for nm in SURFACES:
		var bg: Color = SURFACES[nm]
		var mix := bg.lerp(Color(core.r, core.g, core.b), core.a)
		check(_lum(bg) - _lum(mix) > 0.25, "Kontrast Kern ↔ %s" % nm, "%.2f → %.2f" % [_lum(bg), _lum(mix)])

	# --- echte Projektile auf vier Oberflächen ---
	var fwd := Vector3(-sin(s.look_yaw), 0, -cos(s.look_yaw))
	var side := fwd.cross(Vector3.UP)
	var walls := {}
	var k := 0
	for nm in SURFACES:
		var b := _test_block(s.global_position + fwd * 3.0 + side * (float(k) - 1.5) * 1.3 + Vector3.UP * 0.3,
			Vector3(1.2, 2.0, 0.3), s.look_yaw)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = SURFACES[nm]
		mat.metallic = 0.7 if nm == "metall" else 0.0
		mat.roughness = 0.4 if nm == "metall" else 0.95
		(b.get_child(1) as MeshInstance3D).material_override = mat
		walls[nm] = b
		k += 1
	await frames(3)
	var wd := WeaponDB.get_weapon(&"kar98k")
	var eye := s.global_position + Vector3.UP * 1.5
	k = 0
	for nm in SURFACES:
		var tgt: Vector3 = (walls[nm] as Node3D).global_position + Vector3.UP * 0.3
		var h0: int = Effects.holes_made
		Ballistics.fire(s, eye + side * (float(k) - 1.5) * 1.3, (tgt - (eye + side * (float(k) - 1.5) * 1.3)).normalized(), wd,
			s.exclude_rids(), s.team)
		k += 1
		var ok := false
		for i in 60:
			await get_tree().physics_frame
			if Effects.holes_made > h0:
				ok = true
				break
		var d: Decal = Effects.last_hole
		check(ok and d != null, "%s: Projektil hinterlässt Einschussloch" % nm)
		if ok and d:
			var face := (walls[nm] as Node3D).global_position + fwd * -0.15
			var dist := absf((d.global_position - face).dot(fwd))
			check(dist < 0.03, "%s: Loch auf der getroffenen Fläche" % nm, "%.3f m" % dist)
			check(d.global_basis.y.normalized().dot(-fwd) > 0.95, "%s: Projektion entlang der Flächennormalen" % nm)
			check(d.size.x >= 0.1 and d.size.z >= 0.1, "%s: Größe ≥ 10 cm (vorher 6 cm)" % nm, str(d.size))
			check(not d.distance_fade_enabled and d.upper_fade <= 0.15 and d.lower_fade <= 0.15,
				"%s: keine Entfernungsausblendung, volle Deckkraft an der Fläche" % nm)
	# --- Boden (echter Untergrund der Karte) ---
	var h1: int = Effects.holes_made
	Ballistics.fire(s, eye, (s.global_position + fwd * 1.5 - eye).normalized(), wd, s.exclude_rids(), s.team)
	await frames(10)
	check(Effects.holes_made > h1, "Bodentreffer hinterlässt Einschussloch")
	await _shots(s, fwd, walls)
	# --- Ring-Puffer ---
	var p0 := s.global_position + side * 6.0
	for i in 220:
		Effects.impact(p0 + Vector3(float(i % 20) * 0.05, 0.02, float(i / 20) * 0.05), Vector3.UP)
	await frames(2)
	var live := 0
	for d in Effects._decals:
		if is_instance_valid(d):
			live += 1
	check(Effects._decals.size() <= Effects.MAX_DECALS and live <= Effects.MAX_DECALS, "Obergrenze %d Decals (älteste entfallen)" % Effects.MAX_DECALS,
		str(Effects._decals.size()))
	check(is_instance_valid(Effects.last_hole) and Effects._decals.back() == Effects.last_hole, "Neuestes Loch bleibt erhalten")
	Settings.decals = false
	var h2: int = Effects.holes_made
	Effects.impact(p0, Vector3.UP)
	check(Effects.holes_made == h2, "Option DEKORATIONEN aus → keine Löcher")
	Settings.decals = true
	_finish()


## Kontrollbilder (nur Fenster): nah, 15 m, Zielfernrohr (FOV 6°) aus 40 m
func _shots(s: Soldier, fwd: Vector3, walls: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/impacts"))
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	var mid := Vector3.ZERO
	for nm in walls:
		mid += (walls[nm] as Node3D).global_position
	mid = mid / float(walls.size()) + Vector3.UP * 0.3
	for v in [["nah", 2.5, 60.0], ["15m", 15.0, 60.0], ["zielfernrohr_40m", 40.0, 6.0]]:
		cam.fov = v[2]
		cam.global_position = mid - fwd * (0.15 + float(v[1])) + Vector3.UP * 0.2
		cam.look_at(mid, Vector3.UP)
		cam.make_current()
		for i in 6:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://test_output/impacts/impacts_%s.png" % v[0]))
	cam.queue_free()
