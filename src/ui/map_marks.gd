class_name MapMarks
extends RefCounted
## 0.11.7 Gemeinsame Kartenmarken für Minikarte (src/ui/mp_minimap.gd), große MP-Karte M (MpHud.ZoneMap) und
## Einzelspieler-Karte M (src/ui/tactical_map.gd). [D] Eigene Vorgabe (Original: keine Schussmarken auf Karten).
##  - Schussprotokoll: Events.noise_emitted kind „gunshot“ einer Soldier-Quelle, ohne Schalldämpfer
##    (Klangklasse silenced_* bzw. Geräuschweite < SILENCED_RADIUS), Marke an der Schützenlage, SHOT_TTL s ausblendend.
##    Zusatzfilter `accept(source, pos, radius) -> bool` (SP: nur gehörte/gesehene Gegner).
##  - MP-Sicht: Mitte = eigene lebende Figur bzw. beobachteter Spieler (Zuschauer), freie Zuschauerkamera → nichts;
##    Verbündete nur in Team-Stilen (Deathmatch: niemand), Gegner nur als Schussmarken.
##  - Zeichnen: eigener Pfeil (Lage + Blickrichtung), Verbündeten-Punkt, Schussmarke (Punkt + Ring, ausblendend).
## Datenquellen nur lokal (Net._soldiers, lokale Geräusche) – keine RPCs, Protokoll unverändert.

const SHOT_TTL := 2.5              ## Sichtbarkeit eines Schusses [s]
const SILENCED_RADIUS := 20.0
const MAX_SHOTS := 64
const COL_ALLIED := Color(0.45, 0.7, 1.0)
const COL_AXIS := Color(0.95, 0.85, 0.35)
const COL_ENEMY := Color(1.0, 0.25, 0.2)
const COL_SELF := Color(1, 1, 1)

var shots: Array = []              ## [{pos: Vector3, t: float, src: Soldier}]
var accept: Callable               ## optional: func(source: Soldier, pos: Vector3, radius: float) -> bool


func connect_noise() -> void:
	if not Events.noise_emitted.is_connected(on_noise):
		Events.noise_emitted.connect(on_noise)


func disconnect_noise() -> void:
	if Events.noise_emitted.is_connected(on_noise):
		Events.noise_emitted.disconnect(on_noise)


static func is_silenced_noise(radius: float, wd: WeaponData = null) -> bool:
	if wd and String(wd.sound).begins_with("silenced"):
		return true
	return radius < SILENCED_RADIUS


func on_noise(pos: Vector3, radius: float, source: Node, _team: int, kind: StringName) -> void:
	if kind != &"gunshot" or not (source is Soldier):
		return
	var s := source as Soldier
	var w = s.current_weapon() if s.has_method("current_weapon") else null
	if is_silenced_noise(radius, w.data if w else null):
		return
	if accept.is_valid() and not bool(accept.call(s, pos, radius)):
		return
	shots.append({"pos": pos, "t": SHOT_TTL, "src": s})
	if shots.size() > MAX_SHOTS:
		shots.pop_front()


