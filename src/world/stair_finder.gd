class_name StairFinder
extends RefCounted
## 0.11.7: Treppen aus der sichtbaren Levelgeometrie finden (gleiches Verfahren wie tests/test_stairs.gd: Folgen
## waagerechter Trittflächen mit gleichmäßiger Stufenhöhe 0,07–0,35 m, ≥ 4 Tritte, Kopfraum für einen stehenden
## Soldaten) und je Treppe eine Rampe nur als Navmesh-Quelle anlegen (Physik-Layer LevelBuilder.NAV_ONLY_LAYER, keine
## Kollision für Figuren/Geschosse/Sicht – wie WALK_PATCHES „navramp“ aus B-010c).
## Grund: Recast nimmt viele Original-Treppen nicht ins Netz (echte Stufenkollision mit schmalen Tritten/Podesten,
## Erosion 0,2 m, überlappende Läufe) → Obergeschosse/Dächer waren für die KI unerreichbar (test_stairs „Pfad✗“,
## test_mp_nav Zonen/Spawns im Obergeschoss, Bots hingen vor Treppen). Soldaten laufen weiter auf den echten Tritten.
## Abschaltbar mit --nav_auto_stairs_off (Messung).
## 0.11.7: find stairs in the visible level geometry and add a navmesh-only ramp per stair (no physics collision).

const MIN_TREADS := 4
const RISE_MIN := 0.07
const RISE_MAX := 0.35
const RAMP_W := 0.8
const MAX_SLOPE_DEG := 49.0      ## steilere Läufe nimmt Recast ohnehin nicht (agent_max_slope 50°)


