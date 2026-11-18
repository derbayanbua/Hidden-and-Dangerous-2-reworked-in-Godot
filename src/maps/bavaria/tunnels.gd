extends RefCounted
## Unterirdisches Stollensystem im Stil der Kriegsjahre: Holzverschalung, Rahmen aus Stützbalken, Erdboden und
## schwache Glühlampen. Einstieg hinten am MG42-Holzhaus (offene Treppengrube an der Rückwand), Ausgänge über
## steile Holztreppen im Treppenraum des Antennenhauses und in einem Zimmer des ersten Reihenhauses (Häuserzeile).
## Der Spielboden erhält echte Aussparungen (bavaria._ground mit Löchern), die Hausböden werden an den Treppenlöchern
## ersetzt (Kollision + Darstellung). Alles unter static_root → Kollision, Navmesh und Ballistik ohne Sonderfälle.
## Stollensohle FLOOR_Y, Decke CEIL_Y: unter den Schützengräben (Sohle −1,30 m) bleiben ≥ 0,25 m Erde.
## Ausbau 11/2026: Gangachsen mit Bögen/Knicken (deterministisch, weichen Keller/Treppen aus), Sohle mit leichtem Gefälle
## zu den Treppen (bis −0,18 m, nie unter NAV_ANCHOR_Y), zwei Ausbrüche (breiter, Firste +0,1 m), unregelmäßige
## Verschalung, Kabel, vier kleine Räume (Funkraum, Lager/Munition, Schlafnische, Sanitätsecke) und ein Stichgang mit
## Stahltür zum Geheimraum (Tür/Schloss/Knopf in bunker_extras.gd). Höhen über floor_at/ceil_at (exakt wie das Netz).

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
const LAMP_STEP := 8.0
## Ausbau „realistischer“ (11/2026): kurvige Gänge mit Knicken, Gefälle, Ausbrüche, kleine Räume, Geheimraum.
const DROP := 0.18                ## Gefälle: Sohle sinkt abseits der Treppen bis 0,18 m (bleibt über NAV_ANCHOR_Y)
const RAISE := 0.1                ## höhere Firste an Ausbrüchen (Decke bleibt ≥ 0,3 m unter der Grabensohle −1,30)
const CURVE_STEP := 2.6           ## Stützpunktabstand der Gangachse (Knicke)
const WIDE := 2.3                 ## Breite der Ausbrüche
const NECK := 1.0                 ## Durchgang Gang → Raum
const NECK_W := 1.1
const ROOM_SPECS := [
	{"id": "funkraum", "chain": 0, "t": 0.30, "w": 3.0, "d": 2.8},
	{"id": "lager", "chain": 0, "t": 0.80, "w": 3.2, "d": 2.6},
	{"id": "schlafnische", "chain": 1, "t": 0.50, "w": 2.6, "d": 2.2},
	{"id": "sanitaet", "chain": 2, "t": 0.55, "w": 2.6, "d": 2.4},
]
const SECRET_W := 3.2
const SECRET_D := 3.0

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
var chains: Array = []            ## Gangachsen (PackedVector2Array): 0 MG42→Abzweig, 1 →Antennenhaus, 2 →Reihenhaus, 3 Stichgang
var rooms: Array = []             ## kleine Räume {id, c, t, n, w, d, chain, s, junction, mouth, poly}
var secret := {}                  ## Geheimraum hinter der Stahltür (gleiche Felder + end/door/keypad/dir/side)
var wide_spots: Array = []        ## Ausbrüche {p, t, poly}
var digit_spots: Array = []       ## Ziffern-Fundorte unter Tage / an den Treppen {digit, order, pos, normal, place}
var decor_count := 0
var _mouth_pts: Array = []
var _blockers: Array = []         ## Grundrisse, unter denen kein Gang liegen darf (Keller Haus 16)
var _stair_lines: Array = []      ## [Treppenkopf, Treppenfuß, id] (Welt 2D)
var _tris: Array = []             ## Sohle/Decke: [a, b, c, fa, fb, fc, ca, cb, cc]
var _occupied: Array = []         ## Räume/Ausbrüche (Abstandsprüfung)
var _mats := {}

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
		_mouth_pts.append(b)
		var top3: Vector3 = xf * Vector3(e.top.x, 0, e.top.y)
		_stair_lines.append([Vector2(top3.x, top3.z), b, String(e.id)])
		_stub_digit(e, xf, b, u)
	if m.has_method("_house16_cellar_hole"):
		_blockers.append(m._house16_cellar_hole())
	# Netz: Abzweig nahe dem Reihenhaus, von dort zum Antennenhaus; langer Hauptstollen vom MG42-Haus.
	# Gänge kurvig mit Knicken (deterministisch), Ausbrüche, Stichgang zum Geheimraum, vier kleine Räume.
	if nodes.size() == 3:
		var r: Vector2 = nodes["reihenhaus"]
		var a: Vector2 = nodes["antennenhaus"]
		var j := r + (a - r) * 0.3
		nodes["abzweig"] = j
		for sp in [[nodes["mg42"], j, 11, ["mg42"]], [j, a, 23, ["antennenhaus"]], [j, r, 37, ["reihenhaus"]]]:
			_add_chain(_curve(sp[0], sp[1], sp[2], sp[3]), polys)
		_add_wide_spots(polys)
		_place_secret(m, polys)
		_place_rooms(m, polys)
	var outline := _union(polys)
	# Höhenraster-Anker: Der Navmesh-Bake rastert die Höhe ab der tiefsten Kollisionsgeometrie (Zelle 0,2 m). Der
	# Stollen verschiebt dieses Minimum; der Anker legt es so, dass das Höhenraster der übrigen Karte unverändert bleibt
	# (sonst verlagern sich Netzhöhen in den Häusern um ≈ 0,1 m).
	var anchor_c: Vector2 = segments[0][0] if not segments.is_empty() else Vector2.ZERO
	m.lb.box(Vector3(anchor_c.x, NAV_ANCHOR_Y, anchor_c.y), Vector3(0.1, 0.05, 0.1), mud, 0.0, true, root).name = "NavRasterAnker"
	_floor_ceiling(m, outline, mud, wood)
	_walls(m, outline, mouths, wood)
	_frames_and_lamps(m)
	_decorate(m, wood, mud)
	root.set_meta("entrances", entrances)
	root.set_meta("nodes", nodes)
	root.set_meta("outline", outline)
	print("BAVARIA STOLLEN: %d Einstiege, %d Abschnitte, %.0f m Stollen, %d Lampen, %d Räume + Geheimraum %s, %d Ausbrüche, %d Deko, Möbel verlegt: %s" % [
		entrances.size(), segments.size(), total_length(), lamps.size(), rooms.size(), str(not secret.is_empty()),
		wide_spots.size(), decor_count, str(removed_furniture)])

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

