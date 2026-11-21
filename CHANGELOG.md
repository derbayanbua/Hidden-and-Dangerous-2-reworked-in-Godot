# Changelog



## 0.11.9 (21.11.2026)

**DE**
- **AFRICA2 – Fahrspur sichtbar:** Die hochskalierten Sand-/Spurtexturen hatten die Struktur weggeglättet (Reifenspuren der
  Strecke kaum erkennbar). Die Texturprüfung lehnt jetzt KI-Fassungen mit starkem Kontrastverlust ab; das Spiel nimmt dafür
  die Originaltextur (betrifft auch andere Karten mit demselben Fehler).
- **AFRICA2 – angreifende Flugzeuge:** Wenderate im Anflug wie im Original 0,4 rad/s statt geschätzter 0,9 rad/s – die
  Bf 109 drehen langsamer und greifen deutlich seltener an.
- **AFRICA2 – Leichen/Gegnerbestand:** `HUMAN_Kill` tötet wie im Original sofort (vorher Angriffsauftrag); die fünf
  Leichen am Lager standen dadurch als lebende Gegner herum. Alle 32 Figuren aus den Originaldaten sind vorhanden.
- **AFRICA2 – Gegner nach der ersten Kurve:** Gegner sahen einen Trupp im Fahrzeug nie, weil die eigene Karosserie des
  Ziels jeden Sichtstrahl verdeckte. Jetzt erkennen sie Jeep-/Lkw-Besatzungen; das MG-Nest besetzt bei Alarm das MG 42
  und schießt wie im Originalskript.
- **Bordwaffen im Trupp:** Auch am Bordwaffensitz gilt „Feuer halten bis zum ersten Befehl“; nach der Freigabe (z. B. Taste K)
  feuert der Kamerad vom Sitz. Die Freigabe bleibt beim Ein- und Umsteigen erhalten (Test ergänzt).
- **Flak 38 auf dem Opel Blitz:** Die Rohrachse wurde aus dem Versatz des Rohr-Frames berechnet und zeigte rund 45° nach
  unten. Das Geschütz lief deshalb in den Höhenanschlag, und die Schüsse verließen die Mündung neben dem Rohr. Jetzt folgt
  die Achse dem Mündungspunkt (SHDUM) des Originalmodells; Rohr, Visier und Schuss stimmen überein. Der neue Test
  `test_mounted_guns` prüft alle Bordwaffen auf Fahrzeugen aller Karten: Befestigung, Mündung, Richten und Treffer auf ein
  stehendes Ziel.
- **Scharfschütze trifft wieder (Einzel- und Mehrspieler):** Der Original-Rückstoß wurde bisher auf jede Kugel gerechnet.
  Im Original verstellt er nach dem Schuss nur die Blickrichtung; die Kugel fliegt mit der normalen Streuung dorthin, wohin
  das Absehen zeigt. Mit Zielfernrohr wich jede Kugel bisher bis etwa 2° nach oben ab, ab 50 m ging fast jeder Schuss
  vorbei. Gemessen mit zwei Spielprozessen und der Klasse Scharfschütze auf 20–150 m: vorher 10 von 96 Treffern, jetzt
  93 von 96 (Rumpf angezielt, stehend/hockend/liegend). Der alte Stand ist mit `--recoil_bullet=1` abrufbar.
- **Mehrspieler – Verzugsausgleich:** Der Server prüft Schüsse von Clients jetzt gegen die Lage, die der Schütze gesehen hat
  (Ping + Darstellungsverzögerung, höchstens 350 ms). Vorher zielte man online auf eine bewegte Figur, die beim Server schon
  weiter war. Gemessen bei 120 ms Ping und einem quer laufenden Ziel: vorher 1 von 8 Treffern bestätigt, jetzt 5 von 8.
  Neuer Test `test_mp_sniper` (Host und Client, dediziert mit künstlichem Verzug als `test_mp_sniper_online`).

**EN**
- **AFRICA2 – visible track:** The upscaled sand/track textures had smoothed away their detail (the route's tyre tracks were
  barely visible). The texture check now rejects AI versions with strong contrast loss; the game falls back to the original
  texture (also fixes other maps with the same defect).
- **AFRICA2 – attacking aircraft:** Turn rate on approach is now 0.4 rad/s as in the original instead of an estimated
  0.9 rad/s – the Bf 109s turn more slowly and attack much less often.
- **AFRICA2 – corpses/enemy roster:** `HUMAN_Kill` now kills instantly as in the original (previously an attack order); the
  five corpses at the camp were standing around as live enemies. All 32 figures from the original data are present.
- **AFRICA2 – enemies after the first bend:** Enemies never saw a squad riding in a vehicle because the target's own body
  blocked every line of sight. They now detect jeep/truck crews; the MG nest mans the MG 42 on alarm and fires as in the
  original script.
- **Vehicle guns in the squad:** "Hold fire until the first order" also applies on a vehicle weapon seat; once released
  (e.g. key K) the squad mate fires from the seat. The release is kept when boarding or switching seats (test added).
- **Flak 38 on the Opel Blitz:** The bore axis was taken from the offset of the barrel frame and pointed about 45° downwards.
  The gun ran into its elevation stop and shots left the muzzle away from the barrel. The axis now follows the muzzle
  point (SHDUM) of the original model, so barrel, sight and shot match. The new test `test_mounted_guns` checks every
  vehicle-mounted gun on all maps: mounting, muzzle, aiming and a hit on a stationary target.
- **Sniper hits again (single and multiplayer):** The original recoil was applied to every bullet. In the original it only
  shifts the view direction after the shot; the bullet flies with the normal spread to where the reticle points. With a
  scope every bullet used to deviate up to about 2° upwards, so almost every shot beyond 50 m missed. Measured with two game
  processes and the sniper class at 20–150 m: before 10 of 96 hits, now 93 of 96 (aiming at the torso, standing/crouched/
  prone). The old behaviour is available with `--recoil_bullet=1`.
- **Multiplayer – lag compensation:** The server now checks client shots against the position the shooter actually saw
  (ping + display delay, at most 350 ms). Before, online players aimed at a moving figure that was already further along on
  the server. Measured at 120 ms ping with a target walking sideways: before 1 of 8 hits confirmed, now 5 of 8.
  New test `test_mp_sniper` (host and client; dedicated with simulated delay as `test_mp_sniper_online`).



## 0.11.8 (19.11.2026)

**DE**
- **Schießstand als Testkarte im Einzelspieler:** „Schießstand (Test)“ steht unter EINZELSPIELER › EINZELMISSION bei den
  Übungseinsätzen und startet direkt mit Briefing und Übungsausrüstung; Kampagnenstand bleibt unberührt.
- **Missionsliste mit Bildlauf:** lange Einzelmissions-/Kampagnenlisten laufen nicht mehr aus dem Bild, sondern lassen sich
  scrollen; die gewählte Mission wird sichtbar gehalten.

**EN**
- **Shooting range as a test map in single player:** "Schießstand (Test)" is listed under SINGLE PLAYER › SINGLE MISSION
  with the practice missions and starts directly with briefing and practice equipment; campaign progress is untouched.
- **Scrollable mission list:** long single-mission/campaign lists no longer run off the screen but scroll; the selected
  mission is kept visible.



## 0.11.7 (18.11.2026)

**DE**
- **Testkarte Bavaria:** Panorama-Ring rund um die Karte, Dorf und Werk in der Ferne, Blickschneise, Stollen ausgebaut,
  Leitern nur noch per Benutzen-Taste; Treibstofftanks in Afrika 1 mit Kollision.
- **Rückstoß/KI-Zielfehler nach Original-Waffenart:** Waffenart und -klasse kommen jetzt aus der Original-Gegenstandstabelle
  (belegt): Zielfernrohrgewehre haben den vollen Original-Rückstoß (Faktor 1,0 statt 0,4), die Doppelflinte zählt als
  Art 3 (0,3); KI-Zielfehler: MGs/BAR wie Original Klasse 4, MP 44 ohne MP-Zuschlag.
- **Skript-Scheinfeuer (HUMAN_IllFire) wie im Original:** diese Geschosse fliegen durch Figuren, Fahrzeuge und Objekte und
  treffen nur die Umgebung (Inszenierungen in Alpen, Arktis, Normandie, Tschechien, Afrika).
- **Tag-/Nachtwechsel je Spielmodus:** neue Server-Regel „T/N MODI“ (Konsole/Config `daynightmodes`, Bitmaske:
  1 Deathmatch, 2 Team-Deathmatch, 4 Besetzung, 8 HD2-Aufgaben, 16 Kooperativ; Standard 31 = alle, also wie bisher).
  Wirkt zusammen mit `daynight` auf allen MP-Karten; im LAN-/Internet-Servermenü, im Konfigurationsmenü des dedizierten
  Servers und in der SPIEL-INFO. Protokoll unverändert (DH2-LAN-6).
- **Lichtstimmung je Grafikstufe geprüft:** Vergleichsbilder aller fünf Stufen (Himmel/Horizont/Boden, mittlere
  Helligkeit und Farbe gegen Stufe Hoch) für mehrere Karten; Normandy 3: Schwimmtest im Fluss ergänzt. Behoben:
  Originalkarten waren auf Ultra/4K Ultra 7–58 % dunkler als auf Hoch (globale Beleuchtung SDFGI verdrängte das
  Umgebungslicht); dort bleibt SDFGI jetzt aus, Abweichung höchstens 6 %.
- **Online-Rangliste:** neue Spalte „BOTS“ mit den Abschüssen von KI-Soldaten; „KILLS“ zählt nur Spielerabschüsse.
- **Einschusslöcher besser erkennbar:** größer (12 cm statt 6 cm), mit fast schwarzem Kern, dunklem ausgefranstem Rand
  und weichem Schmauchhof, zufällig gedreht; volle Deckkraft auf Schnee, Holz, Metall und Stein, ohne Ausblenden auf
  Entfernung (auch im Zielfernrohr). Bis zu 160 Löcher/Brandflecken gleichzeitig, die ältesten verschwinden. Gilt für
  eigene, KI- und Netzschüsse (Einzel- und Mehrspieler).
