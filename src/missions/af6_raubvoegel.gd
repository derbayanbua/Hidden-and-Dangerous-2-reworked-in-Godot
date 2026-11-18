extends "res://src/missions/orig_generic.gd"
## AFRICA6 „Raubvögel“: Bordschützen-Einsatz in der Ju 88 (Belege: docs/re_notes_ju88.md, Daten
## orig_cache/africa6/ju88.json aus tools/fmt_ju88.py).
## - Ju 88 folgt der festen Original-Flugbahn (#aircraftA1..6, 25 Bilder/s); Fortschritt nur, solange der
##   Akteur eingeschaltet ist (FRM_SetON durch das Originalskript nach der Zwischensequenz).
## - Spieler sitzen an SEAT01/02/03/00 (Board01..04) mit dem Original-MG des Sitzes.
## - SetActorState(ju88, n): n Jäger (Bf 109) mit zufälligen IDs 1–9, eigene Original-Bahnen, sichtbar ab 9–11 s,
##   feuern nur in ihren Feuerfenstern: Schaden an der Ju 88 = 180/s je Jäger × SetupJunkers88(a)·0,01.
## - Lebenspunkte Ju 88 5000, Jäger 10000 × (0,7/0,85/1,0 je Schwierigkeit); Treffer-Schaden ÷ b·0,01.
## - Sieg: Originalskript (Whenever _FrameInRange(ju88) < 500 am Dummy AF5_obj). Ju 88 bei 0 LP → gescheitert.
## Vereinfachungen: Schwenkgrenzen der MG-Stände und Absturz-/Wackelanimationen (#adamage, #bfshotdwn) nicht
## nachgebildet (Absturz der Jäger: Sturzflug + Explosion), Funksprüche fehlen.

const SEAT_OF_PLAYER := [1, 2, 3, 0]

var j88: Dictionary = {}
var ju88: Node3D
var flight_t := 0.0
var ju88_health := 5000.0
var damage_mult := 0.6          ## SetupJunkers88(a): a·0,01
var hit_div := 1.0              ## SetupJunkers88(b): b·0,01
var fighters: Array = []
var _path: Array = []            ## [[t, pos, rot], …] Ju 88
var _seated := false
const SEAT_DROP := -0.6          ## Figurwurzel unter dem Sitz-Frame [E]
var turrets: Array = []
var _own_rids: Array[RID] = []
var pause_flight := false         ## Testhilfe (test_af6): Flugbahn anhalten
var crashing := false            ## Ju 88 bei 0 LP: Absturz, danach Missionsende (Original #jushotdwn*, 0x423C70)
var _crash_t := 0.0
var _crash_v := Vector3.ZERO
var _prev_pos := Vector3.INF
var _ju_vel := Vector3.ZERO
var _tracers: Array = []         ## Leuchtspuren der Jäger [[Knoten, Geschwindigkeit, Rest-s]]


func _init() -> void:
	super._init()


func _spawn_actors() -> void:
	super._spawn_actors()
	var d = LsRuntime._read_json(orig.mission_dir + "/ju88.json")
	j88 = d if typeof(d) == TYPE_DICTIONARY else {}
	ju88 = runtime.find_frame("ju88") if runtime else null
	if j88.is_empty() or ju88 == null:
		push_warning("AFRICA6: ju88.json oder Akteur ju88 fehlt (tools/fmt_ju88.py)")
		return
	_path = _keys(j88["path"]["segments"])
	ju88_health = _param("c100_health", 5000.0)
	_pose_body(ju88)
	ju88.set_meta("orig_ctl", self)
	ju88.visible = false          # Originalskript schaltet sie nach der Zwischensequenz ein
	_apply_path(ju88, _path, 0.0)
	_board_squad()


