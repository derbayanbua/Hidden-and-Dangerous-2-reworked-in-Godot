extends Node
## Dynamisches Wetter der Karte Bavaria: klar → bewölkt → Regen → Gewitter (zufällig gewichtete Folge, weiche
## Übergänge über Minuten). Wirkt auf Himmel (alps_sky-Uniforms overcast/rain_haze/cloud_time), Panoramaring,
## Sonne/Umgebungslicht/Nebel (über factors(), gelesen von day_night.gd), Regenpartikel nah an der Kamera
## (nicht unter Dächern/in Stollen: Strahl nach oben), Blitze bei Gewitter und Nässe der Böden/Fassaden
## (Rauheit/Albedo, Pfützen im Bodenshader).
## Schalter: --weather=0 = aus (Stand ohne Wetter), --weather=<klar|bewoelkt|regen|gewitter> = fest,
## --weather=dynamisch = Zufallsfolge auch unter --autoplay (dort sonst fest „klar“, damit Tests reproduzierbar sind).
## Mehrspieler: der Server würfelt und sendet den Zustand über eigene RPCs dieses Knotens (wie die Tageszeit,
## ohne neue Protokollversion); Spät-Beitretende fragen ihn beim Start ab.
const STATES := ["klar", "bewoelkt", "regen", "gewitter"]
## je Zustand: Bewölkung, Regen (0–1), Sonne ×, Umgebungslicht ×, Nebel ×, Grau-Anteil, Lampen-Mindeststufe
## (Lampen-Mindeststufe bewusst 0: tagsüber eingeschaltete Raumlichter/Laternen mit Schatten kosteten bis +75 % Draw Calls)
const PARAMS := {
	"klar":     {"cloud": 0.08, "rain": 0.0, "sun": 1.0,  "ambient": 1.0,  "fog": 1.0, "grey": 0.0,  "lamp": 0.0},
	"bewoelkt": {"cloud": 0.7,  "rain": 0.0, "sun": 0.45, "ambient": 0.85, "fog": 1.5, "grey": 0.45, "lamp": 0.0},
	"regen":    {"cloud": 0.95, "rain": 0.7, "sun": 0.22, "ambient": 0.7,  "fog": 2.6, "grey": 0.8,  "lamp": 0.0},
	"gewitter": {"cloud": 1.0,  "rain": 1.0, "sun": 0.1,  "ambient": 0.5,  "fog": 3.4, "grey": 1.0,  "lamp": 0.0},
}
## Übergangsgewichte: nächster Zustand
const NEXT := {
	"klar":     {"klar": 3, "bewoelkt": 5},
	"bewoelkt": {"klar": 4, "bewoelkt": 2, "regen": 3, "gewitter": 1},
	"regen":    {"bewoelkt": 4, "regen": 2, "gewitter": 1},
	"gewitter": {"regen": 3, "bewoelkt": 1},
}
const HOLD_MIN := 240.0           ## Verweildauer [s]
const HOLD_MAX := 600.0
const BLEND_S := 150.0            ## Übergangsdauer [s]
const WET_UP_S := 150.0           ## nass werden bei vollem Regen
const WET_DOWN_S := 600.0         ## abtrocknen
const SYNC_S := 15.0
const RAIN_AMOUNT := 1400
const RAIN_BOX := 16.0            ## halbe Kantenlänge des Regenvolumens um die Kamera [m]

var mission: Node
var enabled := true
var fixed := false
var current := "klar"
var previous := "klar"
var blend := 1.0                  ## 0 = previous, 1 = current
var hold := 0.0
var wet := 0.0
var cloud_time := 0.0
var synced := false
var flash_count := 0
var _rng := RandomNumberGenerator.new()
var _env: Environment
var _rain: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _flash: DirectionalLight3D
var _flash_t := 0.0
var _flash_wait := 20.0
var _sync_t := 0.0
var _apply_t := 0.0
var _sheltered := false
var _wet_mats: Array = []         ## [StandardMaterial3D, Grundrauheit, Grundfarbe]
var _ground_mats: Array = []      ## ShaderMaterial mit Uniform „wetness“