func tick(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		shots[i]["t"] = float(shots[i]["t"]) - delta
		if float(shots[i]["t"]) <= 0.0:
			shots.remove_at(i)


## Schussmarken, deren Schütze weder der Betrachter noch (Team-Stil) verbündet ist
func enemy_shots(center: Soldier, team: int, team_mode: bool) -> Array:
	var out: Array = []
	for e in shots:
		var s = e["src"]
		if is_instance_valid(s) and (s == center or (team_mode and s.team == team)):
			continue
		out.append(e)
	return out


static func alpha_of(e: Dictionary) -> float:
	return clampf(float(e["t"]) / SHOT_TTL, 0.0, 1.0)


static func team_col(team: int) -> Color:
	return COL_AXIS if team == Soldier.TEAM_AXIS else COL_ALLIED


# --- Mehrspieler-Sicht ---------------------------------------------------------------------------------------

## Mitte der Karte: Zuschauer → beobachteter Spieler (freie Kamera: null), sonst eigene lebende Figur
static func mp_center(hud) -> Soldier:
	if hud and hud.get("spectating"):
		if hud.spec_free:
			return null
		var t = Net._soldiers.get(hud.spec_target_id)
		return t if is_instance_valid(t) else null
	var me = Net._soldiers.get(Net.my_id())
	return me if is_instance_valid(me) and me.alive else null


## Lebende Verbündete des Betrachters (ohne ihn selbst), nur Team-Stile
static func mp_allies(center: Soldier, team: int) -> Array:
	var out: Array = []
	if not Net.team_mode() or not is_instance_valid(center):
		return out
	for id in Net._soldiers:
		var s = Net._soldiers[id]
		if is_instance_valid(s) and s != center and s.alive and s.team == team:
			out.append(s)
	return out


static func mp_self_col(center: Soldier) -> Color:
	return COL_SELF if Net.mode() == Net.Mode.DEATHMATCH else team_col(center.team).lightened(0.4)


# --- Zeichnen -----------------------------------------------------------------------------------------------

## Blickrichtung auf einer genordeten Karte (forward() = (−sin yaw, 0, −cos yaw), Norden = −Z oben → x = fw.x, y = fw.z)
static func dir2(fw: Vector3) -> Vector2:
	return Vector2(fw.x, fw.z)


## eigener Pfeil: Lage p, Blickrichtung dir in Kartenpunkten (dir2 bzw. über die Kartenabbildung gedreht)
static func draw_self(ci: CanvasItem, p: Vector2, dir: Vector2, col: Color, k := 1.0) -> void:
	var f := dir.normalized()
	if f == Vector2.ZERO:
		f = Vector2.UP
	var side := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([p + f * 9.0 * k, p - f * 5.0 * k + side * 5.5 * k, p - f * 2.0 * k, p - f * 5.0 * k - side * 5.5 * k])
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0, 0, 0, 0.7), 1.0)


static func draw_ally(ci: CanvasItem, p: Vector2, col: Color, r := 4.5) -> void:
	ci.draw_circle(p, r + 1.0, Color(0, 0, 0, 0.6))
	ci.draw_circle(p, r, col)


static func draw_shot(ci: CanvasItem, p: Vector2, e: Dictionary, k := 1.0) -> void:
	var a := alpha_of(e)
	ci.draw_circle(p, 5.0 * k, Color(COL_ENEMY, a))
	ci.draw_arc(p, (5.0 + (1.0 - a) * 6.0) * k, 0, TAU, 16, Color(COL_ENEMY, a * 0.6), 1.5)


## Affine Abbildung Welt (x, z) → Karte aus Punktpaaren (≥ 3 nicht kollinear: kleinste Quadrate; 2: genordete
## Ähnlichkeit ohne Spiegelung). Ungültig → Transform2D() mit Determinante 0 (Prüfung über determinant()).
static func fit_affine(world: Array, screen: Array) -> Transform2D:
	var n := mini(world.size(), screen.size())
	if n >= 3:
		var a := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		var bu := Vector3.ZERO
		var bv := Vector3.ZERO
		for i in n:
			var w: Vector2 = world[i]
			var s: Vector2 = screen[i]
			var r := Vector3(w.x, w.y, 1.0)
			a.x += r * r.x
			a.y += r * r.y
			a.z += r * r.z
			bu += r * s.x
			bv += r * s.y
		if absf(a.determinant()) > 1e-6:
			var inv := a.inverse()
			var cu: Vector3 = inv * bu
			var cv: Vector3 = inv * bv
			var xf := Transform2D(Vector2(cu.x, cv.x), Vector2(cu.y, cv.y), Vector2(cu.z, cv.z))
			if absf(xf.determinant()) > 1e-9:
				return xf
	if n >= 2:
		var dw: Vector2 = world[1] - world[0]
		var ds: Vector2 = screen[1] - screen[0]
		if dw.length() > 0.5 and ds.length() > 0.5:
			var sc := ds.length() / dw.length()
			var ang := dw.angle_to(ds)
			var xf := Transform2D(ang, Vector2(sc, sc), 0.0, Vector2.ZERO)
			xf.origin = screen[0] - xf.basis_xform(world[0])
			return xf
	return Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