## Junkers88-Parameter aus actors.bin (c100 Lebenspunkte, c200 Jäger-LP, c300 Schadensrate je feuerndem Jäger)
func _param(key: String, dflt: float) -> float:
	var e = j88.get("actor", {}).get("params", {}).get(key, {})
	return float(e.get("value", dflt)) if e is Dictionary else dflt


## Ruhelage: Bug entlang Modell +X → BODY −90° Gier (Original #adamage0), dann Bug = Flugrichtung
static func _pose_body(n: Node3D) -> void:
	var body := n.find_child("BODY", true, false) as Node3D
	if body:
		body.quaternion = Quaternion(0.0, -0.70711, 0.0, 0.70711)


## Segmente → durchgehende Keyliste [Zeit s, Position, Rotation]
static func _keys(segments: Array) -> Array:
	var out: Array = []
	for seg in segments:
		var t0 := float(seg.get("start_s", 0.0))
		var rots: Array = seg.get("rot", [])
		var poss: Array = seg.get("pos", [])
		for i in poss.size():
			var p: Array = poss[i]
			var r: Array = rots[mini(i, rots.size() - 1)] if not rots.is_empty() else [0, 0, 0, 0, 1]
			out.append([t0 + float(p[0]) / 25.0, Vector3(p[1], p[2], p[3]), Quaternion(r[1], r[2], r[3], r[4]).normalized()])
	return out


static func _sample(keys: Array, t: float) -> Array:
	if keys.is_empty():
		return [Vector3.ZERO, Quaternion.IDENTITY]
	if t <= keys[0][0]:
		return [keys[0][1], keys[0][2]]
	var lo := 0
	var hi := keys.size() - 1
	if t >= keys[hi][0]:
		return [keys[hi][1], keys[hi][2]]
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if keys[mid][0] <= t:
			lo = mid
		else:
			hi = mid
	var a: Array = keys[lo]
	var b: Array = keys[hi]
	var k := clampf((t - a[0]) / maxf(b[0] - a[0], 0.0001), 0.0, 1.0)
	return [(a[1] as Vector3).lerp(b[1], k), (a[2] as Quaternion).slerp(b[2], k)]


static func _apply_path(n: Node3D, keys: Array, t: float) -> void:
	var s := _sample(keys, t)
	n.global_transform = Transform3D(Basis(s[1]), s[0])


func _board_squad() -> void:
	var seats: Array = j88.get("seats", [])
	for i in squad.members.size():
		var s: Soldier = squad.members[i]
		var seat_idx: int = SEAT_OF_PLAYER[i % 4]
		var seat: Dictionary = seats[seat_idx] if seat_idx < seats.size() else {}
		var item := int(seat.get("turret", {}).get("weapon_item", 37))
		var wd := WeaponDB.from_orig(item, true)
		if wd == null:
			wd = WeaponDB.get_weapon(&"bren")
		var w := Weapon.new(wd, false)
		w.in_mag = wd.magazine_size
		w.reserve = wd.magazine_size * 30
		var arr: Array[Weapon] = [w, null, null]
		s.weapons = arr
		s.current_slot = 0
		# 0.11.7: Sitz = eigenes MG-Stand-Objekt (Kamera CAMERAFPVx/CAMERA3RDx, Mündung SHDUMxx, Grenzen aus BARRELxx_00)
		var tur := Turret.new()
		tur.name = "Turret%d" % seat_idx
		tur.mission = self
		ju88.add_child(tur)
		tur.setup(seat_idx, seat, s)
		turrets.append(tur)
		s.mounted = tur
		s.collision_layer = 0
		s.collision_mask = 0
		s.stance = Soldier.Stance.CROUCH
		s.stance_request = Soldier.Stance.CROUCH
		s.set_meta("ju88_seat", seat)
		s._on_weapon_switched()
	_seated = true


