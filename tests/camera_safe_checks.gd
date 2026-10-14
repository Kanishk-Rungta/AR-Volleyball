extends SceneTree

class CameraFixture extends RefCounted:
	var id := 0
	var preview_id := 1
	var jpeg_calls := 0
	var yuv_calls := 0
	var jpeg: PackedByteArray
	func getFrame() -> String:
		id += 1
		return JSON.stringify({"id":id, "status":"Safe preview test", "tracking":true, "pose":[0,0,0,0,0,0,1], "projection":[1,0,0,0,0,1,0,0,0,0,-1,-1,0,0,-0.04,0], "jpeg_id":id, "preview_id":preview_id, "uv":[0,0,1,0,0,1,1,1], "hand":[]})
	func getCameraJpeg() -> PackedByteArray:
		jpeg_calls += 1
		return jpeg
	func getCameraYuv() -> PackedByteArray:
		yuv_calls += 1
		return PackedByteArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var demo = load("res://scenes/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	demo.effect.enabled = false
	demo.camera_material.shader = load("res://shaders/camera_compat.gdshader")
	var fixture := CameraFixture.new()
	demo.plugin = fixture
	demo._process(0.016)
	assert(demo.camera_texture == null, "Empty startup preview must wait without decoding/log-spam")
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	fixture.jpeg = image.save_jpg_to_buffer(0.95)
	fixture.preview_id += 1
	demo._process(0.016)
	assert(demo.camera_texture != null and fixture.jpeg_calls == 2 and fixture.yuv_calls == 0)
	assert(demo.camera_texture.get_format() == Image.FORMAT_RGB8)
	var texture_id: int = demo.camera_texture.get_instance_id()
	demo._process(0.016)
	assert(fixture.jpeg_calls == 2, "Do not decode again when only AR tracking changed")
	fixture.preview_id += 1
	demo._process(0.016)
	assert(fixture.jpeg_calls == 3 and demo.camera_texture.get_instance_id() == texture_id)
	if RenderingServer.get_rendering_device() != null:
		for child in demo.get_children():
			if child is CanvasLayer and child.layer >= 0: child.visible = false
		for i in range(10): await process_frame
		await RenderingServer.frame_post_draw
		var output := root.get_texture().get_image()
		var pixel := output.get_pixel(output.get_width()/2, output.get_height()/2)
		assert(pixel.r > 0.7 and pixel.g < 0.2 and pixel.b < 0.2, "Safe RGB preview must be visible independently of AR tracking")
		print("PASS: compatible RGB preview renders expected camera sample")
	print("PASS: safe camera selects JPEG, ignores raw GPU path, uses preview IDs and reuses texture")
	demo.queue_free()
	await process_frame
	quit(0)
