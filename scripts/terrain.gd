extends Node3D
class_name HeightmapTerrain

const RESOLUTION := 65
const SIZE := 8.0
const HEIGHT := 1.65
var image: Image
var body: StaticBody3D

func _ready() -> void:
	var height_texture: Texture2D = load("res://assets/heightmap.png")
	image = height_texture.get_image()
	assert(image != null, "Heightmap asset is missing")
	image.resize(RESOLUTION, RESOLUTION, Image.INTERPOLATE_BILINEAR)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(RESOLUTION - 1):
		for x in range(RESOLUTION - 1):
			for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var px: int = x + offset.x
				var pz: int = z + offset.y
				var h := image.get_pixel(px, pz).r * HEIGHT
				surface.set_uv(Vector2(px, pz) / float(RESOLUTION - 1))
				surface.set_color(Color("426d53").lerp(Color("a4c781"), h / HEIGHT))
				surface.add_vertex(Vector3(float(px) / (RESOLUTION - 1) * SIZE - SIZE / 2, h, float(pz) / (RESOLUTION - 1) * SIZE - SIZE / 2))
	surface.generate_normals()
	surface.index()
	var mesh := surface.commit()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	visual.material_override = material
	add_child(visual)
	body = StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)
	# Island plinth makes the terrain read as a tabletop model.
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, 0.22, SIZE)
	base.mesh = box
	base.position.y = -0.12
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color("213b40")
	base.material_override = base_material
	add_child(base)
	for i in range(24):
		var x := sin(i * 7.12) * 3.6
		var z := cos(i * 3.71) * 3.6
		if Vector2(x, z).length() < 1.2:
			continue
		var tree := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.18
		cone.height = 0.65
		cone.radial_segments = 7
		tree.mesh = cone
		tree.position = Vector3(x, height_at(x, z) + 0.325, z)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("1b5549")
		tree.material_override = mat
		add_child(tree)

func height_at(x: float, z: float) -> float:
	var u := clampf((x / SIZE + 0.5) * (RESOLUTION - 1), 0, RESOLUTION - 1.001)
	var v := clampf((z / SIZE + 0.5) * (RESOLUTION - 1), 0, RESOLUTION - 1.001)
	var ix := int(u)
	var iz := int(v)
	# Match the two triangles in each cell, rather than bilinear interpolation.
	var a := image.get_pixel(ix, iz).r
	var b := image.get_pixel(ix + 1, iz).r
	var c := image.get_pixel(ix, iz + 1).r
	var d := image.get_pixel(ix + 1, iz + 1).r
	var fx := u - ix
	var fz := v - iz
	if fx + fz <= 1.0:
		return (a + (b - a) * fx + (c - a) * fz) * HEIGHT
	return (d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz)) * HEIGHT
