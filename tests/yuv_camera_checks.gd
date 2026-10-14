extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var demo = load("res://scenes/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	var packet := PackedByteArray()
	packet.resize(32)
	packet.encode_u32(0, 4)
	packet.encode_u32(4, 4)
	for i in range(8, 24): packet[i] = 82
	for i in range(24, 28): packet[i] = 90
	for i in range(28, 32): packet[i] = 240
	assert(demo._upload_camera_yuv(packet))
	assert(demo.yuv_textures.size() == 3 and demo.camera_texture.get_width() == 4)
	assert(demo.camera_material.get_shader_parameter("use_yuv"))
	var texture_id: int = demo.camera_texture.get_instance_id()
	assert(demo._upload_camera_yuv(packet))
	assert(demo.camera_texture.get_instance_id() == texture_id, "Reuse camera textures rather than allocating every frame")
	assert(not demo._upload_camera_yuv(packet.slice(0, 20)))
	var odd := packet.duplicate()
	odd.encode_u32(0, 3)
	assert(not demo._upload_camera_yuv(odd))
	if RenderingServer.get_rendering_device() != null:
		demo.environment.background_mode = Environment.BG_CANVAS
		demo.environment.background_canvas_max_layer = -1
		demo.island.visible = false
		demo.effect.enabled = false
		for child in demo.get_children():
			if child is CanvasLayer and child.layer >= 0:
				child.visible = false
		for i in range(10): await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var pixel := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
		assert(pixel.r > 0.7 and pixel.g < 0.2 and pixel.b < 0.2, "GPU YUV conversion must render the expected red camera sample")
		print("PASS: rendered GPU YUV color conversion")
	print("PASS: raw camera packet validation, three planes, texture reuse, malformed packet rejection")
	demo.queue_free()
	await process_frame
	quit(0)
