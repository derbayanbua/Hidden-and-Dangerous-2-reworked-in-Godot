extends Node
## Dynamisches Wetter der Karte Bavaria (src/maps/bavaria/weather.gd).
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_weather
## Prüft: Wetterknoten, Zustandsfolge, Wirkung auf Himmel/Panoramaring/Sonne/Nebel/Lampen, Nässe (Böden/Fassaden),
## Regen nur im Freien (Haus/Stollen trocken), weicher Übergang, Blitze bei Gewitter, Partikelbudget.
var failed := 0
var passed := 0

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung (300 s)")
		_finish())

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("PASS " if ok else "FAIL ", label)

func _finish() -> void:
	print("ERGEBNIS test_bavaria_weather: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	var wx = m.get("weather")
	check(wx != null and String(wx.name) == "Wetter" and wx.get_parent() == m, "Wetterknoten „Wetter“ an fester Stelle")
	if wx == null or not wx.enabled:
		check(false, "Wetter eingeschaltet (ohne --weather=0)")
		_finish()
		return
	check(wx.STATES.has(wx.current), "Startzustand gültig: " + String(wx.current))
	var ok_pick := true
	for i in 200:
		var s: String = wx._pick(wx.STATES[i % 4])
		ok_pick = ok_pick and wx.STATES.has(s)
	check(ok_pick, "Zustandsfolge liefert nur bekannte Zustände")
	var dn = m.day_night
	dn.cycle_min = 0.0
	dn.set_hour(12.0)
	# --- klar
	wx.set_weather("klar", true)
	await _frames(3)
	var sun_clear: float = dn._sun.light_energy
	var fog_clear: float = dn._env.fog_density
	var amb_clear: float = dn._env.ambient_light_energy
	var sky: ShaderMaterial = dn._env.sky.sky_material as ShaderMaterial if dn._env.sky else null
	check(sky == null or float(sky.get_shader_parameter("overcast")) < 0.15, "klar: Himmel fast wolkenlos")
	check(not wx.state().rain_visible, "klar: kein Regen")
	# --- Gewitter
	wx.set_weather("gewitter", true)
	await _frames(3)
	check(dn._sun.light_energy < sun_clear * 0.3, "Gewitter: Sonne gedämpft (%.2f → %.2f)" % [sun_clear, dn._sun.light_energy])
	check(dn._env.ambient_light_energy < amb_clear, "Gewitter: Umgebungslicht dunkler")
	check(dn._env.fog_density > fog_clear * 1.5 or fog_clear == 0.0, "Gewitter: dichterer Nebel")
	check(sky == null or float(sky.get_shader_parameter("overcast")) > 0.9, "Gewitter: geschlossene Wolkendecke im Himmel")
	var ring = m.get("panorama_ring")
	if ring and ring.get("material"):
		check(float(ring.material.get_shader_parameter("overcast")) > 0.9, "Gewitter: Panoramaring abgedunkelt")
	check(dn.state().lamp < 0.05, "Gewitter am Tag: Lampen bleiben aus (Draw-Call-Budget)")
	check(is_equal_approx(wx.wet, 1.0), "Gewitter: Böden nass")
	var mats_ok: bool = wx._wet_mats.size() > 0
	for e in wx._wet_mats:
		mats_ok = mats_ok and (e[0] as StandardMaterial3D).roughness <= float(e[1]) * 0.55 + 0.001
	check(mats_ok, "Nässe: Fassaden-/Bodenmaterialien glatter (%d)" % wx._wet_mats.size())
	for gm in wx._ground_mats:
		if not is_equal_approx(float(gm.get_shader_parameter("wetness")), 1.0):
			mats_ok = false
	check(mats_ok, "Nässe: Bodenshader „wetness“ gesetzt (%d)" % wx._ground_mats.size())
	# --- Regen nur draußen
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	var outside: Vector3 = m.pixel(m.layout.spawns[0].pixel) + Vector3.UP * 1.7
	cam.global_position = outside
	await _frames(4)
	check(not wx.roof_above(outside) and wx.state().rain_visible, "Regen im Freien sichtbar")
	var inside := _house_inside(m)
	if inside.is_finite():
		cam.global_position = inside
		await _frames(4)
		check(wx.roof_above(inside) and not wx.state().rain_visible, "Kein Regen im Haus (Decke über der Kamera)")
	else:
		check(false, "Haus mit Decke gefunden")
	var tunnel := _tunnel_point(m)
	if tunnel.is_finite():
		check(wx.roof_above(tunnel), "Kein Regen im Stollen")
	cam.global_position = outside
	await _frames(2)
	# --- weicher Übergang
	wx.set_weather("klar")
	check(wx.blend < 0.01, "Übergang beginnt weich (nicht sofort)")
	wx._process(wx.BLEND_S * 0.5)
	var mid := float(wx.factors().cloud)
	check(mid > 0.2 and mid < 0.95, "Halber Übergang: Bewölkung dazwischen (%.2f)" % mid)
	wx._process(wx.BLEND_S)
	check(wx.blend >= 1.0 and float(wx.factors().cloud) < 0.15, "Übergang abgeschlossen")
	check(wx.wet < 1.0, "Abtrocknen nach dem Regen beginnt")
	# --- Blitze
	wx.set_weather("gewitter", true)
	for i in 50:
		wx._update_flash(1.0)
	check(wx.flash_count >= 1, "Gewitter: Blitze (%d)" % wx.flash_count)
	# --- Budget
	check(wx._rain.amount <= 1700 and wx._rain.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"Partikelbudget: ein Regenemitter ≤ 1700 ohne Schatten (%d)" % wx._rain.amount)
	cam.queue_free()
	_finish()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	await get_tree().physics_frame

func _house_inside(m: Mission) -> Vector3:
	for b in m.get_tree().get_nodes_in_group("bavaria_buildings"):
		if String(b.name) == "haus_16" or String(b.name).begins_with("haus_"):
			var p: Vector3 = (b as Node3D).global_position + Vector3.UP * 1.6
			var w := m.get_viewport().world_3d
			var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 40.0, 1)
			if not w.direct_space_state.intersect_ray(q).is_empty():
				return p
	return Vector3.INF

func _tunnel_point(m: Mission) -> Vector3:
	# Stollenlampe hängt unter der Decke: knapp darunter liegt Erdreich über dem Punkt
	for n in m.get_tree().get_nodes_in_group("bavaria_tunnel_lamps"):
		return (n as Node3D).global_position + Vector3.DOWN * 0.4
	return Vector3.INF