## Gangachse a → b mit sanften Bögen und kleinen Knicken (Seed je Gang). Weicht der Bogen dem Keller von Haus 16, fremden
## Treppen oder schon gebauten Gängen nicht aus, wird er flacher bis gerade.
func _curve(a: Vector2, b: Vector2, seed_value: int, own_ids: Array) -> PackedVector2Array:
	var len := a.distance_to(b)
	var n := maxi(2, ceili(len / CURVE_STEP))
	var u := (b - a) / maxf(len, 0.01)
	var v := Vector2(-u.y, u.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var amp := clampf(len * 0.09, 0.6, 2.4) * (1.0 if rng.randf() < 0.5 else -1.0)
	var waves := 1.0 if len < 25.0 else 1.6
	var jit: Array = []
	for i in n + 1:
		jit.append(rng.randf_range(-0.35, 0.35))
	for k in [1.0, 0.7, 0.45, 0.25, 0.0]:
		var pts := PackedVector2Array()
		for i in n + 1:
			var f := float(i) / n
			var env := sin(PI * f)
			pts.append(a + u * len * f + v * k * (amp * sin(PI * waves * f) * env + float(jit[i]) * env))
		if k == 0.0 or _axis_ok(pts, own_ids, true):
			return pts
	return PackedVector2Array([a, b])

func _axis_ok(pts: PackedVector2Array, own_ids: Array, check_chains: bool, skip_near := Vector2.INF) -> bool:
	for i in pts.size() - 1:
		for k in 5:
			var q := pts[i].lerp(pts[i + 1], k / 4.0)
			for poly in _blockers:
				if _dist_poly(q, poly) < WIDTH * 0.5 + 1.2:
					return false
			for sl in _stair_lines:
				if not own_ids.has(sl[2]) and _seg_dist(q, sl[0], sl[1]) < WIDTH * 0.5 + 0.9:
					return false
			if check_chains:
				var near_end := q.distance_to(pts[0]) < 4.0 or q.distance_to(pts[-1]) < 4.0 or q.distance_to(skip_near) < 3.0
				if not near_end:
					for c in chains:
						if _dist_polyline(q, c) < WIDTH + 0.8:
							return false
	return true

func _add_chain(pts: PackedVector2Array, polys: Array) -> void:
	chains.append(pts)
	for i in pts.size() - 1:
		segments.append([pts[i], pts[i + 1]])
	polys.append_array(Geometry2D.offset_polyline(pts, WIDTH * 0.5, Geometry2D.JOIN_MITER, Geometry2D.END_SQUARE))

static func chain_length(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size() - 1:
		s += pts[i].distance_to(pts[i + 1])
	return s

## Punkt und Richtung bei Bogenlänge s
static func chain_at(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if s <= acc + l or i == pts.size() - 2:
			var f := clampf((s - acc) / maxf(l, 0.001), 0.0, 1.0)
			return [pts[i].lerp(pts[i + 1], f), (pts[i + 1] - pts[i]).normalized()]
		acc += l
	return [pts[-1], Vector2.RIGHT]

## Achspunkte zwischen Bogenlänge s0 und s1 (beide Richtungen), inklusive Endpunkte
static func chain_between(pts: PackedVector2Array, s0: float, s1: float) -> Array:
	var out: Array = [chain_at(pts, s0)[0]]
	var acc := 0.0
	var marks: Array = []
	for i in range(1, pts.size() - 1):
		acc += pts[i - 1].distance_to(pts[i])
		if acc > minf(s0, s1) + 0.3 and acc < maxf(s0, s1) - 0.3:
			marks.append([acc, pts[i]])
	if s1 < s0:
		marks.reverse()
	for mk in marks:
		out.append(mk[1])
	out.append(chain_at(pts, s1)[0])
	return out

static func _rect(c: Vector2, t: Vector2, n: Vector2, w: float, d: float) -> PackedVector2Array:
	var p := PackedVector2Array([c - t * w * 0.5 - n * d * 0.5, c + t * w * 0.5 - n * d * 0.5, c + t * w * 0.5 + n * d * 0.5, c - t * w * 0.5 + n * d * 0.5])
	if Geometry2D.is_polygon_clockwise(p):
		p.reverse()
	return p

static func _dist_poly(q: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(q, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()]).distance_to(q))
	return best

static func _seg_dist(q: Vector2, a: Vector2, b: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q)

static func _dist_polyline(q: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, _seg_dist(q, pts[i], pts[i + 1]))
	return best

## Raum/Ausbruch frei von Gängen, Treppen, Keller und anderen Räumen?
func _area_ok(m, poly: PackedVector2Array, c: Vector2, chain_clear: float) -> bool:
	if not m.inside_map(Vector3(c.x, 0, c.y)):
		return false
	for ch in chains:
		var l := chain_length(ch)
		var s := 0.0
		while s <= l:
			if _dist_poly(chain_at(ch, s)[0], poly) < chain_clear:
				return false
			s += 0.5
	var grown: Array = Geometry2D.offset_polygon(poly, 0.45)
	for o in _occupied:
		if not Geometry2D.intersect_polygons(grown[0], o).is_empty():
			return false
	var far: Array = Geometry2D.offset_polygon(poly, 1.5)
	for bl in _blockers:
		if not Geometry2D.intersect_polygons(far[0], bl).is_empty():
			return false
	for sl in _stair_lines:
		for k in 9:
			if _dist_poly((sl[0] as Vector2).lerp(sl[1], k / 8.0), poly) < 1.3:
				return false
	return true

func _add_wide_spots(polys: Array) -> void:
	for ci in chains.size():
		var pts: PackedVector2Array = chains[ci]
		var l := chain_length(pts)
		if l < 14.0:
			continue
		for f in [0.36, 0.68]:
			var at := chain_at(pts, l * f)
			var p: Vector2 = at[0]
			var t: Vector2 = at[1]
			var ok := true
			for poly in _blockers:
				ok = ok and _dist_poly(p, poly) > WIDE * 0.5 + 1.2
			for sl in _stair_lines:
				ok = ok and _seg_dist(p, sl[0], sl[1]) > WIDE * 0.5 + 1.0
			for q in nodes.values():
				ok = ok and p.distance_to(q) > 3.5
			if not ok:
				continue
			var poly := _rect(p, t, Vector2(-t.y, t.x), 2.4, WIDE)
			polys.append(poly)
			_occupied.append(poly)
			wide_spots.append({"p": p, "t": t, "poly": poly})

## Kleine Räume seitlich am Gang, über einen kurzen Durchgang erreichbar
func _place_rooms(m, polys: Array) -> void:
	for k in ROOM_SPECS.size():
		var spec: Dictionary = ROOM_SPECS[k]
		var pts: PackedVector2Array = chains[int(spec.chain)]
		var l := chain_length(pts)
		var done := false
		for dt in [0.0, 0.07, -0.07, 0.14, -0.14, 0.21, -0.21, 0.28, -0.28, 0.35, -0.35]:
			if done:
				break
			var f := clampf(float(spec.t) + dt, 0.12, 0.88)
			for side: float in ([1.0, -1.0] if k % 2 == 0 else [-1.0, 1.0]):
				var at := chain_at(pts, l * f)
				var p: Vector2 = at[0]
				var t: Vector2 = at[1]
				var n := Vector2(-t.y, t.x) * side
				var c := p + n * (WIDTH * 0.5 + NECK + float(spec.d) * 0.5)
				var poly := _rect(c, t, n, spec.w, spec.d)
				var near_wide := false
				for ws in wide_spots:
					near_wide = near_wide or (ws.p as Vector2).distance_to(p) < 3.0
				if near_wide or not _area_ok(m, poly, c, WIDTH * 0.5 + 0.45):
					continue
				var o0 := WIDTH * 0.5 - 0.2
				var o1 := WIDTH * 0.5 + NECK + 0.15
				polys.append(_rect(p + n * (o0 + o1) * 0.5, t, n, NECK_W, o1 - o0))
				polys.append(poly)
				_occupied.append(poly)
				rooms.append({"id": String(spec.id), "c": c, "t": t, "n": n, "w": float(spec.w), "d": float(spec.d),
					"chain": int(spec.chain), "s": l * f, "junction": p, "mouth": p + n * (WIDTH * 0.5 + NECK * 0.5), "poly": poly})
				done = true
				break
		if not done:
			push_error("Stollen: kein Platz für Raum " + String(spec.id))

## Stichgang abseits mit Knick, am Ende Stahltür (Durchgang), dahinter der Geheimraum
func _place_secret(m, polys: Array) -> void:
	for ci in [0, 1, 2]:
		var pts: PackedVector2Array = chains[ci]
		var l := chain_length(pts)
		for f in [0.55, 0.45, 0.65, 0.35, 0.75, 0.25]:
			for side: float in [1.0, -1.0]:
				for bend: float in [1.0, -1.0]:
					var at := chain_at(pts, l * f)
					var p: Vector2 = at[0]
					var t: Vector2 = at[1]
					var n := Vector2(-t.y, t.x) * side
					var spur := PackedVector2Array([p, p + n * 2.4, p + n * 4.0 + t * bend * 1.1, p + n * 5.6 + t * bend * 1.1])
					var dl := n
					var end: Vector2 = spur[3]
					var c := end + dl * (1.4 + SECRET_D * 0.5)
					var side_v := Vector2(-dl.y, dl.x)
					var poly := _rect(c, side_v, dl, SECRET_W, SECRET_D)
					var ok := true
					for ws in wide_spots:
						ok = ok and (ws.p as Vector2).distance_to(p) > 3.5
					for q in nodes.values():
						ok = ok and p.distance_to(q) > 4.0
					if not ok or not _axis_ok(spur, [], true, p):
						continue
					if not _area_ok(m, poly, c, WIDTH * 0.5 + 0.6):
						continue
					_add_chain(spur, polys)
					polys.append(_rect(end + dl * 1.0, side_v, dl, NECK_W, 1.1))
					polys.append(poly)
					_occupied.append(poly)
					var sp_poly: Array = Geometry2D.offset_polyline(spur, WIDTH * 0.5 + 0.2)
					_occupied.append_array(sp_poly)
					secret = {"id": "geheimraum", "c": c, "t": side_v, "n": dl, "w": SECRET_W, "d": SECRET_D, "chain": ci,
						"s": l * f, "junction": p, "end": end, "dir": dl, "side": side_v, "door": end + dl * 1.05,
						"keypad": end + dl * 0.77 + side_v * 0.725, "mouth": end + dl * 1.6, "poly": poly}
					return
	push_error("Stollen: kein Platz für den Geheimraum")

## Höhen: Sohle mit leichtem Gefälle zu den Treppen hin (Wasserablauf), Firste an Ausbrüchen etwas höher
func _drop(q: Vector2) -> float:
	var d := INF
	for b in _mouth_pts:
		d = minf(d, q.distance_to(b))
	return DROP * clampf((d - 3.0) / 14.0, 0.0, 1.0)

func _floor_h(q: Vector2) -> float:
	return FLOOR_Y - _drop(q)

func _ceil_h(q: Vector2) -> float:
	var raise := 0.0
	for ws in wide_spots:
		if (ws.p as Vector2).distance_to(q) < 1.9:
			raise = RAISE
	return CEIL_Y - _drop(q) + raise

func _tri_lookup(p: Vector2, ceil_level: bool) -> float:
	for tr in _tris:
		if Geometry2D.point_is_inside_triangle(p, tr[0], tr[1], tr[2]):
			var a: Vector2 = tr[0]
			var b: Vector2 = tr[1]
			var c: Vector2 = tr[2]
			var den := (b - a).cross(c - a)
			if absf(den) < 1e-6:
				continue
			var wb := (p - a).cross(c - a) / den
			var wc := (b - a).cross(p - a) / den
			var wa := 1.0 - wb - wc
			var o := 6 if ceil_level else 3
			return wa * float(tr[o]) + wb * float(tr[o + 1]) + wc * float(tr[o + 2])
	return _ceil_h(p) if ceil_level else _floor_h(p)

## Sohlenhöhe (exakt wie das Sohlennetz) an einem Weltpunkt
func floor_at(p: Vector2) -> float:
	return _tri_lookup(p, false)

func ceil_at(p: Vector2) -> float:
	return _tri_lookup(p, true)

func _floor_ceiling(m, outline: Array, mud: String, wood: String) -> void:
	var lb: LevelBuilder = m.lb
	for poly in outline:
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			push_error("Stollen: Grundriss nicht triangulierbar")
			continue
		for i in range(0, tri.size(), 3):
			var qa: Vector2 = poly[tri[i]]
			var qb: Vector2 = poly[tri[i + 1]]
			var qc: Vector2 = poly[tri[i + 2]]
			_tris.append([qa, qb, qc, _floor_h(qa), _floor_h(qb), _floor_h(qc), _ceil_h(qa), _ceil_h(qb), _ceil_h(qc)])
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
					st.add_vertex(Vector3(q.x, _floor_h(q) if up else _ceil_h(q), q.y))
			var mi := MeshInstance3D.new()
			mi.name = level[3]
			mi.mesh = st.commit()
			mi.material_override = lb.mat(level[1])
			root.add_child(mi)
			mi.create_trimesh_collision()

func _walls(m, outline: Array, mouths: Array, wood: String) -> void:
	var lb: LevelBuilder = m.lb
	var base := FLOOR_Y - 0.05 - DROP
	var h := CEIL_Y + 0.15 - base
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
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
				var yaw := atan2(-dir.y, dir.x)
				lb.box(Vector3(c.x, base, c.y), Vector3(len + PLANK, h, PLANK), wood, yaw, true, root)
				# Unregelmäßige Verschalung: einzelne vorstehende, leicht schiefe Bretter und Erdflecken (nur Optik)
				if len > 0.7:
					for k in (2 if len > 2.5 else 1):
						var f := rng.randf_range(0.2, 0.8)
						var sp: Vector2 = p0.lerp(p1, f) - nrm * 0.018
						var bw := minf(len * rng.randf_range(0.35, 0.7), 1.8)
						var by := FLOOR_Y + rng.randf_range(0.15, 1.8)
						var strip := lb.box(Vector3(sp.x, by, sp.y), Vector3(bw, rng.randf_range(0.12, 0.22), 0.03),
							"darkwood" if rng.randf() < 0.5 else wood, yaw, false, root)
						strip.rotation.z = rng.randf_range(-0.07, 0.07)
					if rng.randf() < 0.18:
						var ep: Vector2 = p0.lerp(p1, rng.randf_range(0.3, 0.7)) - nrm * 0.012
						lb.box(Vector3(ep.x, FLOOR_Y + rng.randf_range(0.6, 1.3), ep.y), Vector3(minf(len * 0.3, 0.6), 0.35, 0.02),
							"trench_mud" if lb._mats.has("trench_mud") else "darkwood", yaw, false, root)

## Rahmen aus Stützbalken entlang aller Gangachsen, Lampen im Abstand LAMP_STEP; Ausbrüche/Abzweige/Durchgänge frei
func _frames_and_lamps(m) -> void:
	var lb: LevelBuilder = m.lb
	var keep_free: Array = nodes.values()
	for rm in rooms:
		keep_free.append(rm.junction)
	if not secret.is_empty():
		keep_free.append(secret.junction)
	for ci in chains.size():
		var pts: PackedVector2Array = chains[ci]
		var len := chain_length(pts)
		var next_lamp := 3.0
		var s := 0.9
		while s < len - 0.6:
			var at := chain_at(pts, s)
			var p: Vector2 = at[0]
			var u: Vector2 = at[1]
			var v := Vector2(-u.y, u.x)
			var yaw := atan2(-u.y, u.x)
			var free := true
			for q in keep_free:
				if p.distance_to(q) < 1.6:
					free = false
			for ws in wide_spots:
				if p.distance_to(ws.p) < 1.6:
					free = false
			if ci == 3 and s > len - 1.0:
				free = false
			if free:
				var cy := ceil_at(p)
				for side in [-1.0, 1.0]:
					var pp: Vector2 = p + v * side * (WIDTH * 0.5 - 0.08)
					var fy := floor_at(pp) - 0.04
					lb.box(Vector3(pp.x, fy, pp.y), Vector3(0.15, cy - fy, 0.15), "darkwood", yaw, true, root)
				lb.box(Vector3(p.x, cy - 0.16, p.y), Vector3(0.16, 0.16, WIDTH), "darkwood", yaw, false, root)
				if s >= next_lamp:
					next_lamp = s + LAMP_STEP
					_lamp(m, root, Vector3(p.x, cy - 0.16, p.y), root)
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
	light.set_meta("base_energy", light.light_energy)
	light.set_meta("bulb", bm)       # Flackern (bunker_extras.gd) dimmt Licht und Birne gemeinsam
	lamp.add_child(light)
	lamp.add_to_group("bavaria_tunnel_lamps")
	lamps.append(light)

# --- Ausstattung (Primitive + vorhandene Projektmodelle, keine neuen Originaldateien) ---------------------------------

func room(id: String) -> Dictionary:
	if id == "geheimraum":
		return secret
	for rm in rooms:
		if rm.id == id:
			return rm
	return {}

## Weg (Sohlenpunkte) vom MG42-Einstieg zu einem Ziel: Ausgang (antennenhaus/reihenhaus), Raum-id oder „geheimraum“
func walk_route(target: String) -> Array:
	var mg: Dictionary = entrances["mg42"]
	var pts: Array = [mg.top, mg.bottom]
	var l0 := chain_length(chains[0])
	var path2: Array = []
	var tail: Array = []
	if target in ["antennenhaus", "reihenhaus"]:
		var ci := 1 if target == "antennenhaus" else 2
		path2 = chain_between(chains[0], 0.0, l0) + chain_between(chains[ci], 0.0, chain_length(chains[ci]))
		var dst: Dictionary = entrances[target]
		tail = [dst.bottom, dst.top, dst.approach]
	else:
		var rm := room(target)
		if rm.is_empty():
			return []
		var ci: int = rm.chain
		if ci == 0:
			path2 = chain_between(chains[0], 0.0, rm.s)
		else:
			path2 = chain_between(chains[0], 0.0, l0) + chain_between(chains[ci], 0.0, rm.s)
		if target == "geheimraum":
			path2 += chain_between(chains[3], 0.0, chain_length(chains[3]))
			path2.append(rm.door)
		path2.append(rm.mouth)
		path2.append(rm.c)
	for q in path2:
		pts.append(Vector3(q.x, floor_at(q), q.y))
	pts.append_array(tail)
	return pts

## Ziffern an den Treppen: I = Stirnbrett innen in der Grube am MG42-Haus, IV = Verschalung am Treppenfuß unter dem Reihenhaus
func _stub_digit(e: Dictionary, xf: Transform3D, b: Vector2, u: Vector2) -> void:
	if String(e.id) == "mg42":
		# Seitliche Verschalung der Grube, 1,5 m hinter dem Treppenkopf, gut 1 m über der Stufe (beim Abstieg sichtbar)
		var top: Vector2 = e.top
		var dir: Vector2 = e.dir
		var lv := Vector2(-dir.y, dir.x)
		var dims := stair_dims(e)
		var s := 1.5
		var tread: float = dims.top_y - ceili(s / float(dims.run)) * float(dims.rise)
		var q: Vector2 = top + dir * s + lv * (float(e.width) * 0.5 - 0.004)
		var pos: Vector3 = xf * Vector3(q.x, tread + 1.0, q.y)
		var nv: Vector3 = (xf.basis * Vector3(-lv.x, 0, -lv.y)).normalized()
		digit_spots.append({"digit": "1", "order": "I", "pos": pos, "normal": nv,
			"place": "Treppengrube hinter dem MG42-Haus, Seitenverschalung"})
	elif String(e.id) == "reihenhaus":
		var v := Vector2(-u.y, u.x)
		var p := b + u * 1.0 + v * (WIDTH * 0.5 - 0.015)
		digit_spots.append({"digit": "5", "order": "IV", "pos": Vector3(p.x, FLOOR_Y + 1.45, p.y), "normal": Vector3(-v.x, 0, -v.y),
			"place": "Stollen am Treppenfuß unter dem Reihenhaus, Seitenwand"})

func _mat(key: String, color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var mt := StandardMaterial3D.new()
		mt.albedo_color = color
		mt.roughness = rough
		mt.metallic = metal
		_mats[key] = mt
	return _mats[key]

func _rp(rm: Dictionary, lx: float, ly: float) -> Vector2:
	return (rm.c as Vector2) + (rm.t as Vector2) * lx + (rm.n as Vector2) * ly

static func _yaw_of(d: Vector2) -> float:
	return atan2(-d.y, d.x)

## Kiste/Quader auf der Sohle (lift = Höhe über der Sohle); mat = Baukasten-Material oder eigenes Material
func _dbox(m, p: Vector2, lift: float, size: Vector3, mat, yaw: float, collide := false) -> Node3D:
	var n: Node3D = m.lb.box(Vector3(p.x, floor_at(p) + lift, p.y), size, mat if mat is String else "wood", yaw, collide, root)
	if mat is Material:
		for c in n.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).material_override = mat
	decor_count += 1
	return n

func _dcyl(p: Vector2, lift: float, r: float, h: float, mat: Material, collide := false) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position.y = h * 0.5
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = h
		cs.shape = sh
		cs.position.y = h * 0.5
		body.add_child(cs)
	root.add_child(body)
	body.position = Vector3(p.x, floor_at(p) + lift, p.y)
	decor_count += 1
	return body

func _dprop(m, model: String, p: Vector2, lift: float, yaw: float, scale_value := 1.0) -> Node3D:
	if not ("_templates" in m) or m._templates == null:
		return null
	var n: Node3D = m._templates.prop(model, Vector3(p.x, floor_at(p) + lift, p.y), yaw, scale_value, false)
	if n:
		n.reparent(root)
		decor_count += 1
	return n

## Bild an der Wand (Quad, Vorderseite zeigt in normal)
func _wall_picture(pos: Vector3, normal: Vector3, size: Vector2, tex: Texture2D) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = tex
	mt.roughness = 1.0
	mi.material_override = mt
	root.add_child(mi)
	mi.transform = Transform3D(Basis.looking_at(-normal, Vector3.UP), pos)
	decor_count += 1

## Lagekarte (prozedural: Papier, Gitter, Höhenlinien, Frontlinie)
static func map_texture() -> ImageTexture:
	var img := Image.create(192, 144, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.80, 0.75, 0.60))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1944
	for x in 192:
		for y in 144:
			if x % 24 == 0 or y % 24 == 0:
				img.set_pixel(x, y, Color(0.55, 0.52, 0.42))
	for k in 6:
		var p := Vector2(rng.randf_range(10, 180), rng.randf_range(10, 130))
		var a := rng.randf() * TAU
		for i in 220:
			a += rng.randf_range(-0.25, 0.25)
			p += Vector2(cos(a), sin(a))
			if p.x >= 0 and p.y >= 0 and p.x < 192 and p.y < 144:
				img.set_pixel(int(p.x), int(p.y), Color(0.45, 0.32, 0.18))
	var p2 := Vector2(20, 120)
	for i in 160:
		p2 += Vector2(1.0, -0.6 + sin(i * 0.15) * 0.8)
		for w in 2:
			var px := int(p2.x)
			var py := int(p2.y) + w
			if px >= 0 and py >= 0 and px < 192 and py < 144:
				img.set_pixel(px, py, Color(0.7, 0.1, 0.08))
	return ImageTexture.create_from_image(img)

## Rotes Kreuz auf Weiß (Sanitätsecke)
static func cross_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.88, 0.87, 0.82))
	for x in 64:
		for y in 64:
			if (absi(x - 32) < 7 and absi(y - 32) < 22) or (absi(y - 32) < 7 and absi(x - 32) < 22):
				img.set_pixel(x, y, Color(0.72, 0.07, 0.06))
	return ImageTexture.create_from_image(img)

