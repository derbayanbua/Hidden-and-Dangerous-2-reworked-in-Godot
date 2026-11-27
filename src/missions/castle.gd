extends Mission
## Testkarte „Castle“. Burganlage aus den Kartendaten assets/maps/castle/data/ (castle_real.gd): DM/TDM in Hauptburg +
## zwei Vorhöfen (F, E, D, innere Grenze an C|D), Eroberung über die ganze Burg mit sechs Zonen A–F (FRONTLINE),
## KI-Hinweise (castle_bot_hints.gd). Ohne Kartendaten Platzhalter aus assets/maps/castle/layout.json: Grenzpolygon,
## welliges Gelände, Blöcke, 16 Starts, 5 Zonen. Test map "Castle"; no original game data needed.
## Direktstart: tools\godot.cmd -- --mission=castle (DM-Fläche) bzw. --mission=castle_occupation (ganze Burg).

const LayoutScript := preload("res://src/maps/castle/castle_layout.gd")
const LAYOUT := "res://assets/maps/castle/layout.json"

var layout: Dictionary = {}
var boundary := PackedVector2Array()
var block_footprints: Array[PackedVector2Array] = []
var asset_report := {"missing": []}
var frontline := false
var _zones: Array = []
## Spielart dieses Registereintrags (castle = DM, castle_tdm = TDM, castle_occupation = Eroberung; fester Stil je
## Eintrag wie bei den Originalkarten). Echte Burg: DM/TDM nur Höfe F, E, D (innere Grenze an C|D), Eroberung ganze Burg.
var play_mode := Net.Mode.DEATHMATCH


static func registry_mode() -> int:
	var e: Dictionary = Game.MISSIONS.get(Game.current_mission_id, {})
	if e.has("mp_mode"):
		return int(e.mp_mode)
	return Net.mode() if Net.is_online else Net.Mode.DEATHMATCH


func occupation() -> bool:
	return play_mode == Net.Mode.OCCUPATION

# Flaggenwechsel in Net._zones nutzen denselben find_frame-Vertrag wie Originalkarten (wie Bavaria).
class ZoneFrames:
	extends RefCounted
	var frames := {}
	func find_frame(id: String) -> Node3D:
		return frames.get(id)
var runtime := ZoneFrames.new()


## Burganlage aus den Kartendaten (castle_real.gd `data_dir()`); ohne sie bleibt das Platzhalter-Layout.
## Castle from the map data when present, else the placeholder layout.
const RealScript := preload("res://src/maps/castle/castle_real.gd")
const Backdrop := preload("res://src/maps/castle/castle_backdrop.gd")
var real = null      ## castle_real.gd-Instanz oder null (Platzhalter)
## Flak/MG 42 auf den Türmen (castle_emplacements.gd, nur echte Burg, alle Spielarten)
const EmplacementsScript := preload("res://src/maps/castle/castle_emplacements.gd")
var emplacements: Array = []


func _build_world() -> void:
	lb.height_scale = 0.0
	lb.size = 300.0
	light_factor = 1.0
	LayoutScript.apply_materials(lb)
	play_mode = registry_mode()
	if RealScript.available() and String(Game.cli.get("castle_real", "1")) != "0":
		real = RealScript.new()
		real.play_mode = play_mode
		layout = real.build(self)
		boundary = LayoutScript.polygon(layout.get("boundary", []))
		# Eroberung: Zonen A–F in Wegreihenfolge, nur Nachbarzonen einnehmbar (Net._attackable)
		frontline = occupation()
		_build_zones()
		real.build_border(self)
		print("CASTLE: echte Burg, %s, %d Gebäude, %d Mauermodule, %d Türme, %d Tore, %d Starts, %d Zonen, Grenze %.0f × %.0f m"
			% [Net.MODE_NAMES[play_mode], real.buildings.count, real.kit.stats.walls, real.kit.stats.towers, real.kit.stats.gates,
			(layout.get("spawns", []) as Array).size(), _zones.size(), bounds().size.x, bounds().size.y])
		Backdrop.build(self)
		_real_environment(env)
		emplacements = EmplacementsScript.build(self)
		return
	layout = LayoutScript.load_layout(LAYOUT)
	boundary = LayoutScript.polygon(layout.get("boundary", []))
	_build_ground()
	_build_blocks()
	_build_zones()
	_build_border()
	print("CASTLE: %d Platzhalter, %d Starts, %d Zonen, Grenze %.0f × %.0f m" % [block_footprints.size(),
		(layout.get("spawns", []) as Array).size(), _zones.size(), bounds().size.x, bounds().size.y])
	Backdrop.build(self)


