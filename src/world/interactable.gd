class_name Interactable
extends Node3D
## Basis für benutzbare Objekte (Taste "Benutzen"). Der PlayerController
## wählt das nächste Objekt in Reichweite vor dem Soldaten.

signal used(by: Soldier)

@export var prompt := "Benutzen"
@export var persistent_id := ""
var enabled := true


func _ready() -> void:
	add_to_group("interactables")


func can_interact(_s: Soldier) -> bool:
	return enabled


func interact(s: Soldier) -> void:
	# Original-Benutzenclip der Figur (Tür, Aufheben, Schalter …; Soldier.play_use_anim)
	if is_instance_valid(s) and s.has_method("play_use_anim"):
		s.play_use_anim(self)
	if is_instance_valid(s):
		FieldInventory.view(s)       # Aufgenommenes in Aufnahmereihenfolge festhalten (Ingame-Inventar, inv_order)
	used.emit(s)


## Sichtlinie Benutzen (alle Karten, SP und MP-Server): Strahl vom Kopf bzw. Oberkörper des Soldaten zum
## Interaktionspunkt gegen die statische Welt (Ebene 1, nur StaticBody3D). Eigene Kollider des Objekts (Teilbaum und
## nächster Kollisionskörper darüber) blockieren nicht; ein Treffer ≤ 0,45 m vor dem Zielpunkt gilt als Objektoberfläche.
## Blockiert jede Kombination aus Augen-/Brusthöhe und Zielpunkt (Fuß/Mitte), ist keine Benutzung möglich
## (z. B. Stellung über der Stollendecke, Schalter hinter der Wand).
static func sight_clear(s: Soldier, it: Node3D) -> bool:
	if not is_instance_valid(s) or not is_instance_valid(it) or not s.is_inside_tree() or not it.is_inside_tree():
		return true
	var space := s.get_world_3d().direct_space_state
	var excl: Array[RID] = s.exclude_rids()
	for c in it.find_children("*", "CollisionObject3D", true, false):
		excl.append((c as CollisionObject3D).get_rid())
	var up := it.get_parent()
	while up != null and up is Node3D:
		if up is CollisionObject3D:
			excl.append((up as CollisionObject3D).get_rid())
			break
		up = up.get_parent()
	if it is CollisionObject3D:
		excl.append((it as CollisionObject3D).get_rid())
	if it.has_method("shot_exclusions"):      # Stellungen: eigenes Modell (Lafette, Bock) liegt neben dem Knoten
		excl.append_array(it.shot_exclusions())
	if it.has_method("own_colliders"):
		excl.append_array(it.own_colliders())
	var tgt: Vector3 = it.global_position
	if it.has_method("interact_point"):
		tgt = it.interact_point()
	# Reichhöhe: mehr als 2,6 m darüber bzw. 2,2 m darunter ist kein Benutzen (z. B. Stellung über einem Treppenschacht)
	var dy := tgt.y - s.global_position.y
	if dy > 2.6 or dy < -2.2:
		return false
	var eyes := [s.global_position + Vector3.UP * 1.5, s.global_position + Vector3.UP * 0.9, s.global_position + Vector3.UP * 0.35]
	var tgts := [tgt + Vector3.UP * 0.15, tgt + Vector3.UP * 0.9]
	for e in eyes:
		for t in tgts:
			if _ray_free(space, e, t, excl):
				return true
	return false


static func _ray_free(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, excl: Array[RID]) -> bool:
	var ex := excl.duplicate()
	for _i in 6:
		var q := PhysicsRayQueryParameters3D.create(a, b, 1)
		q.exclude = ex
		var h := space.intersect_ray(q)
		if h.is_empty():
			return true
		if not h.collider is StaticBody3D:
			ex.append(h.rid)          # Türflügel, Fahrzeuge, Starrkörper: nur statische Welt blockiert
			continue
		return (h.position as Vector3).distance_to(b) <= 0.45
	return true


func serialize() -> Dictionary:
	return {"enabled": enabled}


func deserialize(d: Dictionary) -> void:
	enabled = d.get("enabled", true)
