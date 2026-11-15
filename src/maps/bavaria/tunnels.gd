extends RefCounted
## Unterirdisches Stollensystem im Stil der Kriegsjahre: Holzverschalung, Rahmen aus Stützbalken, Erdboden und
## schwache Glühlampen. Einstieg hinten am MG42-Holzhaus (offene Treppengrube an der Rückwand), Ausgänge über
## steile Holztreppen im Treppenraum des Antennenhauses und in einem Zimmer des ersten Reihenhauses (Häuserzeile).
## Der Spielboden erhält echte Aussparungen (bavaria._ground mit Löchern), die Hausböden werden an den Treppenlöchern
## ersetzt (Kollision + Darstellung). Alles unter static_root → Kollision, Navmesh und Ballistik ohne Sonderfälle.
## Stollensohle FLOOR_Y, Decke CEIL_Y: unter den Schützengräben (Sohle −1,30 m) bleiben ≥ 0,25 m Erde.

const FLOOR_Y := -3.9
const CEIL_Y := -1.7
const WIDTH := 1.6                ## lichte Breite zwischen den Verschalungen
const PLANK := 0.12
const COVER_Y := -0.35            ## Unterkante der Abdeckung über den überdeckten Treppenabschnitten
const HEAD := 2.35                ## Kopffreiheit unter Abdeckung/Kante (Figur 1,8 m + Stufensteigen 0,4 m)
const STUB := 2.0                 ## gerader Stollenansatz unter jeder Treppe
const LANDING := 1.2              ## ebener Austritt am Treppenfuß unter der hohen Abdeckung (Kopffreiheit beim Hinaufsteigen)
const FRAME_STEP := 1.6
const NAV_ANCHOR_Y := -4.2        ## tiefster Kollisionspunkt, Vielfaches der Navmesh-Zellhöhe 0,2 m (siehe build)
const LAMP_STEP := 9.0

## Einstiege in Gebäude-Lokalkoordinaten (x, z) des Treppenkopfs, Abstiegsrichtung, Laufbreite, Steigung/Auftritt.
## inside = Treppenloch im Hausboden (Hausboden Oberkante 0,05 m), sonst offene Grube im Gelände.
const ENTRANCES := [
	{"id": "mg42", "building": "woodland_shed", "top": Vector2(5.6, -2.75), "dir": Vector2(-1, 0), "width": 1.2,
		"rise": 0.19, "run": 0.27, "inside": false},
	{"id": "antennenhaus", "building": "haus_18_shed", "top": Vector2(1.70, -3.085), "dir": Vector2(1, 0), "width": 0.78,
		"rise": 0.25, "run": 0.25, "inside": true},
	{"id": "reihenhaus", "building": "reihe_40_0", "top": Vector2(2.29, 3.05), "dir": Vector2(0, 1), "width": 0.85,
		"rise": 0.25, "run": 0.25, "inside": true},
]
const HOUSE_FLOOR_TOP := 0.05
const X_AXIS := Vector2(0.576, 0.817)          ## wie bavaria.gd (Lageplan → Welt)
const Z_AXIS := Vector2(-0.817, 0.576)

var root: Node3D
var entrances := {}               ## id → Daten (Weltpunkte, siehe _entrance_data)
var nodes := {}                   ## Netzknoten (Weltlage x/z)
var segments: Array = []          ## [Vector2, Vector2] Stollenachsen
var lamps: Array[OmniLight3D] = []
var removed_furniture: Array[String] = []

# --- Geometrie aus dem Lageplan (vor dem Hausbau nutzbar) --------------------------------------------------

static func _spec(m, id: String) -> Dictionary:
	var stack: Array = []
	stack.append_array(m.layout["buildings"])
	for row in m.layout["rows"]:
		stack.append_array(row["reference_units"])
	while not stack.is_empty():
		var s: Dictionary = stack.pop_back()
		if String(s.id) == id:
			return s
		stack.append_array(s.get("extensions", []))
	return {}

