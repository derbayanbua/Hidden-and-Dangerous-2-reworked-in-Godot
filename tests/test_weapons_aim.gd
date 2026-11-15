extends "res://tests/test_aim_ballistics.gd"
## 0.11.6 Waffen-Trefferprüfung (Status docs/status/weapons_aim.md): Visier = Einschlag, gegen die Originalwerte
## (items.sav Zoom/FOV/Overlay über weapons.json, FPV-Modell + FpvAnims.sav-Zielhaltung, Visierlinie im Modell).
## Original [B] hd2.exe 0x5433B0: in der 1. Person startet das Geschoss an der Kamera (0x492790) in Blickrichtung
## (0x492880), Streuung 0x545140, Geschwindigkeit = Richtung · v0 (0x44B030), Fall 9,8 m/s² (0x44B910).
##  darstellung  alle Waffen mit Kimme/Korn bzw. Zielfernrohr × stehend/hockend/liegend: Ego-Ansicht, FOV = items.sav,
##               Overlay mittig (Absehen-Mitte = Bildmitte), Korn (Visierspitze vorn) auf der Bildmitte, Laufachse
##               parallel zur Blickachse, FPV-Modellprojektion 40°
##  treffer      Streuung/Rückstoß 0, Wand auf 10/25/50/100/200/300 m: Einschlag gegen die Originalbahn ab Kamera entlang
##               der Bildmitte (Rest = Abweichung, Fall gesondert); je Waffenklasse und alle Zielfernrohrwaffen
##  zonen        Scharfschützengewehr gegen echte Figur auf 100/200 m: Kopf/Rumpf/Bein; getroffene Zone = Zone der
##               Originalbahn (mit Fall); mit „Präzises Zielen“ = anvisierte Zone
##  eigen        kein Treffer am eigenen Körper/Helm/Ego-Beinen (1. Person, Körper an), Fadenkreuzstrahl frei
##  schrot       Flinte (items.sav 23): Originalwerte, 1 Geschoss, ungezoomt ≥ 9/10 auf 5/10/20 m, Kegelmitte = Fadenkreuz
##  beine        Ego-Beinkopie von oben (stehend/hockend/liegend): keine weggeschnittenen Innenseiten im Blick
##  mp           zwei ENet-Prozesse: Darstellung Host + Client, Client-Zielfernrohrschuss, Server bestätigt dieselbe Zone
##   tools\godot.cmd --headless -- --mission=a1_blizzard --autoplay=test_weapons_aim [--phase=all|darstellung|treffer|zonen|eigen]
##   tools\godot.cmd --headless -- --autoplay=test_weapons_aim --phase=mp       (Client: --wa_peer=1, startet der Test)

const DISTS_A := [10.0, 25.0, 50.0, 100.0, 200.0, 300.0]
## Grenzwerte (fest): Visierlinie Korn ≤ SIGHT_PX Bildpunkte (bezogen auf 720 Zeilen) von der Bildmitte, Laufachse
## ≤ AXIS_DEG; Einschlag-Rest nach Abzug des Falls ≤ 0,5 cm + 0,05 mm je m (300 m: 2 cm)
const SIGHT_PX := 3.0
const AXIS_DEG := 0.5
const FOV_TOL := 0.05
static func hit_limit(d: float) -> float:
	return 0.005 + 0.00005 * d

var report: Array[String] = []
var _mp_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mp_mode = String(Game.cli.get("phase", "all")) == "mp" or Game.cli.has("wa_peer")
	get_tree().create_timer(float(Game.cli.get("test_timeout", "1500")), true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_write_report()
		_finish())
	_run.call_deferred()


func _run() -> void:
	if _mp_mode:
		await load("res://tests/test_weapons_aim_mp.gd").new().run(self)
		_write_report()
		_finish()
		return
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	m = mission()
	check(m != null, "Mission geladen", Game.current_mission_id)
	if m == null:
		_finish()
		return
	await seconds(1.5)
	player = m.squad.leader()
	await _setup_range()
	for s in m.squad.members:            # Vorgabe: keine Läufe ohne Unverwundbarkeit
		s.max_health = 100000.0
		s.health = s.max_health
	if target:
		target.global_position += Vector3(25, 0, 0)
		target.max_health = 100000.0       # Zielfigur übersteht Fehlschüsse der Wandmessung
		target.health = target.max_health
	player.skill_shooting = 100.0
	player.stamina = 100.0
	var ph := String(Game.cli.get("phase", "all")).split(",")
	if "all" in ph or "darstellung" in ph:
		await phase_display(self, m, player, "SP")
	if "all" in ph or "treffer" in ph:
		await _phase_wall()
	if "all" in ph or "zonen" in ph:
		await _phase_zone_hits()
	if "all" in ph or "schrot" in ph:
		await _phase_shotgun()
	if "all" in ph or "eigen" in ph:
		await _phase_self()
	if "all" in ph or "beine" in ph:
		await _phase_legs()
	_write_report()
	_finish()


func _write_report() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://test_output/weapons_aim%s.txt" % ("_mp" if _mp_mode else "")), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n")


# --- Waffenliste aus dem Original (weapons.json = items.sav Verhalten 5 + FPV-Modell) -----------------------------------

