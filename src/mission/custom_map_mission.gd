extends Mission
## Standard-Missionsskript eigener Karten. Lädt die Szene aus dem Manifest unter static_root
## (Kollision → Navmesh wird wie bei jeder Karte selbst gebacken) und liest die Spawn-Marker.
## Default mission script for custom maps: instantiates the manifest scene under static_root and reads spawn markers.
##
## Spawn-Konvention / spawn convention (Marker3D oder Node3D, Blickrichtung −Z):
##   Spawn_Allied*  → Alliierte / allied (Einzelspieler-Start = erster davon)
##   Spawn_Axis*    → Achse / axis
##   Spawn*         → sonst abwechselnd / otherwise alternating
## Eigene Missionsskripte erben von dieser Datei (extends "res://src/mission/custom_map_mission.gd") und überschreiben
## z. B. _setup_objectives() oder mp_zones().

var map_scene: Node3D
var _spawn_points: Array = []      ## [{pos, yaw, team}] (Format wie mp_arena; auch Navmesh-Fokus)


func _build_world() -> void:
	light_factor = 1.0
	var path := String(Game.MISSIONS.get(Game.current_mission_id, {}).get("custom_scene", ""))
	var ps: Resource = load(path) if path != "" and ResourceLoader.exists(path) else null
	if ps is PackedScene:
		var n := (ps as PackedScene).instantiate()
		if n is Node3D:
			map_scene = n
			static_root.add_child(map_scene)
		else:
			push_error("Eigene Karte: Wurzel der Szene ist kein Node3D / scene root is not a Node3D: " + path)
			if n:
				n.free()
	else:
		push_error("Eigene Karte: Szene nicht ladbar / scene not loadable: " + path)
	if map_scene == null:
		lb.box(Vector3(0, -1, 0), Vector3(40, 1, 40), "hedge")     # Notboden, damit nichts fällt
	_collect_spawns()


func _collect_spawns() -> void:
	_spawn_points.clear()
	if map_scene == null:
		_spawn_points.append({"pos": Vector3(0, 0.5, 0), "yaw": 0.0, "team": Soldier.TEAM_ALLIED})
		return
	var nodes := map_scene.find_children("Spawn*", "Node3D", true, false)
	nodes.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var alt := 0
	for n in nodes:
		var nm := String(n.name).to_lower()
		var team := Soldier.TEAM_ALLIED
		if nm.begins_with("spawn_axis"):
			team = Soldier.TEAM_AXIS
		elif not nm.begins_with("spawn_allied"):
			team = Soldier.TEAM_ALLIED if alt % 2 == 0 else Soldier.TEAM_AXIS
			alt += 1
		var t: Transform3D = (n as Node3D).global_transform
		_spawn_points.append({"pos": t.origin + Vector3.UP * 0.3, "yaw": t.basis.get_euler().y, "team": team})
	if _spawn_points.is_empty():
		push_warning("Eigene Karte ohne Spawn-Marker / custom map without spawn markers")
		_spawn_points.append({"pos": Vector3(0, 0.5, 0), "yaw": 0.0, "team": Soldier.TEAM_ALLIED})


func _spawn_actors() -> void:
	if Net.is_online:
		return                                       # Mehrspieler: Figuren kommen vom Server (mp_spawns)
	var sp: Dictionary = _spawn_points[0]
	for p in _spawn_points:
		if int(p["team"]) == Soldier.TEAM_ALLIED:
			sp = p
			break
	spawn_roster(sp["pos"], float(sp["yaw"]), [Vector3(0, 0, 0), Vector3(-2, 0, 2), Vector3(2, 0, 2), Vector3(0, 0, 4)])


func mp_spawns() -> Array:
	return _spawn_points
