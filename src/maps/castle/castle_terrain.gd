extends RefCounted
## Castle: Höhenfeld aus den lokal abgeleiteten Geländedaten (nur zur Laufzeit gelesen, nichts eingebettet).
## Gitter = Grobraster der Basisdatei; Eckhöhen werden, wo vorhanden, aus dem feinen Raster (bilinear) übernommen.
## ground_y() interpoliert exakt auf den Dreiecken des Geländemeshes (Diagonale (x+1,z)–(x,z+1)).
## Castle terrain: heightfield read at runtime; mesh chunks (full res + collision near the castle, coarse elsewhere).

const MeshBatch := preload("res://src/maps/castle/castle_mesh.gd")
const CHUNK := 32

var ox := 0.0
var oz := 0.0
var cell := 2.0
var cols := 0
var rows := 0
var h := PackedFloat32Array()


static func _grid(d: Dictionary) -> Dictionary:
	var out := {"ox": float(d.origin_xz[0]), "oz": float(d.origin_xz[1]), "cell": float(d.cell_m),
		"cols": int(d.cols), "rows": int(d.rows), "h": PackedFloat32Array()}
	var arr: PackedFloat32Array = out.h
	arr.resize(out.cols * out.rows)
	var r := 0
	for row in d.heights:
		var c := 0
		for v in row:
			arr[r * out.cols + c] = float(v)
			c += 1
		r += 1
	out.h = arr
	return out


static func _bilinear(g: Dictionary, x: float, z: float) -> float:
	var fx: float = (x - g.ox) / g.cell
	var fz: float = (z - g.oz) / g.cell
	var i := clampi(int(floor(fx)), 0, g.cols - 2)
	var j := clampi(int(floor(fz)), 0, g.rows - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var a: PackedFloat32Array = g.h
	var c: int = g.cols
	var h0 := lerpf(a[j * c + i], a[j * c + i + 1], tx)
	var h1 := lerpf(a[(j + 1) * c + i], a[(j + 1) * c + i + 1], tx)
	return lerpf(h0, h1, tz)


func setup(base: Dictionary, fine: Dictionary) -> void:
	var g := _grid(base)
	ox = g.ox
	oz = g.oz
	cell = g.cell
	cols = g.cols
	rows = g.rows
	h = g.h
	if fine.is_empty() or not fine.has("heights"):
		return
	var f := _grid(fine)
	var fx0: float = f.ox
	var fz0: float = f.oz
	var fx1: float = f.ox + (f.cols - 1) * f.cell
	var fz1: float = f.oz + (f.rows - 1) * f.cell
	for j in rows:
		var z := oz + j * cell
		if z < fz0 or z > fz1:
			continue
		for i in cols:
			var x := ox + i * cell
			if x >= fx0 and x <= fx1:
				h[j * cols + i] = _bilinear(f, x, z)


func vh(i: int, j: int) -> float:
	return h[clampi(j, 0, rows - 1) * cols + clampi(i, 0, cols - 1)]


func vpos(i: int, j: int) -> Vector3:
	return Vector3(ox + i * cell, vh(i, j), oz + j * cell)


func height(x: float, z: float) -> float:
	var fx := (x - ox) / cell
	var fz := (z - oz) / cell
	var i := clampi(int(floor(fx)), 0, cols - 2)
	var j := clampi(int(floor(fz)), 0, rows - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	if tx + tz <= 1.0:
		var h00 := vh(i, j)
		return h00 + (vh(i + 1, j) - h00) * tx + (vh(i, j + 1) - h00) * tz
	var h11 := vh(i + 1, j + 1)
	return h11 + (vh(i, j + 1) - h11) * (1.0 - tx) + (vh(i + 1, j) - h11) * (1.0 - tz)


func normal_at(i: int, j: int) -> Vector3:
	var dx := vh(i + 1, j) - vh(i - 1, j)
	var dz := vh(i, j + 1) - vh(i, j - 1)
	return Vector3(-dx, 2.0 * cell, -dz).normalized()


func extent() -> Rect2:
	return Rect2(ox, oz, (cols - 1) * cell, (rows - 1) * cell)


## Gelände in Kacheln bauen. full_rect: volle Auflösung + Kollision unter static_parent; sonst grob (Schritt 4) ohne
## Kollision unter coarse_parent. material_fn(x, z) -> String wählt das Material je Gitterzelle (nur volle Auflösung).
func build(static_parent: Node3D, coarse_parent: Node3D, lb: LevelBuilder, full_rect: Rect2, material_fn: Callable) -> Dictionary:
	var stats := {"full": 0, "coarse": 0, "tris": 0}
	var ci := int(ceil(float(cols - 1) / CHUNK))
	var cj := int(ceil(float(rows - 1) / CHUNK))
	for b in cj:
		for a in ci:
			var i0 := a * CHUNK
			var j0 := b * CHUNK
			var i1 := mini(i0 + CHUNK, cols - 1)
			var j1 := mini(j0 + CHUNK, rows - 1)
			var r := Rect2(ox + i0 * cell, oz + j0 * cell, (i1 - i0) * cell, (j1 - j0) * cell)
			var mb := MeshBatch.new()
			if r.intersects(full_rect):
				for j in range(j0, j1):
					for i in range(i0, i1):
						var mat: String = material_fn.call(ox + (i + 0.5) * cell, oz + (j + 0.5) * cell)
						var p00 := vpos(i, j)
						var p10 := vpos(i + 1, j)
						var p01 := vpos(i, j + 1)
						var p11 := vpos(i + 1, j + 1)
						var n00 := normal_at(i, j)
						var n10 := normal_at(i + 1, j)
						var n01 := normal_at(i, j + 1)
						var n11 := normal_at(i + 1, j + 1)
						mb.tri_smooth(p00, p10, p01, n00, n10, n01, mat)
						mb.tri_smooth(p10, p11, p01, n10, n11, n01, mat)
				mb.commit(static_parent, "Terrain_%d_%d" % [a, b], lb, true)
				stats.full += 1
			else:
				var s := 4
				var j := j0
				while j < j1:
					var jn := mini(j + s, j1)
					var i := i0
					while i < i1:
						var inn := mini(i + s, i1)
						var p00 := vpos(i, j)
						var p10 := vpos(inn, j)
						var p01 := vpos(i, jn)
						var p11 := vpos(inn, jn)
						mb.tri_smooth(p00, p10, p01, normal_at(i, j), normal_at(inn, j), normal_at(i, jn), "c_slope", false)
						mb.tri_smooth(p10, p11, p01, normal_at(inn, j), normal_at(inn, jn), normal_at(i, jn), "c_slope", false)
						i = inn
					j = jn
				# Schürzen gegen Nahtrisse zum fein aufgelösten Nachbarn
				var edges := [[Vector2i(i0, j0), Vector2i(i1, j0)], [Vector2i(i1, j0), Vector2i(i1, j1)],
					[Vector2i(i1, j1), Vector2i(i0, j1)], [Vector2i(i0, j1), Vector2i(i0, j0)]]
				for e in edges:
					var pa := vpos(e[0].x, e[0].y)
					var pb := vpos(e[1].x, e[1].y)
					var out := Vector3(pb.z - pa.z, 0, pa.x - pb.x).normalized()
					mb.quad(pa, pb, pb + Vector3.DOWN * 3.0, pa + Vector3.DOWN * 3.0, out, "c_slope", true, false)
				var n := mb.commit(coarse_parent, "TerrainFar_%d_%d" % [a, b], lb, false, false)
				n.set_meta("castle_backdrop_terrain", true)
				stats.coarse += 1
			stats.tris += mb.tri_count
	return stats
