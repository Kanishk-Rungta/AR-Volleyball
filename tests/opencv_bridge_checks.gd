extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var demo = load("res://scenes/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	assert(not demo.session.active and demo.session.info == "Offline")
	demo.set_process(false)
	demo.player.set_physics_process(false)
	demo.opencv.toggle()
	assert(demo.opencv.enabled)
	var commands := PacketPeerUDP.new()
	assert(commands.bind(4244, "127.0.0.1") == OK)
	demo.opencv.calibrate()
	await create_timer(0.06).timeout
	assert(commands.get_available_packet_count() > 0)
	assert(commands.get_packet().get_string_from_utf8() == "center")
	commands.close()
	var video_sender := PacketPeerUDP.new()
	video_sender.set_dest_address("127.0.0.1", 4243)
	var image := Image.create(32, 24, false, Image.FORMAT_RGB8)
	image.fill(Color("35b8ac"))
	video_sender.put_packet(image.save_jpg_to_buffer())
	await create_timer(0.06).timeout
	assert(demo.opencv.preview_texture != null and demo.opencv.preview_texture.get_width() == 32)
	video_sender.close()
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", 4242)
	var packet := {"source":"opencv", "protocol":2, "token":"test", "tracked":true, "calibrated":true, "x":0.7, "y":0, "hit_id":0}
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await create_timer(0.06).timeout
	assert(demo.opencv.direction.x > 0.6)
	packet.hit_id = 1
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await create_timer(0.06).timeout
	assert(demo.game.rally)
	var hit_time: int = demo.game.last_hit_time
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await create_timer(0.06).timeout
	assert(demo.game.last_hit_time == hit_time)
	packet.tracked = false
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await create_timer(0.06).timeout
	assert(demo.opencv.direction == Vector2.ZERO)
	sender.put_packet('{"source":"opencv","protocol":2,"x":"bad"}'.to_utf8_buffer())
	await create_timer(0.6).timeout
	assert(demo.opencv.direction == Vector2.ZERO)
	demo.opencv.toggle()
	sender.close()
	print("PASS: OpenCV movement, deduplicated hit, malformed/stale input, in-game preview decoding, calibration command")
	quit(0)
