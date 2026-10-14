extends Node
var socket := PacketPeerUDP.new()
var enabled := false
var direction := Vector2.ZERO
var last_packet := 0
var previous_gesture := "none"
var info := "OpenCV off"
var session: Node
var video := PacketPeerUDP.new()
var command_socket := PacketPeerUDP.new()
var preview_texture: ImageTexture
var tracker_token := ""
var last_hit_id := 0
var last_preview_time := 0

func calibrate() -> void:
	if enabled:
		command_socket.set_dest_address("127.0.0.1", 4244)
		command_socket.put_packet("center".to_utf8_buffer())

func toggle() -> void:
	enabled = not enabled
	if enabled:
		var error := socket.bind(4242, "127.0.0.1")
		if error != OK:
			enabled = false
			info = "OpenCV bind failed: " + error_string(error)
		else:
			var video_error := video.bind(4243, "127.0.0.1", 262144)
			info = "Show palm, then Center [C]" if video_error == OK else "Hands ready / camera preview port busy"
			tracker_token = ""
	else:
		socket.close()
		video.close()
		preview_texture = null
		direction = Vector2.ZERO
		previous_gesture = "none"
		info = "OpenCV off"

func _process(_delta: float) -> void:
	if not enabled:
		return
	var latest := PackedByteArray()
	for i in range(mini(video.get_available_packet_count(), 20)):
		latest = video.get_packet()
	if not latest.is_empty() and latest.size() < 60000:
		var image := Image.new()
		if image.load_jpg_from_buffer(latest) == OK:
			last_preview_time = Time.get_ticks_msec()
			if preview_texture == null:
				preview_texture = ImageTexture.create_from_image(image)
			else:
				preview_texture.set_image(image)
	var count := 0
	while socket.get_available_packet_count() > 0 and count < 60:
		count += 1
		var bytes := socket.get_packet()
		if bytes.size() > 1024:
			continue
		var packet: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not packet is Dictionary or packet.get("source") != "opencv" or packet.get("protocol") != 2:
			continue
		var x: Variant = packet.get("x", 0)
		var y: Variant = packet.get("y", 0)
		if not (x is float or x is int) or not (y is float or y is int):
			continue
		var movement := Vector2(float(x), float(y))
		if not movement.is_finite():
			continue
		last_packet = Time.get_ticks_msec()
		var tracked: bool = packet.get("tracked", false) == true and packet.get("calibrated", false) == true
		direction = movement.limit_length() if tracked else Vector2.ZERO
		var token := str(packet.get("token", ""))
		var hit_id := int(packet.get("hit_id", 0))
		if token != tracker_token:
			tracker_token = token
			last_hit_id = hit_id
		if hit_id > last_hit_id and tracked:
			session.action("hit")
		last_hit_id = maxi(last_hit_id, hit_id)
		info = str(packet.get("status", "Tracking" if tracked else "Show palm / Center [C]"))
	if Time.get_ticks_msec() - last_packet > 500:
		direction = Vector2.ZERO
		previous_gesture = "none"
		info = "OpenCV: no fresh hand data"
	if Time.get_ticks_msec() - last_preview_time > 1000:
		preview_texture = null
