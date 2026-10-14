extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var demo = load("res://scenes/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	var terrain: HeightmapTerrain = demo.terrain
	var player: TerrainPlayer = demo.player
	assert(terrain.image.get_width() == 65)
	assert(terrain.body.get_child(0).shape is ConcavePolygonShape3D)
	for title in ["Idle", "Walk", "Run", "Jump", "Wave"]:
		assert(player.animation.has_animation(title), "Missing animation: " + title)
	# Test the behaviors independently of frame rate or keyboard state.
	demo.set_process(false)
	player.set_physics_process(false)
	player.direction = Vector2(1, 0)
	var start := player.position.x
	for i in range(60):
		player._physics_process(1.0 / 60)
	assert(player.position.x > start + 0.9)
	assert(player.state == "Walk")
	player.running = true
	player._physics_process(1.0 / 60)
	assert(player.state == "Run")
	player.direction = Vector2.ZERO
	player.jump_requested = true
	player._physics_process(1.0 / 60)
	assert(not player.grounded and player.state == "Jump")
	var peak := player.position.y
	for i in range(90):
		player._physics_process(1.0 / 60)
		peak = maxf(peak, player.position.y)
	assert(player.grounded and player.state == "Idle")
	assert(peak > terrain.height_at(player.position.x, player.position.z) + 0.4)
	player.wave()
	player._physics_process(1.0 / 60)
	assert(player.state == "Wave")
	for i in range(150):
		player._physics_process(1.0 / 60)
	assert(player.state == "Idle")
	player.direction = Vector2(1, 1).normalized()
	for i in range(500):
		player._physics_process(1.0 / 60)
	assert(player.position.x <= 3.70001 and player.position.z <= 3.70001)
	assert(is_equal_approx(player.position.y, terrain.height_at(player.position.x, player.position.z)))
	# Verify calibrated frustum conversion using a non-centered projection.
	var near_plane := 0.02
	var m00 := 1.5
	var m11 := m00 * root.get_visible_rect().size.aspect()
	demo.camera.set_frustum(2 * near_plane / m11, Vector2(0.08 * near_plane / m00, -0.06 * near_plane / m11), near_plane, 100)
	var projection: Projection = demo.camera.get_camera_projection()
	assert(absf(projection.x.x - m00) < 0.001)
	assert(absf(projection.y.y - m11) < 0.001)
	assert(absf(projection.z.x - 0.08) < 0.001)
	assert(absf(projection.z.y + 0.06) < 0.001)
	print("PASS: heightmap, collider, five animations, walk/run/jump/landing, bounds, AR frustum")
	demo.queue_free()
	await process_frame
	quit(0)
