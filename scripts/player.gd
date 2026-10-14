extends CharacterBody3D
class_name TerrainPlayer

var direction := Vector2.ZERO
var running := false
var jump_requested := false
var terrain: HeightmapTerrain
var animation: AnimationPlayer
var rig: Node3D
var vertical_speed := 0.0
var grounded := true
var state := "Idle"
var wave_time := 0.0
var color_index := 0
var size_index := 1
var court_side := 1
var hit_time := 0.0

func set_style(color_value: int, size_value: int) -> void:
	color_index = clampi(color_value, 0, 3)
	size_index = clampi(size_value, 0, 2)
	if rig == null:
		return
	rig.scale = Vector3.ONE * [0.8, 1.0, 1.2][size_index]
	var torso := rig.get_node("Torso") as MeshInstance3D
	(torso.material_override as StandardMaterial3D).albedo_color = [Color("e8b55b"), Color("4ec9b0"), Color("dc719b"), Color("70a9ef")][color_index]

func _ready() -> void:
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	_part("Torso", Vector3(0, 0.62, 0), Vector3(0.34, 0.40, 0.22), Color("e8b55b"))
	_part("Head", Vector3(0, 0.99, 0), Vector3(0.29, 0.28, 0.27), Color("e6ece8"))
	_part("Visor", Vector3(0, 1.0, -0.145), Vector3(0.22, 0.10, 0.025), Color("42daca"))
	_limb("LeftArm", Vector3(-0.23, 0.78, 0), 0.31)
	_limb("RightArm", Vector3(0.23, 0.78, 0), 0.31)
	_limb("LeftLeg", Vector3(-0.105, 0.43, 0), 0.40)
	_limb("RightLeg", Vector3(0.105, 0.43, 0), 0.40)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.18
	capsule.height = 1.08
	shape.shape = capsule
	shape.position.y = 0.54
	add_child(shape)
	animation = AnimationPlayer.new()
	add_child(animation)
	var library := AnimationLibrary.new()
	for title in ["Idle", "Walk", "Run", "Jump", "Wave", "Hit"]:
		var anim := Animation.new()
		anim.length = 1.6 if title == "Idle" else 0.8
		anim.loop_mode = Animation.LOOP_NONE if title in ["Jump", "Hit"] else Animation.LOOP_LINEAR
		for limb in ["LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
			var amount := 0.04 if title == "Idle" else (0.9 if title == "Run" else 0.55)
			var sign_value := -1.0 if limb in ["LeftArm", "RightLeg"] else 1.0
			var track := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track, NodePath("Rig/" + limb + ":rotation:x"))
			for j in range(5):
				var value := sin(j * PI / 2.0) * amount * sign_value
				if title == "Jump":
					value = -0.9 if "Arm" in limb else 0.35
				if title == "Wave":
					value = -2.4 + sin(j * PI / 2) * 0.35 if limb == "RightArm" else 0.0
				if title == "Hit":
					value = -2.5 * sin(j * PI / 4) if "Arm" in limb else 0.1
				anim.track_insert_key(track, j * anim.length / 4.0, value)
		library.add_animation(title, anim)
	animation.add_animation_library("", library)
	animation.play("Idle")

func _part(title: String, pos: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = title
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mesh.material_override = mat
	(rig if parent == null else parent).add_child(mesh)

func _limb(title: String, pos: Vector3, length_value: float) -> void:
	var pivot := Node3D.new()
	pivot.name = title
	pivot.position = pos
	rig.add_child(pivot)
	_part("Mesh", Vector3(0, -length_value / 2, 0), Vector3(0.12, length_value, 0.13), Color("344d65"), pivot)

func _physics_process(delta: float) -> void:
	if terrain == null:
		return
	var speed := 5.0 if running else 3.0
	var move := Vector3(direction.x, 0, direction.y) * speed
	# Movement is in the island's local coordinates; parent can be an AR anchor.
	position.x = clampf(position.x + move.x * delta, -2.75, 2.75)
	position.z = clampf(position.z + move.z * delta, 0.5 if court_side == 1 else -3.7, 3.7 if court_side == 1 else -0.5)
	var floor_height := terrain.height_at(position.x, position.z)
	if grounded:
		position.y = floor_height
	if jump_requested and grounded:
		vertical_speed = 3.4
		grounded = false
	jump_requested = false
	vertical_speed -= 8.5 * delta
	position.y += vertical_speed * delta
	if position.y <= floor_height:
		position.y = floor_height
		vertical_speed = 0
		grounded = true
	if move.length() > 0.05:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-move.x, -move.z), delta * 12)
	var next := "Jump" if not grounded else ("Run" if running else "Walk") if move.length() > 0.05 else "Idle"
	if not grounded:
		next = "Jump"
	wave_time = maxf(0, wave_time - delta)
	hit_time = maxf(0, hit_time - delta)
	if wave_time > 0 and grounded and move.length() < 0.05:
		next = "Wave"
	if hit_time > 0:
		next = "Hit"
	if next != state:
		state = next
		animation.play(state, 0.15)

func wave() -> void:
	wave_time = 2.4

func hit() -> void:
	hit_time = 0.45