## [[item, WeaponData, zoom{scope,fov_deg}, Haltesatz]] aller Handwaffen mit Kimme/Korn oder Zielfernrohr und FPV-Modell
static func aim_weapons() -> Array:
	var out := []
	var items: Dictionary = OrigWeapons.table().get("items", {})
	var keys := items.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		var it: Dictionary = items[k]
		var st := String(it.get("set", ""))
		if not st in ["rifle", "smg", "mg", "pistol"] or String(it.get("fpv", "")) == "":
			continue
		var wd := WeaponDB.from_orig(int(k))
		if wd == null or wd.action in [WeaponData.Action.THROWN, WeaponData.Action.ROCKET, WeaponData.Action.MELEE]:
			continue
		var z := OrigWeapons.zoom(wd)
		if z.is_empty():
			continue
		out.append([int(k), wd, z, st])
	return out


static func is_scope(z: Dictionary) -> bool:
	var sc := int(z.get("scope", 5))
	return sc >= 0 and sc <= 3


# --- Messgrößen der Darstellung --------------------------------------------------------------------------------------

## Korn (oberster Punkt der vorderen 7 cm der FPV-Waffe) in Bildpunkten (720 Zeilen) von der Bildmitte, Laufachse
## (shdum → blsdum, Original-Dummies des FPV-Modells) gegen die Blickachse in Grad. {} ohne FPV-Waffe.
static func sight_measure(rig) -> Dictionary:
	var vmw: Node3D = rig.get("_vm_weapon")
	if not is_instance_valid(vmw):
		return {}
	var gun := vmw.find_child("fpv_weapon", true, false) as Node3D
	if gun == null:
		return {}
	var cam: Camera3D = rig.camera
	var inv := cam.global_transform.affine_inverse()
	var pts: Array[Vector3] = []
	for mi in [gun] + gun.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D) or not (mi as MeshInstance3D).is_visible_in_tree() or (mi as Node).name == "flash":
			continue
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var xf: Transform3D = inv * (mi as MeshInstance3D).global_transform
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(xf * v)
	if pts.is_empty():
		return {}
	var zmin := 0.0
	for p in pts:
		zmin = minf(zmin, p.z)
	var top := -INF
	for p in pts:
		if p.z < zmin + 0.07:
			top = maxf(top, p.y)
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for p in pts:
		if p.z < zmin + 0.07 and p.y > top - 0.003:
			sx += p.x
			sz += p.z
			n += 1
	sx /= n
	sz /= n
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var px := Vector2(sx / -sz / t * 360.0, -(top / -sz) / t * 360.0)
	var axis := INF
	var a := vmw.find_child("shdum", true, false) as Node3D
	var b := vmw.find_child("blsdum", true, false) as Node3D
	if a and b:
		var d := (inv.basis * (b.global_position - a.global_position)).normalized()
		axis = rad_to_deg(d.angle_to(Vector3.FORWARD))
	return {"px": px, "axis": axis, "z": sz}


## Overlay-Mitte (HUD, Absehen) gegen die Bildmitte in Bildpunkten der Oberfläche
static func overlay_offset(hud) -> Vector2:
	if hud == null or hud.get("_binoc_mask") == null:
		return Vector2.INF
	var mk: Control = hud.get("_binoc_mask")
	if not mk.is_visible_in_tree():
		return Vector2.INF
	var vp := mk.get_viewport().get_visible_rect().size
	var c := mk.get_global_rect().get_center()
	return c - vp * 0.5