- **Minikarte als Server-Option:** neue Regel „MINIKARTE“ im LAN-/Internet-Servermenü, Konsole/Config `minimap 0/1`,
  Standard aus. Eingeschaltet erscheint die Minikarte links unten direkt über den Spielersymbolen und ersetzt den Kompass;
  ausgeschaltet bleibt der Kompass wie bisher. Die Regel wird mit den übrigen Serverregeln übertragen (Protokoll
  unverändert, ältere Clients bleiben kompatibel) und in der SPIEL-INFO angezeigt.
- **Große Karte (M) mit Markierungen wie die Minikarte:** eigene Position mit Blickrichtung, Verbündete (nur in
  Teammodi) und kurz (2,5 s) die Lage schießender Gegner – Schalldämpferwaffen bleiben verborgen; Zuschauer sehen die
  Sicht des beobachteten Spielers, mit freier Kamera keine Marken. Im Mehrspieler öffnet M jetzt auch in Deathmatch
  und Team-Deathmatch eine Übersichtskarte (mit Spawnzonen wie bisher die Spawnzonen-Karte). Die taktische Karte im
  Einzelspieler zeigt den aktiven Soldaten als Pfeil und gehörte oder gesehene schießende Gegner auf dieselbe Weise.
  Unabhängig von der Server-Regel „MINIKARTE“; Protokoll unverändert.
- **Schießstand:** neue Übungskarte „Schießstand (Test)“ mit Bahnen auf 3, 7, 10, 25, 50, 100, 200 und 300 m. Auf jeder
  Bahn steht ein unverwundbarer Dummy (echte Soldatenfigur mit allen Trefferzonen), Treffer werden nur protokolliert.
  Dazu eine optionale Prüfreihe für Balance-Änderungen: alle Handwaffen bis 50 m, Gewehre/Karabiner und
  Zielfernrohrwaffen bis 300 m, jede Körperzone, stehend/hockend/liegend, gezoomt und ungezoomt; Bericht mit Zone,
  Abweichung in cm und Schaden.
- **Zielfernrohr eingeschossen:** Schüsse durch das Zielfernrohr treffen im Einzelspieler jetzt die Zone unter dem
  Absehen (vorher fiel die Kugel auf 100/200/300 m rund 10/39/86 cm darunter; ein Kopfschuss auf 300 m traf das Bein
  oder ging vorbei). Neue Einstellung `scope_zero` (Standard an, aus = bisheriges Verhalten). Im Mehrspieler gibt es
  keinen Zielfernrohr-Ausgleich – die Kugel fällt dort realistisch (für Client, Host und Server-KI gleich).
- **Schadensabfall der Gewehre realistischer:** Gewehre, Karabiner, Zielfernrohrwaffen, MGs und StG 44 verlieren auf
  Entfernung nur noch halb so schnell Schaden wie in der Originaltabelle und behalten mindestens 60 % ihres
  Grundschadens. Ein Kopftreffer mit dem Gewehr bleibt auf 300 m tödlich (z. B. Lee-Enfield 125 statt 2,5), ein
  Rumpftreffer wirkt deutlich (25 statt 0,5). Pistolen und MPs fallen weiter stark ab wie im Original. Einzel- und
  Mehrspieler gleich.
- **Streuung nach Haltung festgelegt:** stehend streuen Waffen etwas mehr als hockend, hockend mehr als liegend (Faktor
  1 / 0,75 / 0,5; das Original kennt keinen Haltungsfaktor) – für Spieler und KI gleich, im Einzel- und Mehrspieler; der
  Schießstand prüft die Reihenfolge.
- **Dedizierter Server hängt nicht mehr:** KI-Soldaten liefen nach einem Karten- oder Rundenwechsel in eine
  Endlosschleife (Wahrnehmung über bereits gelöschte Soldaten), die den Speicher füllte; außerdem blieb der Server stehen,
  wenn zwei Kartenwechsel kurz nacheinander kamen (Rundenende und `nextmap`/Abstimmung). Beides behoben; Langlauf über
  2 Stunden ohne Hänger und ohne Speicheranstieg über die Runden (`docs/status/b0117_server_soak.md`).
- **Dedizierter Server im Langlauf stabil:** Rauswurf, Ablehnung und Gast-Zeitlimit trennen einen Spieler jetzt nur
  noch einmal und nur, solange er verbunden ist (vorher eigene Verzögerungen mit `disconnect_peer`, die nach dem Gehen
  erneut trennten – Fehlerschleife). Beim Verlassen werden alle Spielertabellen des Servers geleert (Generationen,
  Leichenlagen, Lebenspunkte, Respawn-Zeiten, Admin-Fehlversuche), die Anmeldetabellen bei jedem Neustart; Test- und
  Diagnoselisten sind begrenzt. Neue Server-Option `--mem_log_s=<s>` schreibt regelmäßig eine Zeile MEMSTAT
  (Speicher, Objekt-/Knotenzahl, Tabellengrößen). Neuer Langlauftest mit wiederholtem Beitreten, Verlassen, Rauswurf
  und Kartenwechsel (kurz in `-Full`, über 2 Stunden mit `-Only test_dedicated_soak_long`). Protokoll unverändert.
- **Soldatenprofil beim Masterserver:** Der Client lädt nach der Anmeldung sein Soldatenprofil hoch (Name, Figur und
  Klasse aus dem SPIELER-SETUP; `PUT /v1/accounts/me/soldiers/{id}`, signiert mit dem Kontoschlüssel, Versionsstand
  `rev`) und aktualisiert es, sobald Klasse oder Figur geändert werden. Vorher wurde nie ein Profil gesendet. Anmeldung
  und Profil-Upload erscheinen im Log (`MASTER: Login ok`, `MASTER: Soldatenprofil gespeichert`).
- **Abschüsse in der Rangliste:** geprüft – der Rundenbericht meldet Abschüsse menschlicher Gegner als `kills` und
  Abschüsse von KI-Soldaten getrennt als `ai_kills` (wie im Master-Protokoll festgelegt). Wer nur KI-Soldaten
  ausschaltet, hat daher `kills` 0; die KI-Abschüsse zählen in `ai_kills` und in die Erfahrung.
- **KI auf Treppen und Bot-Festhängen:** Treppen der Karten werden jetzt automatisch erkannt und als begehbare Fläche ins
  Navigationsnetz übernommen (nur für die Wegsuche, keine neue Kollision). Viele Obergeschosse, Podeste und Dächer sind
  damit für KI-Soldaten erreichbar (Einzel- und Mehrspieler). KI-Soldaten im Mehrspieler bleiben nicht mehr dauerhaft
  hängen: ein misslungener Kletterversuch setzt die Abhilfe nicht mehr zurück, der Notversatz sucht freie Punkte in der
  Nähe, danach beginnt die Abhilfe von vorn (vorher bis über 2 Minuten am selben Fleck).
- **Navigationsnetz am Treppenfuß:** das Netz lag vor vielen Treppen 0,5–0,6 m über dem Boden, KI-Wege endeten dort.
  Die Höhe wird jetzt nur an den Treppenfüßen auf den Boden korrigiert (kein feineres Netz für die ganze Karte, gleiche
  Polygonzahl und Wegsuch-Leistung).
- **KI-Soldaten laufen menschlicher:** Wege führen nicht mehr stur auf der kürzesten Linie. Je Karte entstehen
  Wegpunkte aus Zonen, Spawnplätzen, Aufgabenorten und dem Navigationsnetz; Bots nehmen bei geringem Umweg oft einen
  davon mit und laufen leicht versetzt, so dass mehrere Bots verschiedene Wege zum selben Ziel nehmen. Bei bekannter
  Feindlage bleibt die Deckungsroute. Nur Server, Protokoll unverändert.
- **Notversatz festhängender Bots sicherer:** der Versatz geht höchstens 4 m zur Seite und 2,5 m in der Höhe, nur auf
  echten Boden und nur dorthin, von wo das Ziel weiter erreichbar ist (vorher konnte ein Bot durch die Welt fallen oder
  in eine Senke ohne Weg gesetzt werden). Seitlich versetzte Laufpunkte müssen direkt über das Netz erreichbar sein.
- **Treppen und Leitern für KI-Soldaten:** zwei Original-Treppen, an denen Soldaten hängen blieben (CZECH1, NORMANDY
  Mehrspieler), haben jetzt eine unsichtbare Ersatzrampe wie die Originaltreppen. Mehrteilige Leitern an Türmen werden
  von der KI am Stück geklettert. KI-Soldaten, die zwischen zwei Punkten hin und her pendeln, planen neu oder werden ein
  Stück weitergesetzt.
- **Online wie LAN:** Eine Beförderung über den Masterserver (gewertete Online-Runde) wird jetzt wie im LAN auch den
  übrigen Spielern gemeldet („… wurde befördert zu …“), nicht nur dem Beförderten. Die Rang-Anzeige nutzt dieselbe
  Bedingung wie Rangmeldung und Rundenbericht (Master-Dienstgrad nur auf offiziellen Internet-Servern, sonst
  Original-Rang). Spawn-Schutz und die übrigen Mehrspielerregeln gelten im LAN und online gleich (geprüft).
  Protokoll unverändert.
- **Tastenbelegung geprüft:** beide Standardbelegungen ohne Doppelbelegung, Umbelegen einer unbelegten Aktion auf eine
  belegte Taste lässt keine Doppelbelegung zurück, Speichern/Laden/Zurücksetzen vollständig getestet.
- **LAN-Menü im Original-Look:** LAN-Serverliste und SERVER ERSTELLEN erscheinen ausschließlich als Original-Bildschirme
  (Grafiken zur Laufzeit aus der eigenen Installation); neuer Prüflauf mit Kontrollbildern.
- **Treffsicherheit der Gegner wie im Original (Einzelspieler-Originaleinsätze):** Der Zielfehler der KI folgt jetzt der
  Original-Formel: seitliche Abweichung abhängig vom Wert „Schießen“, der eigenen Haltung und Bewegung, der Zeit seit
  der Zielaufnahme und der Waffenart, auf „leicht“ doppelt und auf „normal“ 1,5-fach so groß. Granaten der KI landen je
  nach „Schießen“ bis zu einige Meter neben dem Ziel. Die bisherige eigene Fehlerformel gilt nur noch für Übungseinsätze
  und Mehrspieler-Bots (`--orig_aim=0` schaltet zurück).
