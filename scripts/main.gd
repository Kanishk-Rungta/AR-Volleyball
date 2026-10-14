extends Node3D

var game: Node3D
var score_label: Label
var rally_label: Label
var team_label: Label
var webcam_preview: TextureRect
var session: Node
var opencv: Node
var network_status: Label
var cv_status: Label
var island: Node3D
var terrain: HeightmapTerrain
var player: TerrainPlayer
var camera: Camera3D
var plugin: Object
var status: Label
var hand_status: Label
var animation_status: Label
var camera_view: TextureRect
var camera_material: ShaderMaterial
var overlay: Control
var effect: IslandCompositor
var environment: Environment
var placed := false
var approximate_placement := false
var ar_active := false
var touch_direction := Vector2.ZERO
var held_directions: Dictionary = {}
var touch_running := false
var phone_fist_armed := false
var phone_fist_samples := 0
var phone_open_samples := 0
var last_gesture_sample := -1
var last_hand_time := 0
var last_frame := -1
var last_tracking_frame_time := 0
var last_jpeg := -1
var camera_texture: ImageTexture
var yuv_textures: Array[ImageTexture] = []
var phone_hands_enabled := false
var camera_safe_preview := true
var camera_status: Label
var placement_button: Button
var frame_data: Dictionary = {}
var orbit := 0.0
var clock_time := 0.0

func _ready() -> void:
	_build_world()
	session = load("res://scripts/session.gd").new()
	session.name = "Session"
	session.demo = self
	add_child(session)
	opencv = load("res://scripts/opencv_bridge.gd").new()
	opencv.session = session
	add_child(opencv)
	_build_ui()
	if "--opencv" in OS.get_cmdline_user_args() and OS.get_name() != "Android":
		opencv.toggle()
	if Engine.has_singleton("PocketAR"):
		plugin = Engine.get_singleton("PocketAR")
		print("AR bridge: JNI method reflection getCameraYuv=", plugin.has_method("getCameraYuv"), "; using direct packaged API calls")
		camera_material.shader = load("res://shaders/camera_compat.gdshader")
		var dimensions := DisplayServer.window_get_size()
		plugin.startSession(dimensions.x, dimensions.y)
		get_viewport().size_changed.connect(_update_ar_display_geometry)
		get_viewport().scaling_3d_scale = 0.6
		effect.enabled = false
		status.text = "Starting camera and ARCore…"
		island.visible = false
		overlay.show_reticle = true
	else:
		status.text = "DESKTOP PREVIEW · phone AR requires Android APK"

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101f30")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9d6ed")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	var compositor := Compositor.new()
	effect = IslandCompositor.new()
	compositor.compositor_effects = [effect]
	environment_node.compositor = compositor
	add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 1.7
	light.shadow_enabled = OS.get_name() != "Android"
	add_child(light)
	camera = Camera3D.new()
	camera.near = 0.02
	camera.far = 100
	camera.fov = 48
	add_child(camera)
	camera.current = true
	island = Node3D.new()
	island.name = "AnchoredIsland"
	add_child(island)
	terrain = load("res://scripts/volleyball_court.gd").new()
	island.add_child(terrain)
	player = TerrainPlayer.new()
	player.terrain = terrain
	island.add_child(player)
	player.position = Vector3(-0.8, 0, 2.4)
	player.set_style(1, 1)
	game = load("res://scripts/volleyball.gd").new()
	game.demo = self
	island.add_child(game)
	_set_preview_camera()

func _set_preview_camera() -> void:
	camera.position = Vector3(sin(orbit) * 10.8, 9.8, cos(orbit) * 10.8)
	camera.look_at(Vector3(0, 0.5, 0))