func _decorate(m, wood: String, _mud: String) -> void:
	var olive := _mat("olive", Color(0.28, 0.30, 0.20), 0.7, 0.3)
	var canvas := _mat("canvas", Color(0.46, 0.42, 0.30))
	var white := _mat("white", Color(0.86, 0.85, 0.80))
	var red := _mat("red", Color(0.62, 0.07, 0.06))
	var black := _mat("black", Color(0.05, 0.05, 0.05), 0.6)
	# Kabel unter der Firste entlang aller Gänge (eine Seite)
	for ci in chains.size():
		var pts: PackedVector2Array = chains[ci]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var u := (b - a).normalized()
			var v := Vector2(-u.y, u.x)
			var mid := (a + b) * 0.5 + v * (WIDTH * 0.5 - 0.06)
			var n: Node3D = m.lb.box(Vector3(mid.x, ceil_at(mid) - 0.36, mid.y), Vector3(a.distance_to(b) + 0.05, 0.025, 0.025), "darkwood", _yaw_of(u), false, root)
			for c in n.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).material_override = black
	# Ausbrüche: Sandsackwall bzw. Fässer + Kiste an der Seite (Mitte bleibt frei)
	for k in wide_spots.size():
		var ws: Dictionary = wide_spots[k]
		var t: Vector2 = ws.t
		var nn := Vector2(-t.y, t.x) * (1.0 if k % 2 == 0 else -1.0)
		var side: Vector2 = (ws.p as Vector2) + nn * (WIDE * 0.5 - 0.3)
		if k % 2 == 0:
			_dbox(m, side, 0.0, Vector3(1.7, 0.5, 0.42), "sandbag", _yaw_of(t), true)
			_dbox(m, side + t * 0.2, 0.5, Vector3(1.1, 0.25, 0.38), "sandbag", _yaw_of(t) + 0.05, false)
		else:
			_dcyl(side - t * 0.55, 0.0, 0.28, 0.88, olive, true)
			_dcyl(side + t * 0.05, 0.0, 0.28, 0.88, olive, true)
			_dbox(m, side + t * 0.75, 0.0, Vector3(0.6, 0.45, 0.42), wood, _yaw_of(t) + 0.15, true)
	for rm in rooms:
		var w: float = rm.w
		var d: float = rm.d
		var yt := _yaw_of(rm.t)
		var cy := ceil_at(rm.c)
		_lamp(m, root, Vector3(rm.c.x, cy - 0.02, rm.c.y), root)
		# Türrahmen am Durchgang
		var mo: Vector2 = rm.mouth
		for s in [-1.0, 1.0]:
			var fp: Vector2 = mo + (rm.t as Vector2) * s * (NECK_W * 0.5 - 0.07)
			_dbox(m, fp, -0.04, Vector3(0.14, ceil_at(fp) - floor_at(fp) + 0.04, 0.14), "darkwood", yt, false)
		match String(rm.id):
			"funkraum":
				_dbox(m, _rp(rm, 0.0, d * 0.5 - 0.42), 0.0, Vector3(1.4, 0.74, 0.7), "darkwood", yt, true)
				_dbox(m, _rp(rm, -0.3, d * 0.5 - 0.45), 0.74, Vector3(0.5, 0.34, 0.3), "radio", yt)
				_dbox(m, _rp(rm, 0.35, d * 0.5 - 0.40), 0.74, Vector3(0.3, 0.22, 0.26), "tank", yt)
				_dbox(m, _rp(rm, -0.3, d * 0.5 - 0.62), 0.86, Vector3(0.3, 0.05, 0.02), white, yt)
				_dprop(m, "e_chair", _rp(rm, 0.0, d * 0.5 - 1.15), 0.0, yt + PI * 0.5)
				_dbox(m, _rp(rm, w * 0.5 - 0.4, -0.25), 0.0, Vector3(0.6, 0.42, 0.45), wood, yt + 0.1, true)
				_dbox(m, _rp(rm, w * 0.5 - 0.4, -0.25), 0.42, Vector3(0.45, 0.3, 0.38), "darkwood", yt - 0.12, false)
				var mp := _rp(rm, -w * 0.5 + 0.015, 0.15)
				_wall_picture(Vector3(mp.x, floor_at(mp) + 1.5, mp.y), Vector3(rm.t.x, 0, rm.t.y), Vector2(0.9, 0.66), map_texture())
				var dp := _rp(rm, 1.05, d * 0.5 - 0.015)
				digit_spots.append({"digit": "3", "order": "III", "pos": Vector3(dp.x, floor_at(dp) + 1.5, dp.y),
					"normal": Vector3(-rm.n.x, 0, -rm.n.y), "place": "Funkraum im Stollen, Rückwand"})
			"lager":
				for lx in [-1.15, -0.45, 0.25]:
					_dbox(m, _rp(rm, lx, d * 0.5 - 0.32), 0.0, Vector3(0.62, 0.44, 0.5), wood, yt, true)
				for lx in [-1.15, -0.45]:
					_dbox(m, _rp(rm, lx, d * 0.5 - 0.32), 0.44, Vector3(0.55, 0.38, 0.45), "darkwood", yt + 0.04, false)
				for lx in [0.1, 0.42]:
					_dbox(m, _rp(rm, lx, d * 0.5 - 0.3), 0.44, Vector3(0.3, 0.16, 0.14), olive, yt + PI * 0.5, false)
				_dcyl(_rp(rm, w * 0.5 - 0.4, d * 0.5 - 0.45), 0.0, 0.29, 0.88, olive, true)
				_dcyl(_rp(rm, w * 0.5 - 0.4, -0.25), 0.0, 0.29, 0.88, olive, true)
				_dbox(m, _rp(rm, -1.1, -d * 0.5 + 0.3), 0.0, Vector3(0.85, 0.45, 0.42), "sandbag", yt, true)
				_dbox(m, _rp(rm, -1.1, -d * 0.5 + 0.3), 0.45, Vector3(0.6, 0.25, 0.38), "sandbag", yt - 0.06, false)
			"schlafnische":
				var b1 := _rp(rm, -0.3, d * 0.5 - 0.42)
				_dbox(m, b1, 0.0, Vector3(1.9, 0.36, 0.72), "darkwood", yt, true)
				_dbox(m, b1, 0.36, Vector3(1.86, 0.05, 0.66), canvas, yt)
				_dbox(m, b1 + (rm.t as Vector2) * 0.25, 0.41, Vector3(1.2, 0.06, 0.68), olive, yt)
				_dbox(m, b1 - (rm.t as Vector2) * 0.72, 0.41, Vector3(0.32, 0.09, 0.5), white, yt)
				var b2 := _rp(rm, w * 0.5 - 0.42, -0.15)
				_dbox(m, b2, 0.0, Vector3(0.72, 0.36, 1.6), "darkwood", yt, true)
				_dbox(m, b2, 0.36, Vector3(0.66, 0.05, 1.56), canvas, yt)
				_dbox(m, b2 - (rm.n as Vector2) * 0.2, 0.41, Vector3(0.68, 0.06, 1.0), olive, yt + 0.03)
				_dbox(m, _rp(rm, -1.0, -0.45), 0.0, Vector3(0.4, 0.45, 0.4), wood, yt + 0.2, true)
				_dprop(m, "e_flaska1", _rp(rm, -1.0, -0.45), 0.45, yt)
			"sanitaet":
				_dbox(m, _rp(rm, 0.2, d * 0.5 - 0.38), 0.0, Vector3(1.2, 0.8, 0.6), "darkwood", yt, true)
				_dbox(m, _rp(rm, 0.2, d * 0.5 - 0.38), 0.8, Vector3(1.22, 0.02, 0.62), white, yt)
				var kit := _rp(rm, -0.15, d * 0.5 - 0.38)
				_dbox(m, kit, 0.82, Vector3(0.32, 0.14, 0.22), white, yt)
				_dbox(m, kit, 0.96, Vector3(0.15, 0.006, 0.04), red, yt)
				_dbox(m, kit, 0.96, Vector3(0.04, 0.006, 0.15), red, yt)
				_dprop(m, "e_flaska1", _rp(rm, 0.55, d * 0.5 - 0.38), 0.82, yt)
				for ly in [-0.6, 0.55]:
					_dbox(m, _rp(rm, -w * 0.5 + 0.4, ly), 0.0, Vector3(0.5, 0.35, 0.35), wood, yt, true)
				_dbox(m, _rp(rm, -w * 0.5 + 0.4, 0.0), 0.35, Vector3(0.55, 0.04, 1.85), canvas, yt)
				for s in [-0.27, 0.27]:
					_dbox(m, _rp(rm, -w * 0.5 + 0.4 + s, 0.0), 0.35, Vector3(0.04, 0.05, 2.05), "darkwood", yt)
				_dprop(m, "e_bucket", _rp(rm, w * 0.5 - 0.35, -0.6), 0.0, yt)
				var fp2 := _rp(rm, 0.2, d * 0.5 - 0.015)
				_wall_picture(Vector3(fp2.x, floor_at(fp2) + 1.6, fp2.y), Vector3(-rm.n.x, 0, -rm.n.y), Vector2(0.45, 0.45), cross_texture())
	if not secret.is_empty():
		var sc := secret
		var ys := _yaw_of(sc.t)
		_lamp(m, root, Vector3(sc.c.x, ceil_at(sc.c) - 0.02, sc.c.y), root)
		# Stahlzarge am Durchgang (nur Optik), Sockel für das Ei, Pult für den Knopf
		var steel := _mat("steel", Color(0.30, 0.32, 0.30), 0.5, 0.7)
		var dr: Vector2 = sc.door
		for s in [-1.0, 1.0]:
			var fp: Vector2 = dr + (sc.side as Vector2) * s * (NECK_W * 0.5 - 0.025)
			_dbox(m, fp, -0.04, Vector3(0.05, ceil_at(fp) - floor_at(fp) + 0.04, 0.16), steel, ys, false)
		_dbox(m, dr, ceil_at(dr) - floor_at(dr) - 0.12, Vector3(NECK_W, 0.12, 0.16), steel, ys, false)
		_dbox(m, _rp(sc, -0.6, sc.d * 0.5 - 0.6), 0.0, Vector3(0.45, 1.0, 0.45), "stone", ys, true)
		_dbox(m, _rp(sc, -0.6, sc.d * 0.5 - 0.6), 1.0, Vector3(0.55, 0.06, 0.55), "stone", ys, false)
		_dbox(m, _rp(sc, sc.w * 0.5 - 0.55, 0.3), 0.0, Vector3(0.6, 0.95, 0.45), steel, ys, true)
		_dbox(m, _rp(sc, sc.w * 0.5 - 0.55, 0.3), 0.95, Vector3(0.62, 0.03, 0.47), _mat("hazard", Color(0.85, 0.7, 0.1)), ys, false)
		for k in 3:
			_dbox(m, _rp(sc, -sc.w * 0.5 + 0.35, -0.6 + k * 0.45), 0.0, Vector3(0.5, 0.42, 0.4), wood, ys + 0.1 * k, true)
