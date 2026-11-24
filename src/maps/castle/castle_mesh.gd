extends RefCounted
## Castle: Sammel-Geometrie je Material (ein MeshInstance3D je Batch, Flächen nach Material zusammengefasst) und
## Kollision als ein ConcavePolygonShape3D. Dreiecke werden über die gewünschte Normale ausgerichtet
## (Godot: Vorderseite im Uhrzeigersinn → (b−a)×(c−a) zeigt von der Vorderseite weg).
## Castle: merged geometry per material plus one trimesh collision shape per batch.

var _st := {}                              # Material → SurfaceTool
var faces := PackedVector3Array()          # Kollisionsdreiecke
var tri_count := 0


func _tool(mat: String) -> SurfaceTool:
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
	return _st[mat]


## uvb = [u, v, Maßstab]: UV = (p·u, p·v) × Maßstab (z. B. Dachflächen entlang der Neigung); sonst ohne UV (triplanar).
## Eine Materialfläche muss durchgehend mit oder ohne UV gefüllt werden.
func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, mat: String, visual := true, collide := true, uvb: Array = []) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	if visual:
		var st := _tool(mat)
		for p in [a, b, c]:
			st.set_normal(n)
			if uvb.size() >= 6:
				# [u, v, su, sv, ou, ov]: UV = (p·u·su + ou, p·v·sv + ov)
				st.set_uv(Vector2(p.dot(uvb[0]) * float(uvb[2]) + float(uvb[4]), p.dot(uvb[1]) * float(uvb[3]) + float(uvb[5])))
			elif not uvb.is_empty():
				st.set_uv(Vector2(p.dot(uvb[0]), p.dot(uvb[1])) * float(uvb[2]))
			st.add_vertex(p)
		tri_count += 1
	if collide:
		faces.append(a)
		faces.append(b)
		faces.append(c)


## Glattes Dreieck mit Normalen je Ecke (Gelände)
func tri_smooth(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, mat: String, collide := true) -> void:
	var st := _tool(mat)
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)
	tri_count += 1
	if collide:
		faces.append(a)
		faces.append(b)
		faces.append(c)


static func newell(poly: PackedVector3Array) -> Vector3:
	var n := Vector3.ZERO
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		n.x += (a.y - b.y) * (a.z + b.z)
		n.y += (a.z - b.z) * (a.x + b.x)
		n.z += (a.x - b.x) * (a.y + b.y)
	return n.normalized() if n.length() > 1e-6 else Vector3.ZERO


## Ebenes (auch konkaves) Polygon in Dreiecke zerlegen
func poly(p: PackedVector3Array, n: Vector3, mat: String, visual := true, collide := true) -> void:
	if p.size() < 3 or n == Vector3.ZERO:
		return
	if p.size() == 3:
		tri(p[0], p[1], p[2], n, mat, visual, collide)
		return
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var p2 := PackedVector2Array()
	for q in p:
		p2.append(Vector2(q.dot(u), q.dot(v)))
	var idx := Geometry2D.triangulate_polygon(p2)
	if idx.is_empty():
		for i in range(1, p.size() - 1):
			tri(p[0], p[i], p[i + 1], n, mat, visual, collide)
		return
	for i in range(0, idx.size(), 3):
		tri(p[idx[i]], p[idx[i + 1]], p[idx[i + 2]], n, mat, visual, collide)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, mat: String, visual := true, collide := true) -> void:
	tri(a, b, c, n, mat, visual, collide)
	tri(a, c, d, n, mat, visual, collide)


## Quader (Mitte/Achsen aus xf, Kantenlängen size) – sechs Seiten
func box(xf: Transform3D, size: Vector3, mat: String, visual := true, collide := true) -> void:
	var h := size * 0.5
	var c := []
	for i in 8:
		c.append(xf * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var bx := xf.basis.x.normalized()
	var by := xf.basis.y.normalized()
	var bz := xf.basis.z.normalized()
	quad(c[1], c[3], c[7], c[5], bx, mat, visual, collide)
	quad(c[0], c[4], c[6], c[2], -bx, mat, visual, collide)
	quad(c[2], c[6], c[7], c[3], by, mat, visual, collide)
	quad(c[0], c[1], c[5], c[4], -by, mat, visual, collide)
	quad(c[4], c[5], c[7], c[6], bz, mat, visual, collide)
	quad(c[0], c[2], c[3], c[1], -bz, mat, visual, collide)


## Quader von Unterkante (bottom-Mitte) aus, waagerechte Drehung über die Achsen ax (Länge) / az (Tiefe)
func block(bottom: Vector3, ax: Vector3, size: Vector3, mat: String, visual := true, collide := true) -> void:
	var x := Vector3(ax.x, 0, ax.z).normalized()
	var z := x.cross(Vector3.UP) * -1.0
	box(Transform3D(Basis(x, Vector3.UP, z), bottom + Vector3.UP * size.y * 0.5), size, mat, visual, collide)


func commit(parent: Node3D, name: String, lb: LevelBuilder, collide := true, shadows := true) -> Node3D:
	var root := Node3D.new()
	root.name = name
	parent.add_child(root)
	if not _st.is_empty():
		var mesh := ArrayMesh.new()
		for mat in _st:
			var st: SurfaceTool = _st[mat]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, lb.mat(mat))
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	if collide and not faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
	return root
