class_name BotNav
extends RefCounted
## Wegfindung der Mehrspieler-KI-Soldaten (Server): Route über das Navigationsnetz mit Zwischenpunkten an
## Deckungen statt über freie Fläche, Erreichbarkeitsprüfung des Ziels, Erkennen von Festhängen und
## gestufte Abhilfe (klettern/springen → seitlich ausweichen → neu planen → Ziel aufgeben → aufs Netz setzen).
## Nur BotBrain verwendet diese Klasse; Einzelspieler-KI unverändert.

const WP_REACH := 2.2            ## Zwischenpunkt gilt als erreicht (waagerecht)
const COVER_SEG := 14.0          ## alle ~14 m Wegstrecke eine Deckung in der Nähe suchen
const COVER_DETOUR := 6.0        ## höchstens so weit neben dem Weg
const PROGRESS_DIST := 1.5       ## Fortschritt = so weit bewegt

var waypoints := PackedVector3Array()
var route_vias := 0              ## Statistik: Routen über eine Wegfolge der Karte
var wp_i := 0
var dest := Vector3.INF          ## Ziel der aktuellen Route
var reachable := true            ## Ziel liegt (nahezu) am Ende des Netzpfads
var path_len := 0.0
var cover_points := 0
var plans := 0
var planned_on_nav := false     ## Route wurde mit fertigem Navigationsnetz geplant

# --- Festhängen ---
var prog_t := 0.0                ## s ohne Fortschritt bei gewünschter Bewegung
var stuck_max := 0.0             ## größter Wert von prog_t (Test/Debug)
var stuck_events := 0
var nudges := 0
var side_pos := Vector3.INF      ## Ausweichpunkt (seitlich)
var side_t := 0.0
var _prog_pos := Vector3.INF
var _stage := 0
var _idle_t := 0.0              ## s ohne Laufwunsch (kurze Pausen zählen nicht als Fortschritt)
var _osc_best := INF            ## kleinster Restweg seit der letzten Planung (Pendel-Erkennung)
var _osc_t := 0.0
var _osc_n := 0
var osc_events := 0             ## Statistik: Pendeln erkannt


# --- Netz-Hilfen (statisch) -----------------------------------------------------------------------

static func map_of(n: Node3D) -> RID:
	return n.get_world_3d().navigation_map


static func nav_ready(n: Node3D) -> bool:
	var m := map_of(n)
	if not m.is_valid() or NavigationServer3D.map_get_iteration_id(m) <= 0:
		return false
	# Missionsnetz wird asynchron gebacken: vorher liefert die Karte (0,0,0) als „nächsten Punkt“
	var mi = Game.current_mission()
	return mi == null or mi.get("nav_ready") != false


static func closest(n: Node3D, p: Vector3) -> Vector3:
	if not nav_ready(n):
		return p
	var c := NavigationServer3D.map_get_closest_point(map_of(n), p)
	if c == Vector3.ZERO and p.length() > 3.0:
		return p                 # keine Netzfläche (Abfrage fehlgeschlagen)
	return c


static func path(n: Node3D, a: Vector3, b: Vector3) -> PackedVector3Array:
	if not nav_ready(n):
		return PackedVector3Array()
	return AIBrain.nav_path(map_of(n), a, b)   # B-010c: Suchgrenze angehoben


static func length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i - 1].distance_to(pts[i])
	return l


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func ends_near(pts: PackedVector3Array, b: Vector3, h := 2.5, v := 2.5) -> bool:
	return pts.size() > 0 and flat(pts[pts.size() - 1], b) < h and absf(pts[pts.size() - 1].y - b.y) < v


## Punkt liegt auf dem Netz (nächster Netzpunkt waagerecht/senkrecht nah)
static func on_nav(n: Node3D, p: Vector3, h := 1.0, v := 1.6) -> bool:
	var c := closest(n, p)
	return flat(c, p) < h and absf(c.y - p.y) < v


## Weglänge über das Netz (INF, wenn das Ziel nicht erreichbar ist)
static func path_cost(n: Node3D, a: Vector3, b: Vector3) -> float:
	var pts := path(n, a, b)
	if pts.size() < 2:
		return a.distance_to(b) if a.distance_to(b) < 3.0 else INF
	return length(pts) if ends_near(pts, b, 3.0, 3.0) else INF


