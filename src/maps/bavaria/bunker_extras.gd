extends Node3D
## Bavaria: Technik zum Stollen (Knoten „StollenTechnik“, feste Lage unter der Mission für Knoten-RPCs).
## - Flackernde Stollenlampen: deterministisch aus (Lampennummer, gemeinsamer Uhr); die Uhr gleicht der Server ab → alle
##   sehen dasselbe Flackern. Ohne Schatten (Lampen aus tunnels.gd).
## - Geheimraum: Stahltür mit Zahlenschloss (Benutzen öffnet das Tastenfeld, Code 1235). Server prüft, öffnet für alle.
##   Drinnen ein bemaltes Osterei auf einem Sockel und ein roter Knopf „TACTICAL NUKE… (coming soon)“ → nur „dö-dö“.
## - Ziffern 1, 2, 3, 5 mit Kreide an vier Orten (Reihenfolge I–IV daneben), siehe digit_spots.
## - Schalter am Fuß des Suchturms (Licht an/aus) und Sicherungskasten im MG42-Haus (Turmstrom fällt 60–300 s aus,
##   Dauer würfelt der Server). Während des Ausfalls schaltet der Schalter nichts ein; danach gilt der Schalterzustand.
## Mehrspieler: Benutzen läuft wie jede Weltaktion über Net (Server führt interact aus). Zustände/Effekte schickt dieser
## Knoten per eigener RPC an die angemeldeten Clients (Anmeldung request_state beim Laden). PROTOCOL DH2-LAN-6 bleibt.
## Klänge prozedural erzeugt (keine Dateien).

const Tunnels := preload("res://src/maps/bavaria/tunnels.gd")
const CODE := "1235"
const OUTAGE_MIN := 60.0
const OUTAGE_MAX := 300.0
const FLICKER_HZ := 20.0
const CLOCK_SYNC_S := 5.0
const MIX_RATE := 22050
enum { POWER_SILENT, POWER_SWITCH, POWER_FUSE, POWER_RESTORED }

var mission: Node
var tunnels: RefCounted
var tower: Node3D
var clock := 0.0                     ## gemeinsame Uhr (Flackern), vom Server abgeglichen
var door_open := false
var door_pivot: Node3D
var door_body: AnimatableBody3D
var keypad: Spot
var keypad_led: StandardMaterial3D
var nuke: Spot
var tower_switch: Spot
var fuse_box: Spot
var switch_lever: Node3D
var switch_led: StandardMaterial3D
var egg: Node3D
var digit_spots: Array = []          ## {digit, order, pos, normal, place, label}
var ui: KeypadUI
var wrong_count := 0
var right_count := 0
var nuke_presses := 0
var fuse_trips := 0
var last_outage := 0.0
var sound_log: Array[String] = []
var last_player: AudioStreamPlayer3D
var _sounds := {}
var _peers := {}
var _rng := RandomNumberGenerator.new()
var _flicker_acc := 0.0
var _sync_acc := 0.0
var _yaw_closed := 0.0
var _yaw_open := 0.0

## Benutzbarer Punkt (Benutzen-Taste); Wirkung entscheidet der Knoten
class Spot:
	extends Interactable
	var host
	var kind := ""

	func can_interact(s: Soldier) -> bool:
		return enabled and host.can_use(kind, s)

	func interact(s: Soldier) -> void:
		super.interact(s)
		host.use(kind, s)

# --- Aufbau --------------------------------------------------------------------------------------------------------

func setup(m: Node) -> void:
	mission = m
	tunnels = m.tunnels
	tower = m.searchlight_tower
	name = "StollenTechnik"
	_rng.randomize()
	_make_sounds()
	if tower:
		tower.outage_ended.connect(_on_outage_ended)

func _ready() -> void:
	if tunnels and not tunnels.secret.is_empty():
		_build_secret()
	if tower:
		_build_switch()
	_build_digits()
	if Net.is_online and multiplayer.is_server():
		multiplayer.peer_disconnected.connect(func(id): _peers.erase(id))
	_late_init.call_deferred()

