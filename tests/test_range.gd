extends "res://tests/test_weapons_aim.gd"
## 0.11.7 Schießstand (Karte src/missions/test_range.gd, Status docs/status/test_range.md) – OPTIONALE Prüfung bei
## Balance-Änderungen an Waffen, nicht in der Standardgruppe von tools\run_tests.ps1 (Gruppe „range“, nur mit -Only).
##  zonen   alle Handwaffen mit Kimme/Korn bzw. Zielfernrohr (weapons.json/items.sav, wie test_weapons_aim) auf 3/7/10/25/50 m,
##          Gewehre/Karabiner (Haltesatz „rifle“) und Zielfernrohrwaffen zusätzlich 100/200/300 m; je Entfernung jede
##          Körperzone des Dummys (Kopf, Rumpf, Ober-/Unterarm, Ober-/Unterschenkel) über den echten Spielerweg: 1. Person,
##          Blick per look_yaw/pitch auf den Zonenpunkt, Feuertaste; gezoomt (RMT, Zielfernrohr/Kimme) und ungezoomt.
##          Streuung/Rückstoß 0 (deterministisch), Luft angehalten. Protokoll: anvisierte Zone, Zone der Visierlinie (gerader
##          Strahl), Zone der Originalbahn (Kamera, v0, 9,8 m/s², unabhängig berechnet), getroffene Zone, Einschlag − Zielpunkt
##          (cm), Fall (cm), Schaden. Bestanden: getroffen = Originalbahn (immer) und mit „Präzises Zielen“ = anvisiert.
##  streu   echte Streuung (items.sav dw15 bzw. Hüfte [E]), 10 Schuss auf den Rumpf je Waffe/Entfernung: Trefferquote/Zonen
##  lage    Trefferkisten gegen das sichtbare Modell (Haut auf der CPU gestellt): stehend/hockend/liegend, je Kiste Anteil der
##          eigenen Knochen-Ecken in der Kiste und Schwerpunkt
##   tools\godot.cmd --headless -- --mission=test_range --autoplay=test_range [--phase=zonen,streu,lage] [--weapons=o_17,kar98k]
##        [--dists=10,100] [--modes=zoom,hip] [--precise=0|1]  (Fenster --shot=1 → test_output/range/*.png)
##   Bericht test_output/range/range_report.txt + range_zones.csv + range_spread.csv

const TARGETS := ["head", "torso", "arm_upper", "arm_lower", "leg_upper", "leg_lower"]
const SPREAD_SHOTS := 10
const STANCE_NAMES := ["steh", "hock", "lieg"]

var rm                       # Schießstand-Mission
var csv: Array[String] = []
var csv_s: Array[String] = []
var _hits: Array = []        # [amount, zone, dummy]
var _impacts: Array = []     # [pos, collider]
var _shot_cam: Array = []
var _cur_dummy: Soldier
var _shots := false


func _hold_target() -> void:
	pass                     # Dummys hält die Mission fest


func _write_report() -> void:
	var dir := ProjectSettings.globalize_path("res://test_output/range")
	DirAccess.make_dir_recursive_absolute(dir)
	for pair in [["range_report.txt", report], ["range_zones.csv", csv], ["range_spread.csv", csv_s]]:
		var f := FileAccess.open(dir + "/" + String(pair[0]), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(pair[1] as Array) + "\n")


