extends Mission
## Schießstand (eigener Entwurf [D], Prüfkarte für Waffenabgleich/Balance, kein Original-Leveldesign).
## Ebene Bahn, Schützenlinie z = 0, je Entfernung eine eigene Bahn (x = LANE_X0 + i · LANE_DX) mit einem „Dummy“:
## echte Soldatenfigur (Original-Figur + Original-Trefferzonen humanzones.4ds wie jeder Gegner), ohne KI, unverwundbar –
## jeder Treffer wird nur protokolliert (`hit_log`, Signal `dummy_hit`). Norden = −Z, die Dummys blicken zur Schützenlinie.
## Start: tools\godot.cmd -- --mission=test_range   Test: --autoplay=test_range (tools\run_tests.ps1 -Only test_range)

signal dummy_hit(dummy: Soldier, amount: float, zone: StringName)

## Entfernungen der Bahnen [D]: 1–5 m (3), 5–10 m (7), 10, 25, 50, 100, 200, 300 m
const DISTANCES := [3.0, 7.0, 10.0, 25.0, 50.0, 100.0, 200.0, 300.0]
const LANE_X0 := -28.0
const LANE_DX := 8.0
const LENGTH := 330.0
const DUMMY_FIGURE := "ge03"          # MP-Standarduniform Achse (Net.MP_UNIFORM_MODEL), Original-Figur aus dem Cache

var dummies: Array[Soldier] = []
var hit_log: Array[Dictionary] = []


func lane_x(i: int) -> float:
	return LANE_X0 + LANE_DX * i


## Standplatz des Schützen für Bahn i (Schützenlinie)
func firing_point(i: int) -> Vector3:
	return Vector3(lane_x(i), 0.0, 0.0)


func dummy_point(i: int) -> Vector3:
	return Vector3(lane_x(i), 0.0, -float(DISTANCES[i]))


func _build_world() -> void:
	light_factor = 1.0
	ground_material = 50
	var w := LANE_DX * DISTANCES.size() + 16.0
	var cx := LANE_X0 + LANE_DX * (DISTANCES.size() - 1) * 0.5
	# ebener Boden (Kasten, Oberkante y = 0) von hinter der Schützenlinie bis hinter die 300-m-Bahn
	lb.box(Vector3(cx, -1.0, -LENGTH * 0.5 + 10.0), Vector3(w, 1.0, LENGTH + 20.0), "hedge")
	# Schützenstand: Holzpodest-Kante und Pfosten an jeder Bahn
	lb.box(Vector3(cx, 0.0, 1.6), Vector3(w, 0.05, 0.4), "darkwood", 0.0, false)
	for i in DISTANCES.size():
		var x := lane_x(i)
		lb.box(Vector3(x - LANE_DX * 0.5, 0.0, 1.2), Vector3(0.12, 1.1, 0.12), "wood")
		# Entfernungstafel neben dem Dummy (Höhe = Bahnnummer + 1 Querlatten, ohne Text)
		var dz := -float(DISTANCES[i])
		lb.box(Vector3(x + 1.6, 0.0, dz), Vector3(0.1, 1.6, 0.1), "wood", 0.0, false)
		for k in i + 1:
			lb.box(Vector3(x + 1.6, 0.25 + k * 0.16, dz + 0.06), Vector3(0.5, 0.08, 0.02), "plaster", 0.0, false)
		# Bahngrenze (flacher Sandstreifen, keine Deckung)
		lb.box(Vector3(x + LANE_DX * 0.5, 0.0, dz * 0.5 - 1.0), Vector3(0.3, 0.04, absf(dz) + 2.0), "sandstone", 0.0, false)
	# Kugelfang am Ende
	lb.box(Vector3(cx, 0.0, -LENGTH + 5.0), Vector3(w, 8.0, 2.0), "stone")


func _spawn_actors() -> void:
	spawn_roster(firing_point(0), 0.0, [Vector3(0, 0, 0), Vector3(-2, 0, 3), Vector3(2, 0, 3), Vector3(0, 0, 6)])
	var tpl: Node3D = OrigWeapons._load(OrigLevel.cache_root() + "/characters/%s.glb" % DUMMY_FIGURE)
	for i in DISTANCES.size():
		var d := spawn_soldier(dummy_point(i), PI, Soldier.TEAM_AXIS, "Dummy %.0f m" % DISTANCES[i], ["", "", ""],
			enemy_uniform, "cap", "dummy_%d" % i)
		d.set_meta("orig_items", [])        # kein Helm: Kopfschaden ohne Helmzufall (Helmregel eigener Fall)
		d.set_meta("range_dummy", true)
		d.max_health = 1.0e9
		d.health = d.max_health
		d.get_node("Perception").set_physics_process(false)
		if tpl:
			d.model.attach_orig(tpl.duplicate())
		# keine Trefferreaktion (Clip würde die Zonen zwischen zwei Schüssen verschieben)
		if d.model and d.damaged.is_connected(d.model._on_damaged):
			d.damaged.disconnect(d.model._on_damaged)
		d.damaged.connect(_on_dummy_damaged.bind(d))
		dummies.append(d)


func _on_dummy_damaged(amount: float, zone: StringName, d: Soldier) -> void:
	hit_log.append({"dummy": String(d.persistent_id), "dist": absf(d.global_position.z), "zone": String(zone), "damage": amount,
		"t": Time.get_ticks_msec()})
	d.health = d.max_health      # unverwundbar: Schaden nur protokolliert
	dummy_hit.emit(d, amount, zone)


func _physics_process(_dt: float) -> void:
	for i in dummies.size():         # Dummys stehen fest auf ihrem Platz (keine KI, kein Wegrutschen)
		var d := dummies[i]
		if not is_instance_valid(d):
			continue
		d.move_input = Vector3.ZERO
		d.velocity = Vector3.ZERO
		d.trigger = false
		var p := dummy_point(i)
		d.global_position.x = p.x
		d.global_position.z = p.z
