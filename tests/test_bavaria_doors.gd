extends Node
## Türprüfung Bavaria: Jede Tür (Door, Stahltür des Bunkers) muss in einer Wandöffnung liegen.
## tools/godot.cmd --headless -- --mission=bavaria --autoplay=test_bavaria_doors [--door_png=<pfad>]
## Je Tür mit echten Strahlen gegen die Weltkollision (Türflügel selbst ausgenommen):
##  1. Durchgang: Strahl quer durch die Türmitte (1,0 m Höhe) trifft nichts → Öffnung frei
##  2. Zarge: links und rechts neben dem Flügel trifft der Querstrahl eine Wand (die Tür sitzt in einer Wand)
##  3. Sturz: oberhalb der Tür trifft der Querstrahl eine Wand
## --door_png schreibt eine Draufsicht (Grundrisse grau, Türen grün = in Öffnung, rot = verstreut).
var failed := 0
var passed := 0
var m: Mission
var report: PackedStringArray = []
var _excl: Array[RID] = []

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(400.0, true, false, true).timeout.connect(func():
		check(false, "Karte nach 400 s nicht bereit")
		_finish())

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	while m == null:
		await get_tree().process_frame
		m = Game.current_mission()
	while not m.nav_ready:
		await get_tree().create_timer(0.1).timeout
	await get_tree().physics_frame
	await get_tree().physics_frame
	var doors := _doors()
	check(doors.size() >= 20, "Türen gefunden: %d" % doors.size())
	for d in doors:
		_excl.append_array(_rids(d.node))
	var res: Array = []
	for d in doors:
		var r := _check_door(d)
		res.append(r)
		check(r.ok, "Tür %s bei %s in Öffnung (frei=%s zarge=%d/2 sturz=%s flügelabstand=%.2f m)" % [r.name, r.pos, r.free, r.jambs, r.lintel, r.body_d])
		report.append("%s\t%s\t%.2f\tok=%s\tfrei=%s\tzarge=%d\tsturz=%s\tfluegel=%.2f" % [r.name, r.pos, r.yaw, r.ok, r.free, r.jambs, r.lintel, r.body_d])
	# Türartige Meshes außerhalb der Door-Knoten (Modelle, Zusammenfassungen) auflisten
	var rx := RegEx.create_from_string("(?i)(door|dver|dvir|tuer|tür|dv\\d|gate|vrata)")
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		var nm := String(mm.name) + "|" + (String(mm.mesh.resource_name) if mm.mesh else "") + "|" + String(mm.get_parent().name)
		if rx.search(nm) != null:
			report.append("MESH\t%s\t%s\tvis=%s" % [String(mm.get_path()).right(90), mm.global_position, mm.is_visible_in_tree()])
	var png := String(Game.cli.get("door_png", ""))
	if png != "":
		_draw(res, png)
	var f := FileAccess.open("res://test_output/bavaria_doors_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n")
	print("PASS Türen geprüft: %d" % doors.size())
	_finish()