- **Lippensynchronität:** geprüft und abgeschlossen; Kontrollbilder auch aus einer Zwischensequenz in Nordafrika.
- **Afrika 6 „Raubvögel“ (Bordschützen in der Ju 88) überarbeitet:** jeder Sitz ist jetzt ein eigener MG-Stand nach dem
  Originalmodell – das MG schwenkt sichtbar innerhalb der Original-Grenzen, die Ego-Kamera sitzt am Original-Kamerapunkt
  des MG und blickt in Laufrichtung, die 3. Person nutzt den Original-Kamerapunkt des Sitzes, der Blick bleibt beim
  Kurvenflug am MG. Geschosse starten an der Mündung, treffen die eigene Ju 88 nicht mehr und das MG zieht beim Dauerfeuer
  nicht mehr vom Ziel weg (vorher trafen nur wenige Schüsse, Abschüsse waren kaum möglich). KI-Kameraden schießen selbst
  auf Jäger im Schwenkbereich (ihre Treffer zählen wie im Original nur begrenzt). Jäger zeigen beim Angriff Leuchtspuren,
  stürzen in Flugrichtung ab; die Ju 88 stürzt bei 0 Lebenspunkten ab, bevor die Mission endet.
- **Ju-88-Schützen sitzen in der Kanzel:** Die Bordschützen sitzen jetzt (Sitzhaltung, Arme unten) mit den Augen auf
  Höhe des Ringvisiers; vorher ragten Kopf und Arme des hockenden Schützen in der 3. Person aus der Kanzel.
- **Blutlachen auf Gras erkennbar:** Lachen reichen sichtbar unter der Leiche hervor und sind kräftiger rot (vorher
  dunkelrot auf dunklem Gras fast unsichtbar). Blutflecken werden nicht mehr als gestreckte Streifen auf Wandfüße und
  Kanten quer zur Fläche projiziert.
- **Waffen toter Soldaten liegen flach:** Nach dem Zur-Ruhe-Kommen der Leiche liegt das Gewehr neben der Hand auf dem
  Boden, statt senkrecht aus dem Körper zu ragen (Einzel- und Mehrspieler, auch bei späterem Beitritt).
- **Schwimmen ohne Waffe:** Beim Schwimmen sind Hand- und Rückenwaffe ausgeblendet – vorher ragte nur die Waffe aus dem
  Wasser. Gilt auch für Mitspieler im Mehrspieler.
- **Kameraden warten auf den ersten Befehl:** In Einzelspieler-Originalmissionen und Übungseinsätzen halten die
  KI-Kameraden zu Beginn ihre Position mit „Feuer halten“ und schießen bis zum ersten Befehl auch dann nicht, wenn sie
  Gegner sehen oder beschossen werden. Jeder Befehl (Folgen, Halten, Feuer frei, Angriff, Aufgaben aus dem Befehlsmenü)
  hebt das auf. Haltung wie der gesteuerte Soldat. Bisheriges Verhalten (Halten mit Feuer frei) per Startoption
  `--squad_start=legacy`.

**EN**
- **Test map Bavaria:** panorama ring around the map, village and works in the distance, sight corridor, tunnel extended,
  ladders only via the use key; fuel tanks in Africa 1 now have collision.
- **Squad mates wait for the first order:** In single-player original missions and practice missions the AI squad mates
  start by holding their position with “Hold fire” and do not shoot before the first order, even when they see enemies
  or come under fire. Any order (follow, hold, fire at will, attack, tasks from the command menu) lifts this. Stance
  copies the controlled soldier. Previous behaviour (hold with fire at will) via the start option `--squad_start=legacy`.
- **Africa 6 “Birds of Prey” (Ju 88 gunners) reworked:** every seat is now its own gun mount based on the original model –
  the MG visibly traverses within the original limits, the first-person camera sits at the MG's original camera point
  and looks down the barrel, third person uses the seat's original camera point, and the view stays on the gun while the
  aircraft turns. Bullets leave the muzzle, no longer hit the own Ju 88, and sustained fire no longer pulls the gun off
  target (before, only a few rounds hit and kills were hardly possible). AI gunners fire at fighters within their arc
  (their hits count only to a limited extent, as in the original). Fighters show tracers while attacking and crash in
  their direction of flight; the Ju 88 crashes at 0 hit points before the mission ends.
- **Recoil/AI aim error by original weapon type:** weapon type and class now come from the original item table
  (verified): scoped rifles get the full original recoil (factor 1.0 instead of 0.4), the double-barrel shotgun counts as
  type 3 (0.3); AI aim error: MGs/BAR use original class 4, MP 44 without the SMG penalty.
- **Scripted fake fire (HUMAN_IllFire) as in the original:** these bullets pass through characters, vehicles and objects and
  only hit the environment (staged scenes in the Alps, Arctic, Normandy, Czech and Africa missions).
- **Day/night cycle per game mode:** new server rule "T/N MODI" (console/config `daynightmodes`, bit mask:
  1 deathmatch, 2 team deathmatch, 4 occupation, 8 HD2 objectives, 16 cooperative; default 31 = all, i.e. unchanged).
  Works together with `daynight` on all MP maps; available in the LAN/Internet server menu, the dedicated server
  configuration and GAME INFO. Protocol unchanged (DH2-LAN-6).
- **Lighting mood per graphics level checked:** comparison images of all five levels (sky/horizon/ground, mean
  brightness and colour against level High) for several maps; Normandy 3: swimming test in the river added. Fixed:
  original maps were 7–58 % darker on Ultra/4K Ultra than on High (SDFGI global illumination replaced the ambient
  light); SDFGI now stays off there, deviation at most 6 %.
- **Online leaderboard:** new "BOTS" column with kills of AI soldiers; "KILLS" counts player kills only.
- **Bullet holes easier to see:** larger (12 cm instead of 6 cm), with a near-black core, dark ragged rim and a soft
  soot halo, randomly rotated; fully opaque on snow, wood, metal and stone and no fading with distance (also through
  scopes). Up to 160 holes/scorch marks at once, oldest are removed. Applies to own, AI and network shots (single and
  multiplayer).
- **Minimap as a server option:** new rule "MINIKARTE" in the LAN/Internet server menu, console/config `minimap 0/1`,
  off by default. When enabled, the minimap is shown bottom-left directly above the player icons and replaces the
  compass; when disabled the compass stays as before. The rule is sent with the other server rules (protocol unchanged,
  older clients stay compatible) and shown in GAME INFO.
- **Large map (M) with the same markers as the minimap:** your own position with view direction, allies (team modes
  only) and, briefly (2.5 s), the position of enemies who fire – silenced weapons stay hidden; spectators see the view
  of the observed player, free camera shows no markers. In multiplayer, M now also opens an overview map in deathmatch
  and team deathmatch (with spawn zones it is the spawn zone map as before). The single player tactical map shows the
  active soldier as an arrow and heard or seen firing enemies the same way. Independent of the server rule
  "MINIKARTE"; protocol unchanged.
- **Shooting range:** new practice map "Schießstand (Test)" with lanes at 3, 7, 10, 25, 50, 100, 200 and 300 m. Each
  lane has an invulnerable dummy (real soldier figure with all hit zones); hits are only logged. Plus an optional test
  series for balance changes: all small arms up to 50 m, rifles/carbines and scoped weapons up to 300 m, every body
  zone, standing/crouching/prone, zoomed and unzoomed; report with zone, offset in cm and damage.
- **Zeroed scopes:** shots through a scope now hit the zone under the reticle in single player (before, the bullet
  dropped about 10/39/86 cm below it at 100/200/300 m; a head shot at 300 m hit the leg or missed). New setting
  `scope_zero` (on by default, off = previous behaviour). In multiplayer there is no scope compensation – the bullet
  drops realistically there (same for client, host and server bots).
- **Rifle damage falloff more realistic:** rifles, carbines, scoped rifles, machine guns and the StG 44 now lose damage
  over distance only half as fast as in the original table and keep at least 60 % of their base damage. A head shot
  with a rifle stays lethal at 300 m (e.g. Lee-Enfield 125 instead of 2.5), a torso hit clearly hurts (25 instead of
  0.5). Pistols and SMGs keep the original strong falloff. Same in single and multiplayer.
- **Spread by stance confirmed:** weapons spread a little more standing than crouching, and more crouching than prone
  (factor 1 / 0.75 / 0.5; the original has no stance factor) – same for players and AI, in single and multiplayer; the
  shooting range checks the order.
- **Dedicated server no longer hangs:** after a map or round change, bots ran into an endless loop (perception over
  already deleted soldiers) that filled memory; the server also froze when two map changes came shortly after each other
  (round end and `nextmap`/vote). Both fixed; soak run over 2 hours without hangs and without memory growth across rounds
  (`docs/status/b0117_server_soak.md`).
- **Dedicated server stable in long runs:** kicks, rejections and the guest timeout now drop a player only once and
  only while still connected (before, separate delayed `disconnect_peer` calls dropped again after the player had left –
  error loop). Leaving clears all per-player server tables (generations, corpse poses, health, respawn times, admin
  login failures), the auth tables are cleared on every restart, and test/diagnostic lists are bounded. New server
  option `--mem_log_s=<s>` prints a periodic MEMSTAT line (memory, object/node count, table sizes). New soak test with
  repeated join, leave, kick and map change (short in `-Full`, over 2 hours with `-Only test_dedicated_soak_long`).
  Protocol unchanged.
- **Soldier profile on the master server:** after logging in, the client uploads its soldier profile (name, figure
  and class from PLAYER SETUP; `PUT /v1/accounts/me/soldiers/{id}`, signed with the account key, revision `rev`) and
  updates it whenever class or figure change. Before, no profile was ever sent. Login and profile upload are logged
  (`MASTER: Login ok`, `MASTER: soldier profile saved`).
