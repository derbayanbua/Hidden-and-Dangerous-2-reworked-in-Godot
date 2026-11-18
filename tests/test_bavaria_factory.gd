extends "res://tests/test_bavaria_landmark.gd"
## Zweiter Fern-Blickfang der Karte Bavaria: Werk im Nordosten (src/maps/bavaria/factory_landmark.gd).
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_factory
## Prüft: außerhalb der Fläche und im Nordosten, keine Kollision/kein Navmesh, innerhalb der Kamera-far, ohne Schatten,
## Zeichenaufrufe < 10, Sichtlinien-Anteil der Schornsteinspitzen, Tag/Nacht (Rauch, Fenster, Glimmen).
## Hilfen (Höhenraster, _clear, _edge_dist) aus test_bavaria_landmark.gd.

func _finish() -> void:
	print("ERGEBNIS test_bavaria_factory: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	var fw = m.get("factory_landmark")
	check(fw != null and fw.get_parent() == m and fw.is_in_group("bavaria_factory"), "Werk vorhanden, Kind der Mission")
	if fw == null:
		_finish()
		return
	var b: PackedVector2Array = m.boundary
	var c := Vector2.ZERO
	for q in b:
		c += q
	c /= b.size()
	# --- Lage: außerhalb, Nordosten ---
	var verts: PackedVector3Array = []
	for mi in [fw.mesh_instance, fw.windows_instance]:
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			for v in (mi as MeshInstance3D).mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				verts.append((mi as MeshInstance3D).global_transform * v)
	var inside := 0
	var min_edge := INF
	for v in verts:
		var q := Vector2(v.x, v.z)
		inside += int(Geometry2D.is_point_in_polygon(q, b))
		min_edge = minf(min_edge, _edge_dist(q, b))
	check(inside == 0, "kein Eckpunkt innerhalb der Spielfläche (%d Ecken)" % verts.size())
	check(min_edge > 15.0, "Geländerand ≥ 15 m von der Grenze (%.0f m)" % min_edge)
	var ring = m.get("panorama_ring")
	if ring != null:
		var rmax := 0.0
		for v in verts:
			if v.y > -0.2:
				rmax = maxf(rmax, Vector2(v.x, v.z).distance_to(ring.center))
		check(rmax < ring.RADIUS, "Werk steht vor dem Panoramaring (%.0f < %.0f m)" % [rmax, ring.RADIUS])
	# Himmelsrichtung wie alps_sky.gdshader: Süd = south_direction, Ost = (s.z, −s.x)
	var south := Vector2(0.817, 0.576)
	var east := Vector2(south.y, -south.x)
	var d: Vector2 = (fw.factory_center - c).normalized()
	var az := rad_to_deg(atan2(d.dot(east), -d.dot(south)))     # 0 = Nord, 90 = Ost
	print("  Werk ", fw.factory_center, ", Azimut %.0f° (0 = N, 90 = O), Abstand Mitte %.0f m" % [az, fw.factory_center.distance_to(c)])
	check(az > 30.0 and az < 60.0, "liegt im Nordosten (Azimut %.0f°)" % az)
	var cd := _edge_dist(fw.factory_center, b)
	check(cd >= 70.0 and cd <= 170.0, "Werk %.0f m außerhalb der Grenze (70–170, vor dem Panoramaring)" % cd)
	# --- keine Kollision, kein Navmesh ---
	var coll: int = fw.find_children("*", "CollisionObject3D", true, false).size() + fw.find_children("*", "CollisionShape3D", true, false).size()
	check(coll == 0, "keine Kollisionskörper/-formen (%d)" % coll)
	var nav_root = m.get("nav_region")
	check(nav_root == null or not (nav_root as Node).is_ancestor_of(fw), "nicht in der Navmesh-Quelle (nav_region)")
	check(m.static_root == null or not m.static_root.is_ancestor_of(fw), "nicht unter static_root")
	var space := m.get_world_3d().direct_space_state
	var top: Vector3 = fw.chimney_tops[0]
	var rq := PhysicsRayQueryParameters3D.create(top + Vector3.UP * 5.0, Vector3(top.x, -5.0, top.z))
	check(space.intersect_ray(rq).is_empty(), "Strahl durch Schlot/Hang trifft nichts (keine Physik)")
	# --- Kamera-far ---
	var far: float = m.VIEW_FAR
	var pts: Array[Vector3] = []
	pts.append_array(verts)
	for p in [fw.smoke, fw.glow]:
		var box: AABB = (p as GPUParticles3D).global_transform * (p as GPUParticles3D).visibility_aabb
		for k in 8:
			pts.append(box.get_endpoint(k))
	var maxd := 0.0
	for q in b:
		var eye := Vector3(q.x, 1.7, q.y)
		for v in pts:
			maxd = maxf(maxd, eye.distance_to(v))
	check(maxd < far, "ganzes Werk inkl. Rauch-AABB innerhalb Kamera-far (%.0f < %.0f m)" % [maxd, far])
	# --- Darstellung, Zeichenaufrufe ---
	var gis: Array = fw.find_children("*", "GeometryInstance3D", true, false)
	var shadow_ok := true
	var range_ok := true
	var dc := 0
	for g in gis:
		var gi := g as GeometryInstance3D
		shadow_ok = shadow_ok and gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		range_ok = range_ok and gi.visibility_range_begin > 20.0 and gi.visibility_range_begin_margin > 0.0 \
			and gi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF \
			and gi.visibility_range_begin + gi.visibility_range_begin_margin < _edge_dist(_xz((gi.global_transform * gi.get_aabb()).get_center()), b)
		if g is MeshInstance3D:
			dc += (g as MeshInstance3D).mesh.get_surface_count()
		elif g is GPUParticles3D:
			dc += 1
	check(shadow_ok, "kein Schattenwurf (%d Geometrien)" % gis.size())
	check(range_ok, "weiche Nahausblendung, von der Spielfläche aus immer sichtbar")
	print("  Zeichenaufrufe Werk: %d (Flächen + Partikel-Durchgänge)" % dc)
	check(dc < 10, "Zeichenaufrufe < 10 (%d)" % dc)
	# Zählung im Renderer: Objekte im Bild mit/ohne Werk (nur mit Fenster aussagekräftig)
	if DisplayServer.get_name() != "headless":
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.global_position = Vector3(c.x, 1.7, c.y)
			cam.look_at(Vector3(fw.factory_center.x, 20.0, fw.factory_center.y))
			await get_tree().create_timer(1.0).timeout
			var on := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			fw.visible = false
			await get_tree().create_timer(1.0).timeout
			var off := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			fw.visible = true
			print("  Renderer: Draw Calls mit Werk %d, ohne %d (Δ %d)" % [on, off, on - off])
	# --- Sichtlinien: Schornsteinspitzen über Wald/Häusern ---
	_height_grid(m, fw)
	var tops: Array = fw.chimney_tops
	var r := Rect2(b[0], Vector2.ZERO)
	for p in b:
		r = r.expand(p)
	var n_all := 0
	var n_any := 0
	var n_tops := 0
	var x := r.position.x
	while x < r.end.x:
		var z := r.position.y
		while z < r.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), b):
				n_all += 1
				var k := 0
				for t in tops:
					k += int(_clear(Vector3(x, 1.7, z), t))
				n_any += int(k > 0)
				if k >= tops.size() - 1:
					print("  SICHT PUNKT %.0f,%.0f (%d/%d Spitzen)" % [x, z, k, tops.size()])
				n_tops += k
			z += 4.0
		x += 4.0
	var pct_any := 100.0 * n_any / maxi(n_all, 1)
	var pct_tops := 100.0 * n_tops / maxi(n_all * tops.size(), 1)
	print("  SICHT Bodenraster: mindestens eine Schlotspitze frei von %d/%d Punkten (%.1f %%), Spitzen gesamt %.1f %%" % [n_any, n_all, pct_any, pct_tops])
	var eyes: Array = []
	for s in m.layout["spawns"]:
		eyes.append(m.pixel(s["pixel"]) + Vector3.UP * 1.7)
	for zz in m.layout["occupation_zones"]:
		eyes.append(m.pixel(zz["pixel"]) + Vector3.UP * 1.7)
	var e_seen := 0
	for e in eyes:
		var ok := false
		for t in tops:
			ok = ok or _clear(e, t)
		e_seen += int(ok)
	print("  SICHT Starts/Zonen: %d/%d" % [e_seen, eyes.size()])
	check(n_any > 0, "Schlotspitzen über dem Waldgürtel sichtbar (%.1f %% des Bodenrasters)" % pct_any)
	# --- Tag/Nacht ---
	var dn = m.day_night
	dn.set_hour(12.0, 0.0)
	dn._apply(true)
	fw._update(true)
	var ds: Color = fw._smoke_mat.albedo_color
	var dw: Color = fw._win_mat.albedo_color
	var dg: Color = fw._fire_mat.albedo_color
	dn.set_hour(0.5, 0.0)
	dn._apply(true)
	fw._update(true)
	var ns: Color = fw._smoke_mat.albedo_color
	var nw: Color = fw._win_mat.albedo_color
	var ng: Color = fw._fire_mat.albedo_color
	check(ds.v > 0.6 and ns.v < ds.v * 0.3, "Rauch tagsüber hellgrau, nachts dunkel (%.2f → %.2f)" % [ds.v, ns.v])
	check(nw.r > 1.0 and dw.r < 0.4, "Fenster nachts erleuchtet (%.2f → %.2f)" % [dw.r, nw.r])
	check(ng.r > dg.r + 1.0 and ng.a > dg.a, "Schlote glimmen nachts (%.2f → %.2f)" % [dg.r, ng.r])
	check(fw.smoke.emitting and fw.glow.emitting and not fw.smoke.local_coords, "Rauch/Glimmen laufen (Weltkoordinaten)")
	_finish()