## Deckungswert eines Bodenpunkts: Hindernisse ringsum in Hüfthöhe (verdeckt/geschützt) und – falls bekannt –
## vom Bedrohungspunkt aus verdeckt (+3)
static func cover_score(space: PhysicsDirectSpaceState3D, p: Vector3, threat: Vector3) -> float:
	var s := 0.0
	var o := p + Vector3.UP * 0.9
	for i in 6:
		var a := TAU * float(i) / 6.0
		var q := PhysicsRayQueryParameters3D.create(o, o + Vector3(cos(a), 0, sin(a)) * 3.0, 1)
		if not space.intersect_ray(q).is_empty():
			s += 1.0
	if threat.is_finite():
		var q2 := PhysicsRayQueryParameters3D.create(threat, o, 1)
		if not space.intersect_ray(q2).is_empty():
			s += 3.0
	return s


# --- Route ------------------------------------------------------------------------------------------

## Route zum Ziel planen. use_cover: Zwischenpunkte an Deckungen nahe dem Weg (nur wenn der Umweg gering ist).
## Rückgabe: Ziel erreichbar (sonst führt die Route zum nächsten erreichbaren Punkt).
func plan(s: Soldier, to: Vector3, threat: Vector3, use_cover: bool) -> bool:
	plans += 1
	planned_on_nav = nav_ready(s)
	waypoints = PackedVector3Array()
	wp_i = 0
	if not dest.is_finite() or flat(dest, to) > 3.0:
		_osc_n = 0
	_osc_best = INF
	_osc_t = 0.0
	dest = to
	cover_points = 0
	side_t = 0.0
	var from := s.global_position
	var pts := path(s, from, to)
	if pts.size() < 2:
		path_len = from.distance_to(to)
		reachable = path_len < 3.0 or not nav_ready(s)
		waypoints.append(to)
		return reachable
	reachable = ends_near(pts, to)
	path_len = length(pts)
	if use_cover and reachable and path_len > 30.0:
		# optionale Wegfolge der Karte (Graben als Annäherung, Flanke) bei kleinem Umweg
		var via := BotGoals.map_route(s, from, to, path_len)
		if via.size() >= 2:
			waypoints.append_array(via)
			waypoints.append(to)
			route_vias += 1
			return reachable
	# 0.11.4: Pfad mit unendlichem/NaN-Punkt (Navigationsfehler „most reachable polygons“) ließ die Deckungsschleife
	# endlos laufen (next_at < inf) – Demo-Server-Hänger. Nur endliche Pfade, Schleife zusätzlich begrenzt.
	# 0.11.4: a path with an infinite/NaN point made the cover loop run forever (demo server hang).
	if not is_finite(path_len) or path_len > 5000.0:
		waypoints.append(to)
		return reachable
	# 0.11.7 (P2): menschlichere Laufwege – Umweg über einen Kartenwegpunkt (Zonen/Spawns/Netz) und seitlich
	# versetzte Zwischenpunkte statt stur gerader Netzlinie; nur erreichbare Ziele, geringer Umweg.
	# 0.11.7 (P2): more human routes – via a map waypoint plus lateral offsets instead of the straight nav line.
	if use_cover and humanize and not threat.is_finite() and reachable and path_len > HUMAN_MIN_LEN \
			and String(Game.cli.get("bot_human", "1")) != "0":
		var hv := human_route(s, from, to, path_len)
		if hv.size() >= 1:
			waypoints.append_array(hv)
			waypoints.append(to)
			human_routes += 1
			return reachable
	if use_cover and path_len > COVER_SEG * 1.6:
		var space := s.get_world_3d().direct_space_state
		var acc := 0.0
		var next_at := COVER_SEG
		var last_wp := from
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var seg := a.distance_to(b)
			var guard := 0
			while acc + seg >= next_at and next_at < path_len - 10.0 and guard < 64:
				guard += 1
				var p := a.lerp(b, (next_at - acc) / maxf(seg, 0.001))
				var c := _cover_near(s, space, p, threat)
				if c.is_finite() and c.distance_to(last_wp) > 7.0:
					waypoints.append(c)
					last_wp = c
					cover_points += 1
				next_at += COVER_SEG
			acc += seg
	waypoints.append(pts[pts.size() - 1] if not reachable else to)
	return reachable


