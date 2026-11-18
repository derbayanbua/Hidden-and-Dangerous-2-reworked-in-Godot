extends "res://tests/test_commands_orig.gd"
## 0.11.7 [D, Vorgabe Auftraggeber]: Startzustand der KI-Kameraden in einer Einzelspieler-Originalmission
## (docs/status/b0117_squad_start.md): HALTEN + FEUER HALTEN, Haltung wie der Anführer. Ohne Befehl bleiben sie stehen
## und schießen auch bei Feindsicht und unter Beschuss nicht; erst ein Befehl (hier „Feuer frei“, Taste K) gibt das Feuer frei.
## Schalter zum alten Stand (B-047: Halten + Feuer frei): --squad_start=legacy (hier ohne Neustart über apply_start_state).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_squad_start


func _mates(sq: SquadManager) -> Array[Soldier]:
	var r: Array[Soldier] = []
	for s in sq.alive_members():
		if s != sq.leader():
			r.append(s)
	return r


func _run() -> void:
	for i in 1200:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen (%s)" % Game.current_mission_id)
	if m == null:
		_finish()
		return
	var sq := m.squad
	var mates := _mates(sq)
	# Zustand direkt nach dem Missionsaufbau
	var ok0 := mates.size() >= 1
	var info := []
	for s in mates:
		var b := sq.brain_of(s)
		info.append("%s o%d r%d st%d a%s" % [s.soldier_name, b.order, b.roe, b.stance_override, b.awaiting_order])
		ok0 = ok0 and b.order == SquadBrain.Order.HOLD and b.roe == SquadBrain.ROE.HOLD_FIRE and b.awaiting_order \
			and b.stance_override == -1 and not b.quiet and not b.quiet_fire
	check(ok0, "Startzustand: Halten, Feuer halten (ohne Befehl), Haltung wie Anführer", ", ".join(info))
	check(not SquadManager.start_legacy(), "Schalter alt (squad_start=legacy) ist aus")
	# Unverwundbarkeit für den Lauf
	for s in sq.members:
		s.max_health = 100000.0
		s.health = s.max_health
	for i in 3000:
		if m.nav_ready:
			break
		await frames(1)
	# Zwischensequenz überspringen (wie test_commands_orig)
	for i in 600:
		var rt0 = m.get("runtime")
		if (rt0 and bool(rt0.get("in_cutscene"))) or m.elapsed > 12.0:
			break
		await frames(1)
	await seconds(1.5)
	for i in 60:
		var rt = m.get("runtime")
		if m.controller.input_enabled and not (rt and bool(rt.get("in_cutscene"))):
			break
		await key(KEY_SPACE)
		await seconds(0.5)
	check(m.controller.input_enabled, "Steuerung frei")
	var calm := 0.0
	for i in 120:
		var ok := true
		for s in sq.members:
			ok = ok and s.is_on_floor() and absf(s.velocity.y) < 0.5
		calm = calm + 0.5 if ok else 0.0
		if calm >= 3.0:
			break
		await seconds(0.5)
	for e in m.enemies:
		var eb = e.get_node_or_null("EnemyBrain")
		if eb:
			eb.enabled = false
		e.set_physics_process(false)
		var per := e.get_node_or_null("Perception")
		if per:
			per.set_physics_process(false)
	for s in sq.members:
		s.health = s.max_health
	var lead := sq.leader()
	mates = _mates(sq)
	var still := true
	for s in mates:
		still = still and sq.brain_of(s).order == SquadBrain.Order.HOLD and sq.brain_of(s).awaiting_order
	check(still, "Nach Intro/Landung weiter Halten ohne Befehl (kein Skript überschreibt)")
	# --- Ohne Befehl: Anführer läuft weg, Kameraden bleiben stehen ---
	lead.global_position = mates[0].global_position + Vector3(2.0, 0.5, 0.0)
	lead.velocity = Vector3.ZERO
	await seconds(1.0)
	var p0 := {}
	for s in mates:
		p0[s] = s.global_position
	await walk("move_forward", 6.0)
	await seconds(2.0)
	var stay := true
	info = []
	for s in mates:
		info.append("%s %.1f m" % [s.soldier_name, moved(p0, s)])
		stay = stay and moved(p0, s) < 2.0
	check(stay, "Ohne Befehl: Kameraden bleiben stehen", ", ".join(info))
	# --- Ohne Befehl: Gegner vor einem Kameraden, Kamerad unter Beschuss → kein Feuer ---
	var shooter: Soldier = mates[0]
	var foe: Soldier = null
	for e in m.enemies:
		if e.alive:
			foe = e
			break
	check(foe != null, "Gegner vorhanden")
	if foe == null:
		_finish()
		return
	var fwd := shooter.forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	foe.global_position = shooter.global_position + fwd * 10.0 + Vector3.UP * 0.1
	foe.velocity = Vector3.ZERO
	var hp0 := foe.health
	var shots0 := {}
	for s in mates:
		shots0[s] = s.last_shot_time
	var sb := sq.brain_of(shooter)
	var seen := false
	var t := 0.0
	while t < 8.0:
		sb._under_fire = 4.0               # Beschuss: wie Soldier.damaged → _under_fire
		await seconds(0.5)
		t += 0.5
		seen = seen or sb.perception.best_target() == foe
	var quiet_ok := foe.health >= hp0 and foe.alive
	for s in mates:
		quiet_ok = quiet_ok and s.last_shot_time == shots0[s]
	check(seen and quiet_ok, "Ohne Befehl: kein Feuer trotz Feindsicht und Beschuss",
		"gesehen %s, Gegner %.0f→%.0f" % [seen, hp0, foe.health])
	check(not sb._may_fire(lead), "Feuerregel sperrt ohne Befehl auch das Selbstschutzfeuer")
	# --- Befehl „Feuer frei“ (Taste K) → Kamerad feuert ---
	await tap("order_roe")
	check(sb.roe == SquadBrain.ROE.FIRE_AT_WILL and not sb.awaiting_order, "Befehl Feuer frei hebt die Sperre auf")
	for s in mates:
		shots0[s] = s.last_shot_time
	var fired := false
	t = 0.0
	while t < 12.0 and not fired:
		await seconds(0.5)
		t += 0.5
		for s in mates:
			fired = fired or s.last_shot_time != shots0[s]
		fired = fired or foe.health < hp0 or not foe.alive
	check(fired, "Nach Befehl Feuer frei: Kamerad eröffnet das Feuer", "%.1f s" % t)
	# --- Bewegungsbefehl hebt die Sperre ebenfalls auf ---
	sq.apply_start_state()
	await tap("order_follow")
	var freed := true
	for s in mates:
		freed = freed and not sq.brain_of(s).awaiting_order and sq.brain_of(s).order == SquadBrain.Order.FOLLOW
	check(freed, "Befehl Folgen hebt die Sperre auf (Feuer halten bleibt Feuerregel)")
	# --- Schalter zum alten Stand ---
	Game.cli["squad_start"] = "legacy"
	for s in mates:
		sq.brain_of(s).set_order(SquadBrain.Order.HOLD)
		sq.brain_of(s).roe = SquadBrain.ROE.FIRE_AT_WILL
	sq.apply_start_state()
	var kept := true
	for s in mates:
		kept = kept and sq.brain_of(s).roe == SquadBrain.ROE.FIRE_AT_WILL and not sq.brain_of(s).awaiting_order
	check(SquadManager.start_legacy() and kept, "Schalter squad_start=legacy: alter Stand (Halten + Feuer frei) bleibt")
	Game.cli.erase("squad_start")
	_finish()