- **Kills in the ranking:** checked – the match report sends kills of human opponents as `kills` and kills of AI
  soldiers separately as `ai_kills` (as defined by the master protocol). Players who only kill AI soldiers therefore
  have `kills` 0; those kills count in `ai_kills` and towards experience.
- **AI on stairs and bot stuck fixes:** map stairs are now detected automatically and added to the navigation mesh as
  walkable surface (path finding only, no new collision). Many upper floors, landings and roofs are now reachable for AI
  soldiers (single and multiplayer). Multiplayer AI soldiers no longer stay stuck indefinitely: a failed climb attempt no
  longer resets the recovery, the emergency nudge searches free points nearby, and the recovery then starts over
  (before, bots could stand on the same spot for over 2 minutes).
- **Safer emergency nudge for stuck bots:** the nudge moves at most 4 m sideways and 2.5 m vertically, only onto real
  ground and only to spots from which the goal stays reachable (before, a bot could fall through the world or be put into
  a dip without a path). Lateral route offsets must be directly reachable over the navigation mesh.
- **Navigation mesh at stair feet:** in front of many stairs the mesh was 0.5–0.6 m above the ground and AI paths ended
  there. The height is now corrected to the ground only at stair feet (no finer mesh for the whole map, same polygon
  count and path search performance).
- **More human bot movement:** routes no longer follow the shortest line rigidly. Per map, waypoints are built from
  zones, spawn slots, objective locations and the navigation mesh; with a small detour bots often pass one of them and
  walk slightly offset, so several bots take different routes to the same goal. With a known enemy position the cover
  route stays. Server only, protocol unchanged.
- **Stairs and ladders for AI soldiers:** two original stairs where soldiers got stuck (CZECH1, NORMANDY multiplayer)
  now have an invisible replacement ramp like the original stairs. Multi-part ladders on towers are climbed by the AI
  in one go. AI soldiers oscillating between two points re-plan or are moved a short distance onward.
- **Online same as LAN:** a promotion from the master server (ranked online round) is now announced to the other
  players as well ("… was promoted to …"), like in LAN, not only to the promoted player. The rank display uses the same
  condition as the rank message and the match report (master rank only on official internet servers, otherwise the
  original rank). Spawn protection and the other multiplayer rules are the same in LAN and online (checked). Protocol
  unchanged.
- **Key bindings checked:** both default layouts have no duplicate keys, rebinding an unbound action to a used key no
  longer leaves a duplicate, saving/loading/reset fully tested.
- **LAN menu in the original look:** the LAN server list and CREATE SERVER are shown only as original screens (graphics
  loaded at runtime from your own installation); new check run with control images.
- **Enemy accuracy as in the original (single-player original missions):** AI aiming error now follows the original
  formula: sideways deviation depending on the "Shooting" value, own stance and movement, time since acquiring the
  target and weapon type; doubled on "easy" and ×1.5 on "normal". AI grenades land up to a few metres off target
  depending on "Shooting". The previous custom error formula remains only for practice missions and multiplayer bots
  (`--orig_aim=0` switches back).
- **Lip sync:** checked and completed; control images also from a cutscene in North Africa.
- **Ju 88 gunners sit inside the turret:** the gunners now sit (seated pose, arms down) with their eyes at the ring
  sight; previously head and arms of the crouching gunner stuck out of the canopy in third person.
- **Blood pools visible on grass:** pools now extend visibly from under the corpse and are a stronger red (previously
  dark red on dark grass was nearly invisible). Blood splats are no longer projected as stretched streaks onto wall bases
  and edges perpendicular to them.
- **Dead soldiers' weapons lie flat:** once the corpse comes to rest, the rifle lies on the ground next to the hand
  instead of sticking straight up out of the body (single and multiplayer, also for late joiners).
- **Swimming without a weapon:** hand and back weapons are hidden while swimming – previously only the weapon stuck
  out of the water. Also applies to other players in multiplayer.

## 0.11.6 (15.11.2026)

**DE**
- **Fallschaden wie im Original:** Gemessen wird vom höchsten Punkt des Flugs bis zur Landung. Bis 3 m kein Schaden,
  darüber steigt er linear (24 Lebenspunkte je Meter) bis höchstens 100; eine 100-LP-Figur stirbt ab etwa 7,2 m.
  Gilt im Einzelspieler für Spieler, Trupp und Gegner; Leitern, Klettern, Treppen und Rampen bleiben ohne Schaden.
  Im Mehrspieler (Regel Fallschaden) entscheidet der Server, der Kill-Feed nennt den Sturz als Ursache.
- **Zielen und Treffen:** In der 1. Person startet der Schuss wie im Original an der Kamera (Visierlinie) statt am Kopf;
  das Geschoss trifft dort, wo Bildmitte, Kimme/Korn oder Absehen hinzeigen (Geschossabfall wie im Original, mit
  „Präzises Zielen“ ausgeglichen). Pistolen-Visierung beim Zielen korrigiert: Korn liegt auf der Bildmitte, Lauf
  parallel zur Blickrichtung (vorher bei P08, Enfield .38, Typ 94 und Tokarew weit daneben, Colt schräg). Neue
  Testreihe für alle Visier- und Zielfernrohrwaffen in Einzel- und Mehrspieler.
- **Schrotflinte (Side by Side):** trifft ungezoomt wieder; wie im Original ein Geschoss mit der geringen Originalstreuung
  ohne zusätzliche Hüftstreuung (vorher bis 3° daneben).
- **Eigene Beine in der 1. Person:** Beim Blick nach unten sieht man nicht mehr durch die Oberschenkel auf den Boden
  (die abgeschnittene Beinkopie wird beidseitig gezeichnet).
- **Dedizierter Server – Kartenrotation über mehrere Spielstile:** Regeln, die noch dem Standard des vorherigen Stils
  entsprechen, folgen jetzt dem Stil der neuen Karte (z. B. Respawn auf Deathmatch-Karten, auch wenn die
  Konfiguration „style objectives“ enthält); vom Admin abweichend gesetzte Werte bleiben erhalten. Vorher konnten
  Spieler und KI-Soldaten auf solchen Servern nur zuschauen bzw. kamen nach dem Tod nicht zurück. Reiner Server-Fix,
  ältere Clients bleiben kompatibel. Das Server-Log nennt jetzt den Grund, warum ein Spieler nicht gespawnt wird.
- **KI-Wege ARCTIC2/NORWAY:** In den Treppenhäusern von ARCTIC2 fanden die Treppen-Verbindungen der KI keinen Anschluss
  an die Podeste – die Startinsel von Commando1 war für die KI abgetrennt. Verbindungen werden jetzt an das nächste
  Podest angeheftet und Rampenenden angebunden. Die Stahltreppen auf der Tirpitz (NORWAY) sind über reine
  Navigationsflächen (ohne Kollision) im Netz; die KI erreicht die oberen Plattformen.
- **Erfüllbarkeitslöser:** Strategie „leise“ schaltet Gegner, deren Skript selbst ein Ziel scheitern lässt, sofort aus
  (ARCTIC4: Offizier am U-Boot); zerstörbare Objekte, auf denen der Trupp steht, werden nicht mehr gesprengt.
- **Türteile und Türrahmen (ARCTIC2 und weitere Karten):** Lage-Ergänzungen der Originalszene (scene2.bin) für
  Modellteile werden jetzt übernommen: Türfenster mit Gitter hängen am beweglichen Türflügel und drehen mit (vorher
  blieb das Gitter im Rahmen stehen), falsch gedrehte Türzargen stehen wieder in ihrer Öffnung. Türabgleich im
  Mehrspieler unverändert.
- **Visiersicht im Fahrzeug im Breitbild:** Richtschützen- und Bordwaffensitze (Panzer, Halbketten …) zeigen das
  Sichtfeld wie im Original als 4:3-Ausschnitt; links und rechts (16:9, 16:10, 21:9) bzw. oben und unten (5:4) ist
  das Bild schwarz, statt am Visier vorbei in die Szene zu schauen. Vertikales Sichtfeld wie im Original, Einzel- und
  Mehrspieler gleich.

- **Hüftstreuung wie im Original:** Das Original kennt keinen eigenen Hüftanschlag-Zweig; alle Waffen mit Originalwert
  streuen aus der Hüfte jetzt genauso wie beim Zielen (vorher geschätzte 2,8–4,5°).
- **Leitern:** Einstieg im ganzen Spiel nur noch per Benutzen-Taste (vorher genügte Dagegenlaufen); KI unverändert.
- **Mehrspieler-Minikarte (neu, eigene Ergänzung):** genordete Karte am rechten Bildrand mit eigener Position und
  Blickrichtung; in Team-Spielstilen erscheinen lebende Verbündete in Teamfarbe (im Deathmatch hat niemand Verbündete).
  Gegner sind nur zu sehen, wenn sie schießen: eine Marke an der Schützenlage blendet in 2,5 s aus. Waffen mit
  Schalldämpfer verraten den Schützen nie. Zuschauer sehen die Karte des beobachteten Spielers. Keine Protokolländerung.
- **Bavaria:** Randbüsche ohne schwarzen Kern, Bäume im dichten Wald sauber geerdet; neuer Stollen vom MG42-Haus zum
  Antennenhaus und zum ersten Reihenhaus; nächtlicher Suchscheinwerferturm.
- **Testserver:** Die Startoption für unverwundbare Testspieler wirkt nur noch im Entwicklungs-Binary, nie im Release.
- **README:** Abschnitt „Kein 100 % Vanilla mehr“ gekürzt.
- **Ausblick 0.12:** Werkzeugmenü (Originaldaten-Konvertierung) auch für Linux geplant.

**EN**
- **Falling damage as in the original:** Measured from the highest point of the fall to the landing. No damage up to
  3 m, above that it rises linearly (24 health points per metre) up to a maximum of 100; a 100 HP figure dies from about
  7.2 m. Applies in single player to the player, squad and enemies; ladders, climbing, stairs and ramps cause no damage.
  In multiplayer (falling damage rule) the server decides, and the kill feed names the fall as the cause.