func _run() -> void:
	for i in 2400:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	m = mission()
	rm = m
	check(m != null and m.has_method("dummy_point"), "Schießstand geladen", Game.current_mission_id)
	if m == null or not m.has_method("dummy_point"):
		_finish()
		return
	player = m.squad.leader()
	await seconds(1.5)
	m.rig.camera.current = true
	for s in m.squad.members:            # Vorgabe: keine Läufe ohne Unverwundbarkeit
		s.max_health = 100000.0
		s.health = s.max_health
		var sb = m.squad.brain_of(s)
		if sb:
			sb.set_physics_process(false)
			sb.set_process(false)
		if s != player:
			s.global_position = Vector3(-40.0 - 2.0 * m.squad.members.find(s), 0.2, 6.0)
	player.skill_shooting = 100.0
	player.stamina = 100.0
	_shots = bool(int(Game.cli.get("shot", "0"))) and DisplayServer.get_name() != "headless"
	var ok_d: bool = rm.dummies.size() == rm.DISTANCES.size()
	for d in rm.dummies:
		ok_d = ok_d and d.model.orig_figure != null and d.model.orig_zones.size() == 10
	check(ok_d, "Dummys auf %s m mit Original-Figur und 10 Original-Trefferzonen" % str(rm.DISTANCES), str(rm.dummies.size()))
	rm.dummy_hit.connect(func(d, a, z): _hits.append([a, z, d]))
	Ballistics.projectile_impact.connect(func(pos, c, sh):
		if sh == player:
			_impacts.append([pos, c]))
	player.shot_fired.connect(func(_w): _shot_cam.append(m.rig.camera.global_transform))
	if m.rig.mode != CameraRig.Mode.FIRST:
		m.rig.toggle_mode()
	report.append("Schießstand 0.11.7 – Dummy-Figur %s, Bahnen %s m" % [rm.DUMMY_FIGURE, str(rm.DISTANCES)])
	var ph := String(Game.cli.get("phase", "lage,zonen,streu")).split(",")
	if "lage" in ph:
		await _phase_align()
	if "zonen" in ph:
		await _phase_range_zones()
	if "streu" in ph:
		await _phase_spread()
	_write_report()
	_finish()


# --- Auswahl ---------------------------------------------------------------------------------------------------------

func _weapons() -> Array:
	var only := String(Game.cli.get("weapons", "")).split(",", false)
	var out := []
	for r in aim_weapons():
		if only.is_empty() or String((r[1] as WeaponData).id) in only or str(r[0]) in only:
			out.append(r)
	return out


## Gewehre/Karabiner (Haltesatz rifle) und Zielfernrohrwaffen: auch 100/200/300 m
static func long_range(row: Array) -> bool:
	return row[3] == "rifle" or is_scope(row[2])


func _lanes(row: Array) -> Array:
	var only := String(Game.cli.get("dists", "")).split(",", false)
	var out := []
	for i in rm.DISTANCES.size():
		var d: float = rm.DISTANCES[i]
		if d > 50.0 and not long_range(row):
			continue
		if not only.is_empty() and not str(int(d)) in only:
			continue
		out.append(i)
	return out


func _equip(row: Array) -> Weapon:
	var wd: WeaponData = row[1]
	var pistol: bool = row[3] == "pistol"
	player.equip(["" if pistol else String(wd.id), String(wd.id) if pistol else "colt", "no36", "", "knife"])
	player.select_slot(WeaponData.Slot.SIDEARM if pistol else WeaponData.Slot.PRIMARY)
	player.stance_request = Soldier.Stance.STAND
	await seconds(1.2)
	return player.current_weapon()


## [Haltung, Modus] je erlaubter Haltung (schwere MGs nur liegend/hockend wie Soldier.fire_stance_max) und Modus
func _combos(w: Weapon, modes: Array) -> Array:
	var only := String(Game.cli.get("stances", "steh,hock,lieg")).split(",", false)
	var out := []
	for st in [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]:
		if not STANCE_NAMES[int(st)] in only or 2 - int(st) > Soldier.fire_stance_max(w.data):
			continue
		for mode in modes:
			out.append([int(st), String(mode)])
	return out


func _set_stance(st: int) -> void:
	if player.stance == st:
		return
	Input.action_release("aim")
	player.stance_request = st
	for i in 150:
		await frames(1)
		if player.stance == st:
			break
	await seconds(0.6)


func _go_lane(i: int) -> void:
	player.global_position = rm.firing_point(i) + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.look_yaw = 0.0
	_cur_dummy = rm.dummies[i]
	await frames(4)


# --- Zielpunkte am Dummy -----------------------------------------------------------------------------------------------

## Trefferkiste je Zielname: Kopf/Rumpf, Arm/Bein der dem Schützen zugewandten rechten Bildseite, oben/unten nach Höhe
func _target_box(d: Soldier, tname: String) -> Hitbox:
	var zone: StringName = {"head": &"head", "torso": &"torso", "arm_upper": &"arm", "arm_lower": &"arm",
		"leg_upper": &"leg", "leg_lower": &"leg"}[tname]
	var cam_right: Vector3 = m.rig.camera.global_basis.x
	var cand: Array[Hitbox] = []
	for hb in d.model.orig_zones:
		if hb.zone != zone:
			continue
		if zone in [&"arm", &"leg"] and ((hb.get_child(0) as Node3D).global_position - d.global_position).dot(cam_right) < 0.0:
			continue
		cand.append(hb)
	if cand.is_empty():
		return null
	cand.sort_custom(func(a, b): return (a.get_child(0) as Node3D).global_position.y > (b.get_child(0) as Node3D).global_position.y)
	return cand[cand.size() - 1] if tname.ends_with("_lower") else cand[0]