## Gebäuderahmen wie bavaria._build_reference_part: [Transform3D, w, d]
static func house_frame(m, id: String) -> Array:
	var spec := _spec(m, id)
	if spec.is_empty():
		return []
	var angle := deg_to_rad(float(spec.angle))
	var direction := Vector2(cos(angle), sin(angle))
	var yaw := atan2(-direction.dot(Z_AXIS), direction.dot(X_AXIS))
	var k := float(m.layout.meters_per_reference_pixel)
	return [Transform3D(Basis(Vector3.UP, yaw), m.pixel(spec.center)), float(spec.w) * k, float(spec.d) * k]

## Treppenmaße: Anzahl Stufen, Steigung, Länge, offener Teil (Loch) – alles in Laufrichtung ab Treppenkopf.
static func stair_dims(e: Dictionary) -> Dictionary:
	var top_y := HOUSE_FLOOR_TOP if e.inside else 0.0
	var drop := top_y - FLOOR_Y
	var n := ceili(drop / float(e.rise))
	var rise := drop / n
	var run := float(e.run)
	var covered := ceili((top_y - (COVER_Y - HEAD)) / rise)
	return {"top_y": top_y, "n": n, "rise": rise, "run": run, "length": n * run, "open": (covered - 1) * run}

static func _local_rect(e: Dictionary, s0: float, s1: float, half: float) -> PackedVector2Array:
	var top: Vector2 = e.top
	var u: Vector2 = e.dir
	var v := Vector2(-u.y, u.x)
	return PackedVector2Array([top + u * s0 - v * half, top + u * s1 - v * half, top + u * s1 + v * half, top + u * s0 + v * half])

