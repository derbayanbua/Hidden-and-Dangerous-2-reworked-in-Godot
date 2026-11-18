extends "res://tests/lan_ui_base.gd"
## 0.11.7: LAN-Menü im Original-Look – MEHRSPIELER-SPIEL – LAN (multiplayer menu.4ds, Titel T2320) und SERVER ERSTELLEN
## (create server.4ds) aus den Original-Menümodellen der Nutzerinstallation (orig_cache, nie im Repo); das alte
## Formular bleibt unsichtbares Datenmodell. Prüft Sichtbarkeit/Layout und schreibt Kontrollbilder (nur Fenster).
##   tools\godot.cmd -- --autoplay=shots_lan_menu --profiles_dir=user://shots_lan_menu --noimport [--shots=1]
## Kontrollbilder: test_output/b0117_lan_browser.png, test_output/b0117_lan_create.png


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_finish())
	_run.call_deferred()


func shot(n: String) -> void:
	if not " ".join(OS.get_cmdline_user_args()).contains("--shots=1"):
		return
	await frames(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var p := ProjectSettings.globalize_path("res://test_output/b0117_lan_%s.png" % n)
	get_viewport().get_texture().get_image().save_png(p)
	print("BILD ", p)


## Sichtbare Steuerelemente außerhalb der Original-Bildschirme (alte Formularoptik) zählen
func _foreign_visible(lm: Node, screen: Node) -> Array:
	var out: Array = []
	for c in lm.find_children("*", "Control", true, false):
		if not (c as Control).is_visible_in_tree() or screen.is_ancestor_of(c) or c == screen:
			continue
		if c is Button or c is LineEdit or c is ItemList or c is SpinBox or c is OptionButton or c is Label:
			out.append(String(c.name))
	return out


func _run() -> void:
	var menu := await menu_with_profile("LanLook")
	menu.open_lan(false)
	await frames(6)
	var lm: LanMenu = menu.lan_menu
	var br: ServerBrowserScreen = lm.browser if lm else null
	check(br != null and br.visible, "LAN: Original-Serverbrowser offen")
	if br == null:
		_finish()
		return
	check(br is OrigScreen and br.has_layout(), "LAN: Bildschirm aus Original-Menümodell (multiplayer menu.4ds)")
	check(br.find_child("BackButton", true, false) != null and br.find_child("CreateButton", true, false) != null,
		"LAN: Original-Knöpfe ZURÜCK/SERVER ERSTELLEN")
	var fv := _foreign_visible(lm, br)
	check(fv.is_empty(), "LAN: kein altes Formular sichtbar", str(fv))
	await shot("browser")
	lm.open_create()
	await frames(6)
	var cs: CreateServerScreen = lm.create_screen
	check(cs != null and cs is OrigScreen and cs.visible and not br.visible, "SERVER ERSTELLEN: Original-Bildschirm (create server.4ds)")
	if cs:
		fv = _foreign_visible(lm, cs)
		check(fv.is_empty(), "SERVER ERSTELLEN: kein altes Formular sichtbar", str(fv))
		await shot("create")
		lm.close_create()
		await frames(4)
	check(br.visible, "ZURÜCK aus SERVER ERSTELLEN → LAN-Browser")
	_finish()
