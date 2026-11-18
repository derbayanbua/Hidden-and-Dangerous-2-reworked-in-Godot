extends Node
## Fern-Blickfang der Karte Bavaria (src/maps/bavaria/landmark.gd).
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_landmark
## Prüft: liegt außerhalb der Spielfläche (350–600 m), keine Kollision/kein Navmesh, innerhalb der Kamera-far,
## ohne Schatten, weiche Nahausblendung, Turm über dem Baumgürtel von mehreren Spielerpositionen, Tag/Nacht, Budget.
## Blickschneise Südwest: Turmspitze von ≥ 25 % der Bodenpunkte und von der Wiesenmitte/Zone C frei.
## Vergleich ohne Schneise: --schneise=0 (dann schlagen die Schneisen-Prüfungen erwartungsgemäß fehl).
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
	print("ERGEBNIS test_bavaria_landmark: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	var m: Mission
	while m == null or not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
		m = Game.current_mission()
	var lm = m.get("landmark")
	check(lm != null and lm.get_parent() == m and lm.is_in_group("bavaria_landmark"), "Blickfang vorhanden, Kind der Mission")
	if lm == null:
		_finish()
		return
	var b: PackedVector2Array = m.boundary
	# --- Lage: außerhalb der Fläche ---
	var verts: PackedVector3Array = []
	var mi: MeshInstance3D = lm.mesh_instance
	for s in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			verts.append(mi.global_transform * v)
	var inside := 0
	var min_edge := INF
	for v in verts:
		var q := Vector2(v.x, v.z)
		if Geometry2D.is_point_in_polygon(q, b):
			inside += 1
		min_edge = minf(min_edge, _edge_dist(q, b))
	check(inside == 0, "kein Eckpunkt innerhalb der Spielfläche (%d Ecken)" % verts.size())
	var tower: Vector3 = lm.tower_top
	print("  Turmspitze ", tower, ", Rauchquelle ", lm.smoke.global_position)
	var tdist := _edge_dist(Vector2(tower.x, tower.z), b)
	check(tdist >= 70.0 and tdist <= 170.0, "Turm %.0f m außerhalb der Grenze (70–170, vor dem Panoramaring)" % tdist)
	var hdist := _edge_dist(lm.hill_center, b)
	check(hdist >= 70.0 and hdist <= 170.0, "Kuppe %.0f m außerhalb der Grenze (70–170)" % hdist)
	check(min_edge > 15.0, "Hangfuß ≥ 15 m von der Grenze (%.0f m)" % min_edge)
	var ring = m.get("panorama_ring")
	if ring != null:
		var rmax := 0.0
		for v in verts:
			if v.y > -0.2:
				rmax = maxf(rmax, Vector2(v.x, v.z).distance_to(ring.center))
		check(rmax < ring.RADIUS, "Dorf steht vor dem Panoramaring (%.0f < %.0f m)" % [rmax, ring.RADIUS])
	# --- keine Kollision, kein Navmesh ---
	var coll: int = lm.find_children("*", "CollisionObject3D", true, false).size() + lm.find_children("*", "CollisionShape3D", true, false).size()
	check(coll == 0, "keine Kollisionskörper/-formen (%d)" % coll)
	var nav_root = m.get("nav_region")
	check(nav_root == null or not (nav_root as Node).is_ancestor_of(lm), "nicht in der Navmesh-Quelle (nav_region)")
	check(m.static_root == null or not m.static_root.is_ancestor_of(lm), "nicht unter static_root (PerfTuning/Navmesh)")
	var space := m.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(tower + Vector3.UP * 5.0, Vector3(tower.x, 5.0, tower.z))
	check(space.intersect_ray(rq).is_empty(), "Strahl durch Turm/Anhöhe trifft nichts (keine Physik)")
	# --- innerhalb der Kamera-far (von jedem Grenzpunkt = entferntester Spielerstandort) ---
	var far: float = m.VIEW_FAR
	var pts: Array[Vector3] = []
	pts.append_array(verts)
	for p in [lm.smoke, lm.fire]:
		var box: AABB = (p as GPUParticles3D).global_transform * (p as GPUParticles3D).visibility_aabb
		for k in 8:
			pts.append(box.get_endpoint(k))
	var maxd := 0.0
	for c in b:
		var eye := Vector3(c.x, 1.7, c.y)
		for v in pts:
			maxd = maxf(maxd, eye.distance_to(v))
	check(maxd < far, "ganzes Objekt inkl. Rauch-AABB innerhalb Kamera-far (%.0f < %.0f m)" % [maxd, far])
	# --- Darstellung: ohne Schatten, weiche Nahausblendung, die Karte liegt außerhalb der Ausblendzone ---
	var gis: Array = lm.find_children("*", "GeometryInstance3D", true, false)
	var shadow_ok := true
	var range_ok := true
	for g in gis:
		var gi := g as GeometryInstance3D
		shadow_ok = shadow_ok and gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		range_ok = range_ok and gi.visibility_range_begin > 20.0 and gi.visibility_range_begin_margin > 0.0 \
			and gi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF \
			and gi.visibility_range_begin + gi.visibility_range_begin_margin < _edge_dist(_xz((gi.global_transform * gi.get_aabb()).get_center()), b)
	check(shadow_ok, "kein Schattenwurf (%d Geometrien)" % gis.size())
	check(range_ok, "weiche Nahausblendung (visibility_range_begin), von der Spielfläche aus immer sichtbar")
	# Budget: Flächen + Partikel-Durchgänge ≈ Draw Calls (Ziel < 30)
	var dc := 0
	for g in gis:
		if g is MeshInstance3D:
			dc += (g as MeshInstance3D).mesh.get_surface_count()
		elif g is GPUParticles3D:
			dc += 1
	check(dc <= 6, "Zeichenaufrufe des Blickfangs ≤ 6 (%d)" % dc)
	# --- Sichtlinien: Turmspitze über Bäumen/Häusern, Blickschneise Südwest (scene_details.vista_factor) ---
	_height_grid(m, lm)
	var eyes: Array = []
	for s in m.layout["spawns"]:
		eyes.append(["Start", m.pixel(s["pixel"]) + Vector3.UP * 1.7])
	for z in m.layout["occupation_zones"]:
		eyes.append(["Zone " + String(z.get("name", "?")).left(1), m.pixel(z["pixel"]) + Vector3.UP * 1.7])
	# OG-Fensterplätze (begehbare Obergeschosse) als erhöhte Spielerpositionen
	for h in m.static_root.get_children():
		for w in (h as Node).get_meta("og_shooting_windows", []):
			eyes.append(["OG-Fenster " + String(h.name), (h as Node3D).to_global(w) + Vector3.UP * 1.6])
	var seen := 0
	var spots := {}
	var zone_c := false
	for e in eyes:
		if _clear(e[1], tower):
			seen += 1
			spots[Vector2i(roundi(e[1].x), roundi(e[1].z))] = true
			zone_c = zone_c or String(e[0]) == "Zone C"
			print("  Sicht frei ab %s %s" % [e[0], e[1]])
	# Bodenraster der Spielfläche (Augenhöhe, 4 m): Anteil mit freiem Blick auf die Turmspitze
	var r := Rect2(b[0], Vector2.ZERO)
	for p in b:
		r = r.expand(p)
	var n_all := 0
	var n_free := 0
	var x := r.position.x
	while x < r.end.x:
		var z := r.position.y
		while z < r.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), b):
				n_all += 1
				if _clear(Vector3(x, 1.7, z), tower, true):
					n_free += 1
					spots[Vector2i(roundi(x), roundi(z))] = true
			z += 4.0
		x += 4.0
	var share := 100.0 * n_free / maxi(n_all, 1)
	print("  Bodenraster: Turmspitze frei von %d/%d Punkten (%.0f %%), erstes Hindernis je Art: %s" % [n_free, n_all, share, _blocked])
	check(spots.size() >= 2, "Turmspitze von ≥ 2 verschiedenen Spielerpositionen über den Bäumen sichtbar (%d Starts/Zonen/Fenster, %d Rasterpunkte)" % [seen, n_free])
	check(share >= VISTA_MIN_SHARE, "Blickschneise: Turmspitze von ≥ %.0f %% der Bodenpunkte frei (%.0f %%)" % [VISTA_MIN_SHARE, share])
	# Wiesenmitte (Schwerpunkt der Wiese) und Wiesenzone C
	var mp: PackedVector2Array = m.polygon(m.layout["meadow"])
	var mc := Vector2.ZERO
	for q in mp:
		mc += q
	mc /= mp.size()
	var mid_free := 0
	for k in 9:
		var off := Vector2(k % 3 - 1, k / 3 - 1) * 6.0
		mid_free += int(_clear(Vector3(mc.x + off.x, 1.7, mc.y + off.y), tower))
	check(mid_free >= 7, "Turmspitze von der Wiesenmitte frei (%d/9 Punkte im 12-m-Feld um %s)" % [mid_free, mc])
	check(zone_c, "Turmspitze von Zone C (Wiese) frei")
	var sd = m.get("scene_details")
	check(sd != null and sd.vista_factor(mc + (sd.vista_tower - mc).normalized() * 90.0) > 0.9,
		"Schneise führt von der Wiesenmitte Richtung Kirche (Keil außerhalb der Grenze)")
	var low := get_tree().get_nodes_in_group("bavaria_vista_bush").size()
	check(low >= 3, "Grenze in der Schneise weiter erkennbar: niedriges Randgebüsch (%d Büsche)" % low)
	var smoke_top: Vector3 = lm.smoke.global_position + Vector3.UP * 90.0 * lm.fx_k
	var seen_smoke := 0
	for e in eyes:
		seen_smoke += int(_clear(e[1], smoke_top))
	check(seen_smoke >= maxi(seen, 3), "Rauchsäule (90 m × Maßstab) von mindestens so vielen Positionen sichtbar wie der Turm (%d/%d)" % [seen_smoke, eyes.size()])
	# --- Tag/Nacht ---
	var dn = m.day_night
	dn.set_hour(12.0, 0.0)
	dn._apply(true)
	lm._update(true)
	var day_smoke: Color = lm._smoke_mat.albedo_color
	var day_fire: Color = lm._fire_mat.albedo_color
	dn.set_hour(0.5, 0.0)
	dn._apply(true)
	lm._update(true)
	var night_smoke: Color = lm._smoke_mat.albedo_color
	var night_fire: Color = lm._fire_mat.albedo_color
	check(night_smoke.v < day_smoke.v * 0.3, "Rauch nachts dunkel (%.2f → %.2f)" % [day_smoke.v, night_smoke.v])
	check(night_fire.r > day_fire.r * 3.0 and night_fire.a > day_fire.a, "Feuer glimmt nachts (%.2f → %.2f)" % [day_fire.r, night_fire.r])
	check(lm.smoke.emitting and lm.fire.emitting and not lm.smoke.local_coords, "Rauch/Feuer laufen (Weltkoordinaten)")
	_finish()

