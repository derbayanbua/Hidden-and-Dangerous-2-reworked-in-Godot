extends RefCounted
## 0.11.7 (AP-48e): Zielfehler der Original-KI nach hd2.exe [B] (REA/Ghidra, SHA256 b0260850…).
## Per preload genutzt (kein class_name).
##
## 0x5722B0 = Zielrichtung des KI-Controllers vor dem Schuss (danach wie beim Spieler 0x545140 dw15-Streuung, KEIN Rückstoß):
##   Richtung ×100, waagrechte Senkrechte p = normiert(−z, 0, x); dir += p · (rand − 0,5) · 2 · s; normieren.
##   → seitlicher Versatz bis ±s Meter auf 100 m (nur waagrecht).
##   s = 0x572120 (Schütze = Mensch des Controllers, +0x44):
##     2·(1 − Schießen/100)                        (Schießen = Mensch +0xFC)
##     + Haltung (+0x4C [P 0 stehen/1 hocken/2 liegen]): 0 → 0,7 + 0,3r; 1 → 0,3 + 0,6r; sonst 0,4r
##     + Bewegung 0x5A5CC0 (−1 = steht): 0 → 0,2 + 0,3r; 1 → 0,3 + 0,2r; 2 → 0,4 + 0,1r; 5 → 0,5 + 0,3r; sonst 0,5r
##     + Controller +0xB0 < 2500 (ms seit Zielaufnahme [P]) → 0,4 + 0,6r
##     + Waffenklasse (vtable+0xC der Gegenstandsdefinition) 1/4 → 0,3 + 0,2r; 2 → 1,0 + 0,4r
##   Controller +0x48 == 3 → s·0,4 [P Sondermodus, nicht nachgebaut]; sonst Schwierigkeit 0x6B6700: 1 → ×2, 2 → ×1,5.
## Granate (gleiche Funktion, Gegenstand +0x48 Typ 2): Zielpunkt je Achse ± (10 − Schießen·0,1) m [B], Wurfwinkel ballistisch.
## Zuordnung Bewegungsklasse/Waffenklasse zu unseren Werten ist [P] (siehe gait_class/weapon_class).

const LOCK_MS := 2500.0


## Bewegungsklasse wie 0x5A5CC0 [P-Zuordnung]: −1 steht, 0 Schleichen, 1 Gehen, 2 Laufschritt, 5 Sprint
static func gait_class(s: Soldier) -> int:
	if s == null or not s.is_moving():
		return -1
	match s.move_mode:
		Soldier.MoveMode.SNEAK:
			return 0
		Soldier.MoveMode.WALK:
			return 1
		Soldier.MoveMode.RUN:
			return 5
	return 2


## Waffenklasse wie Getter vtable+0xC (0x7E0520 = items.sav Waffen-Schlussblock dw0) [B seit 0.11.7, B-051]:
## 1 MPs, 2 Pistolen, 3 Gewehre/MP 44, 4 MGs/BAR, 5 Werfer (WeaponDB.orig_weapon_class). Ohne Originalgegenstand
## bzw. mit `--orig_wkind=0` die alte Zuordnung [P]: 2 Pistole, 1 Automatikwaffe, 0 übrige.
static func weapon_class(w: Weapon) -> int:
	if w == null or w.data == null:
		return 0
	var item := WeaponDB.orig_item_of(w.data.id)
	if item >= 0:
		var c := WeaponDB.orig_weapon_class(item)
		if c >= 0:
			return c
	if w.data.slot == WeaponData.Slot.SIDEARM:
		return 2
	if w.data.action == WeaponData.Action.AUTO or w.data.can_toggle_auto:
		return 1
	return 0


## 0x572120 [B]: seitlicher Fehler in Metern je 100 m
static func deviation(shooting: float, stance: int, gait: int, track_ms: float, wclass: int, rng: RandomNumberGenerator = null) -> float:
	var r := func() -> float: return rng.randf() if rng else randf()
	var s := 2.0 * (1.0 - shooting * 0.01)
	if stance == 0:
		s += r.call() * 0.3 + 0.7
	elif stance == 1:
		s += r.call() * 0.6 + 0.3
	else:
		s += r.call() * 0.4
	match gait:
		0:
			s += r.call() * 0.3 + 0.2
		1:
			s += r.call() * 0.2 + 0.3
		2:
			s += r.call() * 0.1 + 0.4
		5:
			s += r.call() * 0.3 + 0.5
		_:
			s += r.call() * 0.5
	if track_ms < LOCK_MS:
		s += r.call() * 0.6 + 0.4
	if wclass == 1 or wclass == 4:
		s += r.call() * 0.2 + 0.3
	elif wclass == 2:
		s += r.call() * 0.4 + 1.0
	return s


## Schwierigkeitsfaktor aus 0x5722B0 [B]: 1 → 2, 2 → 1,5, sonst 1
static func difficulty_k(level: int) -> float:
	if level == 1:
		return 2.0
	if level == 2:
		return 1.5
	return 1.0


## 0x5722B0 [B]: waagrechter Versatz der Schussrichtung um ±s auf 100 m
static func apply(dir: Vector3, s: float, rng: RandomNumberGenerator = null) -> Vector3:
	var d := dir * 100.0
	var p := Vector3(-d.z, 0.0, d.x)
	if p.length_squared() < 1e-8:
		return dir
	p = p.normalized()
	var u := (rng.randf() if rng else randf()) - 0.5
	d += p * (u * 2.0 * s)
	return d.normalized()


## Granatziel [B]: je Achse ± (10 − Schießen·0,1) m
static func grenade_target(target: Vector3, shooting: float, rng: RandomNumberGenerator = null) -> Vector3:
	var k := 10.0 - shooting * 0.1
	var f := func() -> float: return ((rng.randf() if rng else randf()) - 0.5) * 2.0 * k
	return target + Vector3(f.call(), f.call(), f.call())


## Schießen-Wert eines Originalgegners (actors.bin, nach Schwierigkeit), Rückfall Kaderwert/64
static func shooting_of(s: Soldier) -> float:
	if s == null:
		return 64.0
	if s.has_meta("orig_params"):
		return float((s.get_meta("orig_params") as Dictionary).get("shooting", 64))
	if s.skill_shooting >= 0.0:
		return s.skill_shooting
	return 64.0