- **Aiming and hitting:** In first person the shot now starts at the camera (line of sight) as in the original instead
  of at the head; the bullet hits where the screen centre, iron sights or reticle point (bullet drop as in the
  original, compensated with "Precise aiming"). Pistol sights when aiming fixed: the front sight sits on the screen
  centre and the barrel is parallel to the view (previously far off for P08, Enfield .38, Type 94 and Tokarev, Colt
  tilted). New test series for all iron-sight and scoped weapons in single and multiplayer.
- **Shotgun (Side by Side):** hits again when firing from the hip; as in the original it fires one projectile with the
  small original spread and no extra hip spread (previously up to 3° off).
- **Own legs in first person:** Looking down no longer shows the ground through the thighs (the cut leg copy is now
  drawn double-sided).
- **Dedicated server – map rotation across several game styles:** Rules that still match the default of the previous
  style now follow the style of the new map (e.g. respawn on deathmatch maps even if the configuration contains
  "style objectives"); values set differently by the admin are kept. Previously players and AI soldiers on such servers
  could only spectate or did not come back after dying. Server-side fix only, older clients stay compatible. The server
  log now states why a player is not spawned.
- **AI paths ARCTIC2/NORWAY:** In the ARCTIC2 stairwells the AI's stair connections found no polygon on the landings, so
  Commando1's starting area was cut off for the AI. Connections are now attached to the nearest landing and ramp ends
  are joined. The steel stairs on the Tirpitz (NORWAY) are part of the navigation mesh via navigation-only surfaces
  (no collision); the AI reaches the upper platforms.
- **Completability solver:** The "quiet" strategy now immediately takes out enemies whose own script fails an objective
  (ARCTIC4: officer at the U-boat); destructible objects the squad is standing on are no longer blown up.
- **Door parts and door frames (ARCTIC2 and other maps):** Placement overrides of the original scene (scene2.bin) for
  model parts are now applied: door windows with grilles are attached to the moving door leaf and swing with it
  (previously the grille stayed in the frame), wrongly rotated door frames stand in their opening again. Multiplayer
  door sync unchanged.
- **Vehicle gunner view on wide screens:** Gunner and vehicle weapon seats (tanks, half-tracks …) show the view as a
  4:3 area as in the original; left and right (16:9, 16:10, 21:9) or top and bottom (5:4) are black instead of
  showing the scene past the sight. Vertical field of view as in the original, same in single and multiplayer.
- **Hip spread as in the original:** The original has no separate hip-fire branch; all weapons with an original value
  now spread from the hip exactly as when aiming (previously estimated 2.8–4.5°).
- **Ladders:** Climbing on is now done with the use key everywhere in the game (previously walking into them was
  enough); AI unchanged.
- **Multiplayer minimap (new, own addition):** north-up map at the right edge of the screen with your own position and
  facing; in team styles living allies appear in their team colour (in deathmatch nobody is an ally). Enemies only show
  up when they fire: a mark at the shooter's position fades out within 2.5 s. Weapons with a suppressor never reveal
  the shooter. Spectators see the map of the player they are watching. No protocol change.
- **Bavaria:** Edge bushes without a black core, trees in the dense forest properly grounded; new tunnel from the MG42
  house to the antenna house and the first terraced house; searchlight tower at night.
- **Test server:** The start option for invulnerable test players now only works in the development binary, never in
  a release.
- **README:** Section "No longer 100 % vanilla" shortened.
- **Outlook 0.12:** Tool menu (original data conversion) planned for Linux as well.


## 0.11.5 (14.11.2026)

**DE**
- **Stabilität dedizierter Server:** Endlosschleife der Bot-Navigation (Deckungssuche) behoben, doppeltes Trennen
  bereits getrennter Spieler und freigegebene Rückruf-Funktionen abgesichert; Langlauf mit 24 Bots ohne Hänger und ohne
  Speicherzuwachs.
- **Masterserver nicht erreichbar:** Das Spiel zeigt einen Hinweis (auch bei Serverfehlern/Überlastung), dass der
  Beitritt per IP trotzdem funktioniert (alle Sprachen).
- **Rangliste (online):** Die Profil-Anmeldung am Masterserver fand nie statt – behoben, dadurch werden Spiele wieder
  gewertet. Neuer Bildschirm **RANGLISTE** im Internet-Menü (signierte Abfrage, Blättern, eigenes Konto hervorgehoben).
  Online gilt nur noch der Master-Dienstgrad; Rundenrang-Meldungen nur im LAN.
- **Waffen:**
  - Zweibeinwaffen (u. a. Bren, DP, ZB 26, Typ 97) feuern in SP und MP **nur liegend**, mit Hinweis im HUD; die
    **BAR** bleibt stehend und hockend feuerbar. KI legt sich zum Feuern hin, der Server prüft die Regel.
  - **Zielfernrohr-Rückstoß** korrigiert (Faktor nach Original statt 1,0): Scharfschützengewehre schlugen bis zu 3°
    hoch und trafen dadurch schlecht.
  - Rückstoß je Waffenart nach Original; im Mehrspieler gelten wie im Original immer die vollen Werte.
- **Panzer:** Visiersicht (Fahrer/Schütze) ist Standard, V schaltet auf Verfolgerkamera; MG-Fadenkreuz zeigt auf den
  echten Treffpunkt.
- **Grafik:**
  - Gleiche Lichtstimmung auf allen Grafikstufen: **SSAO und Glow immer an** (nur die Qualität sinkt), fehlendes
    indirektes Licht und Volumennebel werden über Umgebungslicht und Nebel ausgeglichen.
  - Neuer Schneefall (weiche Flocken unterschiedlicher Größe, Wind, Taumeln, folgt der Kamera).
  - Arctic 1 (MP) dunkler und stimmiger; Mehrspielerkarten werden nachts nicht mehr aufgehellt.
  - Normandy 3 (MP): Wasser repariert.
- **Tag-Nacht-Wechsel im Mehrspieler für alle Karten** (LAN und Internet gleich), Serverregeln `daynight` (an/aus,
  Standard aus), `daynightstart` (Startstunde, −1 = Kartenstimmung) und `daynightcycle` (Minuten je 24 h); einstellbar
  im Server-Menü, Launcher/Config und Konsole, sichtbar in SPIEL-INFO. Einzelspieler bleibt bei der Originalstimmung.
- **Testkarte Bavaria:** Tag-/Nachtzyklus mit Sonne, Mond, Himmel und Nebel, Raumlicht, Laternen an Wegen und
  Haustüren, begehbare Obergeschoss-Fenster, größere Fernsicht mit Außenwald und Panorama.
- **KI-Wegsuche (B-010b):** Pfadsuche mit bis zu 65536 Polygonen statt 4096 – lange Wege auf großen Karten werden
  vollständig gefunden; zusätzliche Treppen-/Rampenverbindungen; Ausweichcode für Figuren außerhalb des Netzes entfernt.
- **Erfüllbarkeitsprüfung (B-032c):** Begleitfiguren im Löser geschützt, Zweigprüfung durch gezieltes Ausschalten
  einzelner Gegner.
- **Lippensynchronität (B-052)** für alle sprechenden Figuren nach den Original-Lippendaten.
- **Vögel und Fische (B-053)** aus den Originaldaten der Missionen.
- **Einstellungen:** Tastenmenü vollständig umbelegbar (Doppelbelegung wird getauscht, Rechtsklick löscht, Zurückblättern),
  ZURÜCK-Feld in den Grafikeinstellungen (Esc wirkt ebenso).
- **LAN-Menü** im Original-Aufbau wie der Internet-Serverbrowser.
- **Linux-Build (neu):** offizielles Paket für Linux x86_64 (`.tar.gz` mit Startskripten für Spiel und dedizierten
  Server); unter Linux bisher wenig erprobt. Filme werden unabhängig von Groß-/Kleinschreibung gefunden.
- **Eigener Körper in der 1. Person:** die Figur wirft weiter Schatten, beim Blick nach unten sind die Beine sichtbar;
  mit Zielfernrohr/Fernglas nur Schatten. Option SPIEL „KÖRPER IN 1. PERSON“ (Standard an).
- **Tests schreiben nicht mehr in echte Nutzerdateien** (bekannte Server, Favoriten, Filter, Kartenlisten, Schlüssel).

**EN**
- **Dedicated server stability:** fixed an endless loop in bot navigation (cover search), guarded against disconnecting
  already disconnected players and freed callbacks; long run with 24 bots without hangs or memory growth.
- **Master server unreachable:** the game shows a notice (also on server errors/overload) that joining by IP still
  works (all languages).
- **Leaderboard (online):** the profile login at the master server never happened – fixed, so matches are rated again.
  New **LEADERBOARD** screen in the internet menu (signed query, paging, own account highlighted). Online only the
  master rank counts; round rank messages are LAN only.
- **Weapons:**
  - Bipod weapons (e.g. Bren, DP, ZB 26, Type 97) fire **prone only** in SP and MP, with a HUD notice; the **BAR**
    can still be fired standing and crouching. AI goes prone to fire, the server checks the rule.
  - **Scope recoil** fixed (original factor instead of 1.0): sniper rifles kicked up to 3° and therefore hit poorly.
  - Recoil per weapon type as in the original; multiplayer always uses the full values, as in the original.
- **Tanks:** sight view (driver/gunner) is the default, V switches to the chase camera; MG crosshair points at the real
  impact point.
- **Graphics:**
  - Same lighting mood on all quality levels: **SSAO and glow always on** (only quality drops); missing indirect light
    and volumetric fog are compensated via ambient light and fog.
  - New snowfall (soft flakes of varying size, wind, tumbling, follows the camera).
  - Arctic 1 (MP) darker and moodier; multiplayer maps are no longer brightened at night.
  - Normandy 3 (MP): water fixed.
- **Day/night cycle in multiplayer for all maps** (LAN and internet alike), server rules `daynight` (on/off, default
  off), `daynightstart` (start hour, −1 = map mood) and `daynightcycle` (minutes per 24 h); set in the server menu,
  launcher/config and console, shown in GAME INFO. Single player keeps the original mood.
