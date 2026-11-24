extends RefCounted
## Fahrzeuge der Burgkarte (0.12.2): in Team-DM und Eroberung an der Basis jeder Seite, nahe ihrem ersten Spawnpunkt
## (TDM: erster Start der Seite, Eroberung: erster Platz der Startzone der Seite). Alliierte: Jeep + Halbkette M3,
## Achse: Kübelwagen + Sd.Kfz. 251. Originalmodelle, Schadensmodelle und Fahrkennwerte aus dem orig_cache (wie
## OrigMission._spawn_orig_car); ohne Cache-Modell der Platzhalter-Kübelwagen. DM ohne Fahrzeuge.
## Platzwahl deterministisch (gleiche Geometrie auf allen Rechnern → gleiche Knotenpfade für den Netzabgleich):
## Ringe 6–38 m um den Basispunkt, Fläche frei (Kiste Ebene 1/5), eben, in der Spielfläche, ≥ 4 m von Spawnplätzen.

## [Name, Modell, Ordner mit Modell + Schadensmodell]
const KINDS := {
	0: [["Jeep", "la_jeepuvj", "normandy3_mp"], ["Halbkette M3", "la_halftruck", "czech6_mp_zone"]],
	1: [["Kübelwagen", "la_kubelev", "czech5"], ["Sd.Kfz. 251", "la_hakl_ev", "alps1"]],
}
const FOOT := Vector3(2.6, 2.0, 6.2)      ## Prüfkiste (Breite, Höhe, Länge), Halbkette ≈ 2,1 × 5,8 m


static func wanted(m: Node) -> bool:
	return m.play_mode == Net.Mode.TEAM_DEATHMATCH or m.play_mode == Net.Mode.OCCUPATION


## Basispunkt der Seite (Vector3, INF = keiner)
static func base_point(m: Node, team: int) -> Vector3:
	if m.occupation():
		for z in m.all_zones():
			if int(z.owner) == team and not (z.slots as Array).is_empty():
				return z.slots[0].pos
		return Vector3.INF
	for s in m.mp_spawns():
		if int(s.team) == team:
			return s.pos
	return Vector3.INF


static func place(m: Node) -> Array:
	var out: Array = []
	if not wanted(m):
		return out
	var spawns: Array = []
	for s in m.mp_spawns():
		spawns.append(s.pos)
	for z in m.all_zones():
		for sl in z.slots:
			spawns.append(sl.pos)
	var taken: Array = []
	for team in [0, 1]:
		var base := base_point(m, team)
		if not base.is_finite():
			continue
		var i := 0
		for k in KINDS[team]:
			var spot := _find_spot(m, base, spawns, taken)
			if spot.is_empty():
				print("CASTLE_VEHICLES: kein Platz für %s an der Basis %d" % [k[0], team])
				continue
			taken.append(spot.pos)
			var v := _spawn(m, "castle_veh_%d_%d" % [team, i], k, spot.pos, spot.yaw)
			out.append(v)
			i += 1
	print("CASTLE_VEHICLES: %d Fahrzeuge %s" % [out.size(), str(out.map(func(v): return "%s %s" % [v.vehicle_name, v.global_position.snapped(Vector3.ONE * 0.1)]))])
	return out


