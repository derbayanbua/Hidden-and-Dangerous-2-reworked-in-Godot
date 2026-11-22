extends "res://tests/test_mp_nav.gd"
## B-010c Fehlersuche Navmesh: tools\godot.cmd --headless -- --autoplay=probe_b010d_grid --maps=<id>
##   --box=x0,z0,x1,z1 --levels=y1,y2,... [--step=0.5] [--front_only]
## Ausgabe: POLY-Zeilen (alle Netzpolygone im Kasten mit Eckpunkten), je Rasterpunkt und Ebene Netz vorhanden (N),
## Kollisionsboden ohne Netz (B), Kopfraum bis zur nächsten Fläche, WICKLUNG je getroffenem Körper.


var _seen := {}


## Wicklung des getroffenen Dreiecks (Recast nimmt nur Dreiecke, deren Normale nach oben zeigt)
func _report_winding(h: Dictionary) -> void:
	var body := h.collider as CollisionObject3D
	if body == null:
		return
	var p: Vector3 = h.position
	for sid in body.get_shape_owners():
		var xf: Transform3D = body.global_transform * body.shape_owner_get_transform(sid)
		for k in body.shape_owner_get_shape_count(sid):
			var sh := body.shape_owner_get_shape(sid, k) as ConcavePolygonShape3D
			if sh == null:
				print("   WICKLUNG %s: Form %s" % [body.get_parent().name, body.shape_owner_get_shape(sid, k)])
				continue
			var f := sh.get_faces()
			var up := 0
			var dn := 0
			var hit := ""
			for i in range(0, f.size(), 3):
				var a: Vector3 = xf * f[i]
				var b: Vector3 = xf * f[i + 1]
				var c: Vector3 = xf * f[i + 2]
				var n := (b - a).cross(c - a)
				if n.length() < 1e-6:
					continue
				n = n.normalized()
				if n.y > 0.5:
					up += 1
				elif n.y < -0.5:
					dn += 1
				var bc: Variant = Geometry3D.ray_intersects_triangle(p + Vector3.UP, Vector3.DOWN, a, b, c)
				if bc != null:
					hit = "Treffer-Normale %s" % _v(n)
			print("   WICKLUNG %s: %d Dreiecke oben, %d unten, %s, beidseitig %s" % [body.get_parent().name, up, dn, hit,
				sh.backface_collision])


func _test_map(id: String) -> void:
	var old := Game.current_mission()
	Game.start_mission(id)
	var m: Mission = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000:
		await get_tree().process_frame
		var cm := Game.current_mission() as Mission
		if cm and cm != old and is_instance_valid(cm) and cm.is_node_ready():
			m = cm
			break
	if m == null:
		return
	while not m.nav_ready and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().process_frame
	await frames(5)
	var nav_map := m.nav_region.get_navigation_map()
	var space := m.get_world_3d().direct_space_state
	var bx := String(Game.cli.get("box", "0,0,1,1")).split_floats(",")
	for n in m.find_children("*", "NavigationRegion3D", true, false):
		var nmesh := (n as NavigationRegion3D).navigation_mesh
		if nmesh == null:
			continue
		var vs := nmesh.get_vertices()
		for pi in nmesh.get_polygon_count():
			var poly := nmesh.get_polygon(pi)
			var mid := Vector3.ZERO
			var lo := INF
			var hi := -INF
			for k in poly:
				mid += vs[k]
				lo = minf(lo, vs[k].y)
				hi = maxf(hi, vs[k].y)
			mid /= poly.size()
			if mid.x >= bx[0] and mid.x <= bx[2] and mid.z >= bx[1] and mid.z <= bx[3]:
				var pts := ""
				for k in poly:
					pts += " (%.1f %.2f %.1f)" % [vs[k].x, vs[k].y, vs[k].z]
				print("POLY y %.2f..%.2f:%s" % [lo, hi, pts])
	# B-0121: --src_dump=y0,y1 = Dreiecke der Navmesh-Quellgeometrie im Kasten mit Mittelpunkt-Höhe y0…y1
	if Game.cli.has("src_dump"):
		var yr := String(Game.cli["src_dump"]).split_floats(",")
		var src := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(m.nav_region.navigation_mesh, src, m.nav_region)
		var sv := src.get_vertices()
		var si := src.get_indices()
		var cnt := 0
		for t in range(0, si.size() - 2, 3):
			var a := Vector3(sv[si[t] * 3], sv[si[t] * 3 + 1], sv[si[t] * 3 + 2])
			var b := Vector3(sv[si[t + 1] * 3], sv[si[t + 1] * 3 + 1], sv[si[t + 1] * 3 + 2])
			var c := Vector3(sv[si[t + 2] * 3], sv[si[t + 2] * 3 + 1], sv[si[t + 2] * 3 + 2])
			var mid := (a + b + c) / 3.0
			if mid.x < bx[0] or mid.x > bx[2] or mid.z < bx[1] or mid.z > bx[3] or mid.y < yr[0] or mid.y > yr[1]:
				continue
			var n := (b - a).cross(c - a)
			cnt += 1
			if cnt <= 60:
				print("SRC %s %s %s n=%s" % [a, b, c, n.normalized()])
		print("SRC Dreiecke im Kasten: %d" % cnt)
	var st := float(Game.cli.get("step", "0.5"))
	for ys in String(Game.cli.get("levels", "0")).split(","):
		var y := float(ys)
		print("GRID y=%.2f  (Zeilen z, Spalten x ab %.1f; N=Netz B=Boden ohne Netz .=nichts, Ziffer=Kopfraum dm/2 wenn <1.8)" % [y, bx[0]])
		var z := bx[1]
		while z <= bx[3] + 0.001:
			var row := ""
			var x := bx[0]
			while x <= bx[2] + 0.001:
				var p := Vector3(x, y, z)
				var cp := NavigationServer3D.map_get_closest_point(nav_map, p)
				var on := Vector2(cp.x - x, cp.z - z).length() < 0.25 and absf(cp.y - y) < 0.45
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.35, p + Vector3.DOWN * 0.35, 1)
				q.hit_back_faces = not Game.cli.has("front_only")
				var h := space.intersect_ray(q)
				if not h.is_empty() and h.normal.y < 0.5:
					h = {}
				var ch := "N" if on else ("B" if not h.is_empty() else ".")
				if not h.is_empty() and not on and not _seen.has(h.collider_id):
					_seen[h.collider_id] = true
					_report_winding(h)
				if not h.is_empty() and not on:
					# B-0121: --mask=<Bits> = Kopfraum gegen dieselben Ebenen wie die Navmesh-Quelle (Standard nur Welt)
					var q2 := PhysicsRayQueryParameters3D.create(h.position + Vector3.UP * 0.05, h.position + Vector3.UP * 2.0,
						int(Game.cli.get("mask", "1")))
					q2.collide_with_areas = Game.cli.has("mask")
					q2.hit_back_faces = true
					var h2 := space.intersect_ray(q2)
					if Game.cli.has("mask") and not h2.is_empty() and not _seen.has(-int(h2.collider_id)):
						_seen[-int(h2.collider_id)] = true
						var co := h2.collider as CollisionObject3D
						print("   DECKE %s Ebene %d bei y %.2f" % [co.get_path() if co else "?", co.collision_layer if co else 0,
							h2.position.y])
					if not h2.is_empty():
						ch = str(clampi(int((h2.position.y - h.position.y) * 5.0), 0, 9))
				row += ch
				x += st
			print("  z=%7.2f %s" % [z, row])
			z += st
