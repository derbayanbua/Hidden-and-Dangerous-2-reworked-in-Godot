extends "res://tests/test_gameplay.gd"
## SP-KI Laufwege (docs/status/sp_ki_original.md): Gegnerwege ueber das Fussswegenetz (check2.bin Abschnitt 1) statt nur
## Navmesh, Navmesh-Rueckfall, Schalter --ki_wege=0. Trupp wird jedes Bild auf volle Gesundheit gesetzt (unverwundbar).
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_sp_ki_wege


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func():
		check(false, "Zeitueberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func _heal_squad(m) -> void:
	if m == null or m.squad == null:
		return
	for s in m.squad.members:
		if is_instance_valid(s) and s.alive:
			s.health = s.max_health


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var mm := mission()
		if mm and mm.squad and mm.squad.leader() and mm.get("runtime") and mm.get("nav_ready"):
			break
		await get_tree().process_frame
	await frames(5)
	var m := mission()
	var rt = m.get("runtime") if m else null
	check(rt != null, "a1 mit Skriptlaufzeit geladen")
	if rt == null:
		_finish()
		return
	# Gegner mit EnemyBrain suchen
	var b: EnemyBrain = null
	for node in get_tree().get_nodes_in_group("soldiers"):
		var s := node as Soldier
		if s and s.alive and s.team != m.squad.leader().team:
			var eb := s.get_node_or_null("EnemyBrain") as EnemyBrain
			if eb and eb.runtime != null and not eb.script_control and not eb.suspended:
				b = eb
				break
	check(b != null, "Gegner mit Original-KI gefunden")
	if b == null:
		_finish()
		return
	check(EnemyBrain.walk_route_switch(), "Schalter --ki_wege standardmaessig an")
	check(b.walk_route_enabled(), "Laufwege fuer Originalmission offline aktiv")
	var net := OrigCombatFsm.walk_net(b)
	check(net != null and net.base_pos.size() > 1000, "Fussswegenetz ohne Skriptkante geladen",
		"%d Knoten" % (net.base_pos.size() if net else 0))
	if net == null:
		_finish()
		return
	# Knotenpaar 40-120 m auseinander, verbunden: Planung liefert Knotenlagen
	var start := b.soldier.global_position
	var sn := net.nearest_node(start, EnemyBrain.WALK_SNAP)
	var plan: Array = []
	var goal := Vector3.INF
	if sn >= 0:
		for k in range(0, net.base_pos.size(), 7):
			var p: Vector3 = net.base_pos[k]
			var d := Vector2(p.x - start.x, p.z - start.z).length()
			if d < 40.0 or d > 120.0:
				continue
			plan = b.plan_walk_route(start, p)
			if not plan.is_empty():
				goal = p
				break
	check(sn < 0 or not plan.is_empty(), "Route im Netz geplant", "%d Knoten" % plan.size())
	var all_nodes := true
	for q in plan:
		if net.nearest_node(q, 0.01) < 0:
			all_nodes = false
	check(all_nodes, "Routenpunkte sind Netzknoten")
	# Rueckfall: kurzes Ziel (< 12 m) und Ziel ohne Knoten in 5 m -> Navmesh
	check(b.plan_walk_route(start, start + Vector3(5, 0, 0)).is_empty(), "Kurzes Ziel: Navmesh-Rueckfall")
	check(b.plan_walk_route(start, start + Vector3(0, 0, 5000)).is_empty(), "Ziel ohne Knoten: Navmesh-Rueckfall")
	if goal.is_finite():
		b.set_state(EnemyBrain.State.GUARD)
		b.home_pos = goal
		var r0 := b.walk_routes
		b.move_to(goal, Soldier.MoveMode.RUN)
		check(b.walk_routes == r0 + 1 and b.walk_route_active(), "move_to startet Knotenfolge")
		var passed0 := b.walk_nodes_passed
		var t := 0.0
		while t < 40.0 and b.walk_nodes_passed == passed0:
			_heal_squad(m)
			await frames(6)
			t += 0.1
		check(b.walk_nodes_passed > passed0, "Gegner laeuft Netzknoten ab", "%.1f s, %s, Ziel %s, Weg %.1f m, susp %s, q %d" % [
			t, b.state_name(), str(b.has_move_target()), b.soldier.global_position.distance_to(start), str(b.suspended),
			b._walk_queue.size()])
		# Wiederholter Aufruf mit gleichem Ziel behaelt die Folge
		if b.walk_route_active():
			var q0: int = b._walk_queue.size()
			b.move_to(goal, Soldier.MoveMode.RUN)
			check(b._walk_queue.size() == q0, "Gleiches Ziel: Knotenfolge bleibt")
	# Schalter aus
	Game.cli["ki_wege"] = "0"
	check(not b.walk_route_enabled(), "--ki_wege=0 schaltet ab")
	b.move_to(start, Soldier.MoveMode.WALK)
	check(not b.walk_route_active(), "Ohne Schalter: reines Navmesh")
	Game.cli.erase("ki_wege")
	_finish()