func _late_init() -> void:
	while not mission.nav_ready:
		await get_tree().physics_frame
	_build_fuse_box()
	if Net.is_online and not multiplayer.is_server():
		request_state.rpc_id(1)

func _spot(kind: String, pid: String, prompt_text: String, pos: Vector3) -> Spot:
	var s := Spot.new()
	s.host = self
	s.kind = kind
	s.persistent_id = pid
	s.prompt = prompt_text
	s.name = "Benutzen_" + kind
	add_child(s)
	s.global_position = pos
	return s

func _box_mesh(parent: Node3D, size: Vector3, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	parent.add_child(mi)
	mi.transform = xf
	return mi

func _mat(color: Color, metal := 0.0, rough := 0.8, emit := false) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = color
	mt.metallic = metal
	mt.roughness = rough
	if emit:
		mt.emission_enabled = true
		mt.emission = color
		mt.emission_energy_multiplier = 1.5
	return mt

func _label(parent: Node3D, text: String, size_px: int, color: Color, xf: Transform3D, pixel := 0.0025) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	l.transform = xf
	return l

## Blickt mit der Vorderseite (+Z) in normal
static func _facing(normal: Vector3, pos: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(-normal, Vector3.UP), pos)

func _floor(p: Vector2) -> float:
	return tunnels.floor_at(p)

func _build_secret() -> void:
	var sc: Dictionary = tunnels.secret
	var dl: Vector2 = sc.dir
	var side: Vector2 = sc.side
	var door2: Vector2 = sc.door
	var fy := _floor(door2)
	var h: float = tunnels.ceil_at(door2) - fy - 0.13
	var steel := _mat(Color(0.27, 0.29, 0.27), 0.7, 0.45)
	# Tür: Drehpunkt an der Zarge (Seite −side), Flügel geschlossen entlang +side, offen in den Raum (+dir)
	var hinge := door2 - side * (Tunnels.NECK_W * 0.5)
	door_pivot = Node3D.new()
	door_pivot.name = "Stahltuer"
	add_child(door_pivot)
	_yaw_closed = atan2(-side.y, side.x)
	_yaw_open = _yaw_closed + wrapf(atan2(-dl.y, dl.x) - _yaw_closed, -PI, PI)
	door_pivot.global_position = Vector3(hinge.x, fy, hinge.y)
	door_pivot.rotation.y = _yaw_closed
	door_body = AnimatableBody3D.new()
	door_body.sync_to_physics = false
	door_pivot.add_child(door_body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(Tunnels.NECK_W - 0.02, h, 0.07)
	cs.shape = bs
	cs.position = Vector3(Tunnels.NECK_W * 0.5, h * 0.5, 0)
	door_body.add_child(cs)
	_box_mesh(door_body, Vector3(Tunnels.NECK_W - 0.02, h, 0.07), steel, Transform3D(Basis(), cs.position))
	for yy in [0.35, h * 0.5, h - 0.35]:      # Querriegel
		_box_mesh(door_body, Vector3(Tunnels.NECK_W - 0.12, 0.08, 0.1), steel, Transform3D(Basis(), Vector3(Tunnels.NECK_W * 0.5, yy, 0)))
	_box_mesh(door_body, Vector3(0.05, 0.22, 0.05), _mat(Color(0.15, 0.15, 0.14), 0.8, 0.4),
		Transform3D(Basis(), Vector3(Tunnels.NECK_W - 0.15, 1.05, 0.07)))
	_label(door_body, "ZUTRITT VERBOTEN", 34, Color(0.85, 0.8, 0.65, 0.9), Transform3D(Basis(), Vector3(Tunnels.NECK_W * 0.5, 1.55, 0.056)))
	# Tastenfeld an der Stirnwand neben der Tür
	var kp2: Vector2 = sc.keypad
	var kp := Vector3(kp2.x, _floor(kp2) + 1.35, kp2.y)
	var nrm := Vector3(-dl.x, 0, -dl.y)
	var panel := Node3D.new()
	panel.name = "Zahlenschloss"
	add_child(panel)
	panel.global_transform = _facing(nrm, kp)
	_box_mesh(panel, Vector3(0.13, 0.22, 0.04), _mat(Color(0.12, 0.12, 0.11), 0.6, 0.5), Transform3D())
	_label(panel, "1 2 3\n4 5 6\n7 8 9\nC 0 OK", 15, Color(0.85, 0.85, 0.8), Transform3D(Basis(), Vector3(0, -0.015, 0.021)), 0.0015)
	keypad_led = _mat(Color(0.9, 0.08, 0.05), 0.0, 0.5, true)
	var led := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	led.mesh = sm
	led.material_override = keypad_led
	panel.add_child(led)
	led.position = Vector3(0, 0.1, 0.021)
	keypad = _spot("keypad", "bavaria_bunker_keypad", "Zahlenschloss", kp + nrm * 0.15)
	# Osterei auf dem Sockel, leicht beleuchtet
	var ep: Vector2 = (sc.c as Vector2) + (sc.t as Vector2) * -0.6 + (sc.n as Vector2) * (float(sc.d) * 0.5 - 0.6)
	egg = Node3D.new()
	egg.name = "Osterei"
	add_child(egg)
	egg.global_position = Vector3(ep.x, _floor(ep) + 1.06 + 0.15, ep.y)
	var em := MeshInstance3D.new()
	var es := SphereMesh.new()
	es.radius = 0.105
	es.height = 0.3
	es.radial_segments = 32
	es.rings = 16
	em.mesh = es
	var emat := StandardMaterial3D.new()
	emat.albedo_texture = _egg_texture()
	emat.roughness = 0.35
	em.material_override = emat
	egg.add_child(em)
	egg.rotation.z = 0.12
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.7)
	glow.light_energy = 0.9
	glow.omni_range = 1.8
	glow.shadow_enabled = false
	add_child(glow)
	glow.global_position = egg.global_position + Vector3(0.15, 0.55, 0.1)
	# Roter Knopf auf dem Pult, Schild an der Vorderseite
	var cp: Vector2 = (sc.c as Vector2) + (sc.t as Vector2) * (float(sc.w) * 0.5 - 0.55) + (sc.n as Vector2) * 0.3
	var cy := _floor(cp)
	var t3 := Vector3(sc.t.x, 0, sc.t.y)
	var button := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.085
	cm.bottom_radius = 0.095
	cm.height = 0.06
	button.mesh = cm
	button.material_override = _mat(Color(0.8, 0.05, 0.03), 0.1, 0.35, true)
	add_child(button)
	button.global_position = Vector3(cp.x, cy + 0.98 + 0.03, cp.y)
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.13
	rm.bottom_radius = 0.13
	rm.height = 0.012
	ring.mesh = rm
	ring.material_override = _mat(Color(0.1, 0.1, 0.1))
	add_child(ring)
	ring.global_position = Vector3(cp.x, cy + 0.985, cp.y)
	var front := Vector3(cp.x, cy + 0.6, cp.y) - t3 * 0.31
	var plate := Node3D.new()
	add_child(plate)
	plate.global_transform = _facing(-t3, front)
	_box_mesh(plate, Vector3(0.52, 0.22, 0.01), _mat(Color(0.9, 0.75, 0.1)), Transform3D())
	_label(plate, "TACTICAL NUKE…", 30, Color(0.05, 0.05, 0.05), Transform3D(Basis(), Vector3(0, 0.035, 0.007)), 0.0016)
	_label(plate, "(coming soon)", 24, Color(0.05, 0.05, 0.05), Transform3D(Basis(), Vector3(0, -0.045, 0.007)), 0.0016)
	nuke = _spot("nuke", "bavaria_bunker_nuke", "Knopf drücken", Vector3(cp.x, cy + 1.0, cp.y))

static func _egg_texture() -> ImageTexture:
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	var bands := [Color(0.95, 0.85, 0.3), Color(0.2, 0.55, 0.85), Color(0.9, 0.3, 0.45), Color(0.35, 0.75, 0.35), Color(0.95, 0.6, 0.2)]
	for y in 64:
		for x in 128:
			var zig := int(4.0 * absf(fmod(x / 8.0, 2.0) - 1.0))
			var band := int((y + zig) / 9) % bands.size()
			var c: Color = bands[band]
			var dx := (x % 16) - 8
			var dy := (y % 9) - 4
			if band % 2 == 0 and dx * dx + dy * dy * 3 < 10:
				c = Color(1, 1, 1)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _build_switch() -> void:
	var site: Vector3 = tower.site
	var base := site + Vector3(0.0, 0, 2.15)
	var post := StaticBody3D.new()
	post.name = "Turmschalter"
	add_child(post)
	post.global_position = base
	var pcs := CollisionShape3D.new()
	var pbs := BoxShape3D.new()
	pbs.size = Vector3(0.1, 1.35, 0.1)
	pcs.shape = pbs
	pcs.position.y = 0.675
	post.add_child(pcs)
	var wood := _mat(Color(0.22, 0.16, 0.1))
	_box_mesh(post, Vector3(0.1, 1.35, 0.1), wood, Transform3D(Basis(), Vector3(0, 0.675, 0)))
	var metal := _mat(Color(0.3, 0.33, 0.3), 0.6, 0.5)
	_box_mesh(post, Vector3(0.24, 0.3, 0.12), metal, Transform3D(Basis(), Vector3(0, 1.12, 0.11)))
	# Kabel zum Turmbein
	_box_mesh(post, Vector3(0.025, 0.025, 1.0), _mat(Color(0.05, 0.05, 0.05)), Transform3D(Basis(), Vector3(0, 0.05, -0.5)))
	switch_lever = Node3D.new()
	post.add_child(switch_lever)
	switch_lever.position = Vector3(0.0, 1.12, 0.18)
	_box_mesh(switch_lever, Vector3(0.035, 0.15, 0.035), _mat(Color(0.1, 0.1, 0.1)), Transform3D(Basis(), Vector3(0, 0.07, 0)))
	switch_led = _mat(Color(0.1, 0.9, 0.1), 0.0, 0.5, true)
	var led := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.016
	sm.height = 0.032
	led.mesh = sm
	led.material_override = switch_led
	post.add_child(led)
	led.position = Vector3(0.08, 1.23, 0.175)
	_label(post, "LICHT", 26, Color(0.9, 0.9, 0.85), Transform3D(Basis(), Vector3(0, 1.31, 0.172)), 0.0016)
	tower_switch = _spot("switch", "bavaria_tower_switch", "Turmlicht schalten", base + Vector3(0, 1.12, 0.25))
	_update_switch_visual()

func _update_switch_visual() -> void:
	if switch_lever == null or tower == null:
		return
	switch_lever.rotation.x = -0.55 if tower.switch_on else 0.55
	var c := Color(0.1, 0.9, 0.1) if tower.power_ok() else (Color(0.95, 0.55, 0.05) if tower.switch_on else Color(0.8, 0.08, 0.05))
	switch_led.albedo_color = c
	switch_led.emission = c

## Sicherungskasten an der Innenwand des MG42-Hauses (Wandlage per Strahl, nach dem Laden der Physik)
func _build_fuse_box() -> void:
	var house := mission.static_root.get_node_or_null("woodland_shed") as Node3D
	if house == null:
		return
	var size: Vector2 = house.get_meta("footprint_size", Vector2(6, 4))
	var from := house.to_global(Vector3(-size.x * 0.15, 1.45, 0))
	var to := house.to_global(Vector3(-size.x * 0.15, 1.45, -size.y))
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var pos: Vector3 = house.to_global(Vector3(-size.x * 0.15, 1.45, -size.y * 0.5 + 0.2))
	var nrm: Vector3 = (house.global_transform.basis * Vector3(0, 0, 1)).normalized()
	if not hit.is_empty():
		pos = hit.position
		nrm = Vector3(hit.normal.x, 0, hit.normal.z).normalized()
	var box := Node3D.new()
	box.name = "Sicherungskasten"
	add_child(box)
	box.global_transform = _facing(nrm, pos + nrm * 0.07)
	_box_mesh(box, Vector3(0.34, 0.44, 0.12), _mat(Color(0.32, 0.36, 0.3), 0.5, 0.6), Transform3D())
	_box_mesh(box, Vector3(0.3, 0.4, 0.01), _mat(Color(0.25, 0.28, 0.23), 0.5, 0.6), Transform3D(Basis(), Vector3(0, 0, 0.062)))
	_box_mesh(box, Vector3(0.04, 0.1, 0.03), _mat(Color(0.1, 0.1, 0.1)), Transform3D(Basis(), Vector3(0.1, -0.05, 0.08)))
	_label(box, "STROM", 26, Color(0.95, 0.8, 0.1), Transform3D(Basis(), Vector3(-0.05, 0.08, 0.068)), 0.0016)
	_label(box, "TURM", 22, Color(0.9, 0.9, 0.85), Transform3D(Basis(), Vector3(-0.05, -0.1, 0.068)), 0.0016)
	_box_mesh(box, Vector3(0.025, 1.2, 0.025), _mat(Color(0.05, 0.05, 0.05)), Transform3D(Basis(), Vector3(0, 0.82, 0)))
	fuse_box = _spot("fuse", "bavaria_mg42_fusebox", "Sicherungskasten", pos + nrm * 0.25)

## Kreideziffern: I/IV aus tunnels.gd (Treppengrube, Treppenfuß), III Funkraum, II an der Gerätekiste am Turmfuß
func _build_digits() -> void:
	var spots: Array = []
	if tunnels:
		spots.append_array(tunnels.digit_spots)
	if tower:
		var ax := Basis(Vector3.UP, 0.3) * Vector3.RIGHT
		var pos: Vector3 = tower.site + Vector3(2.1, 0, 0.4) + ax * 0.355 + Vector3.UP * 0.3
		spots.append({"digit": "2", "order": "II", "pos": pos, "normal": ax, "place": "Gerätekiste am Fuß des Suchturms (Wiese)"})
	var rank := {"I": 1, "II": 2, "III": 3, "IV": 4}
	spots.sort_custom(func(a, b): return int(rank.get(a.order, 9)) < int(rank.get(b.order, 9)))
	var chalk := Color(0.92, 0.92, 0.86, 0.88)
	for sp in spots:
		var holder := Node3D.new()
		holder.name = "Kreide_" + String(sp.order)
		add_child(holder)
		holder.global_transform = _facing(sp.normal, sp.pos + (sp.normal as Vector3) * 0.006)
		holder.add_to_group("bavaria_chalk_digits")
		var big := _label(holder, String(sp.digit), 110, chalk, Transform3D(Basis(Vector3.FORWARD, 0.06), Vector3.ZERO), 0.0022)
		_label(holder, String(sp.order), 40, chalk, Transform3D(Basis(), Vector3(0.0, -0.17, 0)), 0.0022)
		sp["label"] = big
		digit_spots.append(sp)

# --- Benutzen ------------------------------------------------------------------------------------------------------

func is_authority() -> bool:
	return not Net.is_online or multiplayer.is_server()

func _is_local_player(s: Soldier) -> bool:
	var pc = mission.get("controller")
	return pc != null and is_instance_valid(s) and pc.get("active") == s

func can_use(kind: String, _s: Soldier) -> bool:
	match kind:
		"keypad":
			return not door_open
	return true

func use(kind: String, s: Soldier) -> void:
	match kind:
		"keypad":
			if not door_open and _is_local_player(s):
				open_keypad()
		"nuke":
			if is_authority():
				nuke_presses += 1
				_nuke_fx()
				_send(&"_nuke_fx", [])
		"switch":
			if is_authority():
				_apply_power(not tower.switch_on, tower.outage_left, POWER_SWITCH)
		"fuse":
			if is_authority():
				trip_fuse()

## Server: Sicherung auslösen (nur wenn der Turm gerade Strom hat bzw. kein Ausfall läuft)
func trip_fuse() -> bool:
	if tower == null or tower.outage_left > 0.0:
		return false
	last_outage = roll_outage()
	fuse_trips += 1
	_apply_power(tower.switch_on, last_outage, POWER_FUSE)
	return true

func roll_outage() -> float:
	return _rng.randf_range(OUTAGE_MIN, OUTAGE_MAX)

func _on_outage_ended() -> void:
	if is_authority():
		_apply_power(tower.switch_on, 0.0, POWER_RESTORED)
	else:
		_update_switch_visual()

func _apply_power(on: bool, left: float, kind: int) -> void:
	_power_state(on, left, kind)
	_send(&"_power_state", [on, left, kind])

@rpc("authority", "call_remote", "reliable")
func _power_state(on: bool, left: float, kind: int) -> void:
	if tower == null:
		return
	tower.switch_on = on
	tower.outage_left = left
	_update_switch_visual()
	match kind:
		POWER_SWITCH:
			if tower_switch:
				_play("click", tower_switch.global_position)
		POWER_FUSE:
			if fuse_box:
				_play("spark", fuse_box.global_position)
				_sparks(fuse_box.global_position)
			Events.say("Sicherung durchgebrannt – Suchturm ohne Strom", 3.0)
		POWER_RESTORED:
			Events.say("Suchturm hat wieder Strom", 2.5)

func _sparks(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3(0, 0.3, 1)
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.01
	p.scale_amount_max = 0.025
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	p.mesh = bm
	p.material_override = _mat(Color(1.0, 0.8, 0.3), 0.0, 0.5, true)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.7, 0.8, 1.0)
	flash.light_energy = 1.0
	flash.omni_range = 2.5
	flash.shadow_enabled = false
	add_child(flash)
	flash.global_position = pos
	get_tree().create_timer(0.15).timeout.connect(flash.queue_free)
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

@rpc("authority", "call_remote", "reliable")
func _nuke_fx() -> void:
	if nuke:
		_play("dodo", nuke.global_position)

# --- Zahlenschloss ---------------------------------------------------------------------------------------------------

func open_keypad() -> void:
	if ui and is_instance_valid(ui):
		return
	ui = KeypadUI.new(self)
	add_child(ui)

## Eingabe vom Tastenfeld: offline/Server direkt, Client fragt den Server
func submit(code: String) -> void:
	if is_authority():
		check_code(code, 0)
	else:
		submit_code.rpc_id(1, code)

@rpc("any_peer", "call_remote", "reliable")
func submit_code(code: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var s = Net._soldiers.get(peer)
	if not is_instance_valid(s) or keypad == null or (s as Node3D).global_position.distance_to(keypad.global_position) > 5.0:
		return
	check_code(code.left(8), peer)

func check_code(code: String, peer: int) -> void:
	var ok := code == CODE
	if ok:
		right_count += 1
		if not door_open:
			_door_state(true, false)
			_send(&"_door_state", [true, false])
	else:
		wrong_count += 1
	if peer == 0 or (Net.is_online and peer == multiplayer.get_unique_id()):
		_code_result(ok)
	elif multiplayer.get_peers().has(peer):
		_code_result.rpc_id(peer, ok)

@rpc("authority", "call_remote", "reliable")
func _code_result(ok: bool) -> void:
	if keypad:
		_play("ok" if ok else "wrong", keypad.global_position)
	if ui and is_instance_valid(ui):
		ui.feedback(ok)

@rpc("authority", "call_remote", "reliable")
func _door_state(open: bool, instant: bool) -> void:
	door_open = open
	if keypad_led:
		var c := Color(0.1, 0.9, 0.1) if open else Color(0.9, 0.08, 0.05)
		keypad_led.albedo_color = c
		keypad_led.emission = c
	if door_pivot == null:
		return
	var target := _yaw_open if open else _yaw_closed
	if instant:
		door_pivot.rotation.y = target
		return
	_play("door", door_pivot.global_position + Vector3.UP)
	var tw := create_tween()
	tw.tween_property(door_pivot, "rotation:y", target, 1.6).set_trans(Tween.TRANS_SINE)

# --- Netz-Abgleich ---------------------------------------------------------------------------------------------------

func _send(method: StringName, args: Array) -> void:
	if not (Net.is_online and multiplayer.is_server()):
		return
	for peer in _peers.keys():
		if multiplayer.get_peers().has(peer):
			callv(&"rpc_id", [peer, method] + args)

@rpc("any_peer", "call_remote", "reliable")
func request_state() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(peer):
		return
	_peers[peer] = true
	_full_state.rpc_id(peer, door_open, tower.switch_on if tower else true, tower.outage_left if tower else 0.0, clock)

@rpc("authority", "call_remote", "reliable")
func _full_state(open: bool, on: bool, left: float, c: float) -> void:
	clock = c
	if open != door_open:
		_door_state(open, true)
	_power_state(on, left, POWER_SILENT)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_clock(c: float) -> void:
	clock = c

# --- Laufzeit: Uhr, Flackern, Ei ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	clock += delta
	if egg:
		egg.rotate_y(delta * 0.4)
	_flicker_acc += delta
	if _flicker_acc >= 1.0 / FLICKER_HZ:
		_flicker_acc = 0.0
		apply_flicker()
	if Net.is_online and multiplayer.is_server() and not _peers.is_empty():
		_sync_acc += delta
		if _sync_acc >= CLOCK_SYNC_S:
			_sync_acc = 0.0
			_send(&"_sync_clock", [clock])

static func _hash01(a: int, b: int) -> float:
	var x := (a * 73856093) ^ (b * 19349663)
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65535.0

## Helligkeitsfaktor der Lampe i zur Zeit t (deterministisch): meist ruhig mit leichtem Glimmen, in zufälligen Phasen
## Flackern; jede fünfte Lampe hat einen Wackelkontakt und flackert öfter.
static func flicker(i: int, t: float) -> float:
	var ep := floori((t + float(i) * 1.37) / 3.0)
	var defect := i % 5 == 2
	if _hash01(i, ep) > (0.55 if defect else 0.2):
		return 1.0 - 0.07 * _hash01(i + 911, floori(t * 6.0))
	var v := _hash01(i * 31 + 7, floori(t * 14.0))
	return 0.06 if v < 0.4 else (0.5 if v < 0.6 else 1.0)

func apply_flicker() -> void:
	if tunnels == null:
		return
	var lamps: Array = tunnels.lamps
	for i in lamps.size():
		var l: OmniLight3D = lamps[i]
		if not is_instance_valid(l):
			continue
		var f := flicker(i, clock)
		l.light_energy = float(l.get_meta("base_energy", 0.75)) * f
		var bm = l.get_meta("bulb", null)
		if bm:
			(bm as StandardMaterial3D).emission_energy_multiplier = 2.2 * f

# --- Klänge (prozedural) ---------------------------------------------------------------------------------------------

func _make_sounds() -> void:
	# „dö-dö“: zwei absteigende, leicht vibrierende Rechtecktöne
	_sounds["dodo"] = _wav([[392.0, 0.26, 0.0], [0.0, 0.07, 0.0], [262.0, 0.5, -30.0]], "square")
	_sounds["beep"] = _wav([[1200.0, 0.06, 0.0]], "sine")
	_sounds["ok"] = _wav([[880.0, 0.09, 0.0], [0.0, 0.03, 0.0], [1320.0, 0.16, 0.0]], "sine")
	_sounds["wrong"] = _wav([[140.0, 0.45, 0.0]], "square")
	_sounds["click"] = _wav([[2200.0, 0.025, 0.0], [0.0, 0.04, 0.0], [900.0, 0.03, 0.0]], "noise")
	_sounds["spark"] = _wav([[0.0, 0.7, 0.0]], "crackle")
	_sounds["door"] = _wav([[55.0, 1.3, 0.0]], "rumble")

## segs: [Frequenz Hz, Dauer s, Gleiten Hz über die Dauer]
func _wav(segs: Array, kind: String) -> AudioStreamWAV:
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phase := 0.0
	for sg in segs:
		var f0: float = sg[0]
		var dur: float = sg[1]
		var glide: float = sg[2]
		var n := int(dur * MIX_RATE)
		for i in n:
			var t := float(i) / MIX_RATE
			var env := minf(1.0, minf(t / 0.01, (dur - t) / 0.03))
			var f := f0 + glide * (t / dur)
			f *= 1.0 + 0.012 * sin(TAU * 6.0 * t)
			phase += TAU * f / MIX_RATE
			var s := 0.0
			if f0 > 0.0 or kind in ["crackle"]:
				match kind:
					"square":
						s = 0.35 * signf(sin(phase)) + 0.15 * sin(phase * 2.0)
					"sine":
						s = 0.5 * sin(phase)
					"noise":
						s = 0.5 * rng.randf_range(-1, 1) * exp(-t * 60.0)
					"crackle":
						s = (rng.randf_range(-1, 1) * 0.8 if rng.randf() < 0.08 + 0.3 * exp(-t * 8.0) else 0.0) * exp(-t * 2.5)
					"rumble":
						s = 0.4 * sin(phase) * (0.6 + 0.4 * rng.randf()) + 0.15 * rng.randf_range(-1, 1)
			var v := int(clampf(s * env, -1.0, 1.0) * 32000.0)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w

func _play(id: String, pos: Vector3) -> void:
	sound_log.append(id)
	if not _sounds.has(id):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[id]
	p.unit_size = 3.0
	p.max_distance = 30.0
	if AudioServer.get_bus_index("SFX") >= 0:
		p.bus = "SFX"
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	last_player = p

func sound_length(id: String) -> float:
	return (_sounds[id] as AudioStreamWAV).get_length() if _sounds.has(id) else 0.0

# --- Tastenfeld-Oberfläche ---------------------------------------------------------------------------------------------

class KeypadUI:
	extends CanvasLayer
	var host
	var entry := ""
	var display: Label
	var _mouse := Input.MOUSE_MODE_VISIBLE
	var _input_was := true

	func _init(h) -> void:
		host = h
		layer = 60
		name = "Zahlenschloss_UI"

	func _ready() -> void:
		_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var pc = host.mission.get("controller")
		if pc:
			_input_was = bool(pc.input_enabled)
			pc.input_enabled = false
			var a = pc.get("active")
			if a:
				a.move_input = Vector3.ZERO
				a.trigger = false
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.14, 0.12, 0.96)
		sb.border_color = Color(0.45, 0.45, 0.4)
		sb.set_border_width_all(2)
		sb.set_content_margin_all(14)
		panel.add_theme_stylebox_override("panel", sb)
		center.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		var title := Label.new()
		title.text = "ZAHLENSCHLOSS"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)
		display = Label.new()
		display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		display.custom_minimum_size = Vector2(220, 40)
		display.add_theme_font_size_override("font_size", 28)
		display.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5))
		box.add_child(display)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		box.add_child(grid)
		for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"]:
			var b := Button.new()
			b.text = "LÖSCHEN" if k == "C" else k
			b.custom_minimum_size = Vector2(70, 48)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(press.bind(k))
			grid.add_child(b)
		var close_b := Button.new()
		close_b.text = "SCHLIESSEN"
		close_b.focus_mode = Control.FOCUS_NONE
		close_b.pressed.connect(close)
		box.add_child(close_b)
		_show()

	func _show() -> void:
		display.text = entry if entry != "" else "_ _ _ _"

	func press(k: String) -> void:
		match k:
			"C":
				entry = ""
			"OK":
				var code := entry
				entry = ""
				host.submit(code)
			_:
				if entry.length() < 6:
					entry += k
				host._play("beep", host.keypad.global_position)
		_show()

	func feedback(ok: bool) -> void:
		display.text = "OFFEN" if ok else "FALSCH"
		if ok:
			get_tree().create_timer(0.6).timeout.connect(close)

	func close() -> void:
		if is_queued_for_deletion():
			return
		var pc = host.mission.get("controller")
		if pc:
			pc.input_enabled = _input_was
		Input.mouse_mode = _mouse
		queue_free()

	func _input(event: InputEvent) -> void:
		if not (event is InputEventKey) or not event.pressed or event.echo:
			return
		var kc: int = (event as InputEventKey).keycode
		if kc >= KEY_0 and kc <= KEY_9:
			press(str(kc - KEY_0))
		elif kc >= KEY_KP_0 and kc <= KEY_KP_9:
			press(str(kc - KEY_KP_0))
		elif kc == KEY_BACKSPACE or kc == KEY_DELETE:
			press("C")
		elif kc == KEY_ENTER or kc == KEY_KP_ENTER:
			press("OK")
		elif kc == KEY_ESCAPE:
			close()
		else:
			return
		get_viewport().set_input_as_handled()
