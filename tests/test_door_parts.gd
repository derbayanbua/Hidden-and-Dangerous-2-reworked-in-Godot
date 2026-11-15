extends "res://tests/test_gameplay.gd"
## Türteile und scene2.bin-Lage-Ergänzungen [D-Fehler ARCTIC2, 0.11.6]:
## (1) Kinder eines Türakteurs laut scene2.bin 0x4020 (lightmaps.json „reparent“, z. B. Türfenster m_okn_d_04 → m_dv_m04)
##     hängen am beweglichen Türframe und drehen beim Öffnen mit.
## (2) Frames mit Lage-Ergänzung (lightmaps.json „frames“) liegen auf der scene2-Weltlage (z. B. Türzarge p4sah16 steht
##     aufrecht in der Öffnung statt quer daneben).
##   tools\godot.cmd --headless -- --autoplay=test_door_parts [--maps=mp_arctic2_mp,…]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(cond.call())


func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _run() -> void:
	var maps := String(Game.cli.get("maps", "mp_arctic2_mp")).split(",", false)
	var port := Net.PORT + 65
	for map in maps:
		Net.host({"name": "DoorParts", "map": map, "mode": Net.Mode.TEAM_DEATHMATCH, "port": port, "max_players": 2,
			"time_limit_min": 0, "score_limit": 0, "warmup_s": 0, "respawn_s": 5, "bots_per_team": 0, "password": "",
			"allow_vehicles": false})
		port += 1
		check(await _wait(func():
			var mm = Game.current_mission()
			return mm != null and mm.is_node_ready() and Net._soldiers.has(1), 600.0), "%s geladen" % map)
		var m: Mission = Game.current_mission()
		await get_tree().create_timer(1.0).timeout
		var orig: OrigLevel = m.get("orig")
		var it: OrigInteractive = m.get("interactive")
		if orig == null or it == null:
			check(false, "%s: Originallevel/Interaktives fehlt" % map)
			continue
		var lm := _read(orig.mission_dir + "/lightmaps.json")
		check(lm.has("frames"), "%s: lightmaps.json mit „frames“ (tools/fmt_lightmaps.py neu ausführen)" % map)
		# (1) Türkinder drehen mit
		var rp: Dictionary = lm.get("reparent", {})
		var n_parts := 0
		for child in rp:
			var d = it.controls.get(String(rp[child]).to_upper())
			if not (d is OrigInteractive.OrigDoor) or d.slide:
				continue
			var c: Node3D = orig.nodes.get(String(child).validate_node_name(), orig.nodes.get(String(child)))
			if c == null:
				continue
			n_parts += 1
			check(d.frame.is_ancestor_of(c), "%s: %s hängt an Tür %s" % [map, child, rp[child]])
			var keep_amount: float = d.amount
			d.amount = 0.0
			d._apply()
			var p0 := OrigInteractive.world_aabb(c).get_center()     # Mitte des Teils (Ursprung kann auf der Angel liegen)
			d.amount = d.open_amount
			d._apply()
			var p1 := OrigInteractive.world_aabb(c).get_center()
			d.amount = keep_amount
			d._apply()
			check(p0.distance_to(p1) > 0.2, "%s: %s bewegt sich mit der Tür (%.2f m)" % [map, child, p0.distance_to(p1)])
		print("TÜRTEILE %s: %d Teile an Drehtüren" % [map, n_parts])
		# (2) Lage-Ergänzungen
		var fr: Dictionary = lm.get("frames", {})
		var n_ok := 0
		for nm in orig.scene2_moved:
			var c: Node3D = orig.nodes.get(nm.validate_node_name(), orig.nodes.get(nm))
			var w: Array = fr[nm].get("world", [0, 0, 0])
			if c and c.global_position.distance_to(Vector3(w[0], w[1], w[2])) < 0.05:
				n_ok += 1
			else:
				check(false, "%s: %s auf scene2-Weltlage" % [map, nm])
		check(n_ok == orig.scene2_moved.size(), "%s: %d Frames aus scene2.bin nachgestellt" % [map, n_ok])
		print("SCENE2 %s: %s" % [map, ", ".join(orig.scene2_moved)])
		if map == "mp_arctic2_mp":
			check(orig.scene2_moved.has("p4sah16"), "ARCTIC2: Türzarge p4sah16 aus scene2.bin gestellt")
			var z: Node3D = orig.nodes.get("p4sah16")
			if z:
				var b := OrigInteractive.world_aabb(z)
				check(b.size.y > 2.0, "ARCTIC2: p4sah16 steht aufrecht (Höhe %.2f m)" % b.size.y)
			check(n_parts >= 3, "ARCTIC2: Türfenster m_okn_d_04/09/10 an ihren Türen (%d)" % n_parts)
		Net.leave(false)
		await get_tree().create_timer(2.0).timeout
	_finish()