func bounds() -> Rect2:
	var b := Rect2(boundary[0], Vector2.ZERO)
	for p in boundary:
		b = b.expand(p)
	return b


func inside_map(p: Vector3) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), boundary)


## Spielfläche der aktuellen Spielart (echte Burg im DM/TDM: nur Höfe D, E, F; sonst = inside_map)
func in_play_area(p: Vector3) -> bool:
	if real != null:
		return real.in_play(Vector2(p.x, p.z))
	return inside_map(p)


## Geländehöhe (leicht wellig, Parameter aus layout.terrain)
func ground_y(x: float, z: float) -> float:
	if real != null:
		return real.terrain.height(x, z)
	return LayoutScript.height(layout.get("terrain", {}), x, z)


func ground_point(xz, lift := 0.0) -> Vector3:
	var x := float(xz[0])
	var z := float(xz[1])
	return Vector3(x, ground_y(x, z) + lift, z)


func _build_ground() -> void:
	var t: Dictionary = layout.get("terrain", {})
	var mesh := LayoutScript.ground_mesh(t, bounds().grow(float(t.get("outer_margin", 30.0))))
	var mi := MeshInstance3D.new()
	mi.name = "PlayableGround"
	mi.mesh = mesh
	mi.material_override = lb.mat(String(t.get("material", "grass")))
	static_root.add_child(mi)
	mi.create_trimesh_collision()


func _build_blocks() -> void:
	for b in layout.get("blocks", []):
		var size := Vector3(b.size[0], b.size[2], b.size[1])   # layout: [Breite x, Tiefe z, Höhe]
		var yaw := deg_to_rad(float(b.get("yaw_deg", 0.0)))
		var c := Vector2(float(b.center[0]), float(b.center[1]))
		# Tiefsten Geländepunkt unter dem Grundriss suchen, Block 1 m eingraben (kein Spalt am Hang)
		var corners := PackedVector2Array()
		var base := INF
		for v in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			var q := c + Vector2(v.x * size.x, v.y * size.z).rotated(-yaw)
			corners.append(q)
			base = minf(base, ground_y(q.x, q.y))
		base = minf(base, ground_y(c.x, c.y)) - 1.0
		var node := lb.box(Vector3(c.x, base, c.y), Vector3(size.x, size.y + 1.0, size.z), String(b.get("material", "stone")), yaw)
		node.name = String(b.id)
		node.set_meta("block_kind", String(b.get("kind", "")))
		node.add_to_group("castle_blocks")
		block_footprints.append(corners)
		# Das Gelände läuft durch den massiven Block; Recast sähe darin eine begehbare Insel (Box = nur Hüllflächen).
		# Hindernis schneidet den Grundriss beim Backen aus dem Navmesh.
		var obstacle := NavigationObstacle3D.new()
		obstacle.name = String(b.id) + "_NavCut"
		obstacle.avoidance_enabled = false
		obstacle.affect_navigation_mesh = true
		obstacle.height = size.y + 1.0
		var verts := PackedVector3Array()
		for q in corners:
			verts.append(Vector3(q.x - c.x, 0.0, q.y - c.y))
		obstacle.vertices = verts
		static_root.add_child(obstacle)
		obstacle.position = Vector3(c.x, base, c.y)