static func _find_spot(m: Node, base: Vector3, spawns: Array, taken: Array) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = FOOT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1 | LevelBuilder.FENCE_LAYER
	var r = m.get("real")
	for rad in [6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 21.0, 24.0, 27.0, 30.0, 34.0, 38.0]:
		var n := int(ceil(TAU * float(rad) / 2.5))
		for j in n:
			var ang := TAU * j / n
			var p2: Vector2 = Vector2(base.x, base.z) + Vector2(cos(ang), sin(ang)) * float(rad)
			if not m.in_play_area(Vector3(p2.x, 0, p2.y)):
				continue
			if r != null and (r.in_building(p2, 2.0) or r.boundary_dist(p2) < 5.0):
				continue
			var pos := _ground(space, m, p2, base.y)
			if not pos.is_finite():
				continue
			var near := false
			for s in spawns:
				near = near or Vector2((s as Vector3).x - p2.x, (s as Vector3).z - p2.y).length() < 4.0
			for t in taken:
				near = near or Vector2((t as Vector3).x - p2.x, (t as Vector3).z - p2.y).length() < 7.0
			if near:
				continue
			# Längsachse quer zum Basispunkt (Front tangential), beide Richtungen probieren
			for yaw in [ang, ang + PI * 0.5]:
				var b := Basis(Vector3.UP, float(yaw))
				if not _flat(space, pos, b):
					continue
				q.transform = Transform3D(b, pos + Vector3.UP * (FOOT.y * 0.5 + 0.35))
				if space.intersect_shape(q, 1).is_empty():
					return {"pos": pos, "yaw": yaw}
	return {}


static func _ground(space: PhysicsDirectSpaceState3D, m: Node, p2: Vector2, ref_y: float) -> Vector3:
	var top := ref_y + 6.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p2.x, top, p2.y), Vector3(p2.x, top - 20.0, p2.y), 1))
	if hit.is_empty() or hit.normal.y < 0.94:
		return Vector3.INF
	return hit.position


## Ecken der Grundfläche höchstens 0,5 m Höhenunterschied
static func _flat(space: PhysicsDirectSpaceState3D, pos: Vector3, b: Basis) -> bool:
	var lo := INF
	var hi := -INF
	for c in [Vector3(-1.1, 0, -2.9), Vector3(1.1, 0, -2.9), Vector3(-1.1, 0, 2.9), Vector3(1.1, 0, 2.9)]:
		var w: Vector3 = pos + b * c
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(w + Vector3.UP * 3.0, w + Vector3.DOWN * 3.0, 1))
		if hit.is_empty():
			return false
		lo = minf(lo, hit.position.y)
		hi = maxf(hi, hit.position.y)
	return hi - lo <= 0.5


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Fahrkennwerte: Eintrag mit passendem Modell, zuerst im Modellordner, sonst in irgendeinem Kartenordner
static func _drive_data(model: String, dir: String) -> Dictionary:
	var root := OrigLevel.cache_root()
	var dirs: Array = [dir]
	var d := DirAccess.open(root)
	if d:
		for sub in d.get_directories():
			if sub != dir:
				dirs.append(sub)
	for sub in dirs:
		var vj = _read_json("%s/%s/vehicles.json" % [root, sub])
		if typeof(vj) != TYPE_DICTIONARY:
			continue
		var vd: Dictionary = vj.get("vehicles", {})
		for k in vd:
			if String((vd[k] as Dictionary).get("model", "")).to_lower() == model:
				return vd[k]
	return {}


static func _spawn(m: Node, pid: String, kind: Array, pos: Vector3, yaw: float) -> Vehicle:
	var v := Vehicle.new()
	v.name = pid
	v.persistent_id = pid
	v.vehicle_name = String(kind[0])
	var model: String = kind[1]
	var dir: String = kind[2]
	var root := OrigLevel.cache_root()
	var mp := "%s/%s/models/%s.glb" % [root, dir, model]
	if FileAccess.file_exists(mp):
		var vis := OrigLevel.parse_glb(mp)
		if vis:
			vis.rotation.y = PI          # LS3D-Modelle blicken nach −Z, VehicleBody3D fährt entlang +Z
			v.custom_visual = vis
			v.drive_model = model
			v.model_path = mp
			var dmp := "%s/%s/models/dm_%s.glb" % [root, dir, model]
			if FileAccess.file_exists(dmp):
				v.dm_path = dmp
			v.drive_data = _drive_data(model, dir)
			v.max_health = 1200.0 if model.contains("hakl") or model.contains("halftruck") else 600.0
	m.dynamic_root.add_child(v)
	v.global_position = pos + Vector3.UP * 0.4
	v.global_rotation.y = yaw
	return v
