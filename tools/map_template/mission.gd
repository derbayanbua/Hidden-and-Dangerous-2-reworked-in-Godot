extends "res://src/mission/custom_map_mission.gd"
## Optionales Missionsskript der Vorlage / optional mission script of the template.
## Ohne Eintrag "script" in map.json wird custom_map_mission.gd direkt verwendet.


func _build_world() -> void:
	super()
	light_factor = 0.9                     # Sichtbarkeit für die KI (1 = Tag, 0,5 = Nacht)
	ground_material = 50                   # Original-Untergrund für Schrittklänge


func _setup_objectives() -> void:
	pass                                   # freie Karte ohne Ziele / free map without objectives
