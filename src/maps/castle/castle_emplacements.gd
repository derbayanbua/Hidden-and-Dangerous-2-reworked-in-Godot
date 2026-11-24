extends RefCounted
## Waffenstellungen auf den Burgtürmen (0.12.2): Türme mit geraden Innentreppen tragen eine Flak 38, Türme mit
## Wendeltreppe ein MG-42-Nest hinter der Brüstung (Lauf zum Hof). Gleicher Waffen-/Netzvertrag wie die Stellungen der
## Testkarte Bavaria (FieldFlak: Benutzen → der Host vergibt den Bedienerplatz, sync_operator an alle; Originalmodelle
## mit HORT00/VERT00/SHDUM00). Ohne Cache-Modell entfällt die Stellung. Plätze auf der Plattform (lokal, Turm-Basis
## b, Plattform y 12): Treppenloch gerade x −0,6…3,14 / z 1,9…3,14, Wendel x −1,3…2,2 / z −1,2…2,2, Leiteraustritt
## (2,8; −2,9) bleiben frei.
const Placement := preload("res://src/maps/bavaria/field_emplacement.gd")
const Kit := preload("res://src/maps/castle/castle_kit.gd")

const FLAK_MODEL := ["la_flake", ["czech6", "normandy", "normandy_mp"]]
const MG_MODEL := ["w_mg42stand", ["africa1", "africa1_obj", "africa3_obj"]]
## Flak: Mitte (−0,8; −0,6), Bediener zur Turm-+x-Seite; MG: Wendel-freier Streifen (−2,3; −2,1), Bediener zu +z
const FLAK_AT := Vector3(-0.8, 0.0, -0.6)
const MG_AT := Vector3(-2.3, 0.0, -2.1)


static func _model_path(spec: Array) -> String:
	for dir in spec[1]:
		var p := "%s/%s/models/%s.glb" % [OrigLevel.cache_root(), dir, spec[0]]
		if FileAccess.file_exists(p):
			return p
	return ""


static func _yaw_back_to(dir: Vector3) -> float:
	# Frame-+Z (Bedienerseite) zeigt nach dir; −Z = Schussrichtung
	return atan2(dir.x, dir.z)


static func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var rel: Transform3D = n.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform \
			if n.is_inside_tree() else _rel_xf(n, mi)
		var bb: AABB = rel * mesh.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


static func _rel_xf(root: Node3D, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p := n
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _collider(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)
	body.position = center


static func build(m: Node) -> Array:
	var out: Array = []
	var r = m.get("real")
	if r == null:
		return out
	var flak_path := _model_path(FLAK_MODEL)
	var mg_path := _model_path(MG_MODEL)
	for t in r.kit.towers:
		var b: Basis = t.basis
		var o: Vector3 = t.pos
		var top := o.y + Kit.TOWER_TOP
		var g: Node = null
		if not bool(t.spiral):
			if flak_path != "":
				g = _flak(m, String(t.id), flak_path, o + b * FLAK_AT + Vector3(0, top - o.y, 0), _yaw_back_to(b.x.normalized()))
		elif mg_path != "":
			g = _mg(m, String(t.id), mg_path, o + b * MG_AT + Vector3(0, top - o.y, 0), _yaw_back_to(b.z.normalized()))
		if g != null:
			g.set_meta("tower", String(t.id))
			out.append(g)
	print("CASTLE_EMPLACEMENTS: %d Stellungen (%s)" % [out.size(), ", ".join(out.map(func(x): return "%s %s" % [x.get_meta("kind"), x.get_meta("tower")]))])
	return out


static func _flak(m: Node, id: String, path: String, pos: Vector3, yaw: float) -> Node:
	var model := OrigLevel.parse_glb(path)
	if model == null:
		return null
	var frame := Node3D.new()
	frame.name = "Flak_" + id
	m.static_root.add_child(frame)
	frame.global_position = pos
	frame.rotation.y = yaw
	frame.add_child(model)
	var bb := _bounds(model)
	model.position -= Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	# Sockel als Kiste (Soldaten laufen nicht hindurch; Rohr/Schild ohne Kollision, Schüsse des Bedieners frei)
	_collider(frame, Vector3(0, 0.45, 0), Vector3(minf(bb.size.x, 1.8), 0.9, minf(bb.size.z, 1.8)))
	var gun := Placement.FieldFlak.new()
	gun.name = "Flak_%s_Bedienung" % id
	m.dynamic_root.add_child(gun)
	gun.init(null, frame, {"name": "castle_flak_" + id, "inventory": [209, 209, 209, 209, 209, 209]}, WeaponDB.get_weapon(&"flak38"), 0)
	gun.frame = frame
	gun.operator_offset = Vector3(0, 0.1, 2.3)
	gun.traverse = model.find_child("HORT00", true, false)
	gun.elevation = model.find_child("VERT00", true, false)
	if gun.traverse:
		gun.traverse_rest = gun.traverse.rotation
	if gun.elevation:
		gun.elevation_rest = gun.elevation.rotation
	gun.base_yaw = yaw
	gun.muzzle = model.find_child("SHDUM00", true, false)
	gun.global_position = gun.gunner_spot() + Vector3.UP * 0.5
	gun.add_to_group("castle_emplacements")
	gun.set_meta("kind", "Flak")
	return gun


static func _mg(m: Node, id: String, path: String, pos: Vector3, yaw: float) -> Node:
	var model := OrigLevel.parse_glb(path)
	if model == null:
		return null
	var frame := Node3D.new()
	frame.name = "MG42_" + id
	m.static_root.add_child(frame)
	frame.global_position = pos
	frame.rotation.y = yaw
	frame.add_child(model)
	var pivot: Node3D = model.find_child("HORT00", true, false)
	if pivot:
		var pl: Vector3 = frame.to_local(pivot.global_position) if pivot.is_inside_tree() else _rel_xf(frame, pivot).origin
		model.position = Vector3(-pl.x, 0, -pl.z)
	# fester Holzbock unter der Originalhalterung (wie Bavaria), Kollision nur der Bock
	m.lb.box(Vector3.ZERO, Vector3(0.18, 1.22, 0.18), "darkwood", 0, true, frame)
	m.lb.box(Vector3(0, 1.17, 0), Vector3(0.65, 0.06, 0.32), "darkwood", 0, true, frame)
	var gun := Placement.FieldFlak.new()
	gun.name = "MG42_%s_Bedienung" % id
	m.dynamic_root.add_child(gun)
	gun.init(null, frame, {"name": "castle_mg42_" + id, "inventory": [33, 33, 33, 33, 33, 33]}, WeaponDB.from_orig(33, true), 0)
	gun.frame = frame
	gun.operator_offset = Vector3(0, 0.1, 1.5)
	# Turm: weiter Schwenkbereich zum Hof, steil nach unten (Plattform 12 m)
	gun.setup_rig({"left": 60.0, "right": 60.0, "up": 15.0, "down": 40.0})
	gun.pitch_min = -deg_to_rad(40.0)
	gun.seat = null
	gun.global_position = gun.gunner_spot() + Vector3.UP * 0.5
	gun.base_yaw = yaw
	gun.add_to_group("castle_emplacements")
	gun.set_meta("kind", "MG42")
	return gun
