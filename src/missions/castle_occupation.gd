extends "res://src/missions/castle.gd"
## Testkarte Castle, Eroberung (Registereintrag castle_occupation). Verhalten = castle.gd (Spielart aus dem Register:
## ganze Burg, Zonen A–F mit FRONTLINE). Eigene Skriptdatei nur, weil der Navmesh-Cache je Skriptname einen Platz hat
## (NavCache.map_id): DM/TDM (innere Grenze C|D schneidet das Netz) und Eroberung verdrängen sich so nicht gegenseitig.
## Castle test map, occupation variant; separate script only to keep its own navmesh cache slot.
