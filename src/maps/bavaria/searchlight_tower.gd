extends Node3D
## Hölzerner Wachturm auf der großen Wiese mit zwei Suchscheinwerfern (SpotLight3D + sichtbarer Lichtkegel).
## Nachts (Lampenstufe des Tageszyklus wie Laternen/Raumlicht) schwenken beide suchend über die Karte. Erfasst ein
## Kegel einen Soldaten mit freier Sichtlinie (Strahl Ebene 1, Laub der Karte), bleibt der Scheinwerfer auf ihm und
## verfolgt ihn; nach Sichtverlust kurz Nachsuchen um die letzte Stelle, dann wieder Suchen. Tagsüber aus.
## Beleuchtete Ziele gelten über die Gruppe „searchlights“ (Mission.light_at) als hell → KI erkennt sie leichter.
## Mehrspieler: der Server (bzw. Einzelspieler) rechnet; Clients melden sich beim Beitritt über eine RPC dieses
## Knotens an und erhalten 10 Hz den Zustand (Winkel/Modus je Kopf). Kein neues Netzprotokoll (DH2-LAN-6 bleibt):
## wie der Tageszyklus nur Knoten-RPCs. Ohne Serverdaten (älterer Server) rechnet der Client selbst mit den ihm
## bekannten Figurenlagen und der synchronen Tageszeit.
## Strom (11/2026): Schalter am Turmfuß (`switch_on`, Standard AN = bisheriges Verhalten „nachts an“) und Stromausfall über
## den Sicherungskasten im MG42-Haus (`outage_left` s). Licht nur nachts UND Schalter an UND kein Ausfall. Gesetzt/abgeglichen
## wird beides vom Knoten „StollenTechnik“ (bunker_extras.gd).

signal outage_ended

const PLATFORM_Y := 7.0
const HEAD_Y := 8.15
const REACH := 95.0
const CONE_DEG := 6.5
const SEARCH_SPEED := 0.95       ## rad/s Nachführen beim Suchen
const TRACK_SPEED := 1.8         ## rad/s Nachführen auf ein Ziel
const LOSE_AFTER := 0.6          ## s ohne Sichtlinie → Ziel verloren
const RESEARCH_S := 5.0          ## s Nachsuchen um die letzte Stelle
const SYNC_HZ := 10.0
enum { SEARCH, TRACK, RESEARCH }

var mission: Node
var site := Vector3.ZERO
var heads: Array = []
var active := false
var exclude: Array[RID] = []
var _t := 0.0
var _sync_t := 0.0
var _subscribers := {}
var _remote_t := -1.0            ## Client: Zeit seit dem letzten Serverstand (< 0 = nie)
var switch_on := true            ## Schalter am Turmfuß
var outage_left := 0.0           ## Restdauer Stromausfall (Sicherungskasten), s

func power_ok() -> bool:
	return switch_on and outage_left <= 0.0

class Head:
	extends Node3D
	var tower
	var index := 0
	var light: SpotLight3D
	var cone_pivot: Node3D
	var cone_mat: ShaderMaterial
	var yaw := 0.0
	var pitch := -0.3
	var mode := 0
	var target: Node3D
	var last_seen := Vector3.ZERO
	var unseen := 0.0
	var research := 0.0
	var on := false
	var net_yaw := 0.0
	var net_pitch := -0.3

	func dir() -> Vector3:
		return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

	## Mission.light_at: Punkt im Kegel und mit Sichtlinie zur Lampe
	func illuminates(pos: Vector3) -> bool:
		if not on:
			return false
		return tower.in_beam(self, pos)

# --- Bau ----------------------------------------------------------------------------------------------------

static func choose_site(m) -> Vector3:
	var ft = preload("res://src/maps/bavaria/field_trenches.gd")
	var meadow: PackedVector2Array = m.polygon(m.layout["meadow"])
	var c := Vector2.ZERO
	for q in meadow:
		c += q
	c /= meadow.size()
	var bb := Rect2(meadow[0], Vector2.ZERO)
	for q in meadow:
		bb = bb.expand(q)
	var cand: Array = []
	var x := floorf(bb.position.x)
	while x <= bb.end.x:
		var z := floorf(bb.position.y)
		while z <= bb.end.y:
			var p := Vector2(x, z)
			if Geometry2D.is_point_in_polygon(p, meadow) and _inside_margin(p, meadow, 6.0):
				cand.append(p)
			z += 1.0
		x += 1.0
	cand.sort_custom(func(a, b): return a.distance_squared_to(c) < b.distance_squared_to(c))
	for p in cand:   # nächster freier Platz zur Wiesenmitte (deterministisch)
		if _clear_of_covers(ft, p) and ft._cover_block(m, p, 3.2) == "":
			return Vector3(p.x, 0, p.y)
	return Vector3(c.x, 0, c.y)