## Schützen mit der Ju 88 mitführen (Lage des Sitz-Frames SEATxx im Modell, sonst pos_actor aus ju88.json)
func _carry_squad() -> void:
	for s in squad.members:
		if not s.alive or not s.has_meta("ju88_seat"):
			continue
		var tur = s.mounted
		if is_instance_valid(tur) and tur.seat_node:
			s.global_position = tur.seat_node.global_position + ju88.global_basis.y.normalized() * tur.seat_drop
		else:
			var seat: Dictionary = s.get_meta("ju88_seat")
			var p: Array = seat.get("pos_actor", [0, 0, 0])
			s.global_position = ju88.global_transform * Vector3(p[0], p[1] + SEAT_DROP, p[2])
		s.velocity = Vector3.ZERO


## Alle Kollisionskörper der Ju 88 und der Schützen (Geschosse/Kamera treffen das eigene Flugzeug nicht)
func own_rids() -> Array[RID]:
	if _own_rids.is_empty() and ju88:
		for b in ju88.find_children("*", "CollisionObject3D", true, false):
			_own_rids.append((b as CollisionObject3D).get_rid())
	var out: Array[RID] = _own_rids.duplicate()
	for s in squad.members:
		if is_instance_valid(s):
			out.append(s.get_rid())
			if s.model:
				for hb in s.model.orig_zones:
					if is_instance_valid(hb):
						out.append(hb.get_rid())
	return out


