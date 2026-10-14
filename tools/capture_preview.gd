extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var demo = load("res://scenes/main.tscn").instantiate()
	root.add_child(demo)
	await create_timer(2.0).timeout
	for i in range(15):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/desktop-preview.png")
	demo.effect.enabled = false
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/desktop-preview-no-effects.png")
	demo.queue_free()
	await process_frame
	quit()
