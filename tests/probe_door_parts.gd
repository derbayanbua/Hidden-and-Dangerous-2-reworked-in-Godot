extends Node
## Sonde Türteile: listet je Originaltür Frame, Kinder und Meshes in der Nähe (nicht unter dem Frame), sowie alle Meshes
## im Umkreis von --at=x,y,z (Radius --r=3).
##   tools\godot.cmd --headless -- --autoplay=probe_door_parts --maps=mp_arctic2_mp --at=-1.92,-8.71,-60.48

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _run() -> void:
	var map := String(Game.cli.get("maps", "mp_arctic2_mp"))
	Net.host({"name": "Probe", "map": map, "mode": Net.Mode.TEAM_DEATHMATCH, "port": Net.PORT + 63, "max_players": 2,
		"time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0, "password": "", "allow_vehicles": false})
	await _wait(func():
		var mm = Game.current_mission()
		return mm != null and mm.is_node_ready() and Net._soldiers.has(1), 400.0)
	var m: Mission = Game.current_mission()
	await get_tree().create_timer(1.0).timeout
	var r := float(Game.cli.get("r", "3"))
	for at_s in String(Game.cli.get("at", "")).split(";", false):
		var c := at_s.split(",")
		var at := Vector3(float(c[0]), float(c[1]), float(c[2]))
		print("AT ", at)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var me := mi as MeshInstance3D
			if me.mesh == null or not me.is_visible_in_tree():
				continue
			var b := me.global_transform * me.get_aabb()
			if b.grow(r).has_point(at):
				print("  MESH %s size=%s c=%s par=%s" % [me.get_path(), b.size, b.get_center(), me.get_parent().name])
	get_tree().quit(0)