## MG-Stand eines Sitzes (Original: Geschützobjekt 0x4C19D0 je Sitz mit Bit 8, re_notes_ju88 §2.5).
## Schwenk HORTxx (Gier, lokal) / VERTxx (Nick) relativ zur Ruhelage im Modell, Grenzen up/down/left/right aus
## BARRELxx_00 [B Daten]; Richtung = −Z des VERT-Frames = Lauf → SHDUMxx (Mündung) [B Modell: SHDUM liegt am
## −Z-Ende des Laufmeshes]. Spieler: Mausbewegung ändert den Winkel relativ zum Flugzeug (Blick bleibt beim Kurven
## am MG). KI: nächster sichtbarer Jäger vor der Waffe ab 10 s (0x5F0E60 [B Funktion, P Verwendung]).
class Turret extends Node3D:
	var mission
	var seat_idx := 0
	var gunner: Soldier
	var seat_node: Node3D
	var hort: Node3D
	var vert: Node3D
	var barrel: Node3D
	var shdum: Node3D
	var cam_fpv: Node3D
	var cam_3rd: Node3D
	var base_h := Transform3D()
	var base_v := Transform3D()
	var lim := {"up": 0.6, "down": 0.17, "left": 0.6, "right": 0.6}
	var rate := deg_to_rad(120.0)
	var yaw := 0.0                  ## relativ zur Ruhelage (+ = links aus Sicht des Schützen)
	var pitch := 0.0
	var _wy := NAN                  ## zuletzt geschriebener Weltblick (Eingabe = Abweichung davon)
	var _wp := NAN
	var _ai_cool := 0.0
	var shots := 0                  ## abgefeuerte Schüsse (Test/HUD)
	var _mag_seen := -1
	var seat_drop := SEAT_DROP      ## Figurwurzel relativ zum Sitz-Frame entlang Flugzeug-oben [E]
	const EYE_SIT := 1.12           ## Augenhöhe über der Figurwurzel im Sitzclip „passenger“ [E]

	## Sitzhaltung des Schützen (BodyAnim: Bordschützensitz ohne Fahrzeug)
	func gunner_seat_clip() -> String:
		return "passenger"

	func setup(idx: int, seat: Dictionary, s: Soldier) -> void:
		seat_idx = idx
		gunner = s
		var ju: Node3D = get_parent()
		seat_node = ju.find_child("SEAT%02d" % idx, true, false) as Node3D
		hort = ju.find_child("HORT%02d" % idx, true, false) as Node3D
		vert = ju.find_child("VERT%02d" % idx, true, false) as Node3D
		barrel = ju.find_child("BARREL%02d_00" % idx, true, false) as Node3D
		shdum = ju.find_child("SHDUM%02d" % idx, true, false) as Node3D
		if vert:
			for n in vert.get_children():
				var nm := String(n.name).to_upper()
				if nm.begins_with("CAMERAFPV"):
					cam_fpv = n as Node3D
				elif nm.begins_with("CAMERA3RD"):
					cam_3rd = n as Node3D
		if hort:
			base_h = hort.transform
		if vert:
			base_v = vert.transform
		# 0.11.7 [E]: Sitzhöhe so, dass die Augen des sitzenden Schützen auf Höhe des Ringvisiers (CAMERAFPV) liegen –
		# vorher ragten Kopf/Arme des hockenden Schützen (fester SEAT_DROP) aus der Kanzel
		if seat_node and cam_fpv:
			var up := ju.global_basis.y.normalized()
			var dy := (cam_fpv.global_position - seat_node.global_position).dot(up)
			seat_drop = clampf(dy - EYE_SIT, -1.6, 0.2)
			print("AF6 Sitz %d: Visier %.2f m über SEAT, Figur %.2f m" % [idx, dy, seat_drop])
		var t: Dictionary = seat.get("turret", {})
		for k in ["up", "down", "left", "right"]:
			lim[k] = deg_to_rad(float(t.get("limit_%s_deg" % k, rad_to_deg(lim[k]))))
		rate = deg_to_rad(float(t.get("speed_h", 120)))
		_apply()

	func valid() -> bool:
		return vert != null and hort != null

	## Laufrichtung (Welt)
	func aim_dir() -> Vector3:
		if vert == null:
			return -get_parent().global_basis.z.normalized()
		return -vert.global_basis.z.normalized()

	func shot_origin() -> Vector3:
		if is_instance_valid(shdum):
			return shdum.global_position
		return vert.global_position + aim_dir() * 0.2 if vert else gunner.eye_position()

	## Streuung am MG-Stand: Original-Zielstreuung der Waffe (items.sav dw15, 0x545140) × Kaderwert Schießen –
	## ohne Haltungs-/Bewegungs-/Bloom-Zuschläge der Handwaffe (Waffe liegt im Lager) [E]
	func spread_deg(w: Weapon) -> float:
		if w == null:
			return 0.0
		return w.data.spread_aim * gunner.skill_k(gunner.skill_shooting, 1.5, 0.7)

	func shot_exclusions() -> Array[RID]:
		return mission.own_rids()

	## 1. Person: CAMERAFPVx am VERT-Frame (folgt dem MG); 3. Person: CAMERA3RDx (Kameraführung in CameraRig)
	func camera_point(fpv: bool) -> Vector3:
		if fpv and is_instance_valid(cam_fpv):
			return cam_fpv.global_position
		if not fpv and is_instance_valid(cam_3rd):
			return cam_3rd.global_position
		return Vector3.INF

	## Fester Kamerapunkt der 3. Person (CameraRig: kein Federarm, Blick = Laufrichtung)
	func fixed_third_camera() -> Vector3:
		return cam_3rd.global_position if is_instance_valid(cam_3rd) else Vector3.INF

	func _apply() -> void:
		if hort:
			hort.transform = Transform3D(base_h.basis * Basis(Vector3.UP, yaw), base_h.origin)
		if vert:
			vert.transform = Transform3D(base_v.basis * Basis(Vector3.RIGHT, pitch), base_v.origin)

	func _clamp() -> void:
		yaw = clampf(yaw, -lim["right"], lim["left"])
		pitch = clampf(pitch, -lim["down"], lim["up"])

	## Weltrichtung → Winkel relativ zur Ruhelage (für KI-Zielen und Tests)
	func angles_for(dir: Vector3) -> Vector2:
		var parent_b: Basis = hort.get_parent().global_basis.orthonormalized() * base_h.basis.orthonormalized()
		var l: Vector3 = parent_b.inverse() * dir.normalized()
		var y := atan2(-l.x, -l.z)
		var p := asin(clampf(l.y, -1.0, 1.0))
		return Vector2(y, p)

	func in_arc(dir: Vector3) -> bool:
		var a := angles_for(dir)
		return a.x <= lim["left"] and a.x >= -lim["right"] and a.y <= lim["up"] and a.y >= -lim["down"]

	func tick(delta: float) -> void:
		if not valid() or not is_instance_valid(gunner) or gunner.mounted != self:
			return
		if not gunner.alive:
			return
		if gunner.is_player_controlled:
			if is_finite(_wy):
				yaw += wrapf(gunner.look_yaw - _wy, -PI, PI)
				pitch += gunner.look_pitch - _wp
		else:
			_ai(delta)
		_clamp()
		_apply()
		var d := aim_dir()
		gunner.look_yaw = atan2(-d.x, -d.z)
		gunner.look_pitch = asin(clampf(d.y, -1.0, 1.0))
		_wy = gunner.look_yaw
		_wp = gunner.look_pitch
		var w := gunner.current_weapon()
		if w and _mag_seen >= 0 and w.in_mag < _mag_seen:
			shots += _mag_seen - w.in_mag
		_mag_seen = w.in_mag if w else -1

	## KI-Bordschütze: nächster lebender, sichtbarer Jäger im Schwenkbereich (≤ 400 m), Feuer bei < 3° Abweichung
	func _ai(delta: float) -> void:
		gunner.trigger = false
		if mission.flight_t < 10.0 or mission.ju88_health <= 0.0 or mission.crashing:
			return
		var best = null
		var bd := 400.0
		var o := shot_origin()
		for f in mission.fighters:
			if not is_instance_valid(f) or f.down or not f.visible:
				continue
			var dd: float = o.distance_to(f.global_position)
			if dd < bd and in_arc(f.global_position - o):
				bd = dd
				best = f
		if best == null:
			return
		var want := angles_for(best.global_position - o)
		var step := rate * delta
		yaw = move_toward(yaw, want.x, step)
		pitch = move_toward(pitch, want.y, step)
		_ai_cool -= delta
		var w := gunner.current_weapon()
		if w == null or _ai_cool > 0.0 or absf(yaw - want.x) + absf(pitch - want.y) > deg_to_rad(3.0):
			return
		# eigener Feuertakt (Waffenintervall), unabhängig vom Truppgehirn; Streuung nach Original-Waffe
		_ai_cool = maxf(w.data.shot_interval(), 0.05)
		var d: Vector3 = gunner._apply_spread(aim_dir(), spread_deg(w))
		Ballistics.fire(gunner, o, d, w.data, mission.own_rids(), gunner.team)
		Effects.muzzle_flash(o, d, Effects.flash_scale(w.data))
		OrigAudio.play_weapon(w.data, "shoot", o, null, gunner.team)
		shots += 1