## Zone eines geraden Strahls Kamera → pt (Visierlinie ohne Fall, gleiche Vorrangregel wie Ballistics)
func _line_zone(from: Vector3, pt: Vector3) -> StringName:
	var dir := (pt - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, pt + dir * 2.0, Ballistics.MASK, player.exclude_rids())
	q.collide_with_areas = true
	var h := m.rig.camera.get_world_3d().direct_space_state.intersect_ray(q)
	if h.is_empty() or not (h.collider is Hitbox):
		return &"-"
	var hb := Ballistics._priority_zone(m.rig.camera.get_world_3d().direct_space_state, h.collider, h.position, dir)
	return &"head" if hb.zone == Helmet.ZONE else hb.zone


## Sichtbarer Punkt der Kiste: Mitte, sonst innerhalb der Kiste versetzt, bis die Visierlinie die Zone trifft
func _aim_point(hb: Hitbox) -> Vector3:
	var cs := hb.get_child(0) as CollisionShape3D
	var half := (cs.shape as BoxShape3D).size * 0.5
	var from := m.rig.camera.global_position
	for o in [Vector3.ZERO, Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0), Vector3(0, 0.4, 0), Vector3(0, -0.4, 0), Vector3(0, 0, 0.4),
			Vector3(0, 0, -0.4), Vector3(0.7, 0, 0), Vector3(-0.7, 0, 0), Vector3(0, 0.7, 0), Vector3(0, -0.7, 0)]:
		var p: Vector3 = cs.global_transform * (o * half)
		if _line_zone(from, p) == hb.zone:
			return p
	return cs.global_position


func _wait_ready(w: Weapon, zoom: bool) -> void:
	for i in 200:
		if w.cooldown <= 0.0 and not w.is_reloading() and (not zoom or (m.rig.zoomed() and float(m.rig.get("_zoom_t")) >= 1.0)):
			break
		await frames(1)
	w.in_mag = w.data.magazine_size


## Ein Schuss auf pt (bzw. auf den sichtbaren Punkt der Kiste hb, nach dem Ausrichten bestimmt): {hit, imp, cam, amount, pt}
func _shoot_at(w: Weapon, pt: Vector3, zoom: bool, hb: Hitbox = null) -> Dictionary:
	await _aim_at(pt)
	await _wait_ready(w, zoom)
	if hb:
		pt = _aim_point(hb)
	m.rig.breath = 1.0
	m.rig.breath_winded = false
	await _aim_at(pt)
	_hits.clear()
	_impacts.clear()
	_shot_cam.clear()
	await tap("fire")
	for i in 90:
		if not _impacts.is_empty() or not _hits.is_empty():
			break
		await frames(1)
	await frames(2)
	var r := {"hit": &"-", "amount": 0.0, "imp": Vector3.INF, "cam": _shot_cam[0] if not _shot_cam.is_empty() else m.rig.camera.global_transform,
		"fired": not _shot_cam.is_empty(), "pt": pt}
	for h in _hits:
		if h[2] == _cur_dummy:
			r["hit"] = h[1]
			r["amount"] = h[0]
			break
	if not _impacts.is_empty():
		r["imp"] = _impacts[0][0]
	return r


# --- Phase zonen ---------------------------------------------------------------------------------------------------

