extends Node
## Kontrollbilder + Messung der Castle-Kulisse (Fenster, kein --headless):
## tools/godot.cmd -- --mission=castle --autoplay=screenshots_castle_backdrop → test_output/castle_backdrop/*.png, perf.txt
## Baut die Kulisse selbst, falls die Mission sie (noch) nicht aufgerufen hat.

const Backdrop := preload("res://src/maps/castle/castle_backdrop.gd")
const OUT := "res://test_output/castle_backdrop/"


func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func(): get_tree().quit(1))


func _run() -> void:
	var m: Mission
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	var waited := 0.0
	while not m.nav_ready and waited < 90.0:      # Navmesh ist für die Kulisse unerheblich
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if m.hud:
		m.hud.visible = false
	var t0 := Time.get_ticks_msec()
	if m.get_node_or_null("CastleBackdrop") == null:
		Backdrop.build(m)
	var built_ms := Time.get_ticks_msec() - t0
	var root := m.get_node_or_null("CastleBackdrop") as Node3D
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var lines: Array = ["build_ms %d" % built_ms, "stats %s" % JSON.stringify(Backdrop.stats)]
	if root == null:
		print("ERGEBNIS: Castle-Kulisse: 0 bestanden, 1 fehlgeschlagen (keine Kulisse)")
		get_tree().quit(1)
		return
	var cam := Camera3D.new()
	cam.set_meta("b041_keep_far", true)
	cam.far = 6000.0
	m.add_child(cam)
	cam.make_current()
	# [Name, Position (y = Höhe über Gelände), Blickziel (absolut)] – Rahmen: x Ost, z Süd, y 0 = Hof
	var views := [
		["mauer_west_see", Vector3(20, 14, -420), Vector3(-120, -62, -470)],
		["mauer_ost_fluss", Vector3(150, 14, -330), Vector3(330, -62, -300)],
		["hang_nah", Vector3(-10, 6, -250), Vector3(-80, -40, -260)],
		["vogel_see", Vector3(-350, 320, -150), Vector3(-60, -60, -520)],
		["uebersicht", Vector3(650, 380, 350), Vector3(120, -40, -420)],
		["sued_horizont", Vector3(100, 15, 60), Vector3(100, 0, 1200)],
		["nord_horizont", Vector3(170, 25, -1010), Vector3(260, 0, -2600)],
		["hoch_sued", Vector3(120, 140, -950), Vector3(160, -40, 400)],
	]
	var ok := 0
	for v in views:
		var p: Vector3 = v[1]
		cam.global_position = Vector3(p.x, m.ground_y(p.x, p.z) + p.y, p.z)
		cam.look_at(v[2])
		cam.fov = 65.0
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var dc_on := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var pr_on := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var img := get_viewport().get_texture().get_image()
		if img.save_png(ProjectSettings.globalize_path(OUT + String(v[0]) + ".png")) == OK:
			ok += 1
		# Anteile: ohne 3D-Bäume, ohne alle Bäume, ohne Häuser
		var parts := []
		for prefix in ["Wald3D", "Wald", "Haeuser", "Ufer", "Kirchtuerme", "Ferngelaende", "Horizont", "Wasser"]:
			for c in root.get_children():
				if String(c.name).begins_with(prefix):
					c.visible = false
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			parts.append("ohne %s %d/%d" % [prefix, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
			for c in root.get_children():
				c.visible = true
		lines.append("%s Anteile: %s" % [v[0], ", ".join(parts)])
		root.visible = false
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var dc_off := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var pr_off := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		root.visible = true
		lines.append("%s draws %d (ohne Kulisse %d) prims %d (ohne %d)" % [v[0], dc_on, dc_off, pr_on, pr_off])
		var pf := FileAccess.open(OUT + "perf.txt", FileAccess.WRITE)
		pf.store_string("\n".join(lines) + "\n")
		pf.close()
	var f := FileAccess.open(OUT + "perf.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	for l in lines:
		print("CASTLE_BACKDROP_PROBE ", l)
	print("ERGEBNIS: Castle-Kulisse: %d bestanden, %d fehlgeschlagen" % [ok, views.size() - ok])
	get_tree().quit(0 if ok == views.size() else 1)