## Zonen aus layout.occupation_zones. Platzhalter: Kreis + Spawnplätze per zone_slot_offsets. Echte Burg (castle_real):
## Quader entlang des Hofs ("box" [Breite, Höhe, Länge], "axis" [x, z]), Höhe "y", Spawnplätze "slots" [[x, z] …].
## Markierungen (Mast mit Flaggen je Besitzer, Name, Eckpfosten) nur in der Eroberung; Flaggen über find_frame.
func _build_zones() -> void:
	var offsets: Array = layout.get("zone_slot_offsets", [[-2.5, -2.5], [2.5, -2.5], [-2.5, 2.5], [2.5, 2.5]])
	var occ := occupation()
	for data in layout.get("occupation_zones", []):
		var center := ground_point(data.pos, 0.8)
		if data.has("y"):
			center = Vector3(float(data.pos[0]), float(data.y), float(data.pos[1]))
		var axis := Vector2(float(data.axis[0]), float(data.axis[1])).normalized() if data.has("axis") else Vector2(0, 1)
		# Blick vom Spawnplatz zur Zonenmitte (look_yaw: 0 = Norden, forward = (−sin, 0, −cos))
		var slots: Array = []
		var slot_list: Array = data.get("slots", [])
		if slot_list.is_empty():
			for o in offsets:
				slot_list.append([float(data.pos[0]) + float(o[0]), float(data.pos[1]) + float(o[1])])
		for q in slot_list:
			var to := Vector2(center.x - float(q[0]), center.z - float(q[1]))
			slots.append({"pos": ground_point(q, 0.3), "yaw": atan2(-to.x, -to.y) if to.length() > 0.5 else 0.0})
		var owner := int(data.get("owner", -1))
		var flags := {}
		for side in ["allied", "axis", "neutral"]:
			flags[side] = String(data.id) + "_" + side
		var z := {"name": String(data.id), "text": String(data.name), "shape": "sphere",
			"xf": Transform3D(Basis(), center), "scale": Vector3.ONE, "radius": float(data.get("radius", 12.0)),
			"capture_time": float(data.get("capture_time_s", 15)), "owner": owner, "capturable": true,
			"flags": flags, "slots": slots, "section": String(data.get("section", ""))}
		if data.has("box"):
			var zx := Vector3(axis.x, 0, axis.y)
			z["shape"] = "box"
			z["xf"] = Transform3D(Basis(Vector3.UP.cross(zx).normalized(), Vector3.UP, zx), center)
			z["scale"] = Vector3(float(data.box[0]), float(data.box[1]), float(data.box[2]))
		_zones.append(z)
		if not occ:
			continue
		var pole := ground_point(data.pos)
		if data.has("box"):
			_zone_corners(z)
		else:
			pole += Vector3(-4, 0, 0)
		lb.cylinder(pole, 0.07, 4.2, "darkwood", false, dynamic_root)
		for side in flags:
			var flag := MeshInstance3D.new()
			flag.name = flags[side]
			var quad := QuadMesh.new()
			quad.size = Vector2(1.8, 1.0)
			flag.mesh = quad
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.18, 0.35, 0.7) if side == "allied" else (Color(0.65, 0.17, 0.13) if side == "axis" else Color(0.7, 0.7, 0.62))
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			flag.material_override = mat
			dynamic_root.add_child(flag)
			flag.position = pole + Vector3(0.9, 3.5, 0)
			flag.visible = side == ("allied" if owner == 0 else ("axis" if owner == 1 else "neutral"))
			runtime.frames[flags[side]] = flag
		var label := Label3D.new()
		label.text = String(data.name)
		label.position = pole + Vector3(0, 5, 0)
		label.font_size = 64
		label.pixel_size = 0.015
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dynamic_root.add_child(label)


## Eckmarken eines Zonenquaders: Pfosten mit weißer Kappe an den Ecken und je Längsseite ein Zwischenpfosten
## (nicht in Gebäuden), ohne Kollision
func _zone_corners(z: Dictionary) -> void:
	var xf: Transform3D = z.xf
	var sc: Vector3 = z.scale
	var pts: Array = []
	for u in [-0.5, 0.5]:
		for v in [-0.5, 0.0, 0.5]:
			pts.append(Vector2(u * sc.x, v * sc.z))
	for q in pts:
		var w: Vector3 = xf * Vector3(q.x, 0, q.y)
		if real != null and real.in_building(Vector2(w.x, w.z), 0.3):
			continue
		var g := ground_point([w.x, w.z])
		lb.cylinder(g - Vector3(0, 0.2, 0), 0.09, 1.6, "darkwood", false, dynamic_root).add_to_group("castle_zone_marks")
		lb.cylinder(g + Vector3(0, 1.4, 0), 0.11, 0.25, "plaster", false, dynamic_root)