func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

func _edge_dist(q: Vector2, b: PackedVector2Array) -> float:
	var d := INF
	for i in b.size():
		d = minf(d, Geometry2D.get_closest_point_to_segment(q, b[i], b[(i + 1) % b.size()]).distance_to(q))
	return d

## Höhenraster (2 m) der Sichthindernisse um die Spielfläche: kleine Objekte/MultiMesh-Instanzen als Weltbox,
## große zusammengefasste Meshes (Baum-/Gebäudebündel) je Eckpunkt. Boden (flach) und Blickfang ausgenommen.
const CELL := 2.0
var _g0 := Vector2.ZERO
var _gw := 0
var _gh := 0
var _grid := PackedFloat32Array()
var _src := PackedByteArray()      ## Art des höchsten Punkts je Zelle (Index in KINDS)
var _cur := 0
var _blocked := {}
const KINDS := ["Haus", "Hecke", "Kartenbaum", "Randkulisse", "Sonstiges"]
const VISTA_MIN_SHARE := 25.0      ## vor der Schneise ≈ 4 % (alte Box-Rasterung) bzw. 8 % (korrigiert, --schneise=0)

func _height_grid(m: Node, lm: Node) -> void:
	var r := Rect2(m.boundary[0], Vector2.ZERO)
	for p in m.boundary:
		r = r.expand(p)
	r = r.grow(90.0)
	_g0 = r.position
	_gw = int(r.size.x / CELL) + 1
	_gh = int(r.size.y / CELL) + 1
	_grid.resize(_gw * _gh)
	_grid.fill(-100.0)
	_src.resize(_gw * _gh)
	for gi in m.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if not g.is_visible_in_tree() or lm.is_ancestor_of(g) or g is GPUParticles3D:
			continue
		var sm := g.material_override as ShaderMaterial
		if sm and sm.shader and sm.shader.code.contains("blend_add"):
			continue                                   # Lichtkegel (Suchturm-Scheinwerfer): additiv, kein Hindernis
		_cur = _kind(g)
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			# Der Dummy-Renderer (headless) hat keinen Instanzpuffer (alle Lagen = Identität → Phantom-Riesenkrone am
			# Ursprung). Lagen dann aus der Meta instance_xforms (scene_details.keep_xforms).
			var metas: Array = g.get_meta("instance_xforms", [])
			for k in mm.instance_count:
				var ixf := g.global_transform * (metas[k] as Transform3D if k < metas.size() else mm.get_instance_transform(k))
				var ibox := ixf * mm.mesh.get_aabb()
				if ibox.size.x < 40.0 and ibox.size.z < 40.0:
					_raster_box(ibox)
				else:
					# zusammengefasste Weltmeshes (Baum-/Heckenbündel als Instanz): je Eckpunkt statt als Riesenbox
					_raster_mesh(mm.mesh, ixf)
			continue
		var box := g.global_transform * g.get_aabb()
		if box.size.y < 1.0 or box.end.y < 2.0:
			continue                                   # Bodenflächen
		if box.size.x < 40.0 and box.size.z < 40.0:
			_raster_box(box)
		elif g is MeshInstance3D and (g as MeshInstance3D).mesh:
			_raster_mesh((g as MeshInstance3D).mesh, g.global_transform)

