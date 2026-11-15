extends Node
## Mehrspieler-Client zu test_fall_damage --phase=mp (zweiter Prozess): beitreten, eigene Figur 6 m über dem Boden
## fallen lassen (Server zieht den Schaden ab, Gesundheit kommt zurück), danach tödlicher Sturz (Kill-Feed „fall“).
## Ergebnisse nach user://fall_damage_client_result.txt.

const RESULT := "user://fall_damage_client_result.txt"
var lines: PackedStringArray = []


func check(c: bool, name: String, detail := "") -> void:
	lines.append(("PASS  " if c else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(_done)
	_run.call_deferred()


func _wait_chat(text: String, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(limit * 1000.0):
		if Net.chat_log.any(func(e): return String(e["text"]) == text):
			return true
		await get_tree().create_timer(0.1).timeout
	return false


## Figur h m über den Boden unter ihr setzen und Landung abwarten
func _drop(me: Soldier, h: float) -> void:
	var at := me.global_position
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 30.0, 1, me.exclude_rids())
	var hit := me.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		at = hit.position
	me.last_fall = {}
	me.global_position = at + Vector3.UP * h
	me.velocity = Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and me.last_fall.is_empty() and me.alive:
		await get_tree().physics_frame


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	Net.local_name = "Gast"
	Net.join("127.0.0.1", 11046, "")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400000:
		await get_tree().create_timer(0.2).timeout
		if Game.current_mission() and Net._soldiers.has(Net.my_id()) and Net._soldiers.has(1):
			break
	var me: Soldier = Net._soldiers.get(Net.my_id())
	check(is_instance_valid(me) and me.alive, "Eigener Soldat vom Server erzeugt")
	if not is_instance_valid(me):
		_done()
		return
	await get_tree().create_timer(1.0).timeout
	Net.send_chat("bereit")
	check(await _wait_chat("los1", 120.0), "Startzeichen Sturz 1")
	await get_tree().create_timer(0.5).timeout
	var hp0 := me.health
	await _drop(me, 6.0)
	check(not me.last_fall.is_empty() and absf(float(me.last_fall.get("damage", 0.0)) - 72.0) < 6.0,
		"Client erkennt Landung aus 6 m (≈ 72 LP)", str(me.last_fall))
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000 and me.health > hp0 - 1.0:
		await get_tree().create_timer(0.1).timeout
	check(me.health < hp0 - 50.0 and me.alive, "Gesundheit vom Server gesenkt (Server entscheidet)",
		"%.1f → %.1f" % [hp0, me.health])
	Net.send_chat("gelandet1")
	check(await _wait_chat("los2", 60.0), "Startzeichen Sturz 2")
	await get_tree().create_timer(1.0).timeout
	await _drop(me, 14.0)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and (is_instance_valid(me) and me.alive):
		await get_tree().create_timer(0.1).timeout
	check(not (is_instance_valid(me) and me.alive), "Tödlicher Sturz: eigener Soldat tot")
	var mid := Net.my_id()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000 and not _feed_has(mid):
		await get_tree().create_timer(0.2).timeout
	check(_feed_has(mid), "Kill-Feed beim Client: Ursache fall")
	_done()


func _feed_has(victim: int) -> bool:
	for e in Net.kill_feed:
		if int(e.get("victim", 0)) == victim and String(e.get("cause", "")) == "fall":
			return true
	return false


func _done() -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	Net.leave(false)
	get_tree().quit(0)