# --- Skriptschnittstelle -------------------------------------------------------------

## SetActorState(ju88, n) mit n = 5/6/7: so viele Jäger mit verschiedenen zufälligen IDs 1–9
func set_actor_state(n: int) -> void:
	ju88.set_meta("actor_state", n)
	if n < 1 or n > 9 or not fighters.is_empty():
		return
	var ids := [1, 2, 3, 4, 5, 6, 7, 8, 9]
	ids.shuffle()
	var fac: Array = j88["fighters"].get("difficulty_factor", [0.7, 0.85, 1.0])
	var hp := _param("c200_fighter_health", 10000.0) * float(fac[clampi(Game.difficulty() - 1, 0, fac.size() - 1)])
	for id in ids.slice(0, n):
		for fp in j88["fighters"].get("paths", []):
			if int(fp.get("id", -1)) == id:
				_spawn_fighter(fp, hp)


func setup_junkers88(a: float, b: float) -> void:
	damage_mult = a * 0.01
	hit_div = maxf(b * 0.01, 0.01)


func _spawn_fighter(fp: Dictionary, hp: float) -> void:
	var f := Fighter.new()
	f.name = "Bf109_%d" % int(fp["id"])
	f.mission = self
	f.keys = _keys(fp.get("segments", []))
	f.windows = fp.get("fire_windows", [])
	f.health = hp
	dynamic_root.add_child(f)
	var vis: Node3D = orig.model_instance("la_bf109canyon")
	if vis:
		f.add_child(vis)
		_pose_body(vis)
	f.build_hitbox()
	f.visible = false
	fighters.append(f)