## Harte Kartengrenze: Bewegungsbarriere Ebene 5 (Sicht/Schüsse frei) + sichtbare Pfähle, wie Bavaria.
func _build_border() -> void:
	for i in boundary.size():
		var a := boundary[i]
		var b := boundary[(i + 1) % boundary.size()]
		var dir := b - a
		var mid := (a + b) * 0.5
		var body := StaticBody3D.new()
		body.name = "MapBoundary_%d" % i
		body.collision_layer = LevelBuilder.FENCE_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(dir.length() + 1.0, 80.0, 0.35)
		cs.shape = box
		body.add_child(cs)
		dynamic_root.add_child(body)
		body.position = Vector3(mid.x, 35.0, mid.y)
		body.rotation.y = atan2(-dir.y, dir.x)
		body.add_to_group("castle_boundaries")
		var steps := maxi(int(dir.length() / 8.0), 1)
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			lb.box(Vector3(p.x, ground_y(p.x, p.y) - 0.3, p.y), Vector3(0.18, 1.8, 0.18), "darkwood", 0.0, false, dynamic_root)


func _spawn_actors() -> void:
	if Net.is_online:
		# Bots erst nach dem ersten Navmesh-Abgleich bewegen (wie Bavaria)
		actors_root.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		var start := ground_point(layout.spawns[0].pos, 0.3)
		spawn_roster(start, 0.0, [Vector3.ZERO, Vector3(2, 0, 0), Vector3(0, 0, 2), Vector3(2, 0, 2)])


## Echte Burg: Kulisse reicht bis ~3,8 km → Kamera-far 4 km, Nebel nur leicht (Horizonthügel sichtbar).
const VIEW_FAR := 4000.0


func _real_environment(e: Environment) -> void:
	if e == null:
		return
	e.fog_density = 0.00012
	e.fog_aerial_perspective = 0.25
	e.fog_sky_affect = 0.3
	e.volumetric_fog_density = 0.0


func _raise_view_far() -> void:
	var cur: Dictionary = ViewDistanceScript.current
	if float(cur.get("far", ViewDistanceScript.DEFAULT_FAR)) < VIEW_FAR:
		cur["far"] = VIEW_FAR
	view_stats["far"] = ViewDistanceScript.camera_far()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and not cam.has_meta("b041_keep_far") and cam.far < VIEW_FAR:
		cam.far = VIEW_FAR


## Zusätzliche Ausschlussflächen für die Kulisse (keine Häuser/Bäume): Grabenbrücken und Türme der Burg
func backdrop_exclude_polygons() -> Array:
	var out: Array = []
	if real == null:
		return out
	for t in real.kit.towers:
		var p: Vector3 = t.pos
		out.append(PackedVector2Array([Vector2(p.x - 8, p.z - 8), Vector2(p.x + 8, p.z - 8), Vector2(p.x + 8, p.z + 8), Vector2(p.x - 8, p.z + 8)]))
	for br in real.bridges:
		var a: Vector3 = br.a
		var b: Vector3 = br.b
		var d := Vector2(b.x - a.x, b.z - a.z).normalized()
		var s := Vector2(-d.y, d.x) * 6.0
		out.append(PackedVector2Array([Vector2(a.x, a.z) - s, Vector2(b.x, b.z) - s, Vector2(b.x, b.z) + s, Vector2(a.x, a.z) + s]))
	return out


## Navmesh-Cache: eigener Speicherplatz je Aufbau (Platzhalter/echte Burg × Spielfläche DM/TDM bzw. Eroberung),
## sonst verdrängt ein Wechsel den anderen Stand und das Netz wird neu gebacken (NavCache.map_id)
func nav_cache_variant() -> String:
	return ("real" if real != null else "ph") + ("-occ" if occupation() else "-dm")


## Fahrzeuge (TDM/Eroberung) an den Basen: im ersten Takt, wenn die Physik die Karte kennt (castle_vehicles.gd)
const VehiclesScript := preload("res://src/maps/castle/castle_vehicles.gd")
var vehicles: Array = []
var _vehicles_placed := false