- **Test map Bavaria:** day/night cycle with sun, moon, sky and fog, room lighting, lanterns along paths and at front
  doors, usable upper-floor windows, longer view distance with outer forest and panorama.
- **AI pathfinding (B-010b):** path search up to 65536 polygons instead of 4096 – long routes on large maps are found
  completely; additional stair/ramp links; fallback code for figures off the navmesh removed.
- **Completability check (B-032c):** escort figures protected in the solver, branch checks by removing specific enemies.
- **Lip sync (B-052)** for all speaking characters from the original lip data.
- **Birds and fish (B-053)** from the original mission data.
- **Settings:** key menu fully rebindable (duplicates are swapped, right-click clears, page back), BACK field in the
  graphics settings (Esc works too).
- **LAN menu** in the original layout like the internet server browser.
- **Linux build (new):** official package for Linux x86_64 (`.tar.gz` with start scripts for the game and the dedicated
  server); little tested on Linux so far. Movies are found regardless of upper/lower case.
- **Own body in first person:** the figure keeps casting its shadow and the legs are visible when looking down; with a
  scope/binoculars only the shadow. Option GAME "KÖRPER IN 1. PERSON" (default on).
- **Tests no longer write to real user files** (known servers, favourites, filters, map lists, keys).

## 0.11.3 (11.11.2026) – Hotfix

**DE**
- **Masterserver-Anmeldung:** Bei kurzen Netzwerkfehlern schickt das Spiel eine Anfrage nicht mehr unverändert erneut,
  sondern baut sie mit neuem Zeitstempel neu auf. Bisher konnte der Masterserver das als Wiederholungsangriff werten und
  einen Server sperren.
- Nach einer Sperre meldet sich ein Server gestaffelt (5/15/60 min bzw. nach der Vorgabe des Masterservers) erneut an
  statt jede Minute.

**EN**
- **Master server registration:** after short network errors the game no longer resends an identical request; it builds
  a new one with a fresh timestamp. Previously the master server could treat this as a replay attack and ban the server.
- After a ban, a server retries registration with a staggered delay (5/15/60 min or as told by the master server)
  instead of every minute.

## 0.11.2 (11.11.2026) – Hotfix

**DE**
- **Spawn-Schutz:** Nach dem Spawn ist man für die Schutzzeit unverwundbar und kann nicht schießen, werfen, stechen
  oder Ladungen legen (Spieler und KI gleich). Der Schutz endet nach Ablauf der Zeit; der Server verwirft Aktionen in
  dieser Zeit. Anzeige „Respawn-Schutz N s – Feuern gesperrt“.
- Diagnose für dedizierte Server: `--bot_trace=1` protokolliert Zustand und Ziele der KI-Soldaten.
- Paketbau: Skript für den Build-Schlüssel auf reines ASCII umgestellt.
- Behoben: Fehlermeldung beim Abschießen eines Helms (fehlende Zweitwaffe auf dem Rücken) und vier ähnliche Stellen.

**EN**
- **Spawn protection:** after spawning you are invulnerable for the protection time and cannot shoot, throw, stab or
  place charges (players and AI alike). Protection ends when the time runs out; the server rejects such actions during
  it. HUD shows "Respawn protection N s – firing locked".
- Diagnostics for dedicated servers: `--bot_trace=1` logs state and targets of AI soldiers.
- Packaging: build-key script converted to plain ASCII.
- Fixed: error when a helmet is shot off (no second weapon on the back) and four similar places.

## 0.11.1 (11.11.2026) – Online-Mehrspieler

- **Internet-Mehrspieler mit Serverbrowser** im Stil des Originals: Serverliste über den Masterserver (sortierbar, Filter,
  Spiel-Info, Favoriten, Direktverbindung per IP). Nicht verifizierte Server sind mit „!“ markiert und werden vor dem
  Beitritt gewarnt (keine Ränge).
- **Server erstellen** im Stil des Originals, alle Server-Regeln bedienbar; neue Regel Gesundheit ORIGINAL / MEHR LEBEN.
- **Spieler-Setup vor dem Spawnen:** Nach jedem Beitritt wird zuerst der Soldat ausgerüstet.
- **Neue Mehrspieler-Klassen:** Sanitäter, Scharfschütze, Panzerabwehr, Sturmsoldat, Schleicher, Schwerer Schütze,
  Aufklärer – mit Soldatenwerten wie im Einzelspieler, automatischer Soldatenwahl, Uniform passend zur Karte und
  Ersatzwaffen nach Kartenfreigabe. Doppelklick legt im Ausrüstungsmenü ab.
- **Ränge und Karriere:** 15 Dienstgrade mit XP; online maßgeblich der Masterserver (Abzeichen und Dienstgrad in der
  Punktetabelle, Beförderungsmeldung, Profilseite), im Einzelspieler lokales Karriereprofil, im LAN wie im Original.
  Faire Wertung von Unterstützung und Heilen.
- **Dedizierter Server** meldet sich als Internet-Server beim Masterserver an (Server-ID im Launcher).
- Netzprotokoll DH2-LAN-6 (ältere Versionen können nicht mehr mitspielen).
- **Kartenobjekte**, die an Teilen anderer Modelle hängen (z. B. Regalbretter), liegen jetzt richtig; festgefahrene
  Skriptfahrzeuge befreien sich.
- **Arktis 2 / Konsole:** Konsole öffnet zuverlässig mit ^ auf deutscher Tastatur, `pos` gut lesbar.
- README mit aktuellem Stand und neuen Screenshots.

## 0.10.9 (11.11.2026)

- **Fehlende Missionsobjekte ergänzt:** tief verschachtelte Akteursdefinitionen werden jetzt vollständig gelesen –
  Tschechien 1 (18 Lichtschalter, Fässer, Verstärkung), Normandie 1 (Original-Spielerstarts, Fässer, weitere Figur),
  Normandie MP (Spawnpunkte, Fässer, Leitern, MG u. a.).
- **Konsolenbefehl `pos`:** zeigt Mission, Position und Blickrichtung und kopiert sie in die Zwischenablage (für
  Fehlermeldungen).
- Lokaler Build entfernt vor dem Bauen ältere Release-Ordner.

## 0.10.8 (10.11.2026)

- **Testkarte „Bavaria (Test)“** im Mehrspieler (Deathmatch, Team-Deathmatch, Eroberung) und als Übungseinsatz.
- **Neues Wasser** je Klimazone (Wellen, Gischt, Tiefenfarbe, Qualität nach Grafikstufe); Option „WASSER: ORIGINAL“.
  Quellen und Lizenzen in `THIRD_PARTY_LICENSES.txt` und im Abspann.
- **Versorgungskisten wie im Original:** anfangs versteckte Kisten erscheinen erst per Skript, jede Kiste hat einen
  begrenzten Vorrat (im Spielstand), getrennte Inhalte für Achse/Alliierte.
- **Missionsfiguren:** Nichtkämpfer geben keine Uniform ab, Namen von Wachen/Zivilisten/Verbündeten am Fadenkreuz,
  „Alle Gegner ausschalten“ zählt nur die vom Original gezählten Gegner, bestimmte Wachen durchschauen jede Tarnung.
- **Tarnung:** wirkt nur ohne sichtbare Waffen oder Rucksack der eigenen Seite.
- **Befehle:** „Vorwärts“ zur Lage des Anführers, „Dorthin“ verteilt nach Original-Tabelle, festes Tempo beim Folgen
  unter 10 m, Ziffernblock-Namen im HUD.
- Behoben: Verschluss der K98 (und anderer Repetierer) blieb in der Ego-Ansicht beim Zielen/Nachladen hängen.

## 0.10.7 (10.11.2026)

- **Befehlsmenü Ziffernblock:** Num 0 = alle, Num 1–6 = 1.–6. Kamerad (der aktive Soldat wird übersprungen), Name des
  Empfängers in der Menüzeile.
- **Befehle näher am Original:** Folgen (Rennen ab 10 m), Deckung suchen (20 m), Deckungsfeuer (4 s), Granate (unter 6 m
  „Negativ“), Feuerbefehle des stillen Angriffs.
- **Leise Befehle:** Kameraden folgen geduckt schleichend, feuern selbstständig nur mit schallgedämpfter Waffe und
  nehmen diese automatisch in die Hand.
- **Waffenstreuung nach Original-Formel** (Abweichung je Waffe aus der Waffentabelle, z. B. K98 ≈ 0,1°, MP 40 ≈ 1,4°).
- Tests stabiler (`test_support_strike`, `test_commands_orig`).

## 0.10.6 (10.11.2026)

- **Kameraden heilen:** Erste-Hilfe-Kit in die Hand, Kameraden (≤ 2 m) anklicken → Verband mit Animation und
  Fortschrittsbalken; Wirkung nach Erste-Hilfe-Wert des Heilenden. Einzelspieler und Mehrspieler (gleiches Team,
  Server prüft Abstand/Verband/Team, nicht im Deathmatch).
- **Soldatenwerte geprüft:** Gesundheit, Kraft/Traglast, Ausdauer, Schießen, Tarnung, Erste Hilfe und Schlösser wirken
  im Spiel, auch nach dem Laden und bei Ersatzleuten. Test `test_sas_values`.
- **Fehlende Waffenmodelle** (Panzerschreck, P08 SD, G43, MAS 36) mit eigenen Platzhaltermodellen in Hand, 3. Person,
  Ego-Ansicht und am Boden.
- Datenschutz-Hinweis im Internet-Mehrspieler in allen Spielsprachen (EN/FR/IT/ES/CS).
- Behoben: Erste-Hilfe-Kit blieb nach dem Tod beim Verbinden und Soldatenwechsel in der Ego-Ansicht in der Hand.

## 0.10.5 (10.11.2026)

- Internet-Mehrspieler: beim ersten Aufruf je Profil Hinweis zur Datenübertragung an den Masterserver (PC-Daten gehasht
  und verschlüsselt, Profilname, IP-Adressen gehasht; nur für Sicherheit und Serverbrowser; Spielstand/Rang lokal und am
  Server). Zustimmen speichert die Zustimmung im Profil, Ablehnen führt zurück ins Hauptmenü. Test `test_menu`.

