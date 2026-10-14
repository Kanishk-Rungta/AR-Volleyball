extends SceneTree

class TrackingFixture extends RefCounted:
	var id := 0
	var tracking := true
	var fist := false
	var hand_present := true
	var error_only := false
	var freeze_frames := false
	var last_placement := Vector2.ZERO
	var jpeg: PackedByteArray
	var pose: Array
	var projection: Array

	func getFrame() -> String:
		if error_only:
			return JSON.stringify({"status":"Test: AR startup/frame error"})
		if not freeze_frames:
			id += 1
		var points: Array = []
		if hand_present:
			for i in range(21):
				points.append([0.5, 0.7, 0.0])
			points[0] = [0.5, 0.85, 0.0]
			for base in [5, 9, 13, 17]:
				var x: float = 0.35 + (base - 5) * 0.03
				points[base] = [x, 0.65, 0.0]
				points[base + 1] = [x, 0.5, 0.0]
				points[base + 2] = [x, 0.35, 0.0]
				points[base + 3] = [0.5, 0.72, 0.0] if fist else [x, 0.2, 0.0]
		return JSON.stringify({"id": id, "jpeg_id": id, "status": "TEST INPUT · synthetic camera", "pose": pose, "projection": projection, "uv": [0,0,1,0,0,1,1,1], "anchor": [0,0,0,0,0,0,1], "anchor_tracking": tracking, "tracking": tracking, "hand": points})

	func getCameraJpeg() -> PackedByteArray:
		return jpeg

	func placeAnchor(x: float, y: float) -> void:
		last_placement = Vector2(x,y)
	func cancelPlacement() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var demo = load("res://scenes/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	demo.player.set_physics_process(false)
	var fixture := TrackingFixture.new()
	var camera: Camera3D = demo.camera
	var q := camera.quaternion
	var p := camera.position * 0.09
	fixture.pose = [p.x,p.y,p.z,q.x,q.y,q.z,q.w]
	var projection := camera.get_camera_projection()
	fixture.projection = []
	for column in [projection.x,projection.y,projection.z,projection.w]:
		for i in range(4): fixture.projection.append(column[i])
	var image := Image.create(64,64,false,Image.FORMAT_RGB8)
	image.fill(Color("704d50"))
	fixture.jpeg = image.save_jpg_to_buffer()
	demo.plugin = fixture
	assert(not demo.game.strike(demo.player), "Phone cannot serve before placing its AR court")
	demo._place()
	assert(fixture.last_placement == Vector2(0.5,0.5))
	demo._process(0.016)
	assert(demo.placed and demo.island.visible)
	assert(demo.environment.background_mode == Environment.BG_CANVAS)
	assert(is_equal_approx(demo.island.scale.x,0.09))
	assert(demo.camera_texture != null)
	assert(demo.overlay.landmarks.size() == 21)
	demo._process(0.016)
	fixture.fist = true
	demo._process(0.016)
	demo._process(0.016)
	assert(demo.game.rally and demo.game.last_touch == 1)
	var hit_time: int = demo.game.last_hit_time
	demo._process(0.016)
	assert(demo.game.last_hit_time == hit_time, "A held fist must not repeat")
	fixture.fist = false
	demo._process(0.016)
	demo._process(0.016)
	fixture.fist = true
	demo.game.reset_match()
	demo.game.last_hit_time = -10000
	demo._process(0.016)
	demo._process(0.016)
	assert(demo.game.rally, "Opening palm must rearm fist hit")
	fixture.tracking = false
	fixture.hand_present = false
	demo._process(0.016)
	assert(not demo.island.visible and demo.overlay.landmarks.is_empty())
	fixture.tracking = true
	demo._process(0.016)
	assert(demo.island.visible)
	fixture.tracking = false
	demo._process(0.016)
	demo._place_approximately()
	var approximate_position: Vector3 = demo.island.position
	demo._process(0.016)
	assert(demo.placed and demo.island.visible and demo.approximate_placement, "Manual placement must work without tracked planes")
	assert(demo.island.position.is_equal_approx(approximate_position), "Native anchor must not overwrite approximate placement")
	assert(not demo.overlay.show_reticle and "Approximate" in demo.status.text)
	demo._place()
	assert(not demo.approximate_placement and not demo.placed, "Rescan must leave approximate mode")
	fixture.tracking = true
	demo._process(0.016)
	fixture.error_only = true
	demo._process(0.016)
	assert(not demo.island.visible and not demo.ar_active, "Native status-only errors must hide stale AR content")
	fixture.error_only = false
	demo._process(0.016)
	assert(demo.island.visible)
	fixture.freeze_frames = true
	demo.last_tracking_frame_time = Time.get_ticks_msec() - 1200
	demo._process(0.016)
	assert(not demo.island.visible, "Frozen camera frames must hide stale AR content")
	fixture.freeze_frames = false
	demo._process(0.016)
	assert(demo.island.visible)
	if RenderingServer.get_rendering_device() != null:
		for i in range(5): await process_frame
		await RenderingServer.frame_post_draw
		var composed := root.get_texture().get_image()
		composed.save_png("res://build/synthetic-camera-check.png")
		var center := composed.get_pixel(composed.get_width()/2, composed.get_height()/2)
		assert(center.g > center.r, "Terrain must remain visible over the camera background")
		demo.effect.enabled = false
		for i in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var ungraded := root.get_texture().get_image()
		ungraded.save_png("res://build/synthetic-camera-no-effects.png")
		assert(composed.get_pixel(10,300) != ungraded.get_pixel(10,300), "Compositor toggle must change the rendered view")
	print("PASS: anchor, camera, AR scale, fist debounce, tracking/error/stale-frame loss and recovery")
	demo.queue_free()
	await process_frame
	quit()
