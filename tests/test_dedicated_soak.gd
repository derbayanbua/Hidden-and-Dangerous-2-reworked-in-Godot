extends "res://tests/lan_ui_base.gd"
## 0.11.7 Langlauf (Soak) des dedizierten Servers, zwei Prozesse: kopfloser Server (--dedicated, Bots, Kartenrotation
## über roundlimit 1/roundcount 1 → jede Minute neue Karte) mit MEMSTAT-Zeile (`--mem_log_s`); dieser Prozess tritt
## wiederholt als ENet-Client bei und geht wieder – abwechselnd Verlassen, Rauswurf per Konsole (kickplayer) und
## Kartenwechsel per Konsole (nextmap) während der Sitzung. Prüft: Server lebt und antwortet über die ganze Dauer,
## keine Doppel-disconnect-/Lambda-Fehler, Peer-/Auth-Tabellen nach dem Gehen leer, kein stetiger Speicher-/
## Objektanstieg über die Runden (Median letztes Drittel ≤ erstes Drittel + Toleranz). Messwerte →
## test_output/soak_memstat.csv, Zusammenfassung → test_output/soak_summary.txt.
##   kurz (run_tests -Full):  --autoplay=test_dedicated_soak --soak_min=12 --mem_log_s=15
##   lang (nur -Only):        --autoplay=test_dedicated_soak --soak_min=130 --mem_log_s=60 --soak_tag=long
## Soak test of the dedicated server: repeated join/leave/kick of a second ENet process, map rotation, memory log.

const DPORT := 11071
const MAPS := ["mp_arctic2_mp", "mp_arctic1_mp"]

