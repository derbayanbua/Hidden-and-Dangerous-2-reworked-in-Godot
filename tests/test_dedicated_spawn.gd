extends "res://tests/lan_ui_base.gd"
## 0.11.6: Spawn auf dem DEDIZIERTEN Server mit aktiver Setup-Sperre (wie Demo-Server: kein --setup_gate=0), zwei Prozesse.
## Server: kopflos --dedicated=<cfg>, Stil Deathmatch, Rotation DM -> HD2-Aufgaben -> Besetzung -> DM, bots 3,
## Spieler unverwundbar (--test_god=1). Client = dieser Prozess mit --setup_gate=1 (Sperre wie ein echter Client):
## SPIELER-SETUP öffnet sich, AKZEPTIEREN -> Server spawnt. Geprüft: später Beitritt (> 30 s), Kartenwechsel über
## alle Stile, erneuter Beitritt nach Kartenwechsel, Diagnosezeilen des Servers („nicht gespawnt: …“).
##   tools\godot.cmd --headless -- --autoplay=test_dedicated_spawn --setup_gate=1 --profiles_dir=user://test_ded_spawn --noimport

const DPORT := 11071
const MAPS := ["mp_arctic2_mp", "mp_arctic1_obj", "mp_arctic4_mp_zone", "mp_arctic1_mp"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(2400.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_end())
	_run.call_deferred()


var _stdio: FileAccess
var _stderr: FileAccess
var _pid := 0
var out_text := ""


func _process(_d: float) -> void:
	if _stdio == null:
		return
	for pipe in [_stdio, _stderr]:
		if pipe == null:
			continue
		for i in 64:
			var b: PackedByteArray = pipe.get_buffer(4096)
			if b.is_empty():
				break
			out_text += b.get_string_from_utf8()


func _console(line: String) -> void:
	_stdio.store_string(line + "\n")
	_stdio.flush()


func _end() -> void:
	var f := FileAccess.open("res://test_output/test_dedicated_spawn_server.txt", FileAccess.WRITE)
	if f:
		f.store_string(out_text)
		f.close()
	if _pid > 0 and OS.is_process_running(_pid):
		_console("quit")
		await get_tree().create_timer(5.0, true, false, true).timeout
		if OS.is_process_running(_pid):
			OS.kill(_pid)
	_finish()


func _mine() -> bool:
	return Game.current_mission() != null and Net._soldiers.has(Net.my_id()) and is_instance_valid(Net._soldiers[Net.my_id()])


## SPIELER-SETUP abwarten und AKZEPTIEREN (wie Klick: Signal accepted des Bildschirms)
func _accept_setup(label: String) -> bool:
	var pm_open := func() -> bool:
		var m = Game.current_mission()
		var pm = m.get_node_or_null("PauseMenu") if m else null
		return pm != null and is_instance_valid(pm.player_setup)
	var ok: bool = await wait_for(pm_open, 300.0)
	check(ok, "%s: SPIELER-SETUP öffnet sich beim Client" % label)
	if not ok:
		return false
	var pm = Game.current_mission().get_node("PauseMenu")
	pm.player_setup.accept()          # AKZEPTIEREN wie Klick (Figur/Klasse/Seite/Ausrüstung, dann accepted)
	return true


func _join(label: String) -> bool:
	Net.local_name = "Spaeter"
	Net.join("127.0.0.1", DPORT)
	if not await _accept_setup(label):
		return false
	var ok: bool = await wait_for(_mine, 120.0)
	check(ok, "%s: eigener Soldat gespawnt" % label, out_text.substr(maxi(out_text.length() - 1500, 0)))
	return ok


func _run() -> void:
	await frames(10)
	check(Net.setup_gate_on(), "Client mit aktiver Setup-Sperre (--setup_gate=1)")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var cfg := ProjectSettings.globalize_path("res://test_output/test_dedicated_spawn.cfg")
	var lines := ["sessionname \"Ded-Spawn\"", "style deathmatch"]
	for mp in MAPS:
		lines.append("mapname " + mp)
	# Demo-Server-Fall: letzte style-Zeile „objectives“ → Aufgaben-Standards (allowrespawn 0, respawntime 0) wurden
	# vor 0.11.6 für die ganze Rotation übernommen, auch auf DM-Karten (kein Spawn/Respawn für Spieler und Bots)
	lines.append_array(["port %d" % DPORT, "bots 3", "style objectives", "server"])
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string("\n".join(PackedStringArray(lines)) + "\n")
	f.close()
	var pargs := [] if OS.has_feature("template") else ["--path", ProjectSettings.globalize_path("res://")]
	# wie dedicated_server_screen.gd: KEIN --setup_gate=0 (Sperre aktiv); --test_god=1 = Spieler unverwundbar
	var r := OS.execute_with_pipe(OS.get_executable_path(), ["--headless"] + pargs + ["--", "--dedicated=" + cfg, "--test_god=1"], false)
	_stdio = r.get("stdio")
	_stderr = r.get("stderr")
	_pid = int(r.get("pid", 0))
	check(_pid > 0, "Dedizierter Server gestartet", str(_pid))
	if _pid <= 0:
		_end()
		return
	var addr := "127.0.0.1:%d" % DPORT
	Net.favorites = [addr]
	Net.browsing_favorites = true
	var up := func() -> bool: return Net.fav_info.has(addr) and int(Net.fav_info[addr].get("bots", 0)) >= 3
	check(await wait_for(up, 400.0), "Server antwortet, Karte geladen, KI-Soldaten", str(Net.fav_info.get(addr, {})))
	Net.browsing_favorites = false
	Net.favorites = []
	# --- 1) später Beitritt (> 30 s nach Rundenbeginn, Deathmatch) ---
	await get_tree().create_timer(35.0, true, false, true).timeout
	await _join("DM spät")
	check(Game.current_mission_id == MAPS[0], "Erste Karte DM", Game.current_mission_id)
	check(Net.mode() == Net.Mode.DEATHMATCH and bool(Net.rule("allow_respawn")) and int(Net.rule("respawn_s")) == 5,
		"Erste Karte: DM-Regeln trotz „style objectives“ (Respawn erlaubt, 5 s)", "%d %s %s" % [Net.mode(),
		str(Net.rule("allow_respawn")), str(Net.rule("respawn_s"))])
	# Respawn nach Tod (Spieler unverwundbar → Tod per Konsole „kill“ ist offline-only; Bots: mindestens einer stirbt
	# und kommt zurück, s. u.) – hier: Bots spawnen nach Tod neu
	var mark := out_text.length()
	var bot_back := func() -> bool:      # Server-Log: KI-Soldat nach dem Beitritt erneut gespawnt (nach Tod)
		return RegEx.create_from_string("NET: Spawn für -\\d+ ").search(out_text.substr(mark)) != null
	check(await wait_for(bot_back, 240.0), "DM: KI-Soldat nach Tod wieder gespawnt (Respawn wirkt)")
	# --- 2) Kartenwechsel über alle Stile (beigetreten bleiben) ---
	for i in [1, 2, 3]:
		_console("nextmap")
		var on_map := func() -> bool: return Game.current_mission_id == MAPS[i] and Game.current_mission() != null
		check(await wait_for(on_map, 400.0), "nextmap -> %s" % MAPS[i], Game.current_mission_id)
		var sp: bool = await wait_for(_mine, 120.0)
		check(sp, "Nach Kartenwechsel auf %s (Stil %d) gespawnt" % [MAPS[i], Net.mode()],
			out_text.substr(maxi(out_text.length() - 1500, 0)))
	# --- 3) Verlassen, > 30 s warten, auf der DM-Karte nach der Rotation erneut beitreten ---
	Net.leave(true)
	var left := func() -> bool: return Game.current_mission() == null
	await wait_for(left, 60.0)
	await get_tree().create_timer(35.0, true, false, true).timeout
	await _join("DM nach Rotation spät")
	check(int(Net.rule("respawn_s")) == 5 and bool(Net.rule("allow_respawn")), "DM-Regeln nach der Rotation (Respawn 5 s, erlaubt)",
		"%s %s" % [str(Net.rule("respawn_s")), str(Net.rule("allow_respawn"))])
	# --- 4) HD2-Aufgaben: später Beitritt -> Zuschauer (Original) mit Diagnose ---
	Net.leave(true)
	await wait_for(left, 60.0)
	var begun := func() -> int: return out_text.count("die Runde beginnt")
	var n0: int = begun.call()
	_console("map " + MAPS[1])
	check(await wait_for(func(): return begun.call() > n0, 400.0), "Aufgaben-Karte geladen, Aufwärmen beendet")
	await get_tree().create_timer(40.0, true, false, true).timeout      # Rundenzeit > 30 s
	Net.local_name = "Zuschauer"
	Net.join("127.0.0.1", DPORT)
	await _accept_setup("Aufgaben spät")
	var spec := func() -> bool: return bool(Net.players.get(Net.my_id(), {}).get("spectator", false))
	check(await wait_for(spec, 120.0), "Aufgaben-Karte, Beitritt nach 30 s: Zuschauer (Original)")
	check(await wait_for(func(): return out_text.contains("nicht gespawnt: Zuschauer"), 60.0),
		"Server-Log nennt den Grund (Zuschauer)")
	check(out_text.contains("nicht gespawnt: im SPIELER-SETUP"), "Server-Log nennt den Grund (SPIELER-SETUP)")
	Net.leave(true)
	await wait_for(left, 60.0)
	_end()
