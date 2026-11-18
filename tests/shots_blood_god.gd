extends "res://tests/shots_blood.gd"
## 0.11.7: shots_blood mit unverwundbarem Trupp (Gesundheit des Trupps wird jedes Bild aufgefüllt) für GPU-Prüfläufe.
##   tools\godot.cmd -- --mission=m01_funkfeuer --autoplay=shots_blood_god --profiles_dir=user://test_blut


func _ready() -> void:
	_keep_alive()
	super._ready()


func _keep_alive() -> void:
	while is_inside_tree():
		var m = mission()
		if m and m.squad:
			for s in m.squad.members:
				if is_instance_valid(s) and s.alive:
					s.health = maxf(s.health, 100.0)
		await get_tree().process_frame