func _finish() -> void:
	print("ERGEBNIS test_bavaria_doors: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

## Alle Türen: Door-Knoten (Häuser) und die Stahltür im Stollen (Drehpunkt an der Zarge)
func _doors() -> Array:
	var out: Array = []
	for n in m.find_children("*", "Door", true, false):
		var d := n as Door
		out.append({"node": d, "name": String(d.get_path()).get_slice("/", -1), "center": d.global_position,
			"basis": d.global_basis, "width": d.width, "height": d.height})
	var bx = m.get("bunker_extras")
	if bx == null:
		for c in m.find_children("*", "", true, false):
			if c.get("door_pivot") is Node3D:
				bx = c
				break
	if bx and bx.get("door_pivot") is Node3D and bx.door_open == false:
		var p: Node3D = bx.door_pivot
		var w := 0.0
		var hh := 1.9
		for cs in p.find_children("*", "CollisionShape3D", true, false):
			if (cs as CollisionShape3D).shape is BoxShape3D:
				w = maxf(w, ((cs as CollisionShape3D).shape as BoxShape3D).size.x)
				hh = ((cs as CollisionShape3D).shape as BoxShape3D).size.y
		var b := p.global_basis
		out.append({"node": p, "name": "Stahltuer", "center": p.global_position + b.x * (w * 0.5), "basis": b, "width": w, "height": hh,
			"lintel_off": 0.08})
	return out

func _rids(n: Node) -> Array[RID]:
	var out: Array[RID] = []
	for c in [n] + n.find_children("*", "CollisionObject3D", true, false):
		if c is CollisionObject3D:
			out.append((c as CollisionObject3D).get_rid())
	return out

func _hit(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = _excl
	return not m.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _check_door(d: Dictionary) -> Dictionary:
	var c: Vector3 = d.center
	var bs: Basis = d.basis
	var x := bs.x.normalized()
	var z := bs.z.normalized()
	var w: float = d.width
	var up := Vector3.UP
	var free := not _hit(c + up * 1.0 + z * 0.7, c + up * 1.0 - z * 0.7) and not _hit(c + up * 0.4 + z * 0.7, c + up * 0.4 - z * 0.7)
	var jambs := 0
	for s in [-1.0, 1.0]:
		var p: Vector3 = c + x * s * (w * 0.5 + 0.3) + up * 1.0
		if _hit(p + z * 0.6, p - z * 0.6):
			jambs += 1
	var top: Vector3 = c + up * (float(d.height) + float(d.get("lintel_off", 0.45)))
	# Flügel (Physik und Darstellung) muss am Türknoten sitzen: Körper liegt um width/2 neben dem Drehpunkt
	var body_ok := true
	var body_d := 0.0
	var wing := c
	if d.node is Door:
		for b in (d.node as Node).find_children("*", "AnimatableBody3D", true, false):
			var ab := b as AnimatableBody3D
			var ps: Transform3D = PhysicsServer3D.body_get_state(ab.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			for mi in ab.find_children("*", "MeshInstance3D", false, false):
				wing = (mi as Node3D).global_position
				body_d = maxf(body_d, Vector2((mi as Node3D).global_position.x - c.x, (mi as Node3D).global_position.z - c.z).length())
			body_d = maxf(body_d, Vector2(ps.origin.x - c.x, ps.origin.z - c.z).length())
		body_ok = body_d <= w * 0.5 + 0.3
	var lintel := _hit(top + z * 0.6, top - z * 0.6) \
		or _hit(c + up * (float(d.height) - 0.1), c + up * (float(d.height) + 0.6))    # Stollen: Decke direkt über dem Flügel
	return {"name": d.name, "pos": Vector3(snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)),
		"yaw": atan2(x.z, x.x), "free": free, "jambs": jambs, "lintel": lintel, "ok": free and jambs == 2 and lintel and body_ok, "body_d": body_d, "wing": wing,
		"c": c, "x": x}

func _draw(res: Array, path: String) -> void:
	var fps: Array = m.get("building_footprints") if m.get("building_footprints") != null else []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for f in fps:
		for p in f:
			lo = lo.min(p)
			hi = hi.max(p)
	for r in res:
		var c: Vector3 = r.c
		lo = lo.min(Vector2(c.x, c.z))
		hi = hi.max(Vector2(c.x, c.z))
	lo -= Vector2(5, 5)
	hi += Vector2(5, 5)
	var sc := 1400.0 / maxf(hi.x - lo.x, hi.y - lo.y)
	var img := Image.create(int((hi.x - lo.x) * sc) + 1, int((hi.y - lo.y) * sc) + 1, false, Image.FORMAT_RGB8)
	img.fill(Color(0.95, 0.95, 0.92))
	var to_px := func(p: Vector2) -> Vector2i: return Vector2i(int((p.x - lo.x) * sc), int((p.y - lo.y) * sc))
	for f in fps:
		var poly: PackedVector2Array = f
		var bl := Vector2(INF, INF)
		var bh := Vector2(-INF, -INF)
		for p in poly:
			bl = bl.min(p)
			bh = bh.max(p)
		for yy in range(int((bl.y - lo.y) * sc), int((bh.y - lo.y) * sc) + 1):
			for xx in range(int((bl.x - lo.x) * sc), int((bh.x - lo.x) * sc) + 1):
				var wp := Vector2(xx / sc + lo.x, yy / sc + lo.y)
				if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height() and Geometry2D.is_point_in_polygon(wp, poly):
					img.set_pixel(xx, yy, Color(0.6, 0.6, 0.6))
	for r in res:
		var c: Vector3 = r.c
		var x: Vector3 = r.x
		var col := Color(0.1, 0.7, 0.1) if r.ok else Color(0.9, 0.1, 0.1)
		var wg: Vector3 = r.wing
		for k in 61:       # Türflügel (sichtbares Mesh) als Strich entlang der Türebene am tatsächlichen Ort
			var t := (k / 60.0 - 0.5) * 1.4
			var p: Vector2i = to_px.call(Vector2(wg.x + x.x * t, wg.z + x.z * t))
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var q := p + Vector2i(ox, oy)
					if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
						img.set_pixelv(q, col)
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	print("PNG ", path)