## Jäger: folgt seiner Originalbahn synchron zur Ju 88; Treffer per Ballistik (on_bullet_hit)
class Fighter extends Node3D:
	var mission
	var keys: Array = []
	var windows: Array = []
	var health := 10000.0
	var down := false
	var hits_taken := 0
	var ai_hits := 0                 ## Original +0xA0: Treffer, die nicht vom Spieler stammen, zählen nur 2× [P]
	var _fall_v := Vector3.ZERO
	var _fall_t := 0.0
	var _prev := Vector3.INF
	var vel := Vector3.ZERO
	var _body: StaticBody3D
	var _tracer_cd := 0.0

	func build_hitbox() -> void:
		var body := StaticBody3D.new()
		_body = body
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10.0, 2.5, 9.0)       # Spannweite Bf 109 ≈ 9,9 m, Länge ≈ 9 m
		cs.shape = box
		body.add_child(cs)
		add_child(body)

	func firing(t: float) -> bool:
		if down:
			return false
		for w in windows:
			if t >= float(w.get("start_s", 0)) and t <= float(w.get("end_s", 0)):
				return true
		return false

	## Originalschaden in Spieleinheiten ×10 (weapon_db: Originalschaden/10), geteilt durch SetupJunkers88(b)
	func on_bullet_hit(dmg: float, shooter: Node) -> void:
		if down or not visible:
			return
		if not (shooter is Soldier and (shooter as Soldier).is_player_controlled):
			ai_hits += 1
			if ai_hits > 2:
				return
		hits_taken += 1
		health -= dmg * 10.0 / mission.hit_div
		if health <= 0.0:
			shoot_down()

	func shoot_down() -> void:
		down = true
		mission.stats["kills"] = int(mission.stats.get("kills", 0)) + 1
		Events.say("Jäger abgeschossen!", 2.5)
		# Bewegungsrichtung = lokale +Z (re_notes_ju88 §2.2); vorher −Z → Absturz rückwärts
		_fall_v = (vel if vel.length() > 5.0 else global_basis.z.normalized() * 60.0) + Vector3.DOWN * 5.0
		if _body:
			_body.collision_layer = 0
		Effects.explosion(global_position, 3.0)

	func tick(t: float, delta: float) -> void:
		if down:
			_fall_t += delta
			_fall_v += Vector3.DOWN * 9.8 * delta
			global_position += _fall_v * delta
			rotate_object_local(Vector3.BACK, 1.5 * delta)
			if _fall_t > 6.0:
				Effects.explosion(global_position, 8.0)
				queue_free()
			return
		mission._apply_path(self, keys, t)
		if _prev.is_finite() and delta > 0.0:
			vel = (global_position - _prev) / delta
		_prev = global_position
		visible = t >= 9.0       # Original: unsichtbar bis 9 s, eingeblendet bis 11 s
		# Leuchtspuren alle 200 ms in Flugrichtung (Original 0x5F54C0: kein Schaden, nur Darstellung) [B]
		if visible and firing(t):
			_tracer_cd -= delta
			if _tracer_cd <= 0.0:
				_tracer_cd = 0.2
				mission._spawn_tracer(global_position + global_basis.z.normalized() * 4.0, global_basis.z.normalized())


