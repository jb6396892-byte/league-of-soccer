extends RefCounted
## Small procedural mesh helpers. All demo art is generated locally.

static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func mesh(parent: Node3D, shape: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = shape
	item.material_override = mat
	item.position = at
	parent.add_child(item)
	return item


static func box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, at, mat)


static func sphere(parent: Node3D, at: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 12
	shape.rings = 6
	return mesh(parent, shape, at, mat)


static func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = a.distance_to(b)
	shape.radial_segments = 6
	var item := mesh(parent, shape, (a + b) * 0.5, mat)
	var direction := (b - a).normalized()
	item.quaternion = Quaternion(Vector3.UP, direction)
	return item


static func ring(parent: Node3D, at: Vector3, radius: float, width: float, mat: Material) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - width * 0.5
	shape.outer_radius = radius + width * 0.5
	shape.rings = 48
	shape.ring_segments = 6
	return mesh(parent, shape, at, mat)


static func capsule(parent: Node3D, at: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var shape := CapsuleMesh.new()
	shape.radius = radius
	shape.height = height
	shape.radial_segments = 12
	shape.rings = 5
	return mesh(parent, shape, at, mat)