func _build_ui() -> void:
	var background_layer := CanvasLayer.new()
	background_layer.layer = -1
	add_child(background_layer)
	camera_view = TextureRect.new()
	camera_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	camera_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	camera_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camera_material = ShaderMaterial.new()
	camera_material.shader = load("res://shaders/camera.gdshader")
	camera_view.material = camera_material
	background_layer.add_child(camera_view)
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	overlay = load("res://scripts/hand_overlay.gd").new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("e9f3ff"))
	theme.set_color("font_color", "Button", Color("e9f3ff"))
	theme.set_stylebox("normal", "Button", _style(Color("223c54"), 10))
	theme.set_stylebox("hover", "Button", _style(Color("31566c"), 10))
	theme.set_stylebox("pressed", "Button", _style(Color("287b80"), 10))
	theme.set_stylebox("panel", "PanelContainer", _style(Color(0.035, 0.075, 0.13, 0.94), 16))
	theme.set_stylebox("normal", "LineEdit", _style(Color("192e44"), 8))
	root.theme = theme
	var header := PanelContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 22
	header.offset_right = -22
	header.offset_top = 18
	header.offset_bottom = 106
	root.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 32)
	header.add_child(header_row)
	var branding := VBoxContainer.new()
	branding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(branding)
	_label(branding, "N E O N  /  V O L L E Y", 28)
	var tag := _label(branding, "TABLETOP ARENA   /   AR + HANDS + MULTIPLAYER", 12)
	tag.modulate = Color("74e0cf")
	var scoreboard := VBoxContainer.new()
	scoreboard.custom_minimum_size.x = 360
	header_row.add_child(scoreboard)
	score_label = _label(scoreboard, "TEAL   00  :  00   CORAL", 26)
	score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team_label = _label(scoreboard, "PRACTICE / FIRST TO 7", 12)
	team_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var top_actions := VBoxContainer.new()
	header_row.add_child(top_actions)
	placement_button = _button(top_actions, "Place court", _place)
	if OS.get_name() == "Android":
		_button(top_actions, "Place without scan", _place_approximately)
	var status_panel := VBoxContainer.new()
	status_panel.position = Vector2(32, 122)
	status_panel.size.x = 460
	root.add_child(status_panel)
	status = _label(status_panel, "Practice arena / your opponent is ready", 14)
	hand_status = _label(status_panel, "PHONE HANDS / close fist to hit", 13)
	animation_status = _label(status_panel, "AVATAR / Idle", 13)
	if OS.get_name() == "Android":
		camera_status = _label(status_panel, "Camera / starting color preview", 13)
	webcam_preview = TextureRect.new()
	webcam_preview.position = Vector2(32, 195)
	webcam_preview.size = Vector2(224, 168)
	webcam_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	webcam_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	webcam_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(webcam_preview)
	# Compact movement pad in the lower left, leaving the court visible.
	var move_panel := PanelContainer.new()
	move_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	move_panel.offset_left = 22
	move_panel.offset_right = 210
	move_panel.offset_top = -245
	move_panel.offset_bottom = -48
	root.add_child(move_panel)
	var move_column := VBoxContainer.new()
	move_panel.add_child(move_column)
	_label(move_column, "MOVE / WASD", 12)
	var pad := GridContainer.new()
	pad.columns = 3
	move_column.add_child(pad)
	for item in [["NW", Vector2(-1,-1)], ["N", Vector2(0,-1)], ["NE", Vector2(1,-1)], ["W", Vector2(-1,0)], ["STOP", Vector2.ZERO], ["E", Vector2(1,0)], ["SW", Vector2(-1,1)], ["S", Vector2(0,1)], ["SE", Vector2(1,1)]]:
		var button := _button(pad, item[0], func(): pass)
		button.custom_minimum_size = Vector2(48, 40)
		var key: String = item[0]
		var value: Vector2 = item[1]
		button.button_down.connect(func(): held_directions[key] = value)
		button.button_up.connect(func(): held_directions.erase(key))
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	center.offset_left = -230
	center.offset_right = 180
	center.offset_top = -173
	center.offset_bottom = -50
	root.add_child(center)
	rally_label = _label(center, "Your serve. HIT to start.", 18)
	rally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(actions)
	var hit_button := _button(actions, "HIT / SERVE [F]", func(): session.action("hit"))
	hit_button.add_theme_stylebox_override("normal", _style(Color("207b79"), 12))
	_button(actions, "JUMP [Space]", func(): session.action("jump"))
	var run := _button(actions, "RUN", func(): pass)
	run.button_down.connect(func(): touch_running = true)
	run.button_up.connect(func(): touch_running = false)
	var hint := _label(center, "Phone: touch to move / Fist: hit" if OS.get_name() == "Android" else "Open palm: move / Fist: hit / C: center hand", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Lobby and player kit stay grouped in one compact card.
	var lobby_panel := PanelContainer.new()
	lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	lobby_panel.offset_left = -338
	lobby_panel.offset_right = -22
	lobby_panel.offset_top = -355
	lobby_panel.offset_bottom = -48
	root.add_child(lobby_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	lobby_panel.add_child(column)
	_label(column, "PLAY TOGETHER / LAN", 13)
	var lobby := HBoxContainer.new()
	column.add_child(lobby)
	var address := LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Host LAN IP"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby.add_child(address)
	var lobby_buttons := HBoxContainer.new()
	column.add_child(lobby_buttons)
	_button(lobby_buttons, "Host", func(): session.host())
	_button(lobby_buttons, "Join", func(): session.join(address.text))
	_button(lobby_buttons, "Leave", func(): session.stop())
	network_status = _label(column, "Solo practice / AI opponent", 12)
	var gear := HBoxContainer.new()
	column.add_child(gear)
	_button(gear, "Kit", func(): session.action("color", player.color_index + 1))
	_button(gear, "Size", func(): session.action("size", player.size_index + 1))
	_button(gear, "Wave", func(): session.action("wave"))
	var extras := HBoxContainer.new()
	column.add_child(extras)
	_button(extras, "New match", func(): session.action("new_match"))
	_button(extras, "Effects", func(): effect.enabled = not effect.enabled)
	_button(extras, "Heightmap", func(): $HeightmapPanel.visible = not $HeightmapPanel.visible)
	var tracking := HBoxContainer.new()
	column.add_child(tracking)
	if OS.get_name() != "Android":
		_button(tracking, "Hands on/off", func(): opencv.toggle())
		_button(tracking, "Center [C]", func(): opencv.calibrate())
	else:
		var hands_button := _button(tracking, "Hand hits: OFF", func(): pass)
		hands_button.pressed.connect(func():
			phone_hands_enabled = not phone_hands_enabled
			if plugin != null:
				plugin.setHandTrackingEnabled(phone_hands_enabled)
			hands_button.text = "Hand hits: ON" if phone_hands_enabled else "Hand hits: OFF"
			_clear_hand())
		var preview_button := _button(tracking, "Camera: Safe", func(): pass)
		preview_button.pressed.connect(func():
			camera_safe_preview = not camera_safe_preview
			if plugin != null:
				plugin.setSafePreviewEnabled(camera_safe_preview)
			camera_material.shader = load("res://shaders/camera_compat.gdshader" if camera_safe_preview else "res://shaders/camera.gdshader")
			last_jpeg = -1
			camera_texture = null
			camera_view.texture = null
			preview_button.text = "Camera: Safe" if camera_safe_preview else "Camera: Fast")
	cv_status = _label(column, "Hands off / keyboard and touch available", 12)
	var footer := Label.new()
	footer.text = "FIRST TO 7  /  STAY ON YOUR HALF  /  GET UNDER THE BALL, THEN HIT"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -30
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 12)
	footer.modulate = Color("9bb5cd")
	root.add_child(footer)
	var map_layer := CanvasLayer.new()
	map_layer.name = "HeightmapPanel"
	map_layer.layer = 3
	map_layer.visible = false
	add_child(map_layer)
	var map_panel := PanelContainer.new()
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	map_panel.offset_left = -180
	map_panel.offset_right = 180
	map_panel.offset_top = -220
	map_panel.offset_bottom = 220
	map_panel.theme = theme
	map_layer.add_child(map_panel)
	var map_column := VBoxContainer.new()
	map_panel.add_child(map_column)
	_label(map_column, "TERRAIN LAB / original heightmap", 16)
	_label(map_column, "The arena uses a flat competition surface.", 12)
	var map := TextureRect.new()
	map.texture = load("res://assets/heightmap.png")
	map.custom_minimum_size = Vector2(320, 320)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_column.add_child(map)
	_button(map_column, "Back to court", func(): map_layer.visible = false)

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_color = Color(0.4, 0.7, 0.8, 0.15)
	style.set_border_width_all(1)
	return style

func _label(parent: Node, text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text_value: String, action: Callable) -> Button:
	var button := Button.new()
	# Gameplay owns arrows and Space; clicking UI must not capture those keys.
	button.focus_mode = Control.FOCUS_NONE
	button.text = text_value
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(func():
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
		action.call())
	parent.add_child(button)
	return button

func _place() -> void:
	if plugin == null:
		session.action("reset")
		return
	if approximate_placement:
		placed = false
		island.visible = false
	approximate_placement = false
	if bool(frame_data.get("pending_placement", false)):
		plugin.cancelPlacement()
		return
	plugin.placeAnchor(0.5, 0.5)
	placement_button.text = "Finding surface..."
	overlay.show_reticle = true
	overlay.queue_redraw()

func _place_approximately() -> void:
	if plugin == null or not frame_data.has("pose"):
		return
	plugin.cancelPlacement()
	approximate_placement = true
	placed = true
	# A horizontal court near the aimed-at point; no detected plane is required.
	var view_pose := _pose(frame_data.pose)
	island.transform = Transform3D(Basis.IDENTITY, view_pose.origin - view_pose.basis.z * 1.2 + Vector3.DOWN * 0.25)
	island.scale = Vector3.ONE * 0.09
	island.visible = true
	overlay.show_reticle = false
	overlay.queue_redraw()

func _process(delta: float) -> void:
	clock_time += delta
	score_label.text = "TEAL   %02d  :  %02d   CORAL" % [game.scores[0], game.scores[1]]
	team_label.text = ("PRACTICE vs AI" if game.training else "LAN MATCH") + (" / YOU: TEAL" if player.court_side == 1 else " / YOU: CORAL")
	rally_label.text = game.message
	webcam_preview.visible = opencv.enabled
	webcam_preview.texture = opencv.preview_texture
	touch_direction = Vector2.ZERO
	for value in held_directions.values():
		touch_direction += value
	var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if get_viewport().gui_get_focus_owner() is LineEdit:
		keyboard = Vector2.ZERO
	player.direction = (keyboard + touch_direction + opencv.direction).limit_length()
	if plugin != null and (not placed or not island.visible):
		player.direction = Vector2.ZERO
	session.submit(player.direction, touch_running or Input.is_physical_key_pressed(KEY_SHIFT))
	network_status.text = session.info if session.active else "Solo practice / AI opponent"
	cv_status.text = opencv.info if plugin == null else "Fist hits enabled / touch buttons move your avatar" if phone_hands_enabled else "Touch play / enable Hand hits after placement"
	player.running = touch_running or Input.is_physical_key_pressed(KEY_SHIFT)
	animation_status.text = "PLAYER · %s    |    %.0f FPS" % [player.state, Engine.get_frames_per_second()]
	if plugin == null:
		hand_status.text = "WEBCAM / open palm: move, fist: hit" if opencv.enabled else "KEYBOARD / F: serve-hit, Space: jump"
		return
	var parsed: Variant = JSON.parse_string(plugin.getFrame())
	if not parsed is Dictionary:
		island.visible = false
		_clear_hand()
		return
	frame_data = parsed
	if camera_status != null:
		var preview_error := str(frame_data.get("preview_error", ""))
		camera_status.text = preview_error if not preview_error.is_empty() else "Camera / receiving color preview" if camera_texture != null else "Camera / waiting for image (%d bytes)" % int(frame_data.get("preview_bytes", 0))
	status.text = str(frame_data.get("status", "Waiting for ARCore"))
	if approximate_placement:
		status.text = "Approximate court / may drift; Move court to rescan"
	overlay.surface_ready = bool(frame_data.get("can_place", false))
	var pending := bool(frame_data.get("pending_placement", false))
	placement_button.text = "Cancel placement" if pending else "Move court" if placed else "Place court"
	if int(frame_data.get("camera_age_ms", 0)) > 400:
		island.visible = false
		camera_view.visible = false
		status.text = "Waiting for fresh camera / hold phone steady"
		_clear_hand()
		return
	camera_view.visible = true
	var frame_id := int(frame_data.get("id", -1))
	if frame_id < 0:
		island.visible = false
		ar_active = false
		_clear_hand()
		return
	if frame_id == last_frame:
		if Time.get_ticks_msec() - last_tracking_frame_time > 1000:
			island.visible = false
			ar_active = false
			status.text = "Camera paused / move phone gently or reopen the app"
		if Time.get_ticks_msec() - last_hand_time > 600:
			_clear_hand()
		return
	last_frame = frame_id
	last_tracking_frame_time = Time.get_ticks_msec()
	if frame_data.has("pose"):
		ar_active = true
		# Render negative CanvasLayers as the 3D background so the camera feed
		# cannot cover the virtual objects in the Mobile renderer.
		environment.background_mode = Environment.BG_CANVAS
		environment.background_canvas_max_layer = -1
		camera.transform = _pose(frame_data.pose)
		var projection: Array = frame_data.projection
		# ARCore's display-oriented projection includes crop and camera intrinsics.
		camera.set_frustum(2.0 * camera.near / float(projection[5]), Vector2(float(projection[8]) * camera.near / float(projection[0]), float(projection[9]) * camera.near / float(projection[5])), camera.near, camera.far)
	if approximate_placement:
		island.visible = true
		overlay.show_reticle = false
	elif frame_data.has("anchor"):
		placed = true
		island.visible = bool(frame_data.get("tracking", false)) and bool(frame_data.get("anchor_tracking", false))
		island.transform = _pose(frame_data.anchor)
		island.scale = Vector3.ONE * 0.09
		overlay.show_reticle = pending
	elif not placed:
		island.visible = false
		overlay.show_reticle = true
	overlay.queue_redraw()
	var jpeg_id := int(frame_data.get("preview_id", frame_data.get("jpeg_id", -1))) if camera_safe_preview else int(frame_data.get("jpeg_id", -1))
	if jpeg_id != last_jpeg and jpeg_id >= 0:
		if not camera_safe_preview:
			if _upload_camera_yuv(plugin.getCameraYuv()):
				last_jpeg = jpeg_id
		else:
			var bytes: PackedByteArray = plugin.getCameraJpeg()
			var image := Image.new()
			if not bytes.is_empty() and image.load_jpg_from_buffer(bytes) == OK:
				if camera_texture == null:
					camera_texture = ImageTexture.create_from_image(image)
					camera_view.texture = camera_texture
				elif image.get_size() == Vector2i(camera_texture.get_width(), camera_texture.get_height()) and image.get_format() == camera_texture.get_format():
					camera_texture.update(image)
				else:
					camera_texture.set_image(image)
				last_jpeg = jpeg_id
	if frame_data.has("uv"):
		var uv: Array = frame_data.uv
		for i in range(4):
			camera_material.set_shader_parameter(["top_left", "top_right", "bottom_left", "bottom_right"][i], Vector2(float(uv[i*2]), float(uv[i*2+1])))
	var hand: Array = frame_data.get("hand", [])
	if hand.size() == 21:
		last_hand_time = Time.get_ticks_msec()
		overlay.landmarks = hand
		var extended := _phone_extended_fingers(hand)
		var fist := extended <= 1
		overlay.pinched = fist
		var sample_id := int(frame_data.get("hand_id", frame_data.get("jpeg_id", frame_id)))
		if sample_id != last_gesture_sample:
			last_gesture_sample = sample_id
			phone_open_samples = phone_open_samples + 1 if extended >= 3 else 0
			phone_fist_samples = phone_fist_samples + 1 if fist else 0
			if phone_open_samples >= 2:
				phone_fist_armed = true
			if phone_fist_samples >= 2 and phone_fist_armed and placed and island.visible:
				session.action("hit")
				phone_fist_armed = false
		hand_status.text = "HAND / FIST: HIT - reopen to rearm" if fist else "HAND / open palm, then close fist to hit"
		overlay.queue_redraw()
	else:
		_clear_hand()
	var hand_error := str(frame_data.get("hand_error", ""))
	if not hand_error.is_empty():
		hand_status.text = hand_error

func _upload_camera_yuv(packet: PackedByteArray) -> bool:
	if packet.size() < 8:
		return false
	var w := int(packet.decode_u32(0))
	var h := int(packet.decode_u32(4))
	if w < 2 or h < 2 or w > 1280 or h > 1280 or w % 2 != 0 or h % 2 != 0:
		return false
	var y_size := w * h
	var uv_size: int = y_size / 4
	if packet.size() != 8 + y_size + uv_size * 2:
		return false
	var offset := 8
	for index in range(3):
		var width: int = w if index == 0 else w / 2
		var height: int = h if index == 0 else h / 2
		var length := y_size if index == 0 else uv_size
		var image := Image.create_from_data(width, height, false, Image.FORMAT_R8, packet.slice(offset, offset + length))
		if yuv_textures.size() <= index:
			yuv_textures.append(ImageTexture.create_from_image(image))
		elif yuv_textures[index].get_width() == width and yuv_textures[index].get_height() == height:
			yuv_textures[index].update(image)
		else:
			yuv_textures[index].set_image(image)
		offset += length
		camera_material.set_shader_parameter(["y_plane", "u_plane", "v_plane"][index], yuv_textures[index])
	camera_texture = yuv_textures[0]
	camera_view.texture = camera_texture
	camera_material.set_shader_parameter("use_yuv", true)
	return true

func _clear_hand() -> void:
	overlay.landmarks = []
	overlay.queue_redraw()
	phone_fist_armed = false
	phone_fist_samples = 0
	phone_open_samples = 0
	last_gesture_sample = -1
	hand_status.text = "HAND · show palm to rear camera"

func _phone_extended_fingers(hand: Array) -> int:
	var dimensions := get_viewport().get_visible_rect().size
	var wrist := Vector2(float(hand[0][0]), float(hand[0][1])) * dimensions
	var count := 0
	for pair in [[8, 6], [12, 10], [16, 14], [20, 18]]:
		var tip := Vector2(float(hand[pair[0]][0]), float(hand[pair[0]][1])) * dimensions
		var joint := Vector2(float(hand[pair[1]][0]), float(hand[pair[1]][1])) * dimensions
		if tip.distance_to(wrist) > joint.distance_to(wrist) * 1.12:
			count += 1
	return count

func _pose(values: Array) -> Transform3D:
	var q := Quaternion(float(values[3]), float(values[4]), float(values[5]), float(values[6]))
	return Transform3D(Basis(q), Vector3(float(values[0]), float(values[1]), float(values[2])))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			session.action("jump")
		elif event.physical_keycode == KEY_F:
			session.action("hit")
		elif event.physical_keycode == KEY_C:
			opencv.calibrate()
		elif event.physical_keycode == KEY_E:
			effect.enabled = not effect.enabled

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and plugin != null:
		_update_ar_display_geometry()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held_directions.clear()
		touch_running = false
		if player != null:
			player.running = false
		if plugin != null and island != null:
			island.visible = false
			_clear_hand()

func _update_ar_display_geometry() -> void:
	if plugin != null and OS.get_name() == "Android":
		var dimensions := DisplayServer.window_get_size()
		plugin.updateDisplayGeometry(dimensions.x, dimensions.y)
