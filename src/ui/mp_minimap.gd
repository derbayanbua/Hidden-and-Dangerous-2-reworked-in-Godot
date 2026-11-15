extends Control
## 0.11.6 Mehrspieler-Minikarte (rechts am Rand, genordet, Mitte = eigene Figur bzw. beobachteter Spieler).
## [D] Eigene Vorgabe: Das Original-HD2 hat im MP-HUD keine Minikarte (nur Kompass mit Kameradenpunkten kul_us,
## OrigHud._update_compass_dots, und die Spawnzonen-Karte M) – nicht weiter in hd2.exe gesucht.
##  - eigene Position + Blickrichtung (Pfeil) immer
##  - Verbündete (gleiches Team, nur Team-Stile; im Deathmatch hat niemand Verbündete) lebend in Teamfarbe,
##    außerhalb der Reichweite am Rand
##  - Gegner nur, wenn sie schießen: Marke an der Schützenlage zum Schusszeitpunkt, SHOT_TTL s ausblendend;
##    Schalldämpferwaffen (Klangklasse silenced_* bzw. Geräuschweite < 20 m, wie CommandMenu.has_silenced) nie
##  - Zuschauer: Sicht des beobachteten Spielers (dessen Team); freie Kamera → Karte aus
## Datenquelle nur lokal vorhandene Netzfiguren (Net._soldiers) und das lokale Schussgeräusch Events.noise_emitted
## (kind „gunshot“, auch für Netzschüsse aus Net._do_act) – keine neuen RPCs, Protokoll unverändert.

const RANGE_M := 60.0              ## Kartenradius in Metern
const SHOT_TTL := 2.5              ## Sichtbarkeit eines Schusses [s]
const SILENCED_RADIUS := 20.0
const COL_ALLIED := Color(0.45, 0.7, 1.0)
const COL_AXIS := Color(0.95, 0.85, 0.35)
const COL_ENEMY := Color(1.0, 0.25, 0.2)
const COL_SELF := Color(1, 1, 1)

var shots: Array = []              ## [{pos: Vector3, t: float, src: Soldier}] (Tests)
var center_soldier: Soldier        ## Mitte der Karte (Tests)
var view_team := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.noise_emitted.connect(_on_noise)


static func is_silenced_noise(radius: float, wd: WeaponData = null) -> bool:
	if wd and String(wd.sound).begins_with("silenced"):
		return true
	return radius < SILENCED_RADIUS


func _on_noise(pos: Vector3, radius: float, source: Node, _team: int, kind: StringName) -> void:
	if kind != &"gunshot" or not (source is Soldier):
		return
	var s := source as Soldier
	var w = s.current_weapon() if s.has_method("current_weapon") else null
	if is_silenced_noise(radius, w.data if w else null):
		return
	shots.append({"pos": pos, "t": SHOT_TTL, "src": s})
	if shots.size() > 64:
		shots.pop_front()


## Lebende Verbündete des Betrachters (ohne ihn selbst)
func allies() -> Array:
	var out: Array = []
	if not Net.team_mode() or not is_instance_valid(center_soldier):
		return out
	for id in Net._soldiers:
		var s: Soldier = Net._soldiers[id]
		if is_instance_valid(s) and s != center_soldier and s.alive and s.team == view_team:
			out.append(s)
	return out


## Sichtbare Gegner-Schussmarken (Quelle ist nicht verbündet und nicht der Betrachter)
func enemy_shots() -> Array:
	var out: Array = []
	for e in shots:
		var s = e["src"]
		if is_instance_valid(s) and (s == center_soldier or (Net.team_mode() and s.team == view_team)):
			continue
		out.append(e)
	return out


func _pick_center() -> Soldier:
	var hud = get_parent().get_parent() if get_parent() else null
	if hud and hud.get("spectating"):
		if hud.spec_free:
			return null
		return Net._soldiers.get(hud.spec_target_id)
	var me: Soldier = Net._soldiers.get(Net.my_id())
	return me if is_instance_valid(me) and me.alive else null


func _process(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		shots[i]["t"] = float(shots[i]["t"]) - delta
		if float(shots[i]["t"]) <= 0.0:
			shots.remove_at(i)
	var root := get_parent() as Control
	if root:
		var h := root.size.y
		var d := clampf(h * 0.24, 120.0, 320.0)
		size = Vector2(d, d)
		position = Vector2(root.size.x - d - 12.0, h * 0.30)
	center_soldier = _pick_center()
	visible = Net.is_online and is_instance_valid(center_soldier)
	view_team = center_soldier.team if visible else -1
	if visible:
		queue_redraw()


func map_point(world: Vector3) -> Vector2:
	var r := size.x * 0.5
	var rel := world - center_soldier.global_position
	var v := Vector2(rel.x, rel.z) / RANGE_M * (r - 6.0)    # Norden (−Z) oben
	if v.length() > r - 6.0:
		v = v.normalized() * (r - 6.0)
	return Vector2(r, r) + v


func _team_col(team: int) -> Color:
	return COL_AXIS if team == Soldier.TEAM_AXIS else COL_ALLIED


func _draw() -> void:
	if not is_instance_valid(center_soldier):
		return
	var r := size.x * 0.5
	var c := Vector2(r, r)
	draw_circle(c, r, Color(0.05, 0.06, 0.04, 0.55))
	draw_arc(c, r, 0, TAU, 48, Color(0.85, 0.8, 0.6, 0.8), 2.0)
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(0.85, 0.8, 0.6, 0.25), 1.0)
	draw_string(get_theme_default_font(), c + Vector2(-4, -r + 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.9, 0.85, 0.65))
	for e in enemy_shots():
		var a := clampf(float(e["t"]) / SHOT_TTL, 0.0, 1.0)
		var p := map_point(e["pos"])
		draw_circle(p, 5.0, Color(COL_ENEMY, a))
		draw_arc(p, 5.0 + (1.0 - a) * 6.0, 0, TAU, 16, Color(COL_ENEMY, a * 0.6), 1.5)
	for s in allies():
		draw_circle(map_point(s.global_position), 4.5, _team_col(s.team))
	# eigene Lage + Blickrichtung (forward = (−sin yaw, 0, −cos yaw) → Karte x = fw.x, y = fw.z)
	var fw := center_soldier.forward()
	var f := Vector2(fw.x, fw.z).normalized()
	if f == Vector2.ZERO:
		f = Vector2.UP
	var side := Vector2(-f.y, f.x)
	var col := COL_SELF if Net.mode() == Net.Mode.DEATHMATCH else _team_col(center_soldier.team).lightened(0.4)
	draw_colored_polygon(PackedVector2Array([c + f * 9.0, c - f * 5.0 + side * 5.5, c - f * 2.0, c - f * 5.0 - side * 5.5]), col)