## 0.10.4 (10.11.2026)

- Bereinigung unfertiger Daten.

## 0.10.3 (10.11.2026)

- **Dedizierter Server mit Konfigurations-Launcher** (nach dem Original-ServerLauncher): eigenes Fenster ohne Spielstart
  über `DedicatedServer.cmd` (liegt im Release-Paket) oder aus dem LAN-/Internet-Menü; Konfigurationen `ServerConfigs\*.cfg`
  neben der EXE, Reiter Allgemein/Regeln/Erweitert/Kooperativ/Server (Status, Log, Konsole). Test `test_dedicated_ui`.
- **Einsatzgebiet verlassen:** Warnung mit 10-s-Zähler, danach gilt die Mission als gescheitert (Einzelspieler).
- **Automatisches Nachladen** bei leerer Waffe.
- **Afrika 1:** Verstärkungspanzer fährt durch (kein Stehenbleiben am Hang), kein abstehendes Teil vor dem Panzer,
  Raketentreffer wirken wie im Original, Begleitschutz kommt, Verteidiger greifen aktiver an.
- **Gap-Analyse je Mission** (`docs/gap/*.md`): Skriptwege nach Alarm (Arktis 3/4, Norwegen) laufen weiter, Burma 2
  Sherman und Normandie 2 Halbkette erreichen alle Wegpunkte, Gegner verlieren das Ziel nach Original-Zeitgeber.
- **Sprengladungen:** Fortschrittsbalken beim Anbringen und Scharfmachen.
- Tests `test_fix0103*`, `test_af1_defenders`.

## 0.10.2 (09.11.2026)

- Afrika 1 schließt wieder ab: Verstärkungspanzer blieb in seiner Grube stecken (zu wenig Zugkraft, gegenseitiges Warten
  mit dem BMW-Gespann). Panzer mit Kriechgang im 1. Gang, Skriptfahrten fahren nach 1,5 s Blockade langsam weiter [E].
  Test `test_af1_finale`.
- Zwischensequenzen: eigene Figur sichtbar statt nur der Ego-Waffe, solange das Skript die Kamera führt
  (`CameraRig._script_camera`). Test `test_af1_cutscene`.
- Performance große Karten: Animationsauswahl ferner Figuren (> 60/120 m) und KI ferner Wachen/Patrouillen gestaffelt
  (`--anim_lod=0`, `--ai_lod=0`), Animationszeit −40…−73 % (`docs/status/perf_gross.md`).
- Gegner-KI (`docs/status/ai_orig2.md`, `--ai_orig2=0`): Granatauslöser nach Original 0x552200, defensive Stellungswahl
  über das Fußwegenetz (0x557D10), Rückzug unter 25 % Gesundheit [E] (`--ai_retreat=0`); 0x58C330 = Waffe in Anschlag.
- Test `test_tools_mines` robuster gegen zufällige Spawnpunkte.

## 0.10.1 (08.11.2026)

**Einzelspieler-KI (Abgleich mit dem Original, `docs/AI_AUDIT_ENEMY.md`, `docs/AI_AUDIT_ALLY.md`)**
- Gegner flankieren auf der eigenen Seite, feuern auch im Anmarsch/Laufen, Original-Zeitgeber (z. B. 15–25 s Warten nach
  Zielverlust), Gangwahl beim Annähern, Stellungsposten bleiben am Platz, Flanken-/Nachrückpunkte aus dem Fußwegenetz.
- Verbündete (z. B. Amerikaner in Schwerttänzer, Burma, Arktis) sind bewaffnet und feuern aus ihrer Stellung statt
  vorzurücken; Rebellen/Piloten u. ä. gehören zur Spielerseite.
- Schwerttänzer: Schlusssequenz mit Kamerafahrt, Mission endet erst danach.

**Grafik**
- Fotorealistische Himmel je Karte (CC0, Poly Haven, siehe `docs/SKY_SOURCES.md`), Original-Himmel als Option.
- Normandie 3: neues Wasser, Tag-/Nachtwechsel (1 Tag = 10 Minuten, im MP synchron).
- Lampen der Originalkarten leuchten als echte Lichter; Rauch nach Explosionen deutlich leichter.
- Mündungsfeuer an der echten Mündung, je Waffentyp.

**Waffen**
- Kugelfall wie im Original; Option „Präzises Zielen“ (aus; im MP Server-Regel).
- Scharfschützen: Luft anhalten mit Shift (4 s, danach Atemnot).

**Mehrspieler / Fahrzeuge**
- Eroberung: Einnahme sichtbar (Fahne, Meldungen, Fortschritt) und auf allen Rechnern festgehalten.
- Fahrzeuge erscheinen neu, Schützen sitzen richtig, Kanonen laden nach (Originalmunition), Granaten sprengen niemanden
  mehr aus dem Fahrzeug.
- Sichtweite im MP etwas größer.

**Fehlerbehebungen**
- Arktis 2: Gitterböden begehbar (Regel für alle Karten).

**Bekannt offen:** Original-Schuss-/Streuroutine nicht entschlüsselt; Respawnzeiten Fahrzeuge geschätzt; test_bots 1 schwankende Prüfung.

## 0.9.9 (07.11.2026)

**Neu**
- Option „Sichtweite“: CLASSIC = Nebel/Sichtweite wie im Original, NEU = ohne Nebel, volle Reichweite mit
  vereinfachten Details in der Ferne. Künstliche Zusatznebel entfernt, Himmel mit Horizontdunst/Sonnenhof/Sternen.
- Coop im LAN-/Internet-Menü: alle Einzelspieler-Missionen 1:1 als Coop-Karten.
- Kameraden halten zu Missionsbeginn ihre Position und folgen erst auf „Folgen“.

**Gore und Ragdoll**
- Leichen werden nicht mehr verzerrt/gestreckt (Knochenabstände bleiben, Gelenke begrenzt).
- Wunden je Kaliber und Trefferzone, Austrittswunden, Blutlachen nach Blutverlust; EXTRA GORE mit Schnittflächen.

**Fahrzeuge**
- Alle 31 Fahrzeugmodelle geprüft: Flak 38 auf dem Opel Blitz bedienbar, Panzer bremsen mit der Handbremse,
  Halbkette M3 fährt.

**KI und Missionen**
- Gegner bleiben deutlich seltener stehen (Wegfolge, unerreichbare Ziele, Untersuchen); Burma-Gegner sind wieder
  bewaffnet (japanische und weitere Waffen fehlten); Skript-Patrouillen laufen auch nach „Defensiv“.
- Trupp feuert nicht, wenn ein Kamerad in der Schusslinie steht.
- `_PlayerInRange` liefert wie im Original die Anzahl der Soldaten im Radius.
- Kanten zwischen Skript-Wegpunkten werden wie im Original geprüft.
- HD/4K-Texturen: fehlerhafte Hochskalierungen fallen automatisch auf die nächste Stufe zurück.

**Fehlerbehebungen**
- Dedizierter Server beendet sich nach „quit“ zuverlässig (auch nach Neustart durch den Wächter).
- MP-Bots laufen nicht mehr endlos denselben unerreichbaren Halteplatz an.
- Konverter legt bei fehlerhaftem Missionsnamen keine leeren Ordner mehr an; Build bricht bei solchen Ordnern ab.

**Tests**
- Neue Testreihen für Fahrzeugtypen, Sichtweite, Gore/Ragdoll und Gegner-Stillstand; Löser prüft Kampagnenketten
  (Afrika 1–6 erfüllbar), Fehlschlagpfade und Zeitlimits.

**Bekannt offen**
- Gegner-KI im Kampf noch nicht wie im Original (Flankenseite, Feuern in Bewegung), Schwerttänzer-Schlusssequenz
  ohne Kamerafahrt, Himmel noch ohne Original-Texturen – siehe Gap-Analyse vom 06.11.2026.

## 0.9.8 (02.11.2026)

**Arktis-Kampagne „menschlich“ geprüft**
- Neuer Löser-Modus `--human=1`: spielt nur mit Spielereingaben, ohne Teleports. arctic1–4 damit durchgespielt
  (arctic1/2 abgenommen, arctic3 von vorn alle Pflichtziele, arctic4 Ziele 1–4).

**Fehlerbehebungen**
- arctic2: Verschlossene Türen ohne Schlüssel lösen das Skript-Ereignis „Benutzen“ aus – die Skripte schließen sie
  beim ersten Benutzen auf (vorher blieben drei Türen für immer zu).
- Originalkarten: Kartengrenz-Deckel (ab 10 m Höhe) sind nur noch von unten fest – man kann nicht mehr auf der
  unsichtbaren Decke über der Karte herumlaufen (arctic3).
- Originalkarten: Unsichtbare Sichtverdecker haben keine Kollision mehr (arctic4, Normandie, czech4/5).
- Zerstörte Fahrzeuge gelten für die Skripte als zerstört (alps1: Zusatzziel „Gepanzertes Fahrzeug zerstören“,
  Übergabe an alps2).
- Join-Prüfung für Skript-Wegpunkte wie im Original; Soldaten warten länger auf Menschen im Weg statt abzubrechen.

**Navigation**
- NORWAY-Stahltreppen und Treppenhaus T1 (arctic2) sind im KI-Wegenetz (KI folgt auf nw1 4/8 statt 1/8).
- mp_normandy2 besser erreichbar (72/81 statt 64/81).

**Tests**
- Kampagnen-Löser: Ketten mit Übergabewerten zwischen Missionsteilen (`-Chain`), Zusatzziele, Fehlschlagpfade und
  Todesfallen werden erkannt und gemieden. Stichproben alps1→alps2 und norway1 komplett.
- Gesamttestreihe 75/77 grün (rot nur die Mess-Suiten Treppen und MP-Erreichbarkeit); `run_tests.ps1 -Exclude`.
- Neue Screenshots im README.

**Bekannt offen**
- arctic4: Tür zur Baracke mit den Unterlagen wird nicht immer angeboten; Ziele 5/6 im Löser nicht erreicht.
- Restliche Erreichbarkeitslücken (norway1-Oberdecks, czech2, mp_burma2, mp_alps1, mp_africa2).