func _phase_range_zones() -> void:
	var modes := String(Game.cli.get("modes", "zoom,hip")).split(",", false)
	var precise := int(Game.cli.get("precise", "-1"))
	var space := m.rig.camera.get_world_3d().direct_space_state
	report.append("")
	report.append("ZONEN (Streuung/Rückstoß 0, Luft angehalten, Präzises Zielen %s, Zielfernrohr eingeschossen %s): Waffe | Modus | m | Ziel | anvisiert → Visierlinie → Originalbahn (ohne Ausgleich) → getroffen [A = Fallausgleich aktiv, erwartet = Visierlinie; sonst erwartet = Originalbahn] | Einschlag−Zielpunkt dx/dy cm | Fall ohne Ausgleich cm | Schaden"
		% ["an" if precise == 1 else ("aus" if precise == 0 else "Einstellung"), "Test aus" if precise == 0 else ("an" if Settings.scope_zero or precise == 1 else "aus")])
	csv.append("item;weapon;stance;mode;dist;target;aimed;sightline;orig_path;hit;compensated;dx_cm;dy_cm;drop_cm;damage;ok_expected;ok_aimed")
	if precise >= 0:
		Ballistics.force_compensation = precise
	var bad: Array[String] = []
	var n := 0
	var n_aim := 0
	var n_path := 0
	var summary := {}
	for row in _weapons():
		var wd0: WeaponData = row[1]
		var w := await _equip(row)
		if w == null:
			continue
		_neutral(w)
		var wd := w.data
		for combo in _combos(w, modes):
			var mode: String = combo[1]
			var sn: String = STANCE_NAMES[int(combo[0])]
			await _set_stance(int(combo[0]))
			var zoom: bool = mode == "zoom"
			if zoom:
				Input.action_press("aim")
				m.rig.breath_force = 1
				await seconds(0.8)
			for li in _lanes(row):
				await _go_lane(li)
				var dist: float = rm.DISTANCES[li]
				var ok_p := 0
				var ok_a := 0
				for tname in TARGETS:
					var hb := _target_box(_cur_dummy, tname)
					if hb == null:
						continue
					var r := await _shoot_at(w, (hb.get_child(0) as Node3D).global_position, zoom, hb)
					var pt: Vector3 = r["pt"]
					var cxf: Transform3D = r["cam"]
					var o := cxf.origin
					var dir := -cxf.basis.z
					var sight_z := _line_zone(o, o + dir * (o.distance_to(pt) + 0.5))
					var path_z := predict_zone(space, o, dir, wd, player.exclude_rids())
					var hit: StringName = r["hit"]
					var imp: Vector3 = r["imp"]
					var dx := NAN
					var dy := NAN
					var drop := NAN
					if imp.is_finite():
						var rh := Vector2(imp.x - o.x, imp.z - o.z).length()
						var sight := o + dir * (rh / maxf(Vector2(dir.x, dir.z).length(), 1e-4))
						var rel := imp - pt
						var right := dir.cross(Vector3.UP).normalized()
						dx = rel.dot(right) * 100.0
						dy = rel.y * 100.0
						drop = (sight.y - orig_path_point(o, dir, wd, rh).y) * 100.0
					# Ausgleich aktiv (Präzises Zielen bzw. 0.11.7 Zielfernrohr eingeschossen) → erwartet = Zone der Visierlinie
					var comp: bool = Ballistics.compensation_enabled() or (zoom and is_scope(row[2]) and Ballistics.scope_compensation_enabled())
					var want_z: StringName = sight_z if comp else path_z
					var ok_path: bool = bool(r["fired"]) and hit == want_z
					var ok_aim: bool = hit == hb.zone
					n += 1
					if ok_path:
						ok_p += 1
						n_path += 1
					if ok_aim:
						ok_a += 1
						n_aim += 1
					if not ok_path:
						bad.append("%s %s %s %.0f m %s→%s (erwartet %s)" % [wd0.id, sn, mode, dist, tname, hit, want_z])
					report.append("  %-3d %-18s %s %-4s %3.0f %-9s %-5s → %-5s → %-5s → %-5s%s | %+6.1f/%+6.1f | %5.1f | %6.1f%s" % [row[0],
						wd0.display_name.left(18), sn, mode, dist, tname, hb.zone, sight_z, path_z, hit, " A" if comp else "  ", dx, dy, drop,
						float(r["amount"]), "" if ok_path else "   <-- FEHLER"])
					csv.append("%d;%s;%s;%s;%.0f;%s;%s;%s;%s;%s;%d;%.1f;%.1f;%.1f;%.1f;%d;%d" % [row[0], wd0.id, sn, mode, dist, tname, hb.zone, sight_z,
						path_z, hit, int(comp), dx, dy, drop, float(r["amount"]), int(ok_path), int(ok_aim)])
				summary["%s|%s|%s|%.0f" % [wd0.id, sn, mode, dist]] = "%d/%d Bahn, %d/%d Ziel" % [ok_p, TARGETS.size(), ok_a, TARGETS.size()]
				if _shots and zoom and li == _lanes(row).back():
					await _snap("%s_%s_%s_%.0fm" % [wd0.id, sn, mode, dist])
			if zoom:
				Input.action_release("aim")
				m.rig.breath_force = -1
				await seconds(0.5)
	Ballistics.force_compensation = -1
	report.append("")
	report.append("Übersicht Zonen (getroffen = Originalbahn / getroffen = anvisiert, je 6 Zonen):")
	for k in summary:
		report.append("  %-28s %s" % [k, summary[k]])
	report.append("Gesamt: %d Schüsse, getroffen = Originalbahn %d, = anvisierte Zone %d" % [n, n_path, n_aim])
	# Grenzfälle: Einschlag genau an der Überlappung Arm/Rumpf (Leerlaufclip bewegt die Arme zwischen Schuss und Einschlag)
	# bzw. Kimme-Wackeln – bis 0,3 % zulässig, alle stehen im Bericht
	check(n > 0 and bad.size() <= int(n * 0.003), "Zonen: getroffene Zone = Zone der Originalbahn (Kamera, v0, Fall) bzw. mit Fallausgleich (Zielfernrohr eingeschossen) = Visierlinie%s, alle Waffen/Entfernungen/Zonen, gezoomt und ungezoomt" % (
		" und = anvisierte Zone (Präzises Zielen)" if precise == 1 else ""), "%d/%d; %s" % [bad.size(), n, ", ".join(bad.slice(0, 10))])


