extends HeightmapTerrain
## Flat playing surface; the original heightmap remains available as an exhibit.
var box_batches: Dictionary = {}

func _ready() -> void:
	image = load("res://assets/heightmap.png").get_image()
	image.resize(RESOLUTION, RESOLUTION)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(6.0, 8.0)
	body = StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = floor_mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)
	box(Vector3(0, -0.2, 0), Vector3(9.2, 0.4, 10.8), Color("12283f"), 0.1)
	box(Vector3(0, -0.015, 2), Vector3(6, 0.04, 4), Color("237b86"))
	box(Vector3(0, -0.015, -2), Vector3(6, 0.04, 4), Color("b85d70"))
	for x in [-3.0, 3.0]:
		box(Vector3(x, 0.015, 0), Vector3(0.045, 0.025, 8), Color("f3e7cb"), 0.3)
	for z in [-4.0, -1.3, 0.0, 1.3, 4.0]:
		box(Vector3(0, 0.015, z), Vector3(6, 0.025, 0.04), Color("f3e7cb"), 0.3)
	# Net with actual mesh strands, glowing posts and top tape.
	for x in [-3.2, 3.2]:
		box(Vector3(x, 0.85, 0), Vector3(0.1, 1.7, 0.1), Color("6cebd9"), 0.8)
		box(Vector3(x, 0.05, 0), Vector3(0.5, 0.08, 0.5), Color("172f47"))
	for i in range(31):
		box(Vector3(-3 + i * 0.2, 0.91, 0), Vector3(0.012, 0.82, 0.012), Color("d6e9ec"))
	for i in range(6):
		box(Vector3(0, 0.5 + i * 0.16, 0), Vector3(6, 0.012, 0.012), Color("d6e9ec"))
	box(Vector3(0, 1.35, 0), Vector3(6.4, 0.07, 0.065), Color("f8e8c4"), 0.25)
	# Stands and stylized audience around the plinth.
	for side in [-1, 1]:
		for row in range(3):
			box(Vector3(side * (3.55 + row * 0.35), row * 0.22, 0), Vector3(0.32, 0.24, 8.6), Color("233c57"))
			for seat in range(13):
				var color := Color("65d5c6") if (seat + row) % 3 == 0 else Color("edbc85") if seat % 2 == 0 else Color("df8997")
				box(Vector3(side * (3.55 + row * 0.35), row * 0.22 + 0.25, -3.8 + seat * 0.62), Vector3(0.14, 0.22, 0.14), color)
		box(Vector3(0, -0.05, side * 4.9), Vector3(8.8, 0.12, 0.045), Color("64e6d1") if side == 1 else Color("ff9b9d"), 0.7)
	var branding := Label3D.new()
	branding.text = "N E O N   /   V O L L E Y"
	branding.font_size = 48
	branding.pixel_size = 0.0035
	branding.position = Vector3(0, 0.1, -4.55)
	branding.rotation_degrees.x = -90
	branding.modulate = Color("f5dcb0")
	add_child(branding)
	_flush_batches()

func box(pos: Vector3, dimensions: Vector3, color: Color, glow := 0.0) -> void:
	var key := color.to_html() + "/" + str(glow)
	if not box_batches.has(key):
		box_batches[key] = {"color": color, "glow": glow, "transforms": []}
	box_batches[key].transforms.append(Transform3D(Basis.from_scale(dimensions), pos))

func _flush_batches() -> void:
	# Hundreds of individual net/audience boxes become a handful of GPU draws.
	for batch in box_batches.values():
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		instances.mesh = mesh
		instances.instance_count = batch.transforms.size()
		for i in range(instances.instance_count):
			instances.set_instance_transform(i, batch.transforms[i])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = instances
		var material := StandardMaterial3D.new()
		material.albedo_color = batch.color
		material.roughness = 0.7
		if batch.glow > 0:
			material.emission_enabled = true
			material.emission = batch.color
			material.emission_energy_multiplier = batch.glow
		visual.material_override = material
		add_child(visual)
	box_batches.clear()

func height_at(_x: float, _z: float) -> float:
	return 0.0
