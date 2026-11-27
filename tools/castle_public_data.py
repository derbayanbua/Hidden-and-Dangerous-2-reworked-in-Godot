# -*- coding: utf-8 -*-
"""Castle: oeffentliche Kartendaten aus den lokalen Arbeitsdaten erzeugen.
Castle: build the public map data from the local working data.

Liest local/castle/derived/*.json (nicht im Repository) und schreibt eine bereinigte Fassung nach
assets/maps/castle/data/: nur lokale Spielkoordinaten (m), ohne Bezugssystem/Ursprung, ohne externe Kennungen,
Adressen, Namen und Herkunftsvermerke; Kennungen neutral umbenannt, Zahlen auf 1 cm gerundet.
Prueft das Ergebnis gegen .git/info/private_words und bricht bei einem Treffer ab.

Aufruf / usage:  python -I tools/castle_public_data.py [--check]
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "local", "castle", "derived")
DST = os.path.join(ROOT, "assets", "maps", "castle", "data")
FILES = ["buildings.json", "castle_features.json", "terrain.json", "terrain_castle_1m.json", "surroundings.json"]

# Schluessel, die entfallen (Bezugssystem, Herkunft, Beschreibungen, externe Kennungen)
DROP_KEYS = {"frame", "source_codes", "assumptions", "previous_estimate_note", "layout", "note", "wall_walk_note",
             "gml_id", "address_local", "function_code", "name_local", "in_lod2", "dgm_y"}
ID_RE = re.compile(r"^([a-g]\d+[a-z]?)_(.+)$")
# Textmarker, die im Ergebnis nicht vorkommen duerfen (zusaetzlich zur privaten Wortliste)
FORBIDDEN = ["epsg", "utm", "deby", "lod2", "dgm", "etrs", "dhhn", "gml"]


def _round(o):
    if isinstance(o, float):
        r = round(o, 2)
        return 0.0 if r == 0 else r
    if isinstance(o, list):
        return [_round(v) for v in o]
    if isinstance(o, dict):
        return {k: _round(v) for k, v in o.items()}
    return o


def _id_map(data):
    """Alte Kennung mit Planpraefix (z. B. a4_xyz) -> neutral (a4_turm)."""
    kinds = {}
    for b in data["buildings.json"]["buildings"]:
        kinds[b["id"]] = b.get("kind", "building")
    feat = data["castle_features.json"]
    for t in feat.get("towers", []):
        kinds.setdefault(t["id"], "tower")
        if t.get("building_ref"):
            kinds.setdefault(t["building_ref"], "tower")
    for g in feat.get("gates", []):
        kinds.setdefault(g["id"], "gate")
    for pp in feat.get("plan_points", {}).values():
        if pp.get("matched_building"):
            kinds.setdefault(pp["matched_building"], pp.get("kind", "building"))
    word = {"tower": "turm", "gate": "tor", "building": "bau", "wall": "mauer", "bridge": "bruecke", "structure": "bau"}
    out, used = {}, set()
    for old in sorted(kinds):
        m = ID_RE.match(old)
        if not m:
            continue
        base = "%s_%s" % (m.group(1), "kapelle" if "kapelle" in old.lower() else word.get(kinds[old], "bau"))
        new, n = base, 1
        while new in used:
            n += 1
            new = "%s%d" % (base, n)
        used.add(new)
        out[old] = new
    return out


def _clean(o, idmap):
    if isinstance(o, dict):
        res = {}
        for k, v in o.items():
            if k in DROP_KEYS:
                continue
            if k == "source" and not isinstance(v, list):
                continue
            if k == "label_local":
                res[k] = "Kapelle" if isinstance(v, str) and "kapelle" in v.lower() else None
                continue
            res[k] = _clean(v, idmap)
        return res
    if isinstance(o, list):
        return [_clean(v, idmap) for v in o]
    if isinstance(o, str):
        return idmap.get(o, o)
    return o


def _strings(o, acc):
    if isinstance(o, dict):
        for k, v in o.items():
            acc.add(k)
            _strings(v, acc)
    elif isinstance(o, list):
        for v in o:
            _strings(v, acc)
    elif isinstance(o, str):
        acc.add(o)


def _private_words():
    p = os.path.join(ROOT, ".git", "info", "private_words")
    if not os.path.exists(p):
        return []
    with open(p, encoding="utf-8") as f:
        return [w.strip().lower() for w in f if w.strip()]


def main():
    check_only = "--check" in sys.argv
    if not check_only:
        data = {}
        for f in FILES:
            with open(os.path.join(SRC, f), encoding="utf-8") as fh:
                data[f] = json.load(fh)
        idmap = _id_map(data)
        os.makedirs(DST, exist_ok=True)
        for f in FILES:
            out = _round(_clean(data[f], idmap))
            with open(os.path.join(DST, f), "w", encoding="utf-8", newline="\n") as fh:
                json.dump(out, fh, ensure_ascii=True, separators=(",", ":"))
        print("Kennungen umbenannt: %d" % len(idmap))
    # Pruefung
    words = _private_words() + FORBIDDEN
    acc = set()
    for f in FILES:
        with open(os.path.join(DST, f), encoding="utf-8") as fh:
            _strings(json.load(fh), acc)
        with open(os.path.join(DST, f), encoding="utf-8") as fh:
            raw = fh.read().lower()
        hits = [i for i, w in enumerate(words) if w and w in raw]
        if hits:
            print("FEHLER: %s enthaelt verbotene Woerter (Index %s)" % (f, hits))
            return 1
        print("%s: %d Bytes, ok" % (f, os.path.getsize(os.path.join(DST, f))))
    texts = sorted(s for s in acc if re.search(r"[A-Za-z]{3,}", s))
    print("Texte im Ergebnis (%d): %s" % (len(texts), ", ".join(texts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