static func _inside_margin(p: Vector2, poly: PackedVector2Array, margin: float) -> bool:
	for i in poly.size():
		if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p) < margin:
			return false
	return true

static func _clear_of_covers(ft, p: Vector2) -> bool:
	for cv in ft.COVERS:
		if (cv[1] as Vector2).distance_to(p) < 7.0:
			return false
	for poly in ft.hole_polygons():
		for i in poly.size():
			if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p) < 5.0:
				return false
	return true

func build(m) -> void:
	mission = m
	name = "Suchturm"
	site = choose_site(m)
	var lb: LevelBuilder = m.lb
	var wood := "h16_wood" if lb._mats.has("h16_wood") else "wood"
	var tower := Node3D.new()
	tower.name = "Wachturm"
	m.static_root.add_child(tower)
	tower.position = site
	tower.add_to_group("bavaria_watchtower")
	var spread := 1.55          # halbe Spreizung am Fuß
	var top := 1.05             # halbe Breite unter der Plattform
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var a := Vector3(sx * spread, 0, sz * spread)
			var b := Vector3(sx * top, PLATFORM_Y, sz * top)
			_beam(lb, tower, a, b, 0.22, "darkwood", true)
			lb.box(a + Vector3(0, -0.05, 0), Vector3(0.5, 0.25, 0.5), "stone", 0, true, tower)
	# Kreuzverbände je Seite in zwei Feldern
	for k in 2:
		var y0 := k * PLATFORM_Y * 0.5
		var y1 := (k + 1) * PLATFORM_Y * 0.5
		var w0 := lerpf(spread, top, float(k) * 0.5)
		var w1 := lerpf(spread, top, float(k + 1) * 0.5)
		for side in 4:
			var basis := Basis(Vector3.UP, side * PI * 0.5)
			var p0 := basis * Vector3(-w0, y0 + 0.3, w0)
			var p1 := basis * Vector3(w1, y1, w1)
			var p2 := basis * Vector3(w0, y0 + 0.3, w0)
			var p3 := basis * Vector3(-w1, y1, w1)
			_beam(lb, tower, p0, p1, 0.11, "darkwood", false)
			_beam(lb, tower, p2, p3, 0.11, "darkwood", false)
			_beam(lb, tower, basis * Vector3(-w1, y1, w1), basis * Vector3(w1, y1, w1), 0.13, "darkwood", false)
	# Plattform, Brüstung, Dach
	lb.box(Vector3(0, PLATFORM_Y, 0), Vector3(3.0, 0.14, 3.0), wood, 0, true, tower)
	for side in 4:
		var basis := Basis(Vector3.UP, side * PI * 0.5)
		var c := basis * Vector3(0, PLATFORM_Y + 0.14, 1.45)
		var plank := lb.box(c, Vector3(3.0, 0.95, 0.08), wood, side * PI * 0.5, true, tower)
		plank.name = "Bruestung_%d" % side
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			lb.box(Vector3(sx * 1.42, PLATFORM_Y + 0.14, sz * 1.42), Vector3(0.13, 2.3, 0.13), "darkwood", 0, true, tower)
	for s in [-1.0, 1.0]:
		var roof := lb.box(Vector3(0, PLATFORM_Y + 2.38, s * 0.85), Vector3(3.6, 0.08, 1.95), "roof", 0, true, tower)
		roof.rotation.x = 0.42 * s
	# Kabel-/Gerätekiste am Fuß
	lb.box(Vector3(2.1, 0, 0.4), Vector3(0.7, 0.55, 0.5), "darkwood", 0.3, true, tower)
	for body in tower.find_children("*", "StaticBody3D", true, false):
		exclude.append((body as StaticBody3D).get_rid())
	# Zwei Scheinwerfer an diagonalen Ecken, etwas außerhalb der Brüstung (freier Strahl nach unten)
	for i in 2:
		var h := Head.new()
		h.tower = self
		h.index = i
		h.name = "Scheinwerfer_%d" % i
		h.add_to_group("searchlights")
		add_child(h)
		var corner := Vector3(1.75, 0, 1.75) if i == 0 else Vector3(-1.75, 0, -1.75)
		h.position = site + Vector3(corner.x, HEAD_Y, corner.z)
		lb.box(Vector3(corner.x * 0.88, PLATFORM_Y + 0.14, corner.z * 0.88), Vector3(0.14, HEAD_Y - PLATFORM_Y - 0.3, 0.14), "darkwood", 0, false, tower)
		_build_head(h)
		h.yaw = PI * i
		heads.append(h)
	m.set_meta("watchtower_site", site)
	print("BAVARIA SUCHTURM: Standort ", site, " (Wiese), 2 Scheinwerfer, Reichweite %.0f m" % REACH)