# --- Phase streu -----------------------------------------------------------------------------------------------------

func _phase_spread() -> void:
	report.append("")
	report.append("STREUUNG (echte Waffenwerte, Rückstoß aus, Luft angehalten, %d Schuss auf die Rumpfmitte): Waffe | Modus | m | Treffer Rumpf/Kopf/Arm/Bein/vorbei | mittlere Abweichung cm" % SPREAD_SHOTS)
	csv_s.append("item;weapon;stance;mode;dist;torso;head;arm;leg;miss;mean_dev_cm;mean_dev_mrad;spread_deg")
	seed(7011)
	var n := 0
	var agg := {}          # "mode|stance" → [Summe mrad, Anzahl]
	var sp_by := {}        # "waffe|mode|m" → {haltung: Streuwinkel °}
	for row in _weapons():
		var wd0: WeaponData = row[1]
		var w := await _equip(row)
		if w == null:
			continue
		player.orig_recoil_off = true
		for combo in _combos(w, String(Game.cli.get("modes", "zoom,hip")).split(",", false)):
			var mode: String = combo[1]
			var sn: String = STANCE_NAMES[int(combo[0])]
			await _set_stance(int(combo[0]))
			var zoom: bool = mode == "zoom"
			if zoom:
				Input.action_press("aim")
				m.rig.breath_force = 1
				await seconds(0.8)
			for li in _lanes(row):
				var dist: float = rm.DISTANCES[li]
				if dist < 10.0:
					continue
				await _go_lane(li)
				var cnt := {&"torso": 0, &"head": 0, &"arm": 0, &"leg": 0, &"-": 0}
				var dev := 0.0
				var dev_a := 0.0
				var nd := 0
				var sp := 0.0
				var dirs: Array = []
				for k in SPREAD_SHOTS:
					w.bloom = 0.0
					var pt := (_target_box(_cur_dummy, "torso").get_child(0) as Node3D).global_position
					sp = player.current_spread()
					var r := await _shoot_at(w, pt, zoom)
					var hz: StringName = r["hit"]
					cnt[hz if cnt.has(hz) else &"-"] += 1
					var imp: Vector3 = r["imp"]
					var cxf: Transform3D = r["cam"]
					if imp.is_finite() and imp.distance_to(pt) < 5.0:
						# Winkel zwischen Einschlag und Zielpunkt vom Schützen aus (entfernungsunabhängig, Fall herausgerechnet:
						# Bezug = Einschlag desselben Schusses ohne Streuung wäre die Bahn; hier quer + Höhe gegen den Zielpunkt)
						dev += Vector2((imp - pt).x, (imp - pt).y).length()
						dirs.append((imp - cxf.origin).normalized())
						nd += 1
					n += 1
				# Streukreis: mittlerer Winkel der Einschläge zu ihrer Mitte (Fall/Ausgleich fallen heraus)
				var cen := Vector3.ZERO
				for dv in dirs:
					cen += dv
				for dv in dirs:
					dev_a += (dv as Vector3).angle_to(cen.normalized()) * 1000.0
				var key := "%s|%s" % [mode, sn]
				if not agg.has(key):
					agg[key] = [0.0, 0]
				agg[key][0] += dev_a
				agg[key][1] += nd
				var sk := "%s|%s|%.0f" % [wd0.id, mode, dist]
				if not sp_by.has(sk):
					sp_by[sk] = {}
				sp_by[sk][sn] = sp
				report.append("  %-3d %-18s %s %-4s %3.0f  %d/%d/%d/%d/%d  %.1f cm  %.2f mrad  (Streuung %.3f°)" % [row[0], wd0.display_name.left(18), sn,
					mode, dist, cnt[&"torso"], cnt[&"head"], cnt[&"arm"], cnt[&"leg"], cnt[&"-"], dev / maxf(nd, 1) * 100.0, dev_a / maxf(nd, 1), sp])
				csv_s.append("%d;%s;%s;%s;%.0f;%d;%d;%d;%d;%d;%.1f;%.2f;%.3f" % [row[0], wd0.id, sn, mode, dist, cnt[&"torso"], cnt[&"head"], cnt[&"arm"],
					cnt[&"leg"], cnt[&"-"], dev / maxf(nd, 1) * 100.0, dev_a / maxf(nd, 1), sp])
			if zoom:
				Input.action_release("aim")
				m.rig.breath_force = -1
				await seconds(0.5)
	check(n > 0, "Streuung: %d Schüsse mit echter Streuung protokolliert" % n)
	# 0.11.7 Vorgabe [D]: stehend etwas ungenauer als hockend, hockend ungenauer als liegend (Mittel über alle Waffen/Entfernungen)
	# Prüfung am wirksamen Streuwinkel im Schussmoment (Soldier.current_spread, deterministisch); der gemessene Streukreis
	# (10 Schuss, Zufall) ist nur Statistik
	report.append("Streukreis je Haltung (Statistik, Mittel aller Waffen/Entfernungen, mrad):")
	for mode in ["zoom", "hip"]:
		var vals := []
		for sn in STANCE_NAMES:
			var a: Array = agg.get("%s|%s" % [mode, sn], [0.0, 0])
			vals.append(float(a[0]) / maxf(float(a[1]), 1.0) if int(a[1]) > 0 else NAN)
		report.append("  %-4s steh %.2f  hock %.2f  lieg %.2f" % [mode, vals[0], vals[1], vals[2]])
	var bad: Array[String] = []
	var nc := 0
	for sk in sp_by:
		var v: Dictionary = sp_by[sk]
		if v.has("steh") and v.has("hock") and float(v["steh"]) <= float(v["hock"]):
			bad.append("%s steh %.3f ≤ hock %.3f" % [sk, v["steh"], v["hock"]])
		if v.has("hock") and v.has("lieg") and float(v["hock"]) <= float(v["lieg"]):
			bad.append("%s hock %.3f ≤ lieg %.3f" % [sk, v["hock"], v["lieg"]])
		nc += 1
	check(nc > 0 and bad.is_empty(), "Streuung nach Haltung: Streuwinkel stehend > hockend > liegend je Waffe/Modus/Entfernung (%d Fälle)" % nc,
		", ".join(bad.slice(0, 8)))