var soak_min := 12.0
var mem_log_s := 15
var tag := "short"
var _stdio: FileAccess
var _stderr: FileAccess
var _pid := 0
var out_text := ""          ## Serverausgabe (gekürzt), MEMSTAT-Zeilen separat
var mem_rows: Array = []    ## Dictionary je MEMSTAT-Zeile
var _partial := ""
var err_counts := {"disconnect_peer": 0, "lambda": 0, "script_error": 0, "net_auth": 0}
var cycles := {"leave": 0, "kick": 0, "nextmap": 0, "join_fail": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soak_min="):
			soak_min = float(a.get_slice("=", 1))
		elif a.begins_with("--mem_log_s="):
			mem_log_s = int(a.get_slice("=", 1))
		elif a.begins_with("--soak_tag="):
			tag = a.get_slice("=", 1)
	get_tree().create_timer(soak_min * 60.0 + 1200.0, true, false, true).timeout.connect(func():
		check(false, "Zeitüberschreitung des Testlaufs")
		_end())
	_run.call_deferred()


var _last_mem_ms := 0
var stalls: Array = []       ## [Zeitpunkt s, Lücke s, CPU-Sekunden des Servers Δ in 5 s]
var _stall_busy := false


## Server-Hänger erkennen: keine MEMSTAT-Zeile seit 3 Intervallen → CPU-Verbrauch des Serverprozesses messen
## (läuft weiter = Endlosschleife, steht = Blockade/Deadlock), letzte Ausgabezeilen protokollieren.
func _stall_probe() -> void:
	if _stall_busy or _last_mem_ms == 0 or _pid <= 0:
		return
	var gap := (Time.get_ticks_msec() - _last_mem_ms) / 1000.0
	if gap < mem_log_s * 3.0 + 10.0:
		return
	_stall_busy = true
	var c0 := _cpu_s()
	await get_tree().create_timer(5.0).timeout
	var c1 := _cpu_s()
	stalls.append([int(gap), snappedf(c1 - c0, 0.01)])
	print("SOAK-STALL: keine MEMSTAT seit %.0f s, Server-CPU %.2f s in 5 s, letzte Ausgabe:\n%s" % [gap + 5.0, c1 - c0,
		out_text.substr(maxi(out_text.length() - 1500, 0))])
	_last_mem_ms = Time.get_ticks_msec()      # nächste Messung frühestens nach weiteren 3 Intervallen
	_stall_busy = false


func _cpu_s() -> float:
	var o: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command", "(Get-Process -Id %d).CPU" % _pid], o)
	return float(String(o[0]).strip_edges().replace(",", ".")) if not o.is_empty() else -1.0


func _process(_d: float) -> void:
	if _stdio == null:
		return
	_stall_probe()
	for pipe in [_stdio, _stderr]:
		if pipe == null:
			continue
		for i in 64:
			var b: PackedByteArray = pipe.get_buffer(4096)
			if b.is_empty():
				break
			_feed(b.get_string_from_utf8())


## Ausgabe zeilenweise auswerten: MEMSTAT sammeln, Fehlermuster zählen, Rest gekürzt behalten
func _feed(s: String) -> void:
	_partial += s
	var lines := _partial.split("\n")
	_partial = lines[lines.size() - 1]
	for i in lines.size() - 1:
		var l := String(lines[i]).strip_edges()
		if l.begins_with("MEMSTAT "):
			_last_mem_ms = Time.get_ticks_msec()
			var row := {}
			for kv in l.substr(8).split(" ", false):
				var p := kv.split("=")
				if p.size() == 2:
					row[p[0]] = p[1]
			mem_rows.append(row)
			continue
		if l.contains("disconnect_peer") and (l.contains("ERROR") or l.contains("!peers")):
			err_counts["disconnect_peer"] += 1
		if l.contains("Lambda capture") or l.contains("previously freed"):
			err_counts["lambda"] += 1
		if l.contains("SCRIPT ERROR"):
			err_counts["script_error"] += 1
		if l.begins_with("NET-AUTH"):
			err_counts["net_auth"] += 1
		out_text += l + "\n"
	if out_text.length() > 200000:
		out_text = out_text.substr(out_text.length() - 100000)


func _console(line: String) -> void:
	if _stdio:
		_stdio.store_string(line + "\n")
		_stdio.flush()


func _server_up() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


func _query_ok(timeout_s: float) -> bool:
	var addr := "127.0.0.1:%d" % DPORT
	Net.fav_info.erase(addr)
	Net.favorites = [addr]
	Net.browsing_favorites = true
	var ok := func() -> bool: return Net.fav_info.has(addr)
	var r: bool = await wait_for(ok, timeout_s)
	Net.browsing_favorites = false
	Net.favorites = []
	return r


func _run() -> void:
	await frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var cfg := ProjectSettings.globalize_path("res://test_output/test_dedicated_soak.cfg")
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string("\n".join(PackedStringArray(["// Langlauf dedizierter Server (0.11.7)", "sessionname \"Soak-Test\"",
		"style deathmatch", "mapname " + MAPS[0], "mapname " + MAPS[1], "port %d" % DPORT, "warmup 0", "pointlimit 0",
		"roundlimit 1", "roundcount 1", "respawntime 3", "bots 4", "adminlogin chef", "adminpass geheim", "server"])) + "\n")
	f.close()
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path("res://test_output/dedicated_soak_server_%s.log" % tag)]
	if not OS.has_feature("template"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	args += ["--", "--dedicated=" + cfg, "--setup_gate=0", "--test_god=1", "--mem_log_s=%d" % mem_log_s,
		"--mem_log_file=" + ProjectSettings.globalize_path("res://test_output/soak_memstat_server_%s.txt" % tag)]
	var r := OS.execute_with_pipe(OS.get_executable_path(), args, false)
	_stdio = r.get("stdio")
	_stderr = r.get("stderr")
	_pid = int(r.get("pid", 0))
	check(_pid > 0 and _stdio != null, "Dedizierter Server gestartet", str(_pid))
	if _pid <= 0:
		_end()
		return
	check(await _query_ok(400.0), "Server antwortet (Karte geladen)")
	var t0 := Time.get_ticks_msec()
	var deadline := t0 + int(soak_min * 60000.0)
	var i := 0
	var auth_left := 0
	var peers_left := 0
	var query_fail := 0
	while Time.get_ticks_msec() < deadline and _server_up() and stalls.size() < 2:
		i += 1
		Net.local_name = "Soak%d" % (i % 10)
		Net.last_error = ""
		Net.join("127.0.0.1", DPORT)
		var in_game := func() -> bool: return Game.current_mission() != null and Net.is_online and Net._soldiers.has(Net.my_id())
		if not await wait_for(in_game, 300.0):
			cycles["join_fail"] += 1
			print("SOAK: Zyklus %d Beitritt fehlgeschlagen (%s)" % [i, Net.last_error])
			if Net.is_online:
				Net.leave(true)
			await wait_for(func() -> bool: return Game.current_mission() == null, 60.0)
			continue
		await get_tree().create_timer(10.0 + float(i % 4) * 5.0).timeout
		match i % 3:
			0:
				_console("kickplayer " + Net.local_name)
				await wait_for(func() -> bool: return not Net.is_online, 60.0)
				cycles["kick"] += 1
			1:
				Net.leave(true)
				cycles["leave"] += 1
			2:
				_console("nextmap")
				var lost := func() -> bool: return not Net.is_online or Game.current_mission() == null
				await wait_for(lost, 20.0)
				var back := func() -> bool: return not Net.is_online or (Game.current_mission() != null and Net._soldiers.has(Net.my_id()))
				await wait_for(back, 300.0)
				if Net.is_online:
					Net.leave(true)
				cycles["nextmap"] += 1
		await wait_for(func() -> bool: return Game.current_mission() == null and not Net.is_online, 90.0)
		await get_tree().create_timer(3.0).timeout
		if not await _query_ok(120.0):
			query_fail += 1
		if i % 10 == 0:
			print("SOAK: %d Zyklen, %.1f min, MEMSTAT %d, Zyklen %s" % [i, (Time.get_ticks_msec() - t0) / 60000.0, mem_rows.size(), str(cycles)])
	var minutes := (Time.get_ticks_msec() - t0) / 60000.0
	check(_server_up(), "Server läuft nach %.1f min noch (kein Absturz/keine Endlosschleife)" % minutes)
	check(minutes >= soak_min * 0.98, "Laufzeit erreicht", "%.1f / %.1f min" % [minutes, soak_min])
	check(query_fail == 0, "Serverabfrage nach jedem Zyklus beantwortet", "%d Ausfälle" % query_fail)
	var joins: int = cycles["leave"] + cycles["kick"] + cycles["nextmap"]
	check(joins >= maxi(3, int(soak_min / 2.0)) and cycles["kick"] > 0 and cycles["leave"] > 0 and cycles["nextmap"] > 0,
		"Beitritt/Verlassen/Rauswurf/Kartenwechsel wiederholt", str(cycles))
	check(cycles["join_fail"] <= maxi(1, joins / 20), "Beitritte zuverlässig", str(cycles))
	# Nach dem letzten Gehen: Tabellen leer (letzte MEMSTAT-Zeile abwarten)
	await get_tree().create_timer(float(mem_log_s) + 3.0).timeout
	if not mem_rows.is_empty():
		var last: Dictionary = mem_rows[mem_rows.size() - 1]
		peers_left = int(last.get("peers", -1))
		auth_left = int(last.get("auth_live", -1)) + int(last.get("auth_pending", -1)) + int(last.get("auth_drop", -1))
		check(peers_left == 0 and int(last.get("players", -1)) == int(last.get("soldiers", -2)) - 0 and int(last.get("gen", 99)) <= 8,
			"Keine Peers übrig, Spielertabelle nur Bots", str(last))
		check(auth_left == 0, "Auth-Tabellen leer (_live/_pending/_dropping)", str(last))
	check(stalls.is_empty(), "Server ohne Hänger (MEMSTAT lückenlos)", str(stalls))
	check(err_counts["disconnect_peer"] == 0, "Keine disconnect_peer-Fehler (Doppel-disconnect)", str(err_counts))
	check(err_counts["lambda"] == 0, "Keine Fehler durch freigegebene Lambda-Captures", str(err_counts))
	check(err_counts["net_auth"] <= joins * 6 + 20, "NET-AUTH-Ausgaben begrenzt (keine Schleife)", "%d bei %d Zyklen" % [err_counts["net_auth"], joins])
	_check_memory()
	_write_outputs(minutes, joins)
	_console("quit")
	await wait_for(func() -> bool: return not _server_up(), 60.0)
	_end()


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


## Kein stetiger Anstieg: Median des letzten Drittels gegen das erste Drittel (erste 2 Proben = Anlauf ausgelassen),
## dazu Steigung über die zweite Hälfte. Toleranzen [E]: Speicher +15 % bzw. +64 MB, Objekte/Knoten +15 %.
func _check_memory() -> void:
	var rows := mem_rows.slice(2) if mem_rows.size() > 6 else mem_rows
	check(rows.size() >= 6, "Genug MEMSTAT-Proben", "%d" % mem_rows.size())
	if rows.size() < 6:
		return
	# Objekt-/Knotenzahlen hängen von der Karte ab → je Karte vergleichen (Proben unmittelbar nach dem Laden sind
	# im Median enthalten); statischer Speicher kartenübergreifend.
	var by_map := {}
	for r in rows:
		if int(r.get("soldiers", 0)) <= 0:
			continue                  # Probe während des Ladens (alte Szene weg, neue noch nicht da)
		var mk := String(r.get("map", ""))
		if not by_map.has(mk):
			by_map[mk] = []
		(by_map[mk] as Array).append(r)
	for key in ["static_mb", "objects", "nodes", "resources", "orphans"]:   # Waisen = Ladevorlagen (MissionLoader), dürfen nicht wachsen
		var groups: Array = [rows] if key == "static_mb" else by_map.values()
		var detail := []
		var ok := true
		for g in groups:
			var ga: Array = g
			if ga.size() < 3:
				continue
			var n := maxi(ga.size() / 3, 1)
			var a := _median(ga.slice(0, n).map(func(r): return float(r.get(key, 0))))
			var b := _median(ga.slice(ga.size() - n).map(func(r): return float(r.get(key, 0))))
			var limit := a * 1.15 + (64.0 if key == "static_mb" else 200.0)
			ok = ok and b <= limit
			detail.append("%s %.1f→%.1f (≤%.1f)" % [String(ga[0].get("map", "")) if key != "static_mb" else "alle", a, b, limit])
		check(ok, "Kein stetiger Anstieg: %s" % key, ", ".join(detail))
	# 0.12.2: Leichen/Ablagestapel/Diagnoselisten begrenzt (Kills der Bots über die ganze Laufzeit)
	var mx := func(k: String) -> int: return int(rows.map(func(r): return int(r.get(k, 0))).max())
	var max_sold: int = mx.call("soldiers")
	check(int(mx.call("corpses")) <= max_sold * 3 + 8, "Leichen begrenzt", "max %d bei %d Soldaten" % [int(mx.call("corpses")), max_sold])
	check(int(mx.call("piles")) <= 96, "Ablagestapel begrenzt", "max %d" % int(mx.call("piles")))
	check(int(mx.call("logs")) <= 6 * 200, "Diagnoselisten begrenzt", "max %d" % int(mx.call("logs")))
	check(int(mx.call("decals")) <= 160, "Decals begrenzt", "max %d" % int(mx.call("decals")))
	var gens: Array = rows.map(func(r): return int(r.get("gen", 0)))
	check(int(gens.max()) <= 64, "Soldaten-Generationstabelle begrenzt", "max %d" % int(gens.max()))
	var maps := {}
	for r in rows:
		maps[String(r.get("map", ""))] = true
	check(maps.size() >= 2, "Kartenrotation während des Laufs", str(maps.keys()))


func _write_outputs(minutes: float, joins: int) -> void:
	var keys := ["t", "static_mb", "objects", "nodes", "orphans", "resources", "peers", "players", "soldiers", "gen",
		"corpses", "decals", "auth_live", "auth_pending", "auth_drop", "chat", "feed", "rejects", "map", "round", "piles", "logs"]
	var f := FileAccess.open("res://test_output/soak_memstat_%s.csv" % tag, FileAccess.WRITE)
	if f:
		f.store_line(",".join(keys))
		for r in mem_rows:
			f.store_line(",".join(keys.map(func(k): return String(r.get(k, "")))))
	var s := FileAccess.open("res://test_output/soak_summary_%s.txt" % tag, FileAccess.WRITE)
	if s:
		s.store_string("Dauer %.1f min, Zyklen %d %s, MEMSTAT %d, Fehlerzähler %s\n" % [minutes, joins, str(cycles), mem_rows.size(), str(err_counts)])
		if not mem_rows.is_empty():
			s.store_string("erste: %s\nletzte: %s\n" % [str(mem_rows[0]), str(mem_rows[mem_rows.size() - 1])])
	print("SOAK-ERGEBNIS: %.1f min, %d Zyklen %s, %d MEMSTAT, Fehler %s" % [minutes, joins, str(cycles), mem_rows.size(), str(err_counts)])


func _end() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_finish()