## Darstellung je Waffe/Haltung (gemeinsam für SP und MP). t = Testknoten (check/seconds/frames), mm = Mission, s = Soldat
static func phase_display(t, mm, s: Soldier, tag: String, only: Array = []) -> Dictionary:
	var rig = mm.rig
	var hud = mm.get("hud")
	var out := {}
	t.report.append("%s Darstellung: Waffe | Haltung | Zoom/Overlay | FOV soll/ist | Korn dx,dy px (720 Z.) | Laufachse ° | Overlay-Mitte px" % tag)
	var bad: Array[String] = []
	var n := 0
	var ws := aim_weapons()
	for row in ws:
		var item: int = row[0]
		if not only.is_empty() and not only.has(item):
			continue
		var wd: WeaponData = row[1]
		var z: Dictionary = row[2]
		var pistol: bool = row[3] == "pistol"
		s.equip(["" if pistol else String(wd.id), String(wd.id) if pistol else "colt", "no36", "", "knife"])
		s.select_slot(WeaponData.Slot.SIDEARM if pistol else WeaponData.Slot.PRIMARY)
		for st in [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]:
			if not s.stance_allows_fire(wd) and 2 - int(st) > Soldier.fire_stance_max(wd):
				continue
			s.stance_request = st
			Input.action_release("aim")
			for i in 90:
				await t.frames(1)
				if s.stance == st and not s.current_weapon().is_reloading():
					break
			await t.seconds(0.6)        # Zoom ganz aus (0,4 s), Pistolenkorrektur wird je Zielvorgang neu gemessen
			Input.action_press("aim")
			for i in 400:
				await t.frames(1)
				if rig.zoomed() and float(rig.get("_zoom_t")) >= 1.0 and (is_scope(z) or (bool(z.get("vorgabe", false)) and bool(rig.get("_vm_fixed")))
						or (bool(rig.get("_vm_hold")) and not rig.get("_vm_anim").is_playing())):
					break
			await t.frames(40)
			n += 1
			var want_fov := OrigWeapons.vfov(float(z["fov_deg"]))
			var fov_ok: bool = absf(rig.camera.fov - want_fov) < FOV_TOL
			var line := "  %-3d %-18s %s | %s | %.2f/%.2f" % [item, wd.display_name.left(18), ["steh", "hock", "lieg"][int(st)],
				("ZF %d" % int(z["scope"])) if is_scope(z) else "Kimme/Korn", want_fov, rig.camera.fov]
			var ok: bool = rig.fpv_active and rig.zoomed() and fov_ok and s.stance == st
			if is_scope(z):
				var ov: Vector2 = overlay_offset(hud)
				var ov_ok: bool = rig.optic_overlay() == int(z["scope"]) and ov.is_finite() and ov.length() <= 0.75 and not rig.get("_viewmodel").visible
				line += " | – | – | %s" % ("%.2f,%.2f" % [ov.x, ov.y] if ov.is_finite() else "kein Overlay")
				ok = ok and ov_ok
			else:
				var sm := sight_measure(rig)
				var vmw: Node3D = rig.get("_vm_weapon")
				var vm: Node3D = rig.get("_viewmodel")
				# FPV-Modell mit eigenem Sichtfeld 40° (0x492130) unter der Weltkamera
				var want_s := tan(deg_to_rad(rig.camera.fov) * 0.5) / tan(deg_to_rad(OrigWeapons.vfov(CameraRig.FPV_MODEL_ZOOM_FOV_H)) * 0.5)
				var s_ok: bool = vm != null and absf(vm.scale.x - want_s) < 0.002 and absf(vm.scale.y - want_s) < 0.002 and is_equal_approx(vm.scale.z, 1.0)
				if sm.is_empty() or not is_instance_valid(vmw):
					line += " | kein FPV-Modell"
					ok = false
				else:
					var px: Vector2 = sm["px"]
					var vorgabe := bool(z.get("vorgabe", false))
					# Original-Zielhaltung (FpvAnims.sav „…Aim“, letztes Bild) unverändert: Waffenwurzel ohne Versatz/Drehung;
					# [D] Pistolen: Korn auf der Bildmitte, Laufachse parallel
					var pose_ok: bool = vorgabe or (vmw.transform.origin.length() < 0.001 and vmw.transform.basis.is_equal_approx(Basis()))
					var sight_ok: bool = not vorgabe or (absf(px.x) <= SIGHT_PX and absf(px.y) <= SIGHT_PX and float(sm["axis"]) <= AXIS_DEG)
					line += " | %+.2f,%+.2f | %.2f | – | %s%s" % [px.x, px.y, float(sm["axis"]), "[D] Pistole" if vorgabe else "Original-Zielhaltung",
						"" if s_ok else " Modell-FOV falsch %.3f/%.3f" % [vm.scale.x, want_s]]
					ok = ok and pose_ok and sight_ok and s_ok and rig.get("_viewmodel").visible
					out["%d/%d" % [item, int(st)]] = px
			t.report.append(line + ("" if ok else "   <-- FEHLER"))
			if not ok:
				bad.append("%d %s" % [item, ["steh", "hock", "lieg"][int(st)]])
		Input.action_release("aim")
		s.stance_request = Soldier.Stance.STAND
		await t.seconds(0.3)
	t.check(n >= (20 if only.is_empty() else only.size()) and bad.is_empty(), "%s Darstellung: %d Fälle (Kimme/Korn- und Zielfernrohrwaffen × Haltung): FOV = items.sav, Absehen mittig, Original-Zielhaltung bzw. Pistolen-Korn mittig (≤ %.0f px, Achse ≤ %.1f°), Modell-FOV 40°" % [tag, n, SIGHT_PX, AXIS_DEG],
		"%d fehlerhaft: %s" % [bad.size(), ", ".join(bad.slice(0, 12))])
	return out


# --- Treffer: Einschlag gegen Originalbahn ab Kamera entlang der Bildmitte -------------------------------------------

## Originalbahn (hd2.exe: Ursprung Kamera, Richtung Bildmitte, v0, 9,8 m/s², ohne Widerstand bei Originalwaffen) bis
## zur Ebene z = plane_z (Wand quer zur Blickachse −Z)
static func orig_path_point(origin: Vector3, dir: Vector3, wd: WeaponData, range_h: float) -> Vector3:
	return Ballistics.trajectory_point(origin, dir * wd.muzzle_velocity, Ballistics.drag_of(wd), range_h)


func _wall_classes() -> Array:
	var rows := [["Pistole", "colt", WeaponData.Slot.SIDEARM], ["MP", "mp40", WeaponData.Slot.PRIMARY],
		["Gewehr", "kar98k", WeaponData.Slot.PRIMARY], ["MG", "o_28", WeaponData.Slot.PRIMARY]]
	for r in aim_weapons():
		if is_scope(r[2]):
			rows.append(["Zielfernrohr", String((r[1] as WeaponData).id), WeaponData.Slot.PRIMARY])
	return rows