# --- Phase lage: Trefferkisten gegen sichtbares Modell -----------------------------------------------------------------

func _phase_align() -> void:
	var d: Soldier = rm.dummies[2]
	report.append("")
	report.append("LAGE der Trefferkisten gegen das sichtbare Modell (Dummy 10 m, Haut auf der CPU gestellt): Haltung | Kiste (Knochen/Zone) | Ecken | Anteil in der Kiste (±2 cm) | Schwerpunkt in Kisten-Halbmaßen x/y/z")
	var bad: Array[String] = []
	for st in [Soldier.Stance.STAND, Soldier.Stance.CROUCH, Soldier.Stance.PRONE]:
		d.stance_request = st
		await seconds(2.5)
		var nm: String = ["steh", "hock", "lieg"][int(st)]
		var verts := _posed_by_bone(d)
		var head_y := 0.0
		for hb in d.model.orig_zones:
			if hb.zone == &"head":
				head_y = (hb.get_child(0) as Node3D).global_position.y - d.global_position.y
		report.append("  %s: Haltung ist %d, Kopfkiste %.2f m über dem Boden" % [nm, int(d.stance), head_y])
		if int(d.stance) != int(st):
			bad.append("%s Haltung nicht eingenommen" % nm)
		for hb in d.model.orig_zones:
			var bone := String(hb.get_meta("bone", ""))
			var cs := hb.get_child(0) as CollisionShape3D
			var half := (cs.shape as BoxShape3D).size * 0.5
			var inv := cs.global_transform.affine_inverse()
			var pts: Array = verts.get(bone, [])
			var inside := 0
			var c := Vector3.ZERO
			for p in pts:
				var l: Vector3 = inv * (p as Vector3)
				c += l
				if absf(l.x) <= half.x + 0.02 and absf(l.y) <= half.y + 0.02 and absf(l.z) <= half.z + 0.02:
					inside += 1
			var frac := float(inside) / maxf(pts.size(), 1)
			c /= maxf(pts.size(), 1)
			var cn := Vector3(c.x / half.x, c.y / half.y, c.z / half.z)
			var ok := pts.size() > 0 and absf(cn.x) <= 1.0 and absf(cn.y) <= 1.0 and absf(cn.z) <= 1.0
			report.append("  %s  %s/%-5s %4d  %3.0f %%  %+.2f/%+.2f/%+.2f%s" % [nm, bone, hb.zone, pts.size(), frac * 100.0, cn.x, cn.y, cn.z,
				"" if ok else "   <-- Schwerpunkt außerhalb"])
			if not ok:
				bad.append("%s %s" % [nm, bone])
		if _shots:
			d.model.show_zones(true)
			var cam := Camera3D.new()
			m.add_child(cam)
			cam.fov = 40.0
			var cc := (d.model.orig_zones[0].get_child(0) as Node3D).global_position
			cam.global_position = cc + Vector3(1.8, 0.8, 2.4)
			cam.look_at(cc)
			cam.current = true
			await seconds(1.0)
			await _snap("lage_%s" % nm)
			cam.queue_free()
			m.rig.camera.current = true
			d.model.show_zones(false)
	d.stance_request = Soldier.Stance.STAND
	await seconds(2.0)
	check(bad.is_empty(), "Lage: Schwerpunkt der sichtbaren Ecken jedes Knochens liegt in seiner Trefferkiste (stehend/hockend/liegend)", ", ".join(bad))