func _kind(g: Node) -> int:
	var n := g
	while n != null:
		if n.is_in_group("bavaria_boundary_screen") or n.is_in_group("bavaria_outer_forest_ring") or n.is_in_group("bavaria_outer_forest_dense"):
			return 3
		if n.is_in_group("bavaria_buildings") or n.is_in_group("bavaria_aux_houses"):
			return 0
		if n.is_in_group("bavaria_hedge_batches") or n.is_in_group("bavaria_hedges"):
			return 1
		if n.is_in_group("bavaria_tree_batches") or n.is_in_group("bavaria_all_tree_roots"):
			return 2
		n = n.get_parent()
	return 4

func _raster_mesh(mesh: Mesh, xf: Transform3D) -> void:
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			_raster_point(xf * v)

func _cell(x: float, z: float) -> int:
	var cx := int((x - _g0.x) / CELL)
	var cz := int((z - _g0.y) / CELL)
	if cx < 0 or cz < 0 or cx >= _gw or cz >= _gh:
		return -1
	return cz * _gw + cx

func _raster_point(v: Vector3) -> void:
	var c := _cell(v.x, v.z)
	if c >= 0 and v.y > _grid[c]:
		_grid[c] = v.y
		_src[c] = _cur

func _raster_box(b: AABB) -> void:
	if b.end.y < 2.0 or b.size.x > 150.0 or b.size.z > 150.0:
		return
	var x := b.position.x
	while x <= b.end.x + 0.01:
		var z := b.position.z
		while z <= b.end.z + 0.01:
			_raster_point(Vector3(x, b.end.y, z))
			z += CELL
		x += CELL

## Strecke Auge → Ziel in 1-m-Schritten über dem Höhenraster (konservativ: Kronen-/Bündelhöhe statt Laublücken).
func _clear(eye: Vector3, target: Vector3, tally := false) -> bool:
	var len2 := Vector2(eye.x, eye.z).distance_to(Vector2(target.x, target.z))
	var d := 1.5
	while d < len2:
		var f := d / len2
		var x := lerpf(eye.x, target.x, f)
		var z := lerpf(eye.z, target.z, f)
		var c := _cell(x, z)
		if c < 0:
			return true                                 # aus dem Raster heraus: nur noch Umland
		if _grid[c] > eye.y + (target.y - eye.y) * f:
			if tally:
				var k: String = KINDS[_src[c]]
				_blocked[k] = _blocked.get(k, 0) + 1
			return false
		d += 1.0
	return true