func _beam(lb: LevelBuilder, parent: Node3D, a: Vector3, b: Vector3, thick: float, material: String, collide: bool) -> void:
	var len := a.distance_to(b)
	var beam := lb.box(Vector3.ZERO, Vector3(thick, len, thick), material, 0, collide, parent)
	for child in beam.get_children():
		if child is Node3D:
			(child as Node3D).position.y -= len * 0.5
	beam.position = (a + b) * 0.5
	beam.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

func _build_head(h: Head) -> void:
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.30
	cm.height = 0.62
	body.mesh = cm
	body.rotation.x = PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.21)
	mat.metallic = 0.6
	mat.roughness = 0.45
	body.material_override = mat
	h.add_child(body)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.29
	lm.bottom_radius = 0.29
	lm.height = 0.02
	lens.mesh = lm
	lens.rotation.x = PI * 0.5
	lens.position.z = -0.32
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.97, 0.86)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.95, 0.82)
	glass.emission_energy_multiplier = 0.0
	lens.material_override = glass
	lens.name = "Linse"
	h.add_child(lens)
	h.set_meta("glass", glass)
	var light := SpotLight3D.new()
	light.light_color = Color(1.0, 0.96, 0.86)
	light.light_energy = 28.0
	light.spot_range = REACH
	light.spot_angle = CONE_DEG
	light.spot_angle_attenuation = 0.6
	light.spot_attenuation = 0.35
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 3.0
	light.position.z = -0.36
	light.visible = false
	h.add_child(light)
	h.light = light
	var pivot := Node3D.new()
	pivot.position.z = -0.36
	h.add_child(pivot)
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = tan(deg_to_rad(CONE_DEG))   # +Y-Seite → weit (zeigt nach −Z)
	mesh.bottom_radius = 0.004
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	cone.mesh = mesh
	cone.rotation.x = -PI * 0.5
	cone.position.z = -0.5
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform float strength = 0.16;
varying float along;
void vertex() { along = VERTEX.y + 0.5; }
void fragment() {
	float fade = pow(1.0 - clamp(along, 0.0, 1.0), 1.4) * smoothstep(0.0, 0.02, along);
	float rim = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.2);
	ALBEDO = tint.rgb * strength * fade * (0.35 + 0.65 * rim);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	cone.material_override = sm
	pivot.add_child(cone)
	pivot.visible = false
	h.cone_pivot = pivot
	h.cone_mat = sm

# --- Laufzeit -------------------------------------------------------------------------------------------------

func _ready() -> void:
	if Net.is_online and not multiplayer.is_server():
		subscribe.rpc_id(1)
	if Net.is_online and multiplayer.is_server():
		multiplayer.peer_disconnected.connect(func(id): _subscribers.erase(id))

func night_level() -> float:
	var dn = mission.get("day_night") if mission else null
	if dn == null or not dn.has_method("state"):
		return 0.0
	return float(dn.state().get("lamp", 0.0))

func is_authority() -> bool:
	return not Net.is_online or multiplayer.is_server()

func _physics_process(delta: float) -> void:
	if heads.is_empty():
		return
	_t += delta
	if outage_left > 0.0:
		outage_left = maxf(0.0, outage_left - delta)
		if outage_left <= 0.0:
			outage_ended.emit()
	var want := night_level() >= 0.5 and power_ok()
	if want != active:
		_set_active(want)
	var remote := not is_authority() and _remote_t >= 0.0 and _remote_t < 1.5
	if not is_authority() and _remote_t >= 0.0:
		_remote_t += delta
	for h in heads:
		if remote:
			h.yaw = lerp_angle(h.yaw, h.net_yaw, minf(1.0, delta * 12.0))
			h.pitch = lerpf(h.pitch, h.net_pitch, minf(1.0, delta * 12.0))
		elif active:
			_think(h, delta)
		h.rotation = Vector3(h.pitch, h.yaw, 0)
		if active:
			_update_cone(h)
	if is_authority() and Net.is_online and active and not _subscribers.is_empty():
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = 1.0 / SYNC_HZ
			var data := PackedFloat32Array()
			for h in heads:
				data.append_array([h.yaw, h.pitch, float(h.mode)])
			for peer in _subscribers.keys():
				if multiplayer.get_peers().has(peer):
					sync_heads.rpc_id(peer, data)