func _ready() -> void:
	name = "Wetter"
	_rng.seed = int(Time.get_unix_time_from_system()) ^ 0x5eed
	var arg := String(Game.cli.get("weather", ""))
	if arg == "" and Game.cli.has("autoplay"):
		arg = "klar"    # Tests/Kontrollbilder reproduzierbar; Wetter dort nur per --weather=<zustand> bzw. set_weather()
	if arg == "0":
		enabled = false
	elif STATES.has(arg):
		fixed = true
		current = arg
		previous = arg
		wet = 1.0 if arg in ["regen", "gewitter"] else 0.0
	else:
		current = _pick(_pick("klar"))      # Startzustand: Folge ab „klar“ gewürfelt
		previous = current
	hold = _rng.randf_range(HOLD_MIN, HOLD_MAX)
	if not enabled:
		return
	if Net.is_online and not multiplayer.is_server():
		request_state.rpc_id(1)
	_build_rain()
	_flash = DirectionalLight3D.new()
	_flash.name = "Blitz"
	_flash.light_color = Color(0.82, 0.86, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.visible = false
	_flash.rotation = Vector3(-1.2, 0.4, 0.0)
	add_child(_flash)

func bind(env: Environment) -> void:
	_env = env
	if not enabled or mission == null:
		return
	var lb = mission.get("lb")
	if lb:
		for key in ["plaster", "damaged", "brick", "stone", "roof", "slate", "wood", "darkwood", "rubble", "earth",
				"grass", "meadow", "h16_plaster", "h16_roof", "h16_wood"]:
			var m = lb._mats.get(key)
			if m is StandardMaterial3D:
				_wet_mats.append([m, (m as StandardMaterial3D).roughness, (m as StandardMaterial3D).albedo_color])
	var gs = mission.get("ground_surfaces")
	if gs and gs.get("materials") is Dictionary:
		for m in gs.materials.values():
			if m is ShaderMaterial:
				_ground_mats.append(m)
	_apply_visuals()

## Faktoren für day_night.gd (Sonne, Umgebungslicht, Nebel, Grau, Lampen) – gemischt zwischen previous/current.
func factors() -> Dictionary:
	if not enabled:
		return {}
	var a: Dictionary = PARAMS[previous]
	var b: Dictionary = PARAMS[current]
	var t := smoothstep(0.0, 1.0, blend)
	var out := {}
	for k in a:
		out[k] = lerpf(float(a[k]), float(b[k]), t)
	return out

func value(key: String) -> float:
	return float(factors().get(key, 0.0))

func state() -> Dictionary:
	return {"enabled": enabled, "current": current, "previous": previous, "blend": blend, "wet": wet,
		"rain": value("rain") if enabled else 0.0, "cloud": value("cloud") if enabled else 0.0,
		"sheltered": _sheltered, "rain_visible": _rain != null and _rain.emitting, "flashes": flash_count}

## Zustand setzen (Server/Einzelspieler, Tests). instant = ohne Übergang.
func set_weather(s: String, instant := false) -> void:
	if not STATES.has(s):
		return
	previous = current if not instant else s
	current = s
	blend = 1.0 if instant else 0.0
	hold = _rng.randf_range(HOLD_MIN, HOLD_MAX)
	if instant:
		wet = 1.0 if s in ["regen", "gewitter"] else (wet if s == "bewoelkt" else 0.0)
	_apply_visuals()
	_refresh_day_night()
	if Net.is_online and multiplayer.is_server():
		sync_state.rpc(current, previous, blend, wet, hold)

func _pick(from: String) -> String:
	var w: Dictionary = NEXT[from]
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := _rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return from

func _process(delta: float) -> void:
	if not enabled:
		return
	cloud_time += delta
	if blend < 1.0:
		blend = minf(1.0, blend + delta / BLEND_S)
	var authority := not Net.is_online or multiplayer.is_server()
	if authority and not fixed:
		hold -= delta
		if hold <= 0.0 and blend >= 1.0:
			var nxt := _pick(current)
			if nxt != current:
				set_weather(nxt)
			else:
				hold = _rng.randf_range(HOLD_MIN, HOLD_MAX)
	var rain := value("rain")
	if rain > 0.3:
		wet = minf(1.0, wet + delta * rain / WET_UP_S)
	else:
		wet = maxf(0.0, wet - delta / WET_DOWN_S)
	_update_rain(rain)
	_update_flash(delta)
	_apply_t -= delta
	if _apply_t <= 0.0:
		_apply_t = 0.5
		_apply_visuals()
	if Net.is_online and multiplayer.is_server():
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = SYNC_S
			sync_state.rpc(current, previous, blend, wet, hold)

func _apply_visuals() -> void:
	var f := factors()
	var cloud := float(f.get("cloud", 0.0))
	var haze := float(f.get("rain", 0.0))
	var sky_mat := _env.sky.sky_material as ShaderMaterial if _env and _env.sky else null
	if sky_mat:
		sky_mat.set_shader_parameter("overcast", cloud)
		sky_mat.set_shader_parameter("rain_haze", haze)
		sky_mat.set_shader_parameter("cloud_time", cloud_time)
	var ring = mission.get("panorama_ring") if mission else null
	if ring and ring.get("material") is ShaderMaterial:
		ring.material.set_shader_parameter("overcast", cloud)
		ring.material.set_shader_parameter("rain_haze", haze)
	for e in _wet_mats:
		var m: StandardMaterial3D = e[0]
		m.roughness = float(e[1]) * lerpf(1.0, 0.5, wet)
		m.albedo_color = (e[2] as Color) * lerpf(1.0, 0.78, wet)
	for m in _ground_mats:
		m.set_shader_parameter("wetness", wet)

func _refresh_day_night() -> void:
	var dn = mission.get("day_night") if mission else null
	if dn and dn.has_method("_apply"):
		dn._apply(true)

# --- Regen -------------------------------------------------------------------------------------------------
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Regen"
	var q := float(Settings.quality)
	_rain.amount = int(RAIN_AMOUNT * clampf(0.5 + q * 0.2, 0.4, 1.2))
	_rain.lifetime = 1.1
	_rain.preprocess = 1.1
	_rain.emitting = false
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-RAIN_BOX, -14, -RAIN_BOX), Vector3(RAIN_BOX * 2, 22, RAIN_BOX * 2))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(RAIN_BOX, 0.3, RAIN_BOX)
	_rain_mat.direction = Vector3(0.08, -1, 0.03)
	_rain_mat.spread = 4.0
	_rain_mat.gravity = Vector3(0, -12, 0)
	_rain_mat.initial_velocity_min = 8.0
	_rain_mat.initial_velocity_max = 11.0
	_rain.process_material = _rain_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.5)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = Color(0.70, 0.76, 0.84, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	_rain.draw_pass_1 = quad
	add_child(_rain)

func _update_rain(rain: float) -> void:
	if _rain == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or rain < 0.05:
		_rain.emitting = false
		_sheltered = false
		return
	_sheltered = _roof_above(cam.global_position)
	_rain.emitting = not _sheltered
	_rain.amount_ratio = clampf(rain, 0.05, 1.0)
	_rain.global_position = cam.global_position + Vector3(0, 7.0, 0)

## Dach/Decke/Erdreich über der Kamera (Innenräume, Stollen, Vordächer)
func roof_above(pos: Vector3) -> bool:
	return _roof_above(pos)

func _roof_above(pos: Vector3) -> bool:
	var w := get_viewport().world_3d if is_inside_tree() else null
	if w == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.UP * 40.0, 1)
	return not w.direct_space_state.intersect_ray(q).is_empty()

func _update_flash(delta: float) -> void:
	if _flash == null:
		return
	if current != "gewitter" or blend < 0.5:
		_flash.visible = false
		return
	_flash_wait -= delta
	if _flash_wait <= 0.0:
		_flash_wait = _rng.randf_range(12.0, 40.0)
		_flash_t = 0.35
		flash_count += 1
	if _flash_t > 0.0:
		_flash_t -= delta
		var k := maxf(0.0, _flash_t / 0.35)
		_flash.visible = true
		_flash.light_energy = 1.6 * k * (0.6 + 0.4 * sin(_flash_t * 60.0))
	else:
		_flash.visible = false

# --- Mehrspieler ------------------------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func request_state() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if multiplayer.get_peers().has(peer):
		sync_state.rpc_id(peer, current, previous, blend, wet, hold)

@rpc("authority", "call_remote", "reliable")
func sync_state(cur: String, prev: String, b: float, w: float, h: float) -> void:
	if not STATES.has(cur) or not STATES.has(prev):
		return
	current = cur
	previous = prev
	blend = clampf(b, 0.0, 1.0)
	wet = clampf(w, 0.0, 1.0)
	hold = h
	synced = true
	_apply_visuals()
	_refresh_day_night()