func _phase_wall() -> void:
	var impacts: Array = []
	var cb := func(pos: Vector3, c: Object, sh: Node):
		if sh == player:
			impacts.append([pos, c])
	Ballistics.projectile_impact.connect(cb)
	var shot_cam := []
	var sc_cb := func(_w): shot_cam.append(m.rig.camera.global_transform)
	player.shot_fired.connect(sc_cb)
	report.append("Treffer (Streuung/Rückstoß 0, Luft angehalten): Abweichung Einschlag ↔ Originalbahn (cm) / Fall unter der Visierlinie (cm) je %s m" % str(DISTS_A))
	var bad: Array[String] = []
	for c in _wall_classes():
		for st in [Soldier.Stance.STAND, Soldier.Stance.PRONE]:
			var prim: String = c[1] if c[2] == WeaponData.Slot.PRIMARY else "kar98k"
			var side: String = c[1] if c[2] == WeaponData.Slot.SIDEARM else "colt"
			player.equip([prim, side, "no36", "", "knife"])
			player.select_slot(c[2])
			player.stance_request = st
			await seconds(1.4)
			var w := player.current_weapon()
			if not player.stance_allows_fire(w.data):
				continue
			_neutral(w)
			Input.action_press("aim")
			m.rig.breath_force = 1
			await seconds(1.0)
			var cells: Array[String] = []
			var worst := 0.0
			var miss := 0
			for dist in DISTS_A:
				_wall_at(dist)
				m.rig.breath = 1.0
				m.rig.breath_winded = false
				var eye := player.eye_position()
				await _aim_at(Vector3(eye.x + 0.2, eye.y + 0.1, eye.z - dist))
				for i in 150:
					if w.cooldown <= 0.0 and not w.is_reloading() and m.rig.zoomed():
						break
					await frames(1)
				w.in_mag = w.data.magazine_size
				await frames(3)
				impacts.clear()
				shot_cam.clear()
				await tap("fire")
				for i in 120:
					if not impacts.is_empty():
						break
					await frames(1)
				# Bildmitte im Schussmoment (Kimme/Korn wackelt auch bei angehaltener Luft, 0x466970)
				var o: Vector3 = (shot_cam[0] as Transform3D).origin if not shot_cam.is_empty() else Vector3.INF
				var dir: Vector3 = -(shot_cam[0] as Transform3D).basis.z if not shot_cam.is_empty() else Vector3.FORWARD
				if impacts.is_empty() or shot_cam.is_empty():
					miss += 1
					cells.append("-")
					continue
				var imp: Vector3 = impacts[0][0]
				var rh := Vector2(imp.x - o.x, imp.z - o.z).length()
				var pred := orig_path_point(o, dir, w.data, rh)
				var sight := o + dir * (rh / Vector2(dir.x, dir.z).length())
				var e := imp.distance_to(pred)
				worst = maxf(worst, e / hit_limit(dist))
				cells.append("%.1f/%.1f" % [e * 100.0, (sight.y - pred.y) * 100.0])
			Input.action_release("aim")
			m.rig.breath_force = -1
			var ok := miss == 0 and worst <= 1.0
			report.append("  %-12s %-10s %s  %s%s" % [c[0], String(c[1]), ["steh", "hock", "lieg"][int(st)], "  ".join(cells), "" if ok else "   <-- FEHLER"])
			if not ok:
				bad.append("%s %s" % [c[1], ["steh", "hock", "lieg"][int(st)]])
	player.shot_fired.disconnect(sc_cb)
	check(bad.is_empty(), "Treffer: Einschlag = Originalbahn ab Kamera/Bildmitte (Rest ≤ 0,5 cm + 0,05 mm/m) 10–300 m, alle Klassen und Zielfernrohre",
		", ".join(bad))
	# Mit Wackeln (Luft nicht angehalten, Original 0x466970): Bildmitte im Moment des Schusses (Kamera beim Signal
	# shot_fired = gezeigtes Bild) gegen Einschlag
	var bad2: Array[String] = []
	var cam_at := []
	var shot_cb := func(_w): cam_at.append(m.rig.camera.global_transform)
	player.shot_fired.connect(shot_cb)
	for sid in ["o_17", "o_13", "kar98k"]:
		player.equip([sid, "colt", "no36", "", "knife"])
		player.select_slot(WeaponData.Slot.PRIMARY)
		player.stance_request = Soldier.Stance.STAND
		player.skill_shooting = 40.0          # stärkeres Wackeln (2 − Können)
		await seconds(1.4)
		var w := player.current_weapon()
		_neutral(w)
		Input.action_press("aim")
		m.rig.breath_force = 0
		await seconds(1.0)
		var cells: Array[String] = []
		for dist in [100.0, 200.0, 300.0]:
			_wall_at(dist)
			var eye := player.eye_position()
			await _aim_at(Vector3(eye.x, eye.y, eye.z - dist))
			for k in 3:
				for i in 150:
					if w.cooldown <= 0.0 and not w.is_reloading() and m.rig.zoomed():
						break
					await frames(1)
				w.in_mag = w.data.magazine_size
				await frames(7 + 11 * k)
				impacts.clear()
				cam_at.clear()
				await tap("fire")
				for i in 120:
					if not impacts.is_empty():
						break
					await frames(1)
				if impacts.is_empty() or cam_at.is_empty():
					cells.append("-")
					bad2.append("%s %.0f m kein Einschlag" % [sid, dist])
					continue
				var cxf: Transform3D = cam_at[0]
				var o := cxf.origin
				var dir := -cxf.basis.z
				var imp: Vector3 = impacts[0][0]
				var pred := orig_path_point(o, dir, w.data, Vector2(imp.x - o.x, imp.z - o.z).length())
				var e := imp.distance_to(pred)
				cells.append("%.1f" % (e * 100.0))
				if e > hit_limit(dist):
					bad2.append("%s %.0f m %.1f cm" % [sid, dist, e * 100.0])
		Input.action_release("aim")
		m.rig.breath_force = -1
		report.append("  Wackeln %-8s Rest (cm) 100/200/300 m je 3 Schüsse: %s" % [sid, " ".join(cells)])
	player.skill_shooting = 100.0
	player.shot_fired.disconnect(shot_cb)
	Ballistics.projectile_impact.disconnect(cb)
	check(bad2.is_empty(), "Treffer mit Wackeln (Zielfernrohr/Kimme, Können 40): Einschlag = Bahn der im Schussmoment gezeigten Bildmitte",
		", ".join(bad2))