func _set_active(on: bool) -> void:
	active = on
	for h in heads:
		h.on = on
		h.light.visible = on
		h.cone_pivot.visible = on
		(h.get_meta("glass") as StandardMaterial3D).emission_energy_multiplier = 6.0 if on else 0.0
		if not on:
			h.mode = SEARCH
			h.target = null
			h.pitch = -0.15

## Suchmuster: Bodenpunkt kreist um den Turm (je Kopf gegenläufig versetzt), Entfernung pendelt 14–62 m.
func search_point(h: Head) -> Vector3:
	var ang := _t * 0.30 + PI * h.index
	var r := 14.0 + 48.0 * (0.5 + 0.5 * sin(_t * 0.41 + 1.7 * h.index))
	return site + Vector3(-sin(ang) * r, 0.0, -cos(ang) * r)

func _aim(h: Head, p: Vector3, speed: float, delta: float) -> void:
	var to := p - h.global_position
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	h.yaw = rotate_toward(h.yaw, yaw, speed * delta)
	h.pitch = move_toward(h.pitch, pitch, speed * delta)

func _think(h: Head, delta: float) -> void:
	match h.mode:
		SEARCH:
			_aim(h, search_point(h), SEARCH_SPEED, delta)
			_acquire(h)
		RESEARCH:
			h.research -= delta
			var ang := _t * 2.2 + h.index
			_aim(h, h.last_seen + Vector3(sin(ang), 0, cos(ang)) * 3.5, TRACK_SPEED, delta)
			if not _acquire(h) and h.research <= 0.0:
				h.mode = SEARCH
		TRACK:
			var tgt := h.target
			if tgt == null or not is_instance_valid(tgt) or not bool(tgt.get("alive")):
				_lose(h)
				return
			var aim := _aim_point(tgt)
			_aim(h, aim, TRACK_SPEED, delta)
			if in_beam(h, aim, 2.2):
				h.last_seen = aim
				h.unseen = 0.0
			else:
				h.unseen += delta
				if h.unseen > LOSE_AFTER:
					_lose(h)

func _lose(h: Head) -> void:
	h.target = null
	h.mode = RESEARCH
	h.research = RESEARCH_S

func _aim_point(s: Node3D) -> Vector3:
	return s.global_position + Vector3.UP * 1.0

## Ziel im Kegel? (Kegel mit Faktor k aufgeweitet; Verfolgen toleriert die Nachführung)
func in_beam(h: Head, pos: Vector3, k := 1.0) -> bool:
	var origin := h.light.global_position
	var to := pos - origin
	var d := to.length()
	if d > REACH or d < 0.5:
		return false
	if h.dir().angle_to(to) > deg_to_rad(CONE_DEG) * k:
		return false
	return has_sight(origin, pos)

func has_sight(origin: Vector3, pos: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(origin, pos, 1, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.position.distance_to(pos) > 0.6:
		return false
	if mission and mission.has_method("foliage_blocks_sight") and mission.foliage_blocks_sight(origin, pos):
		return false
	return true

func _acquire(h: Head) -> bool:
	for s in get_tree().get_nodes_in_group("soldiers"):
		if not is_instance_valid(s) or not bool(s.get("alive")):
			continue
		if in_beam(h, _aim_point(s)):
			h.target = s
			h.mode = TRACK
			h.unseen = 0.0
			h.last_seen = _aim_point(s)
			return true
	return false

func _update_cone(h: Head) -> void:
	var origin := h.light.global_position
	var q := PhysicsRayQueryParameters3D.create(origin, origin + h.dir() * REACH, 1, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var len := REACH if hit.is_empty() else origin.distance_to(hit.position)
	h.cone_pivot.scale = Vector3.ONE * maxf(len, 1.0)

## Für Tests: gerade verfolgtes Ziel je Kopf
func tracked() -> Array:
	return heads.map(func(h): return h.target if h.mode == TRACK else null)

# --- Netz (Knoten-RPCs, kein Protokollwechsel) ------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func subscribe() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if multiplayer.get_peers().has(peer):
		_subscribers[peer] = true

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_heads(data: PackedFloat32Array) -> void:
	_remote_t = 0.0
	for i in mini(heads.size(), data.size() / 3):
		var h: Head = heads[i]
		h.net_yaw = data[i * 3]
		h.net_pitch = data[i * 3 + 1]
		h.mode = int(data[i * 3 + 2])