# --- Menschlichere Laufwege (0.11.7, P2) --------------------------------------------------------------
# Je Karte ein Wegpunktsatz aus Zonenmitten, Spawnplätzen, Aufgabenorten und Zufallspunkten des Navmesh
# (einmal je Netzstand erzeugt). Eine Route nimmt mit Wahrscheinlichkeit HUMAN_P einen Wegpunkt im Korridor
# zwischen Start und Ziel (Umweg ≤ 35 % + 8 m, beide Teilwege erreichbar) und versetzt die Teilstrecken alle
# ~16 m seitlich um 0,8–2,5 m (Netzpunkt, Sichtlinie frei). Werte [D].
# Per map one waypoint set (zone centres, spawn slots, objectives, random navmesh points); routes take a
# corridor waypoint with probability HUMAN_P and lateral offsets every ~16 m. Values [D].

const HUMAN_P := 0.5             ## Anteil der Routen über einen Kartenwegpunkt
const HUMAN_MIN_LEN := 25.0      ## erst ab dieser Netzweglänge
const HUMAN_DETOUR := 1.35       ## Umweg höchstens Faktor + 8 m
const JITTER_SEG := 16.0
const RANDOM_WPS := 48

static var humanize := true      ## --bot_human=0 schaltet ab (Vergleichsmessung)
static var _wp_cache := {}       ## "<map-RID>:<iteration>" → PackedVector3Array
var human_routes := 0            ## Statistik: Routen mit Kartenwegpunkt/Versatz
var human_vias := PackedVector3Array()   ## gewählte Kartenwegpunkte (Test: Streuung je Bot)