# --- Zonen an echter Figur (Scharfschützengewehr) -------------------------------------------------------------------

## Zone, die die Originalbahn (Kamera, Richtung, v0, Fall) an der Figur trifft – unabhängig vom Spielcode berechnet
static func predict_zone(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, wd: WeaponData, exclude: Array[RID]) -> StringName:
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var pos := origin
	var v := dir * wd.muzzle_velocity
	var drag := Ballistics.drag_of(wd)
	for i in int(Ballistics.MAX_LIFETIME / dt):
		var sp := v.length()
		v -= v * (drag * sp * dt)
		v.y -= Ballistics.GRAVITY * dt
		var nx := pos + v * dt
		var q := PhysicsRayQueryParameters3D.create(pos, nx, Ballistics.MASK, exclude)
		q.collide_with_areas = true
		var h := space.intersect_ray(q)
		if not h.is_empty():
			if h.collider is Hitbox:
				var hb := Ballistics._priority_zone(space, h.collider, h.position, v.normalized())
				return &"head" if hb.zone == Helmet.ZONE else hb.zone
			return &"-"
		pos = nx
	return &"-"


var _tplat: StaticBody3D


func _target_at(dist: float) -> void:
	if _tplat == null:
		_tplat = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(4, 1, 4)
		cs.shape = bx
		_tplat.add_child(cs)
		m.add_child(_tplat)
	var p := player.global_position + Vector3(0, 0, -dist)
	_tplat.global_position = p - Vector3(0, 0.7, 0)
	target.global_position = p
	target.look_yaw = 0.0          # blickt nach Süden zum Schützen (+Z)
	target.velocity = Vector3.ZERO
	target.set_physics_process(true)


func _phase_zone_hits() -> void:
	if target == null:
		check(false, "Zonen: Zielfigur vorhanden")
		return
	if wall:
		wall.global_position += Vector3(0, -500, 0)
	player.stance_request = Soldier.Stance.STAND
	player.global_position = plat.global_position + Vector3(0, 0.7, 8.0)
	player.velocity = Vector3.ZERO
	player.look_pitch = 0.0
	player.look_yaw = 0.0
	await seconds(1.0)
	var got := []
	var cb := func(_amount: float, zone: StringName): got.append(zone)
	target.damaged.connect(cb)
	report.append("Zonen (Scharfschützengewehr, Streuung 0, Luft angehalten): anvisiert → Originalbahn → getroffen")
	var bad: Array[String] = []
	var bad_p: Array[String] = []
	for sid in ["o_17", "o_13"]:
		player.equip([sid, "colt", "no36", "", "knife"])
		player.select_slot(WeaponData.Slot.PRIMARY)
		player.stance_request = Soldier.Stance.STAND
		await seconds(1.4)
		var w := player.current_weapon()
		_neutral(w)
		Input.action_press("aim")
		m.rig.breath_force = 1
		await seconds(1.0)
		for mode in [0, 1]:
			Ballistics.force_compensation = mode
			for dist in [100.0, 200.0]:
				_target_at(dist)
				for zone in [&"head", &"torso", &"leg"]:
					target.max_health = 100000.0
					target.health = 100000.0
					for i in 40:
						_hold_target_at()
						await frames(1)
					var hb := _zone_box(zone)
					if zone == &"leg":
						hb = _leg_box()
					m.rig.breath = 1.0
					m.rig.breath_winded = false
					await _aim_at((hb.get_child(0) as Node3D).global_position)
					for i in 150:
						if w.cooldown <= 0.0 and not w.is_reloading() and m.rig.zoomed():
							break
						_hold_target_at()
						await frames(1)
					w.in_mag = w.data.magazine_size
					await frames(2)
					var cam := m.rig.camera
					var pz := predict_zone(cam.get_world_3d().direct_space_state, cam.global_position, -cam.global_basis.z, w.data, player.exclude_rids())
					got.clear()
					await tap("fire")
					for i in 60:
						if not got.is_empty():
							break
						_hold_target_at()
						await frames(1)
					var hz: StringName = got[0] if not got.is_empty() else &"-"
					var want: StringName = zone if mode == 1 else pz
					var ok: bool = hz == want and pz != &"-"
					report.append("  %-5s %s %3.0f m %-5s → Bahn %-5s → Treffer %-5s%s" % [sid, "präzise" if mode == 1 else "original", dist, zone, pz, hz,
						"" if ok else "   <-- FEHLER (Ziel %s lebt %s, Kamera %s)" % [str(target.global_position.round()), str(target.alive), str(cam.global_position.round())]])
					if not ok:
						(bad_p if mode == 1 else bad).append("%s %.0f m %s→%s (Bahn %s)" % [sid, dist, zone, hz, pz])
		Ballistics.force_compensation = -1
		Input.action_release("aim")
		m.rig.breath_force = -1
	target.damaged.disconnect(cb)
	check(bad.is_empty(), "Zonen Original (Fall): getroffene Zone = Zone der Originalbahn, Kopf/Rumpf/Bein auf 100/200 m", ", ".join(bad))
	check(bad_p.is_empty(), "Zonen Präzises Zielen: getroffene Zone = anvisierte Zone, Kopf/Rumpf/Bein auf 100/200 m", ", ".join(bad_p))


