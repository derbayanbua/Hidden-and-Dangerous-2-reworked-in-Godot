extends "res://tests/test_gameplay.gd"
## 0.11.9: alle auf Fahrzeugen montierten Bordwaffen aller Karten (orig_cache/*/models, Modelle mit SEATnn + HORT/VERT +
## BARREL). Je Waffensitz: Richtteile hängen fest am Fahrzeug (auch nach Drehen/Versetzen), Mündung SHDUM liegt auf der
## Rohrachse (turret_dir), Rohr richtet sich auf ein stehendes Ziel aus (Seite + Höhe) und der Schuss des Spielers
## trifft dieses Ziel (Geschoss bzw. Granate). Anlass: AFRICA2 Opel Blitz Flak 38 – Rohrachse ~50° nach unten.
##   tools\godot.cmd --headless -- --mission=af1_spaghetti_airport --autoplay=test_mounted_guns [--models=la_opelfaf,…]

const TRACK_Y := 600.0
const TARGET_DIST := 30.0

class Target extends StaticBody3D:
	var hits := 0
	func on_bullet_hit(_damage, _shooter) -> void:
		hits += 1

var _levels := {}
var _hale: Soldier
var _report: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(2300.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


## Modelle mit Bordwaffen: {schlüssel: {model, mis, folders}} (gleiche Datei in mehreren Ordnern nur einmal)
func _collect() -> Dictionary:
	var out := {}
	var root := OrigLevel.cache_root()
	var dirs := DirAccess.get_directories_at(root)
	var skipped := {}
	var statics := {}       # Modelle fester Waffenstellungen (Akteurtyp 21 „StaticWeapon“) in irgendeiner Karte
	for mis in dirs:
		var md := root + "/" + mis + "/models"
		if not DirAccess.dir_exists_absolute(md):
			continue
		var ip := root + "/" + mis + "/interactive.json"
		if FileAccess.file_exists(ip):
			var rx := RegEx.create_from_string("\"class\":\\s*\"StaticWeapon\"[\\s\\S]{0,600}?\"model\":\\s*\"([^\"]+)\"")
			for mt in rx.search_all(FileAccess.get_file_as_string(ip)):
				statics[mt.get_string(1).to_lower()] = true
		for f in DirAccess.get_files_at(md):
			if not f.ends_with(".glb") or f.begins_with("dm_") or f.begins_with("w_"):
				continue
			var path := md + "/" + f
			var names := _node_names(path)
			var seat := names.any(func(n): return n.begins_with("SEAT"))
			var rig := names.any(func(n): return n.begins_with("HORT") or n.begins_with("VERT"))
			var bar := names.any(func(n): return n.begins_with("BARREL"))
			if not (seat and rig and bar):
				continue
			var model := f.get_basename()
			# Keine Fahrzeuge: feste Waffenstellungen (interactive.json, OrigEmplacement), Zwischensequenz-Modelle (cut*),
			# Ju 88 der AFRICA6 (eigene Bordschützen-Klasse Af6.Turret, test_af6)
			if model.begins_with("cut") or model.contains("ju88") or statics.has(model.to_lower()):
				skipped[model] = true
				continue
			var key := "%s|%d" % [model, FileAccess.open(path, FileAccess.READ).get_length()]
			if not out.has(key):
				out[key] = {"model": model, "mis": mis, "folders": []}
			out[key]["folders"].append(mis)
	for k in out.keys():
		if statics.has(String(out[k]["model"]).to_lower()):
			skipped[out[k]["model"]] = true
			out.erase(k)
	var sk := skipped.keys()
	sk.sort()
	print("MOUNTED-AUSGENOMMEN (keine Fahrzeuge): ", ", ".join(sk))
	return out


func _node_names(path: String) -> Array:
	var res: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 20 or f.get_32() != 0x46546C67:
		return res
	f.get_32()
	f.get_32()
	var ln := f.get_32()
	f.get_32()
	var j = JSON.parse_string(f.get_buffer(ln).get_string_from_utf8())
	if typeof(j) == TYPE_DICTIONARY:
		for n in j.get("nodes", []):
			res.append(String(n.get("name", "")).to_upper())
	return res


func _run() -> void:
	for i in 3000:
		if mission() and mission().squad and mission().squad.leader():
			break
		await get_tree().process_frame
	var m := mission()
	check(m != null, "Mission geladen")
	if m == null:
		_finish()
		return
	if m.get("runtime") and m.runtime:
		m.runtime.auto_skip = true
		await seconds(1.0)
		if m.runtime.in_cutscene:
			m.runtime.end_cutscene()
	isolate_enemies([])
	_hale = m.squad.leader()
	_hale.max_health = 99999.0
	_hale.health = 99999.0
	for mb in m.squad.members:
		if mb != _hale:
			m.squad.brain_of(mb).set_order(SquadBrain.Order.HOLD)
			mb.global_position = Vector3(-300, TRACK_Y + 0.5, -300)
	_test_block(Vector3(0, TRACK_Y - 1.0, 0), Vector3(400, 1, 400), 0.0)
	var phase := String(Game.cli.get("phase", "all"))
	var only: Array = String(Game.cli.get("models", "")).split(",", false)
	if phase != "static":
		var models := _collect()
		check(not models.is_empty(), "Fahrzeugmodelle mit Bordwaffen gefunden", "%d" % models.size())
		var keys := models.keys()
		keys.sort()
		for k in keys:
			var e: Dictionary = models[k]
			if not only.is_empty() and not only.any(func(o): return String(e["model"]).contains(String(o))):
				continue
			await _test_model(e)
	if phase != "vehicles":
		var st := _collect_static()
		check(not st.is_empty(), "Feste Waffenstellungen gefunden", "%d" % st.size())
		var sk := st.keys()
		sk.sort()
		for k in sk:
			if not only.is_empty() and not only.any(func(o): return String(k).contains(String(o))):
				continue
			await _test_static(st[k])
	print("MOUNTED-GUNS-BERICHT")
	for l in _report:
		print("  " + l)
	for k in _levels:
		(_levels[k] as OrigLevel).release()
	_finish()


func _spawn(mis: String, model: String, pos: Vector3, yaw: float) -> Vehicle:
	if not _levels.has(mis):
		var holder := Node3D.new()
		get_tree().current_scene.add_child(holder)
		_levels[mis] = OrigLevel.new(mis, holder)
	var vis: Node3D = (_levels[mis] as OrigLevel).model_instance(model)
	if vis == null:
		return null
	vis.rotation.y = PI
	var v := Vehicle.new()
	v.name = ("mg_" + mis + "_" + model).validate_node_name()
	v.persistent_id = "mg_" + mis + "_" + model
	v.vehicle_name = model
	v.custom_visual = vis
	v.drive_model = model
	var dir := OrigLevel.cache_path(mis)
	v.model_path = dir + "/models/" + model + ".glb"
	v.dm_path = dir + "/models/dm_" + model + ".glb"
	mission().dynamic_root.add_child(v)
	v.global_position = pos + Vector3.UP * 0.4
	v.global_rotation.y = yaw
	return v


func _test_model(e: Dictionary) -> void:
	var model: String = e["model"]
	var mis: String = e["mis"]
	var label := "%s (%s)" % [model, mis]
	var v := _spawn(mis, model, Vector3(0, TRACK_Y, 0), 0.7)
	check(v != null, "%s: Modell geladen" % label)
	if v == null:
		_report.append("%s | Karten %s | Modell fehlt" % [label, ",".join(e["folders"])])
		return
	await seconds(1.5)
	if v.turrets.is_empty():
		check(false, "%s: Waffensitz erkannt" % label)
		_report.append("%s | Karten %s | kein Waffensitz" % [label, ",".join(e["folders"])])
		v.queue_free()
		await frames(2)
		return
	var parts: Array = []
	for i in v.turrets:
		parts.append(await _test_turret(v, i, label))
	_report.append("%s | Karten %s | %s" % [label, ",".join(e["folders"]), "; ".join(parts)])
	v.queue_free()
	await frames(2)


func _pivot(v: Vehicle, i: int) -> Node3D:
	var t: Dictionary = v.turrets[i]
	return t["vert"] if t["vert"] else t["hort"]


func _test_turret(v: Vehicle, i: int, label: String) -> String:
	var nm := "%s Sitz %d" % [label, i]
	var t: Dictionary = v.turrets[i]
	var piv := _pivot(v, i)
	var res := "S%d" % i
	# 1) fest am Fahrzeug: Lage des Richtteils im Fahrzeugraum bleibt beim Drehen/Versetzen gleich
	var rel0 := v.global_transform.affine_inverse() * piv.global_position
	var inside := absf(rel0.x) < v._size.x * 0.75 + 0.3 and rel0.y > -0.5 and rel0.y < v._size.y + 1.0 and absf(rel0.z) < v._size.z * 0.75 + 0.3
	v.global_transform = Transform3D(Basis(Vector3.UP, v.global_rotation.y + 1.3), v.global_position + Vector3(3.0, 0, -2.0))
	await frames(3)
	var rel1 := v.global_transform.affine_inverse() * piv.global_position
	check(inside and rel0.distance_to(rel1) < 0.03, "%s: Richtteil hängt am Fahrzeug" % nm, "Lage %s → %s, Größe %s" % [rel0, rel1, v._size])
	await seconds(1.0)
	# 2) Mündung auf der Rohrachse
	var mp := v.muzzle_point(i)
	var d := v.turret_dir(i)
	var off := mp - piv.global_position
	var lateral := (off - d * off.dot(d)).length()
	var has_muzzle: bool = t["muzzle"] != null
	check(not has_muzzle or (off.dot(d) > 0.3 and lateral < 0.35), "%s: Mündung auf der Rohrachse" % nm,
		"vor %.2f m, seitlich %.2f m, Rohrneigung %.1f°" % [off.dot(d), lateral, rad_to_deg(asin(clampf(d.y, -1, 1)))])
	res += " Mündung %s seitl. %.2f m" % ["SHDUM" if has_muzzle else "–", lateral]
	# 3) Spieler besetzt, richtet auf ein stehendes Ziel, Schuss trifft
	_hale.global_position = v.global_position + v.global_basis.x * (v._size.x * 0.5 + 1.2) + Vector3.UP * 0.2
	await frames(1)
	if not v.board(_hale, false, i):
		check(false, "%s: Spieler besetzt die Bordwaffe" % nm)
		return res + " nicht besetzbar"
	await frames(2)
	# Zielrichtung: Ruhe-Seitenrichtung des Rohrs, Höhe 0° innerhalb der Höhengrenzen relativ zur Ruhelage
	var rest := v.turret_dir(i)
	var p0 := asin(clampf(rest.y, -1.0, 1.0))
	var lo := p0 - minf(float(t["down"]), Vehicle.PITCH_ABS) + deg_to_rad(3.0)
	var hi := p0 + minf(float(t["up"]), Vehicle.PITCH_ABS) - deg_to_rad(3.0)
	var pitch := clampf(deg_to_rad(2.0), lo, hi) if lo <= hi else p0
	var hdir := Vector3(rest.x, 0, rest.z).normalized()
	if hdir.length() < 0.5:
		hdir = -v.global_basis.z
	var aim_dir := (hdir * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var target_pos := v.muzzle_point(i) + aim_dir * TARGET_DIST
	var tg := Target.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.2, 2.2, 2.2)
	cs.shape = bx
	tg.add_child(cs)
	tg.collision_layer = 1
	mission().dynamic_root.add_child(tg)
	tg.global_position = target_pos
	await frames(2)
	for k in int(Engine.physics_ticks_per_second * 4.0):
		var to := target_pos - v.muzzle_point(i)
		_hale.look_yaw = atan2(-to.x, -to.z)
		_hale.look_pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
		await get_tree().physics_frame
	var to_t := (target_pos - v.muzzle_point(i)).normalized()
	var err := rad_to_deg(v.turret_dir(i).angle_to(to_t))
	check(err < 1.5, "%s: Rohr richtet sich auf stehendes Ziel aus" % nm, "Abweichung %.2f°" % err)
	check(_hale.global_position.distance_to(v.seat_transform(i).origin) < 0.8, "%s: Schütze bleibt am Sitz" % nm)
	res += " Richtfehler %.2f°" % err
	var w := _hale.current_weapon()
	if w == null or w != v.seat_weapon(i):
		res += " ohne Waffe"
		print("MOUNTED-HINWEIS %s: keine Bordwaffe (itemid/Munition)" % nm)
	else:
		w.in_mag = w.data.magazine_size
		if w.reserve < w.data.magazine_size:
			w.reserve = w.data.magazine_size
		var ex0 := Effects.explosion_count
		var rocket := w.data.action == WeaponData.Action.ROCKET
		var hit := false
		var shots := [0]
		var cb := func(_w): shots[0] += 1
		_hale.shot_fired.connect(cb)
		for burst in 3:
			Input.action_press("fire")
			for k in 8:
				var to := target_pos - v.muzzle_point(i)
				_hale.look_yaw = atan2(-to.x, -to.z)
				_hale.look_pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
				await get_tree().physics_frame
			Input.action_release("fire")
			await seconds(1.6 if rocket else 0.8)
			if rocket:
				var le: Dictionary = Effects.last_explosion
				var n = le.get("node")
				hit = Effects.explosion_count > ex0 and is_instance_valid(n) and (n as Node3D).global_position.distance_to(target_pos) < 3.0
			else:
				hit = tg.hits > 0
			if hit:
				break
			if rocket and w.in_mag <= 0:
				w.in_mag = w.data.magazine_size
				await seconds(w.data.reload_time + 0.2)
		_hale.shot_fired.disconnect(cb)
		check(shots[0] > 0 and hit, "%s: %s trifft stehendes Ziel auf %.0f m" % [nm, w.data.display_name, TARGET_DIST],
			"Schüsse %d, Treffer %d, Granate %s" % [shots[0], tg.hits, str(rocket)])
		res += " %s %s" % [w.data.display_name, "Treffer" if hit else "KEIN Treffer"]
	v.leave(_hale)
	await frames(2)
	# 0.12.1: KI-Schütze im Waffensitz (HUMAN_BoardVehicle) feuert auf HUMAN_Attack-Frame (CZECH6 Isu152 c5_r18:
	# HUMAN_Attack(isu_target, 20000)), Panther-Besatzung c5_g08–g10
	if w != null and w == v.seat_weapon(i):
		var ai := mission().spawn_enemy(v.global_position + v.global_basis.x * (v._size.x * 0.5 + 1.5), 0.0, ["", "", ""], "mg_ai_%d" % i, {"skill": 0.9, "reaction": 0.3})
		var br: EnemyBrain = ai.get_node("EnemyBrain")
		await frames(2)
		if v.board(ai, false, i):
			await frames(2)
			var aw := ai.current_weapon()
			if aw:
				aw.in_mag = aw.data.magazine_size
				aw.reserve = maxi(aw.reserve, aw.data.magazine_size * 3)
			var n_sh := [0]
			var cb3 := func(_w): n_sh[0] += 1
			ai.shot_fired.connect(cb3)
			tg.hits = 0
			var ex1 := Effects.explosion_count
			var rk := w.data.action == WeaponData.Action.ROCKET
			br.script_control = true
			br.script_attack_order(tg, 20.0, false)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 12000 and not (n_sh[0] > 0 and _hit(tg, target_pos, ex1, rk)):
				await get_tree().physics_frame
			var ok := _hit(tg, target_pos, ex1, rk)
			check(n_sh[0] > 0 and ok, "%s: KI-Schütze feuert/trifft HUMAN_Attack-Frame" % nm, "Schüsse %d, Treffer %s" % [n_sh[0], str(ok)])
			res += " | KI %d Schüsse %s" % [n_sh[0], "Treffer" if ok else "kein Treffer"]
			ai.shot_fired.disconnect(cb3)
			br.cease_fire()
			v.leave(ai)
		else:
			check(false, "%s: KI besetzt Waffensitz" % nm)
		mission().enemies.erase(ai)
		ai.queue_free()
	tg.queue_free()
	await frames(2)
	return res


# --- 0.12.1: feste Waffenstellungen (Akteurtyp 21 „StaticWeapon“, OrigEmplacement) -----------------------------

## Stellungsmodelle aller Karten: {modell: {model, mis, folders}}
func _collect_static() -> Dictionary:
	var out := {}
	var root := OrigLevel.cache_root()
	var rx := RegEx.create_from_string("\"class\":\\s*\"StaticWeapon\"[\\s\\S]{0,600}?\"model\":\\s*\"([^\"]+)\"")
	for mis in DirAccess.get_directories_at(root):
		var ip := root + "/" + mis + "/interactive.json"
		if not FileAccess.file_exists(ip):
			continue
		for mt in rx.search_all(FileAccess.get_file_as_string(ip)):
			var model := mt.get_string(1).to_lower()
			if not FileAccess.file_exists(root + "/" + mis + "/models/" + model + ".glb"):
				continue
			if not out.has(model):
				out[model] = {"model": model, "mis": mis, "folders": []}
			if not (mis in out[model]["folders"]):
				out[model]["folders"].append(mis)
	return out


func _make_target(pos: Vector3) -> Target:
	var tg := Target.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.2, 2.2, 2.2)
	cs.shape = bx
	tg.add_child(cs)
	tg.collision_layer = 1
	mission().dynamic_root.add_child(tg)
	tg.global_position = pos
	return tg


