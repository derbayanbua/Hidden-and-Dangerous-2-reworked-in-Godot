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
	var models := _collect()
	check(not models.is_empty(), "Fahrzeugmodelle mit Bordwaffen gefunden", "%d" % models.size())
	var only: Array = String(Game.cli.get("models", "")).split(",", false)
	var keys := models.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = models[k]
		if not only.is_empty() and not only.any(func(o): return String(e["model"]).contains(String(o))):
			continue
		await _test_model(e)
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
	tg.queue_free()
	await frames(2)
	return res
