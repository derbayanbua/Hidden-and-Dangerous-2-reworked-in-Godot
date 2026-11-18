extends Control
## 0.11.6 Mehrspieler-Minikarte (0.11.7: Server-Regel „minimap“, Standard aus; an = links unten über der Truppleiste
## statt Kompass; genordet, Mitte = eigene Figur bzw. beobachteter Spieler).
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
## 0.11.7: Schussprotokoll, Sichtregeln und Marken liegen gemeinsam in src/ui/map_marks.gd (MapMarks); die große
## MP-Karte M (MpHud.ZoneMap) liest Sicht und Schüsse von hier, die SP-Karte M (TacticalMap) nutzt MapMarks direkt.

const RANGE_M := 60.0              ## Kartenradius in Metern
const SHOT_TTL := MapMarks.SHOT_TTL               ## Sichtbarkeit eines Schusses [s]
const SILENCED_RADIUS := MapMarks.SILENCED_RADIUS

var marks := MapMarks.new()
var shots: Array:                  ## [{pos: Vector3, t: float, src: Soldier}] (Tests)
	get: return marks.shots
var center_soldier: Soldier        ## Mitte der Karte (Tests; auch Sicht der großen MP-Karte)
var view_team := -1
const MARGIN := 10.0
const BAR_TOP_FRAC := 0.89078     ## Oberkante tabl01/soldier00 (gameinterface.4ds, Anteil der Bildhöhe)


## Oberkante der Truppleiste in Bildschirmpunkten: Original-HUD-Feld tabl01, sonst Anteil wie im Original
func squad_bar_top(h: float) -> float:
	var m = Game.current_mission()
	var oh = m.hud.get("orig_hud") if m is Mission and m.hud else null
	if oh and is_instance_valid(oh):
		for nm in ["tabl01", "soldier00"]:
			if oh.elements.has(nm) and oh.elements[nm].has("screen"):
				return (oh.elements[nm]["screen"] as Rect2).position.y
	return h * BAR_TOP_FRAC


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.connect_noise()


func _exit_tree() -> void:
	marks.disconnect_noise()


static func is_silenced_noise(radius: float, wd: WeaponData = null) -> bool:
	return MapMarks.is_silenced_noise(radius, wd)


## Lebende Verbündete des Betrachters (ohne ihn selbst)
func allies() -> Array:
	return MapMarks.mp_allies(center_soldier, view_team)


## Sichtbare Gegner-Schussmarken (Quelle ist nicht verbündet und nicht der Betrachter)
func enemy_shots() -> Array:
	return marks.enemy_shots(center_soldier, view_team, Net.team_mode())


func _process(delta: float) -> void:
	marks.tick(delta)
	var root := get_parent() as Control
	if root:
		var h := root.size.y
		var d := clampf(h * 0.24, 120.0, 320.0)
		size = Vector2(d, d)
		# 0.11.7: links unten, unmittelbar über der Truppleiste (Spielersymbole), an der Stelle des Kompasses links
		var bar_top := squad_bar_top(h)
		position = Vector2(MARGIN, maxf(MARGIN, bar_top - d - MARGIN))
	center_soldier = MapMarks.mp_center(root.get_parent() if root else null)
	# Betrachterteam auch bei ausgeschalteter Minikarte (die große Karte M nutzt dieselbe Sicht)
	view_team = center_soldier.team if is_instance_valid(center_soldier) else -1
	# 0.11.7: Server-Regel „minimap“ (Standard aus); an → ersetzt den Kompass (hud.gd/OrigHud.compass_hidden)
	visible = Net.minimap_enabled() and is_instance_valid(center_soldier)
	if visible:
		queue_redraw()


func map_point(world: Vector3) -> Vector2:
	var r := size.x * 0.5
	var rel := world - center_soldier.global_position
	var v := Vector2(rel.x, rel.z) / RANGE_M * (r - 6.0)    # Norden (−Z) oben
	if v.length() > r - 6.0:
		v = v.normalized() * (r - 6.0)
	return Vector2(r, r) + v


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
		MapMarks.draw_shot(self, map_point(e["pos"]), e)
	for s in allies():
		MapMarks.draw_ally(self, map_point(s.global_position), MapMarks.team_col(s.team))
	MapMarks.draw_self(self, c, MapMarks.dir2(center_soldier.forward()),MapMarks.mp_self_col(center_soldier))