## Treffer prüfen: Geschoss trifft die Kiste bzw. Granate explodiert ≤ 3 m vom Ziel
func _hit(tg: Target, target_pos: Vector3, ex0: int, rocket: bool) -> bool:
	if not rocket:
		return tg.hits > 0
	var le: Dictionary = Effects.last_explosion
	var n = le.get("node")
	var p = le.get("pos", null)
	if Effects.explosion_count <= ex0:
		return false
	if p is Vector3:
		return (p as Vector3).distance_to(target_pos) < 3.0
	return is_instance_valid(n) and (n as Node3D).global_position.distance_to(target_pos) < 3.0


func _test_static(e: Dictionary) -> void:
	var model: String = e["model"]
	var mis: String = e["mis"]
	var nm := "Stellung %s (%s)" % [model, mis]
	if not _levels.has(mis):
		var holder0 := Node3D.new()
		get_tree().current_scene.add_child(holder0)
		_levels[mis] = OrigLevel.new(mis, holder0)
	var frame: Node3D = (_levels[mis] as OrigLevel).model_instance(model)
	check(frame != null, "%s: Modell geladen" % nm)
	if frame == null:
		_report.append("%s | Modell fehlt" % nm)
		return
	var holder := Node3D.new()
	holder.name = ("st_" + model).validate_node_name()
	mission().dynamic_root.add_child(holder)
	holder.global_transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(40, TRACK_Y, 40))
	if frame.get_parent():
		frame.get_parent().remove_child(frame)
	holder.add_child(frame)
	var path := OrigLevel.cache_path(mis) + "/models/" + model + ".glb"
	var rig: Dictionary = OrigInteractive.rig_params(path)
	var wd: WeaponData = OrigInteractive.heavy_weapon(int(rig.get("itemid", -1)))
	if wd == null:
		wd = WeaponDB.from_orig(33, true)       # MG 42 (Stellungen ohne itemid, Laufzeit: Munition der Stellung)
	var emp := OrigInteractive.OrigEmplacement.new()
	emp.name = holder.name + "_emp"
	mission().dynamic_root.add_child(emp)
	emp.init(null, frame, {"name": model, "inventory": [1, 2, 3, 4]}, wd, 1 if model.contains("crouch") else (2 if model.contains("lie") else 0))
	emp.model_path = path
	emp.setup_rig(rig)
	await frames(2)
	var res := "%s | Karten %s | %s" % [nm, ",".join(e["folders"]), wd.display_name]
	var piv: Node3D = emp.vert if emp.vert else emp.hort
	if piv == null:
		check(false, "%s: Richtteile HORT/VERT" % nm)
		_report.append(res + " | kein Rig")
		holder.queue_free()
		emp.queue_free()
		return
	# 1) Befestigung: Richtteil und Mündung bleiben beim Drehen/Versetzen der Stellung an ihrem Platz im Modell
	var rel0 := holder.global_transform.affine_inverse() * emp.shot_origin()
	holder.global_transform = Transform3D(Basis(Vector3.UP, 2.0), Vector3(43, TRACK_Y, 38))
	await frames(2)
	var rel1 := holder.global_transform.affine_inverse() * emp.shot_origin()
	check(rel0.distance_to(rel1) < 0.03 and rel0.length() < 6.0, "%s: Rohr hängt an der Stellung" % nm, "%s → %s" % [rel0, rel1])
	# 2) Mündung auf der Rohrachse (Seelenachse durch den Rohr-Frame BARREL bzw. den Richt-Frame)
	var d: Vector3 = emp.barrel_dir()
	var bar: Node3D = emp.get("barrel") as Node3D
	var ref: Node3D = bar if bar else piv
	var off := emp.shot_origin() - ref.global_position
	var lateral := (off - d * off.dot(d)).length()
	var has_m := is_instance_valid(emp.muzzle)
	check(not has_m or (off.dot(d) > 0.05 and lateral < 0.35), "%s: Mündung auf der Rohrachse" % nm,
		"vor %.2f m, seitlich %.2f m, Neigung %.1f°" % [off.dot(d), lateral, rad_to_deg(asin(clampf(d.y, -1, 1)))])
	res += " | Mündung seitl. %.2f m" % lateral
	# 3) Spieler: Rohr richtet sich auf ein Ziel 30 m in Ruhe-Seitenrichtung, Schuss trifft
	# Höhe 2° innerhalb der Höhengrenzen relativ zur Ruhelage (la_kan17mmw: Rohr ruht 35° hoch, down25 → ≥ 10°)
	var hdir := Vector3(d.x, 0, d.z).normalized()
	var p0 := asin(clampf(d.y, -1.0, 1.0))
	var lo := p0 - deg_to_rad(float(emp.lim["down"])) + deg_to_rad(3.0)
	var hi := p0 + deg_to_rad(float(emp.lim["up"])) - deg_to_rad(3.0)
	var pa := clampf(deg_to_rad(2.0), lo, hi) if lo <= hi else p0
	var aim_dir := (hdir * cos(pa) + Vector3.UP * sin(pa)).normalized()
	var target_pos := emp.shot_origin() + aim_dir * TARGET_DIST
	var tg := _make_target(target_pos)
	_hale.global_position = emp.gunner_spot() + Vector3.UP * 0.2
	emp.mount(_hale)
	await frames(2)
	for k in int(Engine.physics_ticks_per_second * 2.0):
		var to := target_pos - emp.shot_origin()
		_hale.look_yaw = atan2(-to.x, -to.z)
		_hale.look_pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
		await get_tree().physics_frame
	var err := rad_to_deg(emp.barrel_dir().angle_to((target_pos - emp.shot_origin()).normalized()))
	check(err < 1.5, "%s: Rohr zeigt aufs Ziel (Spieler)" % nm, "Abweichung %.2f°" % err)
	res += " | Richtfehler %.2f°" % err
	var w := _hale.current_weapon()
	var rocket := w != null and w.data.action == WeaponData.Action.ROCKET
	var shots := [0]
	var cb := func(_w): shots[0] += 1
	_hale.shot_fired.connect(cb)
	var ex0 := Effects.explosion_count
	var hit := false
	for burst in 3:
		if w:
			w.in_mag = w.data.magazine_size
		Input.action_press("fire")
		for k in 8:
			var to := target_pos - emp.shot_origin()
			_hale.look_yaw = atan2(-to.x, -to.z)
			_hale.look_pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
			await get_tree().physics_frame
		Input.action_release("fire")
		await seconds(1.6 if rocket else 0.8)
		hit = _hit(tg, target_pos, ex0, rocket)
		if hit:
			break
		if rocket and w:
			await seconds(w.data.reload_time + 0.2)
	_hale.shot_fired.disconnect(cb)
	check(shots[0] > 0 and hit, "%s: Spieler trifft Ziel auf %.0f m" % [nm, TARGET_DIST], "Schüsse %d, Treffer %d" % [shots[0], tg.hits])
	res += " | Spieler %s" % ("Treffer" if hit else "KEIN Treffer (%d Schüsse)" % shots[0])
	emp.dismount()
	await frames(2)
	_hale.global_position = Vector3(-200, TRACK_Y + 0.5, -200)
	# 4) KI-Bediener (wie HUMAN_BoardVehicle): HUMAN_Attack auf einen Frame (Skript, Zombie) und freies Feuer auf einen
	#    gesehenen Gegner (Defensiv)
	var ai := mission().spawn_enemy(emp.gunner_spot() + Vector3.UP * 0.2, 0.0, ["", "", ""], "st_ai_" + model, {"sight": 80.0, "skill": 0.9, "reaction": 0.3})
	var br: EnemyBrain = ai.get_node("EnemyBrain")
	await frames(2)
	emp.mount(ai)
	await frames(2)
	var ai_shots := [0]
	var cb2 := func(_w): ai_shots[0] += 1
	ai.shot_fired.connect(cb2)
	tg.hits = 0
	ex0 = Effects.explosion_count
	br.script_control = true
	br.script_attack_order(tg, float(Game.cli.get("attack_ms", "300")) / 1000.0, false)     # NORMANDY x_n1_n43: HUMAN_Attack(shoot, 300)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and not (ai_shots[0] > 0 and _hit(tg, target_pos, ex0, rocket)):
		await get_tree().physics_frame
	var ai_hit := _hit(tg, target_pos, ex0, rocket)
	check(ai_shots[0] > 0, "%s: KI feuert auf HUMAN_Attack-Frame" % nm, "Schüsse %d" % ai_shots[0])
	check(ai_hit, "%s: KI trifft HUMAN_Attack-Frame" % nm, "Treffer %d" % tg.hits)
	res += " | KI-Frame %d Schüsse %s" % [ai_shots[0], "Treffer" if ai_hit else "kein Treffer"]
	tg.queue_free()
	await frames(2)
	br.script_control = false
	br.cease_fire()
	ai_shots[0] = 0
	var h0 := _hale.health
	_hale.global_position = target_pos - Vector3.UP * 1.2
	_hale.stance_request = 0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000 and _hale.health >= h0:
		_hale.global_position = target_pos - Vector3.UP * 1.2
		await get_tree().physics_frame
	check(ai_shots[0] > 0, "%s: KI feuert auf gesehenen Gegner" % nm, "Schüsse %d" % ai_shots[0])
	check(_hale.health < h0, "%s: KI trifft gesehenen Gegner" % nm, "Gesundheit %.0f → %.0f" % [h0, _hale.health])
	res += " | KI-Gegner %d Schüsse %s" % [ai_shots[0], "Treffer" if _hale.health < h0 else "kein Treffer"]
	_hale.health = _hale.max_health
	ai.shot_fired.disconnect(cb2)
	emp.dismount()
	_hale.global_position = Vector3(-200, TRACK_Y + 0.5, -200)
	mission().enemies.erase(ai)
	ai.queue_free()
	emp.queue_free()
	holder.queue_free()
	_report.append(res)
	await frames(3)