## 0.9.7 (01.11.2026)

**Neu**
- Blut-Stufe „EXTRA GORE“ (Option, Standard aus): Körperteile werden je nach Treffer/Explosion abgetrennt, mit Physik und Stumpf.
- Mehrspieler-Coop auf Kampagnenkarten (Leben je Spieler/Team, Coop-Schwierigkeit); einmalige Spawnplätze ohne Respawn.
- Builds liefern EXE + separate `.pck` + `version.txt` (Versionsprüfung beim Start); neues Skript für das öffentliche Paket.

**Originaltreue (KI und Skripte)**
- Kampfautomat der Gegner nach dem Original (Anmarsch, Flankieren im 5-m-Raster, Nachrücken, Feuerpausen); Sichtweite nach
  Waffenhaltung, Sprint am auffälligsten, sofortige Erkennung.
- Alarm wie im Original: kein kartenweiter Alarm mehr in Originalmissionen, nur Zuruf/Schüsse in Hörweite.
- Schwierigkeitsgrad wirkt auf die Gegnerwerte; Scharfschützen-Posten, Skript-Angriffsbefehl, Uniformtarnung mit Tarnwert.
- Spielstände in Originalmissionen speichern den kompletten Skriptzustand.
- Skript-Auslöser im Original-Takt, Führerwege über das Original-Wegpunktnetz, weitere bisher wirkungslose Befehle umgesetzt.
- Original-Partikel, Zwischensequenz-Ende aus der Kameraanimation, Zerstörungsanimationen und explodierende Fässer.
- Leuchtturmlicht, Lichtwechsel, Gesichter, Wetterrichtung/-farbe aus den Skripten.

**Fehlerbehebungen**
- Operation Schwerttänzer: beide Panzer hingen fest – behoben.
- Graue Wände in der Ferne (africa1, arctic1) – Himmelswürfel des Originals stand fest in der Landschaft.
- arctic2: Löser-Sackgasse an Treppen behoben; arctic1 ohne Teleports bis Ziel 2 durchgespielt.

**Sicherheit und Robustheit**
- Mehrspieler: Munition/Respawn nicht mehr vom Client, Anmeldepflicht, Admin-Login-Sperre, gedrosselte Serverabfrage
  und Sprachchat, abgesicherte Admin-Befehle.
- Spielstände mit Versionsnummer und Rückfall auf Sicherungskopie; Einstellungen werden geprüft.
- Nutzer-Werkzeug: Export setzt nach Fehlern korrekt fort, funktioniert mit allen Sprachversionen, liefert Original-Schriften mit.

**Leistung**
- Wahrnehmung und HUD deutlich schneller; Texturkompression halbiert bis viertelt den Speicherbedarf.
- Zusammengefasste Level-Meshes (weniger Draw Calls); Navmesh-Cache: Ladezeit z. B. arctic1 109 s → 17 s.

**Tests:** Gesamttestreihe mit Sperre, Zeitlimit je Reihe und Ergebnistabelle; viele neue Testreihen.

**Bekannt offen**
- Arktis „menschlich“: arctic2–4 laufen noch; NORWAY-Treppen und weitere Erreichbarkeitslücken (B-010b).
- Neue Screenshots folgen mit dem nächsten Update.

## 0.9.6 (30.10.2026)

**Mehrspieler-Sicherheit und Stabilität (Code-Review)**
- Server prüft alle Client-Meldungen selbst: Fahrzeuge nur vom Fahrer, Schüsse mit Waffenbesitz/Munition/Feuerrate/
  Position, Bewegung plausibel (kein Teleport/Speedhack), Benutzen und Sitze mit Abstand/Belegung, ungültige
  Waffen-IDs und doppelte Anmeldungen werden verworfen. Neue Protokollversion (ältere Versionen können nicht beitreten).
- Profile: Testläufe löschen nur noch Testordner, Profilordner sind eindeutig.
- Spielstände werden geprüft geladen und sicher gespeichert (Zwischendatei + Sicherung).
- Zurückgesetzte Tastenbelegungen bleiben zurückgesetzt; VSync vereinheitlicht; „Gamma-Korrektur“ ist eine echte Gammakurve.

**Spiel**
- Drahtschere im Truppmenü: Kamerad schneidet den Zaun, KI nutzt danach die Lücke.
- Haltende Kameraden laufen nach einer Aktion nicht mehr zurück; kein Ausweichen beim Soldatenwechsel.
- Benutzen wählt das Objekt in Blickrichtung (Doppeltür africa1).
- Ragdoll-Leichen liegen natürlicher (straffere Gelenke).
- F3-Doppeldruck auch unter Last zuverlässig.
- Original-Steuerung vervollständigt (36 Aktionen ergänzt, u. a. Aktionsmenü ', Ziele Komma, Pause P, Handbremse Alt,
  Taktik-Tasten der Karte); eigene Verbesserungen bleiben. Belegungsseiten mit Unterseiten.
- Gegner-KI in Originalmissionen: Sicht- und Hörformel, Granatregel und dritter KI-Modus („Zombie“) wie im Original.
- Navigation: al1 stabil, NORWAY-Treppen teilweise verbessert.

**Grafik und HUD**
- Original-Schriften für Befehlsmenü, Waffenfeld, Meldungen und Ziele.
- HUD: Befehls-/Feuerregel-Symbole je Kamerad, Kompass-Treffer/-Geräusch, Fortschrittsbalken (Arbeit, Verband, Atemluft),
  Aktionssymbol, Kameradenname unter dem Fadenkreuz; lange Waffennamen werden gestaucht.
- Burma: Regen statt Schnee (Original-Wetter); africa1-Intro: Soldaten sitzen auf der Bank.

**Bekannt offen**
- NORWAY: Stahltreppen fehlen im Navigationsnetz; weitere Karten mit Erreichbarkeitslücken (B-010b).
- Kampftaktik (Deckung/Flanke/Rückzug) noch eigene Lösung.

## 0.9.5 (25.10.2026)

**Level**
- africa1 (Flughafen): Eingangstüren vorne/hinten und die Doppeltür im hinteren Vorraum lassen sich öffnen
  (im Original feste Flügel – bewusste Abweichung).
- Operation Schwerttänzer: Tür am Startpunkt lässt sich öffnen.
- arctic1: Zielmarker zuerst am Fremdenführer, danach am Eingang zur Basis.
- arctic1: Am Haupteingang zur Basis ist links wieder Schnee statt Wasser.
- arctic1: Zäune lassen sich mit der Drahtschere zerschneiden; Zaunfelder sind nicht mehr durchlaufbar.
- arctic1: Kein Durchfallen unter die Karte mehr, Kamera schaut nicht mehr durch Wände.
- arctic2: Zielmarker nur für freigegebene Sprengplätze (max. 4), lesbare Entfernung, sichtbarer Zeitzünder.

**Helme und Inventar**
- Helme sitzen wie im Original am Kopf; eigene Schüsse treffen weder eigenen Helm noch Körper.
- Zweite Langwaffe (Gewehr/MP) wird sichtbar auf dem Rücken getragen, Taste 1 tauscht Hand/Rücken.
- Munition und Granaten liegen mit Rucksack zuerst im Rucksack und belasten die Taschen nicht; Nachladen greift
  automatisch darauf zu (auch bei KI-Kameraden).
- Inventar: Mausrad blättert, Entf legt ab, Enter = Doppelklick-Aktion, Hinweistexte je Platz.

**Truppe und KI**
- Befehlsmenü im Original-Rahmen mit allen Aktionen der Original-Tabelle (Tür, Gegner, Gefangener, Leiche,
  Kamerad, Kiste, Mine …).
- Folgen mit Original-Formationen (Pfeil, Linie, Kolonne, Block), Abstandsstufen, Mindestabstand 1,2 m und
  Lösen bei Festhängen.
- arctic1: Gegner reagieren nach Alarm, Kanisternik wandert nicht mehr aus der Karte, Hund greift wie im
  Original an und hat die Original-Animationen.
- KI-Werte aus dem Original: Postenradius defensiver Gegner, Wechsel zu defensiv unter 50 % Gesundheit,
  Suchzeiten 20–30 s.

**Effekte**
- Ragdoll-Physik (Option, Standard an): Tod beginnt mit dem Original-Todesclip und geht fließend in die
  Physik über; Schuss- und Explosionswucht, auch im Mehrspieler.
- Blut auf der Kleidung (folgt Körper und Ragdoll), Blutspuren Verwundeter, Blut bei Messer/Splitter,
  roter Treffer-Rand am Bildschirm; alles über „BLUTFLECKEN“ abschaltbar.

**Bekannt offen**
- Neu festgestellt: Die KI nutzt zerschnittene Zäune noch nicht; der Drahtschere-Befehl im Truppmenü findet sie
  noch nicht.
- Neu festgestellt: Ragdoll-Leichen liegen teils zu verdreht.
- Bereits aus 0.9.4: Weiße Partikel in Burma, Figuren mit ausgestreckten Armen im Afrika-Intro.

## 0.9.4 (25.10.2026)
- Truppsteuerung: F1–F4 Soldaten markieren/übernehmen, 1–8 Waffen, B Fernglas, mittlere Maustaste Feuermodus.
- Schwere MGs nur liegend (auch Mehrspieler), Granatwurf sichtbar.
- Helme mit Kopfschuss-Schutz (fallen ab, wieder aufsetzbar), Rucksackraum nur mit Rucksack, HUD am Bildschirmrand.
- Navigation: große Karten, Leitern/Brücken für die KI, Treppen.
- Grafik (Wolken, Explosionen, 4K Ultra), Luftunterstützung im Mehrspieler, weitere Sprachen.

## 0.9.3 (24.10.2026)
- Einzelspieler-Kampagne: alle 24 Teile durchspielbar.
- Truppbefehle, Schaden und Hitboxen wie im Original, Bluteffekte, Ingame-Inventar, LAN-Menü,
  Nutzer-Werkzeug HD2-Werkzeuge.cmd für Export und Upscaling.