func _hold_target_at() -> void:
	target.move_input = Vector3.ZERO
	target.velocity = Vector3.ZERO
	target.trigger = false
	target.aiming = false


## Bein: untere Beinkiste (p/t = Unterschenkel), sichtbar von vorn
func _leg_box() -> Hitbox:
	var best: Hitbox = null
	for hb in target.model.orig_zones:
		if hb.zone != &"leg":
			continue
		var y := (hb.get_child(0) as Node3D).global_position.y
		if best == null or y > (best.get_child(0) as Node3D).global_position.y:
			best = hb        # Oberschenkel (größer, nicht vom Rumpf verdeckt)
	return best


# --- Schrotflinte (Side by Side, items.sav 23) ----------------------------------------------------------------------

## Original [B]: ein Geschoss je Schuss (0x7D4FD0 Typ 3 → 0x451100, keine Schrotschleife), Streuung nur dw15 · 0,01
## (0x545140, kein Hüft-/Zielzweig), Schaden 1000 zotti, Abfall ab 35 m mit 35 zotti/m (0x44B3B0), v0 500 m/s.
func _phase_shotgun() -> void:
	if target == null:
		return
	if wall:
		wall.global_position += Vector3(0, -500, 0)
	var o: Dictionary = WeaponDB._orig_row(23)
	var wd := WeaponDB.from_orig(23)
	check(wd != null and int(o.get("magazine", 0)) == 2 and absf(wd.damage - float(o.get("damage", 0)) / 10.0) < 0.01
		and absf(wd.muzzle_velocity - float(o.get("muzzle_velocity", 0))) < 0.01 and absf(wd.falloff_start - float(o.get("dist_param", 0))) < 0.01
		and absf(wd.falloff_per_m - float(o.get("recoil_spread", 0)) / 10.0) < 0.01,
		"Schrot: Werte = items.sav 23 (Schaden 100, v0 500, Abfall ab 35 m 3,5/m, 2 Schuss)", str(o))
	check(absf(wd.spread_hip - wd.spread_aim) < 1e-4 and absf(wd.spread_aim - rad_to_deg(atan(float(o.get("aim_spread", 0)) * 0.01))) < 0.002,
		"Schrot: Streuung ungezoomt = gezoomt = dw15·0,01 rad (Original ohne Hüftzweig)", "Hüfte %.3f° Ziel %.3f°" % [wd.spread_hip, wd.spread_aim])
	if m.rig.mode != CameraRig.Mode.THIRD:
		m.rig.toggle_mode()
	player.equip(["o_23", "colt", "no36", "", "knife"])
	player.select_slot(WeaponData.Slot.PRIMARY)
	player.stance_request = Soldier.Stance.STAND
	player.global_position = plat.global_position + Vector3(0, 0.7, 8.0)
	player.look_pitch = 0.0
	player.skill_shooting = 100.0
	player.orig_recoil_off = false      # Original-Rückstoß 0x5454D0 bleibt an (Treffer wie im Spiel)
	await seconds(1.4)
	var w := player.current_weapon()
	var got := []
	var cb := func(_a: float, zone: StringName): got.append(zone)
	target.damaged.connect(cb)
	seed(2311)
	var rows: Array[String] = []
	var bad: Array[String] = []
	for dist in [5.0, 10.0, 20.0]:
		_target_at(dist)
		var hits := 0
		var n := 10
		for k in n:
			target.health = 100000.0
			target.max_health = 100000.0
			for i in 20:
				_hold_target_at()
				await frames(1)
			await _aim_at((_zone_box(&"torso").get_child(0) as Node3D).global_position)
			for i in 150:
				if w.cooldown <= 0.0 and not w.is_reloading():
					break
				await frames(1)
			w.in_mag = w.data.magazine_size
			got.clear()
			var s0 := Ballistics.shots_fired
			await tap("fire")
			for i in 30:
				if not got.is_empty():
					break
				await frames(1)
			if Ballistics.shots_fired - s0 != 1:
				bad.append("%.0f m %d Geschosse" % [dist, Ballistics.shots_fired - s0])
			if not got.is_empty():
				hits += 1
		rows.append("%.0f m %d/%d" % [dist, hits, n])
		if hits < 9:
			bad.append("%.0f m nur %d/%d" % [dist, hits, n])
	target.damaged.disconnect(cb)
	report.append("Schrot ungezoomt (3. Person, Können 100, Original-Rückstoß, Rumpf): " + ", ".join(rows))
	check(bad.is_empty(), "Schrot ungezoomt: ein Geschoss je Schuss, ≥ 9/10 Rumpftreffer auf 5/10/20 m", ", ".join(rows + bad))
	# Mitte des Streukegels = Fadenkreuz: 40 Schüsse auf eine Wand in 10 m, mittlerer Einschlag gegen Fadenkreuzpunkt
	_target_at(60.0)
	target.global_position += Vector3(30, 0, 0)
	_wall_at(10.0)
	var impacts: Array = []
	var icb := func(pos: Vector3, _c: Object, sh: Node):
		if sh == player:
			impacts.append(pos)
	Ballistics.projectile_impact.connect(icb)
	var eye := player.eye_position()
	player.orig_recoil_off = true       # Kegelmitte ohne Rückstoß (der hebt nur, 0x5454D0)
	var aim_pt := Vector3(eye.x, eye.y, eye.z - 10.0)
	var wants := []
	var w_cb := func(_w): wants.append(m.rig.crosshair_point())
	player.shot_fired.connect(w_cb)
	var sum := Vector3.ZERO
	var nn := 0
	for k in 40:
		await _aim_at(aim_pt)
		for i in 150:
			if w.cooldown <= 0.0 and not w.is_reloading():
				break
			await frames(1)
		w.in_mag = w.data.magazine_size
		impacts.clear()
		wants.clear()
		await tap("fire")
		for i in 30:
			if not impacts.is_empty():
				break
			await frames(1)
		if not impacts.is_empty() and not wants.is_empty():
			sum += (impacts[0] as Vector3) - (wants[0] as Vector3)
			nn += 1
	player.shot_fired.disconnect(w_cb)
	Ballistics.projectile_impact.disconnect(icb)
	player.orig_recoil_off = false
	var mean := sum / maxf(nn, 1)
	report.append("Schrot Kegelmitte 10 m: %d Einschläge, Mittel − Fadenkreuz %s cm" % [nn, str((mean * 100.0).round())])
	check(nn == 40 and Vector2(mean.x, mean.y).length() < 0.03, "Schrot: Mitte des Streukegels = Fadenkreuz im Schussmoment (3. Person, 10 m, ≤ 3 cm)",
		"%d Einschläge, Abweichung %.1f cm" % [nn, Vector2(mean.x, mean.y).length() * 100.0])
	player.skill_shooting = 100.0