## Liste von Treppen: {treads: Array[Vector3], bottom: Vector3, top: Vector3}
static func find(root: Node, space: PhysicsDirectSpaceState3D) -> Array:
	var uf := {}
	var tris: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.get_aabb().size.y > 30.0:
			continue
		var xf: Transform3D = mi.global_transform
		var f := mi.mesh.get_faces()
		for i in range(0, f.size() - 2, 3):
			var a: Vector3 = xf * f[i]
			var b: Vector3 = xf * f[i + 1]
			var c: Vector3 = xf * f[i + 2]
			var n := (b - a).cross(c - a)
			var ln := n.length()
			if ln < 1e-5 or absf(n.y) < 0.985 * ln:
				continue
			var ka := Vector3i((a * 50.0).round())
			var kb := Vector3i((b * 50.0).round())
			var kc := Vector3i((c * 50.0).round())
			_union(uf, ka, kb)
			_union(uf, ka, kc)
			tris.append([ka, ln * 0.5, (a + b + c) / 3.0, a, b, c])
	var patches := {}
	for t in tris:
		var r: Vector3i = _find(uf, t[0])
		var p: Dictionary = patches.get(r, {})
		if p.is_empty():
			p = {"area": 0.0, "sum": Vector3.ZERO, "lo": Vector2(INF, INF), "hi": Vector2(-INF, -INF), "y": (t[3] as Vector3).y}
			patches[r] = p
		p.area += t[1]
		p.sum += t[2] * t[1]
		for k in [3, 4, 5]:
			var v: Vector3 = t[k]
			p.lo = Vector2(minf(p.lo.x, v.x), minf(p.lo.y, v.z))
			p.hi = Vector2(maxf(p.hi.x, v.x), maxf(p.hi.y, v.z))
	var tread: Array = []
	for r in patches:
		var p: Dictionary = patches[r]
		var ext: Vector2 = p.hi - p.lo
		if p.area < 0.06 or minf(ext.x, ext.y) < 0.12 or minf(ext.x, ext.y) > 3.0 or maxf(ext.x, ext.y) > 10.0:
			continue
		p.c = p.sum / p.area
		tread.append(p)
	tread.sort_custom(func(x, y): return x.y < y.y)
	var grid := {}
	for i in tread.size():
		var k := Vector2i(floori(tread[i].c.x), floori(tread[i].c.z))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(i)
	var preds: Array = []
	preds.resize(tread.size())
	for i in tread.size():
		var pi: Dictionary = tread[i]
		var lst: Array = []
		var k0 := Vector2i(floori(pi.c.x), floori(pi.c.z))
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for j in grid.get(k0 + Vector2i(dx, dz), []):
					var pj: Dictionary = tread[j]
					var dy: float = pi.y - pj.y
					if dy < RISE_MIN or dy > RISE_MAX:
						continue
					var hd := Vector2(pi.c.x - pj.c.x, pi.c.z - pj.c.z).length()
					if hd < 0.12 or hd > 1.6:
						continue
					if pi.lo.x > pj.hi.x + 0.1 or pj.lo.x > pi.hi.x + 0.1 or pi.lo.y > pj.hi.y + 0.1 or pj.lo.y > pi.hi.y + 0.1:
						continue
					lst.append(j)
		preds[i] = lst
	var used := {}
	var out: Array = []
	for round_i in 200:
		var best: Array = []
		var prev: Array = []
		best.resize(tread.size())
		prev.resize(tread.size())
		var top_i := -1
		for i in tread.size():
			best[i] = 0 if used.has(i) else 1
			prev[i] = -1
			if used.has(i):
				continue
			for j in preds[i]:
				if used.has(j) or best[j] + 1 <= best[i]:
					continue
				var ar: float = tread[i].area / tread[j].area
				if ar < 0.4 or ar > 2.5:
					continue
				if prev[j] >= 0:
					var r1: float = tread[i].y - tread[j].y
					var r0: float = tread[j].y - tread[prev[j]].y
					if absf(r1 - r0) > 0.06:
						continue
					var v1: Vector3 = tread[i].c - tread[j].c
					var v0: Vector3 = tread[j].c - tread[prev[j]].c
					if absf(Vector2(v1.x, v1.z).angle_to(Vector2(v0.x, v0.z))) > deg_to_rad(60.0):
						continue
				best[i] = best[j] + 1
				prev[i] = j
			if top_i < 0 or best[i] > best[top_i]:
				top_i = i
		if top_i < 0 or best[top_i] < MIN_TREADS:
			break
		var chain: Array = []
		var i2 := top_i
		while i2 >= 0:
			chain.push_front(i2)
			used[i2] = true
			i2 = prev[i2]
		var st := _make_stair(chain.map(func(ix): return tread[ix].c), space)
		if not st.is_empty():
			out.append(st)
	return out


static func _make_stair(pts: Array, space: PhysicsDirectSpaceState3D) -> Dictionary:
	while pts.size() > 0 and not _free(space, pts[-1]):
		pts.pop_back()
	while pts.size() > 0 and not _free(space, pts[0]):
		pts.pop_front()
	while pts.size() > 0 and _buried(space, pts[0]):     # im Gelände versunkene Tritte (BURMA1)
		pts.pop_front()
	if pts.size() < MIN_TREADS:
		return {}
	for p in pts:
		if not _free(space, p):
			return {}
	var h: float = pts[-1].y - pts[0].y
	if h < 0.3:
		return {}
	# 0.11.7: kurze Läufe (0,3–0,45 m, TUTORIAL T7) bekommen keine Rampe (Recast überbrückt sie), aber die Fußkorrektur
	var small := h < 0.45
	var d0: Vector3 = pts[1] - pts[0]
	d0.y = 0.0
	d0 = d0.normalized()
	var bottom: Vector3 = pts[0]
	var probe: Vector3 = pts[0] - d0 * 0.6
	var q := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.1, probe + Vector3.DOWN * 0.6, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and pts[0].y - hit.position.y < RISE_MAX + 0.05 and _free(space, hit.position):
		bottom = hit.position
	return {"treads": pts, "bottom": bottom, "top": pts[-1], "small": small}