func _on_tick(_delta: float) -> void:
	if real != null:
		_raise_view_far()
	if not _vehicles_placed:
		_vehicles_placed = true
		vehicles = VehiclesScript.place(self)
	if nav_ready and actors_root.process_mode == Node.PROCESS_MODE_DISABLED:
		actors_root.process_mode = Node.PROCESS_MODE_INHERIT
	if nav_ready and real != null:
		if not slots_refined:
			_refine_slots()
		if not Net.is_online or multiplayer.is_server():
			_hint_tick()


func _setup_objectives() -> void:
	pass


## Zonen für Net/HUD/KI: nur in der Eroberung (DM/TDM ohne Zonen; Zonenplätze in A–C lägen sonst außerhalb der
## Spielfläche, z. B. für den Funkgerät-Spawn). all_zones() = alle Zonen unabhängig von der Spielart (Tests, Bilder).
func mp_zones() -> Array:
	return _zones if occupation() else []


func all_zones() -> Array:
	return _zones


func mp_spawns() -> Array:
	var out: Array = []
	for s in layout.get("spawns", []):
		var yaw: float = float(s.yaw) if s.has("yaw") else (-PI * 0.5 if int(s.team) == 0 else PI * 0.5)
		out.append({"pos": ground_point(s.pos, 0.3), "yaw": yaw, "team": int(s.team)})
	return out


## Nach dem Navmesh: Spawnplätze je Zone prüfen und ordnen – auf dem Netz, Soldatenkapsel frei, bevorzugt ohne
## Sichtlinie (Augenhöhe, Ebene 1) zu den Nachbarzonen (Gegner an der Front). Behalten: die besten 6 (mind. 4; zu
## wenige gültige → Liste unverändert). Auf allen Rechnern gleich (gleiche Geometrie).
var slots_refined := false
var slot_stats := {}       ## Zonen-ID → {kept, valid, hidden}


func _refine_slots() -> void:
	slots_refined = true
	var space := get_world_3d().direct_space_state
	var map := get_world_3d().navigation_map
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1 | LevelBuilder.FENCE_LAYER
	for zi in _zones.size():
		var z: Dictionary = _zones[zi]
		var nb: Array = []
		for j in [zi - 1, zi + 1]:
			if j >= 0 and j < _zones.size():
				nb.append((_zones[j].xf as Transform3D).origin)
		var scored: Array = []
		for s in z.slots:
			var p: Vector3 = s.pos
			var np := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(np.x - p.x, np.z - p.z).length() > 0.6 or absf(np.y - (p.y - 0.3)) > 0.8:
				continue
			q.transform = Transform3D(Basis(), p + Vector3.UP * 0.85)
			if not space.intersect_shape(q, 1).is_empty():
				continue
			var hidden := 0
			for c in nb:
				var r := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.3, (c as Vector3) + Vector3.UP * 0.2, 1)
				if not space.intersect_ray(r).is_empty():
					hidden += 1
			scored.append([hidden * 10.0 - p.distance_to((z.xf as Transform3D).origin) * 0.1, s, hidden == nb.size()])
		scored.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		var st := {"valid": scored.size(), "hidden": scored.filter(func(e): return e[2]).size(), "kept": (z.slots as Array).size()}
		if scored.size() >= 4:
			z.slots = scored.slice(0, mini(scored.size(), 6)).map(func(e): return e[1])
			st.kept = (z.slots as Array).size()
			st.hidden = scored.slice(0, mini(scored.size(), 6)).filter(func(e): return e[2]).size()
		slot_stats[z.name] = st
	print("CASTLE_SLOTS ", slot_stats)


## KI-Hinweise (wie Bavaria): nach dem Navmesh schrittweise erzeugt und geprüft (Server bzw. offline)
const HintsScript := preload("res://src/maps/castle/castle_bot_hints.gd")
var bot_hint_data: RefCounted = null


func _hint_tick() -> void:
	if bot_hint_data == null:
		bot_hint_data = HintsScript.new()
		bot_hint_data.prepare(self)
	if not bot_hint_data.done:
		bot_hint_data.step(self, 4)


func bot_hints(center: Vector3, radius: float) -> Array:
	return bot_hint_data.near(center, radius) if bot_hint_data != null else []


func bot_hint_stance(pos: Vector3) -> int:
	return bot_hint_data.stance_at(pos) if bot_hint_data != null else -1