## Ecken der Figur in der aktuellen Pose, gruppiert nach dominantem Knochen (Name)
func _posed_by_bone(d: Soldier) -> Dictionary:
	var out := {}
	for mi in d.model.orig_figure.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		if not mesh_i.is_visible_in_tree() or mesh_i.mesh == null or mesh_i.skin == null:
			continue
		var skel := mesh_i.get_node_or_null(mesh_i.skeleton) as Skeleton3D
		if skel == null:
			continue
		var skin := mesh_i.skin
		var mats: Array[Transform3D] = []
		var names: Array[String] = []
		for bi in skin.get_bind_count():
			var bone := skin.get_bind_bone(bi)
			if bone < 0:
				bone = skel.find_bone(skin.get_bind_name(bi))
			bone = maxi(bone, 0)
			mats.append(skel.global_transform * skel.get_bone_global_pose(bone) * skin.get_bind_pose(bi))
			names.append(skel.get_bone_name(bone))
		for si in mesh_i.mesh.get_surface_count():
			var arr := mesh_i.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty():
				continue
			var per := bones.size() / maxi(v.size(), 1)
			for vi in v.size():
				var p := Vector3.ZERO
				var ws := 0.0
				var best := -1
				var bw := 0.0
				for k in per:
					var wgt := wts[vi * per + k]
					if wgt > 0.0:
						p += (mats[bones[vi * per + k]] * v[vi]) * wgt
						ws += wgt
						if wgt > bw:
							bw = wgt
							best = bones[vi * per + k]
				if best < 0:
					continue
				var key := names[best]
				if not out.has(key):
					out[key] = []
				(out[key] as Array).append(p / maxf(ws, 1e-6))
	return out


func _snap(tag: String) -> void:
	await frames(3)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output/range"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_output/range/%s.png" % tag))