static func _buried(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 0.1, 1)
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and hit.position.y > p.y + 0.2


static func _free(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.6
	params.shape = cap
	params.transform = Transform3D(Basis(), p + Vector3(0, 0.42 + 0.8, 0))
	params.collision_mask = 1
	return space.intersect_shape(params, 1).is_empty()


static func _find(uf: Dictionary, k: Vector3i) -> Vector3i:
	var r := k
	while uf.has(r) and uf[r] != r:
		r = uf[r]
	var c := k
	while uf.has(c) and uf[c] != r:
		var nx: Vector3i = uf[c]
		uf[c] = r
		c = nx
	return r


static func _union(uf: Dictionary, a: Vector3i, b: Vector3i) -> void:
	if not uf.has(a):
		uf[a] = a
	if not uf.has(b):
		uf[b] = b
	var ra := _find(uf, a)
	var rb := _find(uf, b)
	if ra != rb:
		uf[rb] = ra


## Je gefundener Treppe eine Navmesh-Rampe (Fuß → oberster Tritt, Oberkante durch beide Punkte, 0,8 m breit) unter
## parent anlegen. Gerade Läufe als ein Kasten; Wendeltreppen (Richtungswechsel > 25°) je Abschnitt.
## Rückgabe: Anzahl Rampen.
static func add_nav_ramps(parent: Node3D, scan_root: Node, space: PhysicsDirectSpaceState3D) -> int:
	var stairs := find(scan_root, space)
	if stairs.is_empty():
		return 0
	var body := StaticBody3D.new()
	body.name = "NavStairRamps"
	body.collision_layer = LevelBuilder.NAV_ONLY_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	# 0.11.7: Fußpunkte + Laufrichtung für die örtliche Höhenkorrektur des Netzes (Mission._snap_stair_feet)
	var feet: Array = []
	for st: Dictionary in stairs:
		var tr: Array = st["treads"]
		var dv: Vector3 = tr[1] - tr[0]
		dv.y = 0.0
		if dv.length() > 0.01:
			feet.append([st["bottom"], dv.normalized(), tr[0], tr[-1]])
	body.set_meta("feet", feet)
	var n := 0
	for st: Dictionary in stairs:
		if st.get("small", false):
			continue
		# ab dem untersten Tritt (nicht ab dem Boden davor): eine Rampe bis auf den Boden hob das Netz am Fuß um eine
		# Zellhöhe an (ARCTIC1 T7: Netz 0,5 m über dem Fuß); die erste Stufe ≤ 0,35 m überbrückt Recast (Steigen 0,4 m)
		var pts: Array = (st["treads"] as Array).duplicate()
		# Abschnitte mit gleichbleibender Richtung
		var seg_start := 0
		for i in range(1, pts.size()):
			var last := i == pts.size() - 1
			var bend := false
			if not last and i + 1 < pts.size():
				var v0: Vector3 = pts[i] - pts[seg_start]
				var v1: Vector3 = pts[i + 1] - pts[i]
				bend = absf(Vector2(v0.x, v0.z).angle_to(Vector2(v1.x, v1.z))) > deg_to_rad(25.0)
			if last or bend:
				if _ramp(body, pts[seg_start], pts[i]):
					n += 1
				seg_start = i
	return n


static func _ramp(body: StaticBody3D, a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var flat := Vector3(d.x, 0, d.z)
	if flat.length() < 0.2 or rad_to_deg(atan2(d.y, flat.length())) > MAX_SLOPE_DEG:
		return false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var thick := 0.12
	var yaw := atan2(flat.x, flat.z)
	var pitch := -atan2(d.y, flat.length())
	box.size = Vector3(RAMP_W, thick, d.length())
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	cs.transform = Transform3D(basis, (a + b) * 0.5 - basis.y * thick * 0.5)
	cs.shape = box
	body.add_child(cs)
	return true