static func _to_world(xf: Transform3D, poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		var q := xf * Vector3(p.x, 0, p.y)
		out.append(Vector2(q.x, q.z))
	return out

## Aussparungen für Spielboden/Fernboden: offener Teil jeder Treppe (Weltlage)
static func hole_polygons(m) -> Array:
	var out: Array = []
	for e in ENTRANCES:
		var f := house_frame(m, e.building)
		if f.is_empty():
			continue
		var dims := stair_dims(e)
		out.append(_to_world(f[0], _local_rect(e, 0.0, dims.open, float(e.width) * 0.5)))
	return out

## Grundrisse für Deko-/Vegetationsabstand: Grube im Gelände samt Brüstung
static func footprints(m) -> Array:
	var out: Array = []
	for e in ENTRANCES:
		if e.inside:
			continue
		var f := house_frame(m, e.building)
		if f.is_empty():
			continue
		var dims := stair_dims(e)
		out.append(_to_world(f[0], _local_rect(e, -0.4, dims.open + 0.3, float(e.width) * 0.5 + PLANK + 0.35)))
	return out

# --- Bau ----------------------------------------------------------------------------------------------------

func build(m) -> void:
	var lb: LevelBuilder = m.lb
	root = Node3D.new()
	root.name = "Stollen"
	m.static_root.add_child(root)
	root.add_to_group("bavaria_tunnels")
	var wood := "h16_wood" if lb._mats.has("h16_wood") else "wood"
	var mud := "trench_mud" if lb._mats.has("trench_mud") else "earth"
	var polys: Array = []
	var mouths: Array = []
	for e in ENTRANCES:
		var house := m.static_root.get_node_or_null(String(e.building)) as Node3D
		var f := house_frame(m, e.building)
		if house == null or f.is_empty():
			push_error("Stollen: Gebäude fehlt " + String(e.building))
			continue
		var xf: Transform3D = f[0]
		var dims := stair_dims(e)
		_build_stair(m, e, dims, xf, f[1], f[2], house, wood, mud)
		var u3: Vector3 = xf.basis * Vector3(e.dir.x, 0, e.dir.y)
		var u := Vector2(u3.x, u3.z).normalized()
		var ext: float = dims.length + LANDING
		var bottom3: Vector3 = xf * Vector3(e.top.x + e.dir.x * ext, 0, e.top.y + e.dir.y * ext)
		var b := Vector2(bottom3.x, bottom3.z)
		var stub_end := b + u * STUB
		nodes[String(e.id)] = stub_end
		# Ansatz: rechteckig, stumpf an der Treppenmündung, über den Knoten hinaus (Überlappung mit dem Folgestück)
		var v := Vector2(-u.y, u.x) * WIDTH * 0.5
		var far := stub_end + u * WIDTH * 0.5
		polys.append(PackedVector2Array([b - v, far - v, far + v, b + v]))
		mouths.append({"b": b, "u": u, "half": float(e.width) * 0.5, "top_cover": COVER_Y})
		segments.append([b, stub_end])
		entrances[String(e.id)] = _entrance_data(e, dims, xf, b)
	# Netz: Abzweig nahe dem Reihenhaus, von dort zum Antennenhaus; langer Hauptstollen vom MG42-Haus
	if nodes.size() == 3:
		var r: Vector2 = nodes["reihenhaus"]
		var a: Vector2 = nodes["antennenhaus"]
		var j := r + (a - r) * 0.3
		nodes["abzweig"] = j
		for pair in [[nodes["mg42"], j], [j, a], [j, r]]:
			segments.append(pair)
			for poly in Geometry2D.offset_polyline(PackedVector2Array([pair[0], pair[1]]), WIDTH * 0.5, Geometry2D.JOIN_SQUARE, Geometry2D.END_SQUARE):
				polys.append(poly)
	var outline := _union(polys)
	# Höhenraster-Anker: Der Navmesh-Bake rastert die Höhe ab der tiefsten Kollisionsgeometrie (Zelle 0,2 m). Der
	# Stollen verschiebt dieses Minimum; der Anker legt es so, dass das Höhenraster der übrigen Karte unverändert bleibt
	# (sonst verlagern sich Netzhöhen in den Häusern um ≈ 0,1 m).
	var anchor_c: Vector2 = segments[0][0] if not segments.is_empty() else Vector2.ZERO
	m.lb.box(Vector3(anchor_c.x, NAV_ANCHOR_Y, anchor_c.y), Vector3(0.1, 0.05, 0.1), mud, 0.0, true, root).name = "NavRasterAnker"
	_floor_ceiling(m, outline, mud, wood)
	_walls(m, outline, mouths, wood)
	_frames_and_lamps(m)
	root.set_meta("entrances", entrances)
	root.set_meta("nodes", nodes)
	root.set_meta("outline", outline)
	print("BAVARIA STOLLEN: %d Einstiege, %d Abschnitte, %.0f m Stollen, %d Lampen, Möbel verlegt: %s" % [
		entrances.size(), segments.size(), total_length(), lamps.size(), str(removed_furniture)])

func total_length() -> float:
	var s := 0.0
	for seg in segments:
		s += (seg[0] as Vector2).distance_to(seg[1])
	return s

## Weltpunkte je Einstieg: Vorplatz (vor dem Treppenkopf auf Boden-/Hausbodenhöhe), Treppenkopf, Treppenfuß,
## Knoten am Stollenansatz; dazu der Gehweg (Mittellinie) für Tests/KI.
func _entrance_data(e: Dictionary, dims: Dictionary, xf: Transform3D, bottom: Vector2) -> Dictionary:
	var top: Vector2 = e.top
	var u: Vector2 = e.dir
	var approach := top - u * 0.45
	if String(e.id) == "reihenhaus":
		approach = Vector2(1.30, 2.62)      # Zimmerecke vor dem Treppenkopf (Tür vom Flur liegt daneben)
	var y: float = dims.top_y
	return {
		"approach": xf * Vector3(approach.x, y, approach.y),
		"top": xf * Vector3(top.x + u.x * 0.15, y, top.y + u.y * 0.15),
		"bottom": Vector3(bottom.x, FLOOR_Y, bottom.y),
		"node": Vector3(bottom.x, FLOOR_Y, bottom.y),
		"open_length": dims.open, "length": dims.length, "steps": dims.n, "rise": dims.rise,
		"building": String(e.building), "inside": bool(e.inside),
	}

func _union(polys: Array) -> Array:
	var acc: Array = []
	for p in polys:
		var merged: PackedVector2Array = p
		var rest: Array = []
		for q in acc:
			var res := Geometry2D.merge_polygons(merged, q)
			var outers := res.filter(func(r): return not Geometry2D.is_polygon_clockwise(r))
			if outers.size() == 1 and res.size() == 1:
				merged = outers[0]
			else:
				rest.append(q)
		rest.append(merged)
		acc = rest
	return acc

# --- Treppen -------------------------------------------------------------------------------------------------

func _build_stair(m, e: Dictionary, dims: Dictionary, xf: Transform3D, w: float, d: float, house: Node3D, wood: String, mud: String) -> void:
	var lb: LevelBuilder = m.lb
	var holder := Node3D.new()
	holder.name = "Treppe_" + String(e.id)
	root.add_child(holder)
	holder.transform = xf
	var top: Vector2 = e.top
	var u: Vector2 = e.dir
	var v := Vector2(-u.y, u.x)
	var half := float(e.width) * 0.5
	var yaw := atan2(-u.y, u.x)       # lokale Box-x-Achse entlang der Laufrichtung
	var top_y: float = dims.top_y
	var run: float = dims.run
	var at := func(s: float, t: float) -> Vector2: return top + u * s + v * t
	# Stufen (Trittstufe + massiver Unterbau bis zur Sohle)
	for k in range(1, dims.n):
		var tread: float = top_y - k * dims.rise
		var c: Vector2 = at.call((k - 0.5) * run, 0.0)
		lb.box(Vector3(c.x, FLOOR_Y, c.y), Vector3(run + 0.012, tread - FLOOR_Y, float(e.width)), "darkwood" if k % 2 else wood, yaw, false, holder)
	# Begangen wird eine unsichtbare Ersatzrampe über den Stufenkanten (wie die Originaltreppen): steile Kellertreppen
	# (bis 44°) lassen sich so ohne Stufensteigen hinauf- und hinablaufen; Navmesh/KI ebenso.
	var drop_y: float = top_y - FLOOR_Y
	var a3 := Vector3(top.x, top_y, top.y)
	var b3 := Vector3(top.x + u.x * dims.length, FLOOR_Y, top.y + u.y * dims.length)
	var xa := (b3 - a3).normalized()
	var za := Vector3(v.x, 0, v.y)
	var ya := za.cross(xa).normalized()
	if ya.y < 0:
		ya = -ya
		za = -za
	var ramp := StaticBody3D.new()
	ramp.name = "Ersatzrampe"
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(a3.distance_to(b3) + 0.1, 0.2, float(e.width))
	rcs.shape = rbox
	ramp.add_child(rcs)
	holder.add_child(ramp)
	ramp.transform = Transform3D(Basis(xa, ya, za), (a3 + b3) * 0.5 - ya * 0.1)
	ramp.set_meta("slope_deg", rad_to_deg(atan2(drop_y, dims.length)))
	var ext: float = dims.length + LANDING
	var sole: Vector2 = at.call(ext * 0.5, 0.0)
	lb.box(Vector3(sole.x, FLOOR_Y - 0.1, sole.y), Vector3(ext + 0.3, 0.1, float(e.width) + 2 * PLANK), mud, yaw, true, holder)
	# Seitliche Verschalung: offener Teil bis zur Geländeoberkante, überdeckter Teil bis unter das Erdreich
	var wall_top_open := top_y + (0.45 if not e.inside else -0.005)
	for side in [-1.0, 1.0]:
		var t: float = side * (half + PLANK * 0.5)
		var c0: Vector2 = at.call(dims.open * 0.5 - 0.06, t)
		lb.box(Vector3(c0.x, FLOOR_Y - 0.05, c0.y), Vector3(dims.open + 0.12 + PLANK, wall_top_open - FLOOR_Y + 0.05, PLANK), wood, yaw, true, holder)
		var cover_len: float = ext - dims.open
		var c1: Vector2 = at.call(dims.open + cover_len * 0.5, t)
		lb.box(Vector3(c1.x, FLOOR_Y - 0.05, c1.y), Vector3(cover_len, minf(top_y, 0.0) - 0.03 - FLOOR_Y, PLANK), wood, yaw, true, holder)
		# Stützbalken an der Verschalung
		var posts := int(dims.length / 1.1)
		for i in posts + 1:
			var s := minf(i * 1.1 + 0.2, dims.length - 0.1)
			var tread_y: float = top_y - clampi(int(s / run) + 1, 1, dims.n) * dims.rise
			var top_post: float = wall_top_open if s < dims.open else COVER_Y
			var pc: Vector2 = at.call(s, side * (half - 0.06))
			lb.box(Vector3(pc.x, tread_y, pc.y), Vector3(0.12, top_post - tread_y, 0.12), "darkwood", yaw, false, holder)
	# Stirnbrett am Treppenkopf
	var head_c: Vector2 = at.call(-PLANK * 0.5, 0.0)
	lb.box(Vector3(head_c.x, FLOOR_Y, head_c.y), Vector3(PLANK, top_y - 0.01 - FLOOR_Y, float(e.width) + 2 * PLANK), wood, yaw, true, holder)
	# Abdeckung über dem überdeckten Teil + Sturz an der Lochkante + Sturz zur niedrigeren Stollendecke
	var cover_c: Vector2 = at.call((dims.open + ext) * 0.5, 0.0)
	lb.box(Vector3(cover_c.x, COVER_Y, cover_c.y), Vector3(ext - dims.open, 0.08, float(e.width) + 2 * PLANK), wood, yaw, true, holder)
	var lintel: Vector2 = at.call(dims.open + 0.08, 0.0)
	lb.box(Vector3(lintel.x, COVER_Y, lintel.y), Vector3(0.16, minf(top_y, 0.0) - 0.01 - COVER_Y, float(e.width) + 2 * PLANK), "darkwood", yaw, true, holder)
	var drop: Vector2 = at.call(ext + 0.05, 0.0)
	lb.box(Vector3(drop.x, CEIL_Y - 0.12, drop.y), Vector3(0.10, COVER_Y - CEIL_Y + 0.12, float(e.width) + 2 * PLANK), "darkwood", yaw, true, holder)
	if e.inside:
		_house_opening(m, e, dims, house, w, d, holder, at, yaw)
	else:
		_pit_dressing(m, e, dims, holder, at, yaw, wood)
	# Lampe am Treppenfuß
	var foot: Vector2 = at.call(ext - 0.5, 0.0)
	_lamp(m, holder, Vector3(foot.x, COVER_Y - 0.05, foot.y), holder)

## Offene Grube hinter dem MG42-Haus: Brüstung, Stützen, Bretterdach über dem unteren Teil
func _pit_dressing(m, e: Dictionary, dims: Dictionary, holder: Node3D, at: Callable, yaw: float, wood: String) -> void:
	var lb: LevelBuilder = m.lb
	var half := float(e.width) * 0.5
	var s0 := maxf(0.6, dims.open - 1.7)
	var s1: float = dims.open
	for side in [-1.0, 1.0]:
		for s in [s0, s1]:
			var p: Vector2 = at.call(s, side * (half + PLANK * 0.5))
			lb.box(Vector3(p.x, 0.45, p.y), Vector3(0.13, 0.95, 0.13), "darkwood", yaw, true, holder)
	var roof: Vector2 = at.call((s0 + s1) * 0.5, 0.0)
	var r := lb.box(Vector3(roof.x, 1.40, roof.y), Vector3(s1 - s0 + 0.5, 0.07, float(e.width) + 2 * PLANK + 0.5), wood, yaw, true, holder)
	r.rotation.z = 0.10
	var beam: Vector2 = at.call(s1, 0.0)
	lb.box(Vector3(beam.x, 1.30, beam.y), Vector3(0.14, 0.12, float(e.width) + 2 * PLANK + 0.3), "darkwood", yaw, false, holder)
	# Sandsäcke an der Stirnseite (Graben-/Stollenanmutung), Einstieg bleibt frei
	var bag: Vector2 = at.call(dims.open + 0.45, 0.0)
	lb.box(Vector3(bag.x, 0.0, bag.y), Vector3(0.55, 0.42, float(e.width) + 2 * PLANK + 0.4), "sandbag", yaw, true, holder)

## Treppenloch im Hausboden: alten Boden (Kollision + Darstellung) ersetzen, Geländer, Möbel im Treppenbereich verlegen.
func _house_opening(m, e: Dictionary, dims: Dictionary, house: Node3D, w: float, d: float, holder: Node3D, at: Callable, yaw: float) -> void:
	var lb: LevelBuilder = m.lb
	var half := float(e.width) * 0.5
	var hole := Rect2(at.call(0.0, -half), Vector2.ZERO).expand(at.call(dims.open, half))
	# 1) alter durchgehender Boden: Kollisionskörper entfernen, Dreiecke aus der Hausdarstellung nehmen
	for child in house.get_children():
		if child is StaticBody3D and (child as Node3D).position.distance_to(Vector3(0, -0.3, 0)) < 0.01:
			for cs in child.get_children():
				if cs is CollisionShape3D and cs.shape is BoxShape3D and (cs.shape as BoxShape3D).size.distance_to(Vector3(w, 0.35, d)) < 0.02:
					child.free()
					break
	_strip_floor_visual(house, w, d)
	# 2) neuer Boden in vier Teilen um das Loch
	var floor_holder := Node3D.new()      # neben dem Haus (die Hülle bleibt EIN zusammengefasstes Mesh)
	floor_holder.name = "Hausboden_" + String(e.id)
	root.add_child(floor_holder)
	floor_holder.global_transform = house.global_transform
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var z0 := -d * 0.5
	var z1 := d * 0.5
	for r in [Rect2(x0, z0, hole.position.x - x0, d), Rect2(hole.end.x, z0, x1 - hole.end.x, d),
			Rect2(hole.position.x, z0, hole.size.x, hole.position.y - z0), Rect2(hole.position.x, hole.end.y, hole.size.x, z1 - hole.end.y)]:
		if r.size.x > 0.01 and r.size.y > 0.01:
			lb.box(Vector3(r.get_center().x, -0.3, r.get_center().y), Vector3(r.size.x, 0.35, r.size.y), "darkwood", 0.0, true, floor_holder)
	# 3) Geländer an der offenen Längsseite und am Lochende (Treppenkopf bleibt frei)
	var t := half + 0.03     # Seite zum Raum hin (die andere liegt an der Außenwand)
	_rail(lb, holder, at.call(0.35, t), at.call(dims.open, t))
	_rail(lb, holder, at.call(dims.open + 0.03, -half - 0.05), at.call(dims.open + 0.03, half + 0.05))
	# 4) Möbel im Treppen- und Vorplatzbereich verlegen (Raumeinrichtung lief vorher)
	var clear := hole.grow(0.12)
	var landing := Rect2(at.call(-0.85, -half - 0.6), Vector2.ZERO).expand(at.call(0.0, half + 0.9))
	var holder_name := "Einrichtung_" + String(house.name)
	var furn: Node = m.static_root.get_node_or_null(holder_name)
	if furn:
		for n in furn.find_children("*", "Node3D", true, false):
			if not is_instance_valid(n) or not n.has_meta("bounds"):
				continue
			var b: AABB = n.get_meta("bounds")
			var fp := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
			if b.position.y < 1.4 and (fp.intersects(clear) or fp.intersects(landing)):
				removed_furniture.append(String(house.name) + "/" + String(n.get_meta("furniture_type", n.name)))
				if m.interior_decoration and "furnishings" in m.interior_decoration:
					m.interior_decoration.furnishings.erase(n)
				n.free()
	house.set_meta("tunnel_hatch", {"hole": hole, "id": String(e.id)})

func _rail(lb: LevelBuilder, holder: Node3D, a: Vector2, b: Vector2) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.1:
		return
	var yaw := atan2(-dir.y, dir.x)
	var mid := (a + b) * 0.5
	var y0 := HOUSE_FLOOR_TOP
	lb.box(Vector3(mid.x, y0 + 0.92, mid.y), Vector3(len, 0.06, 0.06), "darkwood", yaw, true, holder)
	lb.box(Vector3(mid.x, y0 + 0.45, mid.y), Vector3(len, 0.05, 0.04), "darkwood", yaw, false, holder)
	var posts := maxi(1, int(len / 0.9))
	for i in posts + 1:
		var p := a.lerp(b, float(i) / posts)
		lb.box(Vector3(p.x, y0, p.y), Vector3(0.07, 0.95, 0.07), "darkwood", 0.0, true, holder)

## Bodenplatte der Baukasten-Hülle (Quader w × 0,35 × d bei y −0,30) aus dem zusammengefassten Hausmesh entfernen.
static func _strip_floor_visual(house: Node3D, w: float, d: float) -> int:
	var removed := 0
	for vis in house.find_children("*", "MeshInstance3D", false, false):
		var src := (vis as MeshInstance3D).mesh as ArrayMesh
		if src == null:
			continue
		var out := ArrayMesh.new()
		for si in src.get_surface_count():
			var arrays := src.surface_get_arrays(si)
			var mat := src.surface_get_material(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			var tri_count := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
			var keep := PackedInt32Array()
			var changed := false
			for ti in tri_count:
				var ids := [idx[ti * 3], idx[ti * 3 + 1], idx[ti * 3 + 2]] if idx.size() > 0 else [ti * 3, ti * 3 + 1, ti * 3 + 2]
				var floor_tri := true
				for i in ids:
					var p := verts[i]
					if absf(absf(p.x) - w * 0.5) > 0.01 or absf(absf(p.z) - d * 0.5) > 0.01 or (absf(p.y - 0.05) > 0.01 and absf(p.y + 0.3) > 0.01):
						floor_tri = false
						break
				if floor_tri:
					changed = true
					removed += 1
					continue
				keep.append_array(ids)
			if changed:
				arrays[Mesh.ARRAY_INDEX] = keep
			if keep.is_empty() and changed:
				continue
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, mat)
		if removed > 0:
			(vis as MeshInstance3D).mesh = out
	return removed

# --- Stollen ---------------------------------------------------------------------------------------------------

func _floor_ceiling(m, outline: Array, mud: String, wood: String) -> void:
	var lb: LevelBuilder = m.lb
	for poly in outline:
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			push_error("Stollen: Grundriss nicht triangulierbar")
			continue
		for level in [[FLOOR_Y, mud, true, "Stollensohle"], [CEIL_Y, wood, false, "Stollendecke"]]:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var up: bool = level[2]
			for i in range(0, tri.size(), 3):
				var a: Vector2 = poly[tri[i]]
				var b: Vector2 = poly[tri[i + 1]]
				var c: Vector2 = poly[tri[i + 2]]
				var ccw := (b - a).cross(c - a) > 0
				# Godot: Vorderseite im Uhrzeigersinn (von der Normalen aus gesehen)
				if ccw != up:
					var tmp := b
					b = c
					c = tmp
				for q in [a, b, c]:
					st.set_normal(Vector3.UP if up else Vector3.DOWN)
					st.set_uv(q * (0.45 if up else 0.6))
					st.add_vertex(Vector3(q.x, level[0], q.y))
			var mi := MeshInstance3D.new()
			mi.name = level[3]
			mi.mesh = st.commit()
			mi.material_override = lb.mat(level[1])
			root.add_child(mi)
			mi.create_trimesh_collision()

func _walls(m, outline: Array, mouths: Array, wood: String) -> void:
	var lb: LevelBuilder = m.lb
	var h := CEIL_Y + 0.15 - (FLOOR_Y - 0.05)
	for poly in outline:
		for i in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			var pieces: Array = [[a, b]]
			for mo in mouths:
				var on_line: bool = absf((a - mo.b).dot(mo.u)) < 0.03 and absf((b - mo.b).dot(mo.u)) < 0.03
				if not on_line:
					continue
				var v := Vector2(-mo.u.y, mo.u.x)
				var ta: float = (a - mo.b).dot(v)
				var tb: float = (b - mo.b).dot(v)
				pieces = []
				var lo := minf(ta, tb)
				var hi := maxf(ta, tb)
				for iv in [[lo, minf(hi, -mo.half - PLANK)], [maxf(lo, mo.half + PLANK), hi]]:
					if iv[1] - iv[0] > 0.02:
						pieces.append([mo.b + v * iv[0], mo.b + v * iv[1]])
			for pc in pieces:
				var p0: Vector2 = pc[0]
				var p1: Vector2 = pc[1]
				var dir := p1 - p0
				var len := dir.length()
				if len < 0.02:
					continue
				var nrm := Vector2(-dir.y, dir.x).normalized()
				var mid := (p0 + p1) * 0.5
				if Geometry2D.is_point_in_polygon(mid + nrm * 0.05, poly):
					nrm = -nrm
				var c := mid + nrm * PLANK * 0.5
				lb.box(Vector3(c.x, FLOOR_Y - 0.05, c.y), Vector3(len + PLANK, h, PLANK), wood, atan2(-dir.y, dir.x), true, root)

func _frames_and_lamps(m) -> void:
	var lb: LevelBuilder = m.lb
	var junctions: Array = nodes.values()
	var since_lamp := LAMP_STEP * 0.5
	for seg in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var len := a.distance_to(b)
		if len < 0.5:
			continue
		var u := (b - a) / len
		var v := Vector2(-u.y, u.x)
		var yaw := atan2(-u.y, u.x)
		var s := 0.9
		while s < len - 0.6:
			var p := a + u * s
			var near_node := false
			for q in junctions:
				if p.distance_to(q) < 1.7:
					near_node = true
			if not near_node:
				for side in [-1.0, 1.0]:
					var pp: Vector2 = p + v * side * (WIDTH * 0.5 - 0.08)
					lb.box(Vector3(pp.x, FLOOR_Y, pp.y), Vector3(0.15, CEIL_Y - FLOOR_Y, 0.15), "darkwood", yaw, true, root)
				lb.box(Vector3(p.x, CEIL_Y - 0.16, p.y), Vector3(0.16, 0.16, WIDTH), "darkwood", yaw, false, root)
				since_lamp += FRAME_STEP
				if since_lamp >= LAMP_STEP:
					since_lamp = 0.0
					_lamp(m, root, Vector3(p.x, CEIL_Y - 0.16, p.y), root)
			s += FRAME_STEP

## Schwache Glühlampe am Kappbalken (Fassung, Birne, Licht ohne Schatten)
func _lamp(m, parent: Node3D, pos: Vector3, _owner: Node3D) -> void:
	var lamp := Node3D.new()
	lamp.name = "Stollenlampe_%d" % lamps.size()
	parent.add_child(lamp)
	lamp.position = pos
	var wire := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.008
	wm.bottom_radius = 0.008
	wm.height = 0.18
	wire.mesh = wm
	wire.position.y = -0.09
	wire.material_override = m.lb.mat("darkwood")
	lamp.add_child(wire)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.10
	bulb.mesh = sm
	bulb.position.y = -0.22
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.85, 0.55)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.72, 0.38)
	bm.emission_energy_multiplier = 2.2
	bulb.material_override = bm
	lamp.add_child(bulb)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.42)
	light.light_energy = 0.75
	light.omni_range = 5.5
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 10.0
	light.position.y = -0.26
	lamp.add_child(light)
	lamp.add_to_group("bavaria_tunnel_lamps")
	lamps.append(light)