## Wegpunktsatz der aktuellen Karte (Zonen, Spawns, Aufgaben, Netz-Zufallspunkte)
static func map_waypoints(n: Node3D) -> PackedVector3Array:
	if not nav_ready(n):
		return PackedVector3Array()
	var m := map_of(n)
	var key := "%d:%d" % [m.get_id(), NavigationServer3D.map_get_iteration_id(m)]
	if _wp_cache.has(key):
		return _wp_cache[key]
	var raw: Array = []
	var mi = Game.current_mission()
	if mi != null and mi.has_method("mp_zones"):
		for z in mi.mp_zones():
			if z.has("xf"):
				raw.append((z["xf"] as Transform3D).origin)
			for sl in z.get("slots", []):
				raw.append(sl["pos"])
	if mi != null and mi.has_method("mp_objectives"):
		for o in mi.mp_objectives():
			if o is Dictionary and o.get("pos") is Vector3:
				raw.append(o["pos"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	seed(rng.randi())
	for k in RANDOM_WPS:
		raw.append(NavigationServer3D.map_get_random_point(m, 1, true))
	randomize()
	var out := PackedVector3Array()
	for p in raw:
		var c := closest(n, p)
		if not c.is_finite() or (c == Vector3.ZERO and (p as Vector3).length() > 3.0):
			continue
		var dup := false
		for q in out:
			if flat(q, c) < 6.0:
				dup = true
				break
		if not dup:
			out.append(c)
	if _wp_cache.size() > 8:
		_wp_cache.clear()
	_wp_cache[key] = out
	return out


## Wegpunkte einer „menschlichen“ Route (ohne Endziel); leer = gerader Netzweg bleibt
func human_route(s: Soldier, from: Vector3, to: Vector3, direct: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var via := Vector3.INF
	if randf() < HUMAN_P:
		var cands: Array = []
		for w in map_waypoints(s):
			if flat(w, from) < 8.0 or flat(w, to) < 8.0:
				continue
			var est := flat(from, w) + flat(w, to)
			if est <= direct * HUMAN_DETOUR + 8.0:
				cands.append(w)
		cands.shuffle()
		for w in cands.slice(0, 3):
			var c1 := path_cost(s, from, w)
			if not is_finite(c1):
				continue
			var c2 := path_cost(s, w, to)
			if is_finite(c2) and c1 + c2 <= direct * HUMAN_DETOUR + 8.0:
				via = w
				break
	var legs: Array = [[from, via], [via, to]] if via.is_finite() else [[from, to]]
	var space := s.get_world_3d().direct_space_state
	for leg in legs:
		var pts := path(s, leg[0], leg[1])
		if pts.size() >= 2:
			out.append_array(_jitter(s, space, pts))
		if leg[1] != to:
			out.append(leg[1])
	if via.is_finite():
		human_vias.append(via)
		if human_vias.size() > 16:
			human_vias.remove_at(0)
	return out


## Seitlich versetzte Zwischenpunkte entlang eines Netzpfads (Sichtlinie zum Pfadpunkt frei, gleiche Ebene)
func _jitter(s: Soldier, space: PhysicsDirectSpaceState3D, pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var total := length(pts)
	if total < JITTER_SEG * 1.5:
		return out
	var side := 1.0 if randf() < 0.5 else -1.0
	var acc := 0.0
	var next_at := JITTER_SEG * randf_range(0.6, 1.1)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var guard := 0
		while acc + seg >= next_at and next_at < total - 8.0 and guard < 64:
			guard += 1
			var p := a.lerp(b, (next_at - acc) / maxf(seg, 0.001))
			var d := b - a
			d.y = 0.0
			if d.length() > 0.05:
				var perp := Vector3(-d.z, 0, d.x).normalized() * side * randf_range(0.8, 2.5)
				var c := closest(s, p + perp)
				# 0.11.7: Versatzpunkt muss über das Netz direkt erreichbar sein (sonst Umweg/andere Insel → Pendeln,
				# mp_burma1_obj: Führer kam nicht vom Spawn weg)
				if absf(c.y - p.y) < 1.0 and flat(c, p) > 0.6 and path_cost(s, p, c) <= flat(c, p) * 1.5 + 1.0:
					var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.9, c + Vector3.UP * 0.9, 1)
					if space.intersect_ray(q).is_empty():
						out.append(c)
					else:
						out.append(p)
				else:
					out.append(p)
			if randf() < 0.45:
				side = -side          # Wechsel der Seite: leichtes Schlängeln statt Linie
			next_at += JITTER_SEG * randf_range(0.8, 1.25)
		acc += seg
	return out


## Deckung in der Nähe eines Wegpunkts: besser gedeckt als der Wegpunkt selbst, auf derselben Seite von Wänden
func _cover_near(s: Soldier, space: PhysicsDirectSpaceState3D, p: Vector3, threat: Vector3) -> Vector3:
	var base := cover_score(space, p, threat)
	var best := Vector3.INF
	var best_s := maxf(base + 1.0, 2.0)
	var a0 := randf() * TAU
	for i in 6:
		var a := a0 + TAU * float(i) / 6.0
		var c := closest(s, p + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, COVER_DETOUR))
		if absf(c.y - p.y) > 2.0 or flat(c, p) > COVER_DETOUR + 0.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, c + Vector3.UP * 1.0, 1)
		if not space.intersect_ray(q).is_empty():
			continue           # hinter einer Wand: kein kurzer Umweg
		var sc := cover_score(space, c, threat)
		if sc >= best_s:
			best_s = sc
			best = c
	return best


## Aktueller Steuerpunkt: Ausweichpunkt oder nächster nicht erreichter Zwischenpunkt
func steer(s: Soldier) -> Vector3:
	if side_t > 0.0 and side_pos.is_finite():
		return side_pos
	while wp_i < waypoints.size() - 1 and flat(s.global_position, waypoints[wp_i]) < WP_REACH:
		wp_i += 1
	if wp_i < waypoints.size():
		return waypoints[wp_i]
	return dest


## Steuerpunkt ist eine Deckung auf dem Weg (nicht das Endziel)
func at_cover_waypoint(s: Soldier) -> bool:
	return wp_i < waypoints.size() - 1 and flat(s.global_position, waypoints[wp_i]) < WP_REACH + 0.5


func remaining(s: Soldier) -> float:
	if waypoints.is_empty():
		return INF
	var l := s.global_position.distance_to(waypoints[mini(wp_i, waypoints.size() - 1)])
	for i in range(wp_i + 1, waypoints.size()):
		l += waypoints[i - 1].distance_to(waypoints[i])
	return l


func clear() -> void:
	waypoints = PackedVector3Array()
	wp_i = 0
	dest = Vector3.INF


# --- Festhängen -------------------------------------------------------------------------------------

## Je Physikschritt. Rückgabe = Maßnahme: 0 keine, 1 springen/klettern, 2 seitlich ausweichen,
## 3 neu planen, 4 Ziel aufgeben, 5 aufs Netz setzen
func track(s: Soldier, delta: float, wants_move: bool) -> int:
	var p := s.global_position
	if side_t > 0.0:
		side_t -= delta
	# 0.11.7: kurze Unterbrechungen (Kletterversuch der Stufe 1, Formation wartet) setzen die Abhilfe-Stufe nicht
	# mehr zurück – sonst Schleife „2 s fest → klettern → zurückfallen → Stufe 0“ ohne Aufgeben/Notversatz
	# (mp_czech2_obj: Bot 31–34 s am selben Fleck, prog_t nie über 13 s). Erst > 1,5 s ohne Laufwunsch = neu.
	# 0.11.7: short interruptions (stage-1 climb attempt, formation wait) no longer reset the remedy stage.
	if s.has_method("is_climbing") and s.is_climbing():
		return 0                 # Kletterbewegung: weder Fortschritt noch Pause (Ergebnis zählt danach)
	if not wants_move:
		_idle_t += delta
		if _idle_t > 1.5:
			_prog_pos = p
			prog_t = 0.0
			_stage = 0
		return 0
	_idle_t = 0.0
	# 0.11.7: Pendeln erkennen – der Bot bewegt sich (Ankerprüfung unten greift nicht), kommt dem Ziel über die Route aber
	# nicht näher (mp_arctic3_obj: Führer pendelt 150 s unter dem Wachturm zwischen zwei Inselbrücken). Nach 12 s ohne
	# 1,5 m Restweg-Gewinn neu planen (andere Kartenwegpunkte/Versatz), nach weiteren 12 s Ziel aufgeben.
	# 0.11.7: oscillation detection – moving but not closing in on the goal along the route.
	if dest.is_finite() and not waypoints.is_empty() and String(Game.cli.get("bot_osc", "1")) != "0":
		var rem := remaining(s)
		if rem < _osc_best - 1.5:
			_osc_best = rem
			_osc_t = 0.0
		else:
			# Klettern zählt oben nicht mit (Rückkehr vor dieser Stelle); Ausweichschritte der Festhäng-Abhilfe setzen den
			# Anker zurück – deshalb hier unabhängig von der Geschwindigkeit (mp_czech4: Führer an einer Inselbrücke vor
			# seinem Spawn, Ausweichen ↔ Rückkehr, Notversatz wurde nie erreicht)
			_osc_t += delta
			if _osc_t > 15.0:
				_osc_t = 0.0
				_osc_n += 1
				osc_events += 1
				# kein Aufgeben (Zielwechsel ließ mp_arctic1_obj immer wieder dasselbe Ziel wählen): abwechselnd neu planen
				# und Notversatz
				# zweites Pendeln: Notversatz Richtung Weg (mp_arctic1_obj: Inselbrücken zwischen den Wachturmbeinen sind
				# im Netz verbunden, die Kapsel kommt aber nicht durch)
				return 5 if _osc_n % 2 == 0 else 3
	# Fortschritt waagerecht (0.11.7): ein Kletter-/Leiterversuch, der hoch- und wieder zurückfällt, zählte als
	# Fortschritt (> 1,5 m senkrecht) → mp_arctic1_obj/arctic3_obj Führer 150 s an derselben Stelle ohne Abhilfe
	if not _prog_pos.is_finite() or flat(p, _prog_pos) > PROGRESS_DIST:
		_prog_pos = p
		prog_t = 0.0
		_stage = 0
		return 0
	prog_t += delta
	stuck_max = maxf(stuck_max, prog_t)
	var act := 0
	if _stage == 0 and prog_t > 2.0:
		act = 1
	elif _stage == 1 and prog_t > 4.0:
		act = 2
	elif _stage == 2 and prog_t > 7.0:
		act = 3
	elif _stage == 3 and prog_t > 9.5:
		act = 2
	elif _stage == 4 and prog_t > 12.5:
		act = 4
	elif _stage == 5 and prog_t > 15.5:
		act = 5
	elif _stage >= 6 and prog_t > 18.0:
		# 0.11.7: Abhilfen erschöpft → von vorn (vorher blieb der Bot nach dem Notversatz dauerhaft stehen)
		_stage = 0
		prog_t = 0.0
		_prog_pos = p
		return 0
	if act != 0:
		_stage += 1
		stuck_events += 1
	return act


## Seitlich ausweichen: Netzpunkt 3–6 m quer zur Wunschrichtung, 2 s lang direkt ansteuern
func sidestep(s: Soldier, toward: Vector3) -> void:
	var d := toward - s.global_position
	d.y = 0.0
	if d.length() < 0.1:
		d = s.forward()
	var perp: Vector3 = Vector3(-d.z, 0, d.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
	for k in 2:
		var c := closest(s, s.global_position + perp * randf_range(3.0, 6.0) - d.normalized() * 1.0)
		if flat(c, s.global_position) > 1.2:
			side_pos = c
			side_t = 2.0
			return
		perp = -perp
	side_pos = closest(s, s.global_position - d.normalized() * 3.0)
	side_t = 2.0


## Ecken nicht schneiden: zwei schräge Fühlerstrahlen (Hüfthöhe, 0,9 m) alle 0,15 s; trifft einer eine Wand,
## schiebt der Rückgabevektor seitlich davon weg. Höchstens 2 Strahlen je 0,15 s.
## Don't cut corners: two angled whisker rays (hip height, 0.9 m) every 0.15 s; if one hits a wall the returned
## vector pushes sideways away from it. At most 2 rays per 0.15 s.
var _wh_t := 0.0
var _wh_push := Vector3.ZERO

func wall_push(s: Soldier, dir: Vector3, delta: float) -> Vector3:
	_wh_t -= delta
	if _wh_t > 0.0:
		return _wh_push
	_wh_t = 0.15
	_wh_push = Vector3.ZERO
	dir.y = 0.0
	if dir.length() < 0.1:
		return _wh_push
	dir = dir.normalized()
	var space := s.get_world_3d().direct_space_state
	var o := s.global_position + Vector3.UP * 0.6
	var right := Vector3(-dir.z, 0, dir.x)
	for side: float in [1.0, -1.0]:
		var probe := (dir * 0.7 + right * side * 0.5).normalized() * 0.9
		var q := PhysicsRayQueryParameters3D.create(o, o + probe, 1, [s.get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var k := 1.0 - o.distance_to(hit["position"]) / 0.9
			_wh_push -= right * side * clampf(k, 0.2, 1.0)
	return _wh_push


## Flanken-Zwischenpunkt: Netzpunkt etwa auf halbem Weg, vom Gegner weg versetzt und von ihm aus verdeckt, damit
## der Flankierer nicht in gerader Linie durchs Schussfeld läuft. Billige Prüfungen (Abstand) vor Strahl, Strahl vor
## Netzpfad; höchstens 3 Versuche. INF = kein geeigneter Punkt (dann direkter Netzweg).
## Flank via-point: navmesh point near the halfway mark, offset away from the enemy and hidden from him, so the
## flanker does not run straight through the line of fire. Cheap checks (distance) before ray, ray before nav path;
## at most 3 tries. INF = none found (then the direct nav path is used).
static func flank_via(s: Soldier, from: Vector3, to: Vector3, threat: Vector3) -> Vector3:
	if not threat.is_finite() or not nav_ready(s) or flat(from, to) < 8.0:
		return Vector3.INF
	var mid := from.lerp(to, 0.5)
	var away := mid - threat
	away.y = 0.0
	if away.length() < 0.1:
		return Vector3.INF
	away = away.normalized()
	var space := s.get_world_3d().direct_space_state
	var direct := flat(from, to)
	for k in 3:
		var c := closest(s, mid + away * (2.0 + 2.5 * float(k)))
		if flat(c, from) < 3.0 or flat(c, to) < 3.0 or absf(c.y - mid.y) > 3.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(threat + Vector3.UP * 1.5, c + Vector3.UP * 1.0, 1)
		if space.intersect_ray(q).is_empty():
			continue           # vom Gegner aus sichtbar / visible from the enemy
		var l := path_cost(s, from, c) + path_cost(s, c, to)
		if is_finite(l) and l < direct * 2.5 + 10.0:
			return c
	return Vector3.INF


## Letzte Abhilfe nach > 15 s ohne Fortschritt: Soldat liegt neben dem Netz (z. B. in einer Kollisionslücke
## eingeklemmt) → auf den nächsten Netzpunkt setzen; auf dem Netz → 1 m Richtung Weg versetzen, falls dort frei.
## Bewusste Notlösung (wie Unstuck-Hilfen anderer Spiele), nur KI-Soldaten.
func nudge(s: Soldier, toward: Vector3) -> bool:
	# 0.11.7: vom Versatzpunkt muss das Ziel weiter erreichbar sein (mp_burma1_obj: Versatz in eine Senke 2 m tiefer,
	# danach Aufgabe unerreichbar und abgelöst) – geprüft in _nudge_ok
	_nudge_goal = dest if dest.is_finite() else toward
	var p := s.global_position
	var c := closest(s, p)
	var target := Vector3.INF
	if flat(c, p) > 0.8 or absf(c.y - p.y) > 1.5:
		target = c
	else:
		var pts: PackedVector3Array = path(s, p, toward if toward.is_finite() else p)
		if pts.size() >= 2:
			# 0.11.7: Punkt ~1,6 m entlang des Pfads (auch über eine kurze Inselbrücke hinweg), nicht nur Richtung pts[1]
			var want := 1.6
			var q := p
			for k in range(1, pts.size()):
				var seg := q.distance_to(pts[k])
				if seg >= want:
					q = q.lerp(pts[k], want / maxf(seg, 0.001))
					want = 0.0
					break
				want -= seg
				q = pts[k]
			target = closest(s, q)
	if not s.has_method("_fits"):
		return false
	# 0.11.7: Versatz nur in der Nähe und nur auf echten Boden. Der nächste Netzpunkt kann weit weg liegen (anderes
	# Stockwerk, Netz ohne Kollision, Testgelände über der Karte: test_bots Mauerraster – Führer landete 400 m tiefer).
	# 0.11.7: nudge only nearby and onto a real floor (nearest nav point may be far below/above).
	if target.is_finite() and not _nudge_ok(s, p, target):
		target = Vector3.INF
	if not target.is_finite() or not s._fits(target + Vector3.UP * 0.05):
		# 0.11.7: erster Versatz passt nicht (Kapsel klemmt, mp_czech2_obj > 120 s fest) → Netzpunkte im Ring 1,5/3 m
		target = Vector3.INF
		for r: float in [1.5, 3.0]:
			for k in 8:
				var a := TAU * float(k) / 8.0
				var c2 := closest(s, p + Vector3(cos(a), 0, sin(a)) * r)
				if flat(c2, p) > 0.8 and absf(c2.y - p.y) < 2.0 and _nudge_ok(s, p, c2) and s._fits(c2 + Vector3.UP * 0.05):
					target = c2
					break
			if target.is_finite():
				break
	if Game.cli.has("bot_nudge_debug"):
		print("NUDGE %s bei %s → %s" % [s.soldier_name, str(p.snapped(Vector3.ONE * 0.1)), str(target.snapped(Vector3.ONE * 0.1)) if target.is_finite() else "abgelehnt"])
	if not target.is_finite():
		return false
	var fl := _floor_at(s, target)
	if s._fits(fl + Vector3.UP * 0.05):
		target = fl
	s.global_position = target + Vector3.UP * 0.05
	s.velocity = Vector3.ZERO
	nudges += 1
	_prog_pos = Vector3.INF
	return true


const NUDGE_MAX_FLAT := 4.0      ## Notversatz höchstens so weit waagerecht [D]
const NUDGE_MAX_UP := 2.5        ## und senkrecht (ein Stockwerk/Kletterstelle) [D]


## Notversatz zulässig: nah, und unter dem Zielpunkt liegt Weltkollision (kein Netz ohne Boden, kein Fall ins Leere)
func _nudge_ok(s: Soldier, from: Vector3, to: Vector3) -> bool:
	if flat(from, to) > NUDGE_MAX_FLAT or absf(to.y - from.y) > NUDGE_MAX_UP:
		return false
	if not _floor_hit(s, to).is_finite():
		return false
	if _nudge_goal.is_finite() and is_finite(path_cost(s, from, _nudge_goal)) and not is_finite(path_cost(s, to, _nudge_goal)):
		return false             # vorher erreichbar, danach nicht mehr → kein Versatz
	return true


var _nudge_goal := Vector3.INF


## Boden unter einem Netzpunkt (Strahl 1,2 m darüber bis 1,0 m darunter, nur Welt); INF = kein Boden
func _floor_hit(s: Soldier, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.2, p + Vector3.DOWN * 1.0, 1, [s.get_rid()])
	var hit := s.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## Netzpunkt auf die echte Bodenhöhe setzen (Detailnetz kann bis ~1 m neben der Kollision liegen)
func _floor_at(s: Soldier, p: Vector3) -> Vector3:
	var h := _floor_hit(s, p)
	return h if h.is_finite() else p