func _on_tick(delta: float) -> void:
	super._on_tick(delta)
	if ju88 == null or j88.is_empty():
		return
	if crashing:
		_crash_tick(delta)
	else:
		if ju88.visible and not pause_flight:
			flight_t += delta
		_apply_path(ju88, _path, flight_t)
		if _prev_pos.is_finite() and delta > 0.0:
			_ju_vel = (ju88.global_position - _prev_pos) / delta
		_prev_pos = ju88.global_position
	if _seated:
		_carry_squad()
		for tur in turrets:
			if is_instance_valid(tur):
				tur.tick(delta)
	_tracer_tick(delta)
	var firing := 0
	for f in fighters:
		if is_instance_valid(f):
			f.tick(flight_t, delta)
			if f.firing(flight_t) and not crashing:
				firing += 1
	if firing > 0 and ju88.visible and not crashing:
		var before := ju88_health
		ju88_health -= _param("c300_attack_damage", 180.0) * damage_mult * firing * delta
		# Original-Schadensstufen bei 4000/3000/2000/1000 LP
		if int(before / 1000.0) != int(ju88_health / 1000.0) and ju88_health > 0.0:
			Events.say("Ju 88 getroffen – Zustand %d %%" % int(ju88_health / 50.0), 2.5)
		if ju88_health <= 0.0 and not finished:
			_start_crash()


## Ju 88 bei 0 LP: Absturz (Original: zufällige Animation #jushotdwn1..8, Jäger stellen das Feuer ein, Boden-
## kontakt → Explosion, dann Missionsende 0x423C70) – Nachbau: Sturzflug aus der letzten Geschwindigkeit [E]
func _start_crash() -> void:
	crashing = true
	ju88_health = 0.0
	_crash_t = 0.0
	_crash_v = _ju_vel if _ju_vel.length() > 5.0 else ju88.global_basis.z.normalized() * 45.0
	Effects.explosion(ju88.global_position + ju88.global_basis.x * 4.0, 3.0)
	Events.say("Die Ju 88 stürzt ab!", 3.0)


func _crash_tick(delta: float) -> void:
	_crash_t += delta
	_crash_v += Vector3.DOWN * 9.8 * delta
	ju88.global_position += _crash_v * delta
	ju88.rotate_object_local(Vector3.BACK, 0.6 * delta)
	if _crash_v.length() > 1.0:
		var fwd := _crash_v.normalized()
		var cur := ju88.global_basis.z.normalized()
		var axis := cur.cross(fwd)
		if axis.length() > 0.001:
			ju88.global_rotate(axis.normalized(), minf(cur.angle_to(fwd), 0.8 * delta))
	var q := PhysicsRayQueryParameters3D.create(ju88.global_position, ju88.global_position + _crash_v * delta * 2.0 + Vector3.DOWN, 1, own_rids())
	var hit := ju88.get_world_3d().direct_space_state.intersect_ray(q)
	if (not hit.is_empty() or _crash_t > 8.0) and not finished:
		Effects.explosion(ju88.global_position, 10.0)
		finish(false, "Die Ju 88 wurde abgeschossen.")


## Leuchtspur (5×5×25 skaliert im Original, 500 m/s, ≤ 500 m) – nur Darstellung
func _spawn_tracer(pos: Vector3, dir: Vector3) -> void:
	if _tracers.size() > 60:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 2.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dynamic_root.add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT), pos)
	_tracers.append([mi, dir * 500.0, 1.0])


func _tracer_tick(delta: float) -> void:
	for i in range(_tracers.size() - 1, -1, -1):
		var tr: Array = _tracers[i]
		tr[2] -= delta
		if tr[2] <= 0.0 or not is_instance_valid(tr[0]):
			if is_instance_valid(tr[0]):
				tr[0].queue_free()
			_tracers.remove_at(i)
			continue
		(tr[0] as Node3D).global_position += tr[1] * delta