# --- Ego-Beine von oben ----------------------------------------------------------------------------------------------

## Blick senkrecht nach unten (größte Neigung) je Haltung: Strahlen durch die Bildmitte (±15 % der Bildhöhe) gegen die
## gebackenen Beinkopien (aktuelle Skelettpose). Durchsichtig = erste getroffene Fläche ist eine Rückseite und das
## Material schneidet Rückseiten weg. Mit --shot=1 (Fenster) Bilder test_output/fpv_legs/<haltung>.png
func _phase_legs() -> void:
	var keep := Settings.fpv_body
	Settings.fpv_body = true
	if m.rig.mode != CameraRig.Mode.FIRST:
		m.rig.toggle_mode()
	player.equip(["kar98k", "colt", "no36", "", "knife"])
	player.select_slot(WeaponData.Slot.PRIMARY)
	player.global_position = plat.global_position + Vector3(0, 0.7, 8.0)
	var shots := bool(int(Game.cli.get("shot", "0"))) and DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/fpv_legs"))
	var bad: Array[String] = []
	for st in [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]:
		player.stance_request = st
		await seconds(1.5)
		player.look_pitch = -m.rig.pitch_limit()
		await seconds(0.6)
		var legs: Array[MeshInstance3D] = player.model.fpv_leg_meshes()
		var cam := m.rig.camera
		var tris: Array = []       # [a, b, c, cull_back]
		for mi in legs:
			if not mi.is_visible_in_tree():
				continue
			# Pose auf der CPU skinnen (kopflos gibt es keine Skin-Referenz zum Backen): Skelett · Knochen · Bindepose
			var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			var skin := mi.skin
			if skel == null or skin == null:
				bad.append("%s ohne Skelett/Skin" % mi.name)
				continue
			var mats: Array[Transform3D] = []
			for bi in skin.get_bind_count():
				var bone := skin.get_bind_bone(bi)
				if bone < 0:
					bone = skel.find_bone(skin.get_bind_name(bi))
				mats.append(skel.global_transform * skel.get_bone_global_pose(maxi(bone, 0)) * skin.get_bind_pose(bi))
			for si in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(si)
				var cull_back: bool = mat is BaseMaterial3D and (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK
				var arr := mi.mesh.surface_get_arrays(si)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var per := bones.size() / maxi(v.size(), 1)
				var posed := PackedVector3Array()
				posed.resize(v.size())
				var used := {}
				for ti in idx:
					used[ti] = true
				for vi in used:
					var p := Vector3.ZERO
					var ws := 0.0
					for k in per:
						var wgt := wts[vi * per + k]
						if wgt > 0.0:
							p += (mats[bones[vi * per + k]] * v[vi]) * wgt
							ws += wgt
					posed[vi] = p / maxf(ws, 1e-6)
				for ti in range(0, idx.size() - 2, 3):
					tris.append([posed[idx[ti]], posed[idx[ti + 1]], posed[idx[ti + 2]], cull_back])
		var rays := 0
		var leg_rays := 0
		var see := 0
		var inner := 0
		var t := tan(deg_to_rad(cam.fov) * 0.5)
		for gy in range(-6, 7):
			for gx in range(-6, 7):
				var d := (cam.global_basis * Vector3(gx / 6.0 * 0.3 * t, gy / 6.0 * 0.3 * t, -1.0)).normalized()
				var o := cam.global_position
				rays += 1
				var best := INF
				var back := false
				var back_geom := false
				for tr in tris:
					var hp = Geometry3D.ray_intersects_triangle(o, d, tr[0], tr[1], tr[2])
					if hp == null:
						continue
					var dd: float = o.distance_to(hp)
					if dd < best:
						best = dd
						var nrm: Vector3 = ((tr[1] as Vector3) - tr[0]).cross((tr[2] as Vector3) - tr[0])
						# Godot: Vorderseite = im Uhrzeigersinn → Normale (b−a)×(c−a) zeigt nach hinten
						back_geom = nrm.dot(d) < 0.0
						back = back_geom and tr[3]
				if best < INF:
					leg_rays += 1
					if back:
						see += 1
					if back_geom:
						inner += 1
		var nm: String = ["stehend", "hockend", "liegend"][int(st)]
		report.append("Ego-Beine %s, Blick %.0f°: %d Dreiecke, %d/%d Strahlen auf den Beinen, davon zuerst Innenseite (offener Schnitt) %d, durchsichtig (Innenseite weggeschnitten) %d" % [nm,
			rad_to_deg(player.look_pitch), tris.size(), leg_rays, rays, inner, see])
		if tris.is_empty() or see > 0:
			bad.append("%s %d/%d durchsichtig" % [nm, see, leg_rays])
		if shots:
			await seconds(0.5)
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/fpv_legs/%s.png" % nm))
	player.look_pitch = 0.0
	player.stance_request = Soldier.Stance.STAND
	Settings.fpv_body = keep
	check(bad.is_empty(), "Ego-Beine von oben (stehend/hockend/liegend, größte Neigung): keine durchsichtigen Stellen", ", ".join(bad))


# --- Eigener Körper -----------------------------------------------------------------------------------------------

func _phase_self() -> void:
	if wall:
		wall.global_position += Vector3(0, -500, 0)
	var keep_body := Settings.fpv_body
	Settings.fpv_body = true
	var impacts: Array = []
	var cb := func(pos: Vector3, c: Object, sh: Node):
		if sh == player:
			impacts.append([pos, c])
	Ballistics.projectile_impact.connect(cb)
	var own: Array[String] = []
	var n := 0
	if m.rig.mode != CameraRig.Mode.FIRST:
		m.rig.toggle_mode()
	for wid in ["kar98k", "o_17", "mp40", "o_28"]:
		player.equip([wid, "colt", "no36", "", "knife"])
		player.select_slot(WeaponData.Slot.PRIMARY)
		for st in [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]:
			player.stance_request = st
			await seconds(1.4)
			var w := player.current_weapon()
			if not player.stance_allows_fire(w.data):
				continue
			_neutral(w)
			for aim in [false, true]:
				if aim:
					Input.action_press("aim")
					await seconds(0.8)
				for pitch in [-1.15, -0.6, -0.25, 0.0]:
					player.look_pitch = clampf(pitch, -m.rig.pitch_limit(), m.rig.pitch_limit())
					await frames(6)
					for i in 150:
						if w.cooldown <= 0.0 and not w.is_reloading():
							break
						await frames(1)
					w.in_mag = w.data.magazine_size
					var cp: Vector3 = m.rig.crosshair_point(800.0)
					impacts.clear()
					await tap("fire")
					for i in 30:
						if not impacts.is_empty():
							break
						await frames(1)
					n += 1
					for im in impacts:
						var col: Object = im[1]
						var mine: bool = col == player or (col is Hitbox and (col as Hitbox).soldier == player) \
							or (col is Node and player.is_ancestor_of(col))
						if mine:
							own.append("%s %s Neigung %.2f %s" % [wid, ["steh", "hock", "lieg"][int(st)], pitch, str(col)])
					if m.rig.camera.global_position.distance_to(cp) < 0.3:
						own.append("%s Fadenkreuzstrahl endet am eigenen Körper" % wid)
				if aim:
					Input.action_release("aim")
					await seconds(0.4)
	player.stance_request = Soldier.Stance.STAND
	player.look_pitch = 0.0
	Ballistics.projectile_impact.disconnect(cb)
	Settings.fpv_body = keep_body
	report.append("Eigen: %d Schüsse (1. Person, Körper/Ego-Beine an, steh/hock/lieg, Hüfte/Zielen, Blick bis −66°), eigene Treffer: %s" % [n, str(own)])
	check(n > 40 and own.is_empty(), "Eigen: kein Treffer am eigenen Körper/Helm/Waffe/Ego-Beinen, Fadenkreuzstrahl frei", "%d Schüsse %s" % [n, str(own.slice(0, 5))])
