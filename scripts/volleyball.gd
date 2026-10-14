extends Node3D
## Arcade volleyball: server owns ball, score, rally and training opponent.
var demo: Node
var ball: MeshInstance3D
var shadow: MeshInstance3D
var landing: MeshInstance3D
var sound: AudioStreamPlayer
var bot: TerrainPlayer
var velocity := Vector3.ZERO
var ball_position := Vector3(-0.8, 1.2, 2.4)
var scores: Array = [0, 0]
var serving_side := 1
var last_touch := 0
var rally := false
var winner := 0
var message := "Your serve. Press HIT / F or close fist."
var point_wait := 0.0
var last_hit_time := -10000
var training := true
var trail: Array[MeshInstance3D] = []
var trail_clock := 0.0

func _ready() -> void:
	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("fff1bf")
	material.emission_enabled = true
	material.emission = Color("e9aa4c")
	material.emission_energy_multiplier = 0.2
	ball.material_override = material
	add_child(ball)
	# Contrasting bands make the ball read as a volleyball.
	for axis in [0, 1]:
		var band := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.168
		torus.outer_radius = 0.183
		band.mesh = torus
		band.rotation_degrees.x = 90 if axis == 0 else 0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("324d79")
		band.material_override = mat
		ball.add_child(band)
	shadow = MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 0.22
	disk.bottom_radius = 0.22
	disk.height = 0.006
	shadow.mesh = disk
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.03, 0.12, 0.2, 0.45)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material_override = shadow_mat
	add_child(shadow)
	landing = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.4
	landing.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("ffd68c")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("ffd68c")
	landing.material_override = ring_mat
	add_child(landing)
	sound = AudioStreamPlayer.new()
	sound.volume_db = -16
	add_child(sound)
	bot = TerrainPlayer.new()
	bot.terrain = demo.terrain
	bot.court_side = -1
	add_child(bot)
	bot.position = Vector3(0.7, 0, -2.4)
	bot.set_style(2, 1)
	for i in range(8):
		var dot := MeshInstance3D.new()
		var dot_mesh := SphereMesh.new()
		dot_mesh.radius = 0.04 * (1 - i / 10.0)
		dot_mesh.height = dot_mesh.radius * 2
		dot.mesh = dot_mesh
		dot.material_override = material
		dot.visible = false
		add_child(dot)
		trail.append(dot)
	_render()

func authoritative() -> bool:
	return demo.session == null or not demo.session.active or multiplayer.is_server()

func reset_match() -> void:
	scores = [0, 0]
	winner = 0
	serving_side = 1
	rally = false
	last_touch = 0
	point_wait = 0
	message = "New match. Teal serves. First to 7."

func set_roster(count: int) -> void:
	training = count < 2
	bot.visible = training
	bot.set_physics_process(training and authoritative())
	if not training:
		bot.direction = Vector2.ZERO

func strike(avatar: TerrainPlayer) -> bool:
	if not authoritative() or winner != 0 or point_wait > 0:
		return false
	if demo.plugin != null and (not demo.placed or not demo.island.visible):
		return false
	var side := avatar.court_side
	if not rally:
		if side != serving_side:
			return false
		ball_position = avatar.position + Vector3(0, 1.25, -side * 0.35)
	elif side == last_touch or Vector2(avatar.position.x - ball_position.x, avatar.position.z - ball_position.z).length() > 1.5 or ball_position.y < 0.4 or ball_position.y > avatar.position.y + 2.6:
		return false
	if Time.get_ticks_msec() - last_hit_time < 300:
		return false
	last_hit_time = Time.get_ticks_msec()
	rally = true
	last_touch = side
	# Assist the trajectory so a beginner can clear the net without aiming in 3D.
	var target_x := clampf(avatar.position.x + avatar.direction.x * 1.8, -2.3, 2.3)
	var target_z := -side * 2.65
	var flight_time := 1.35
	velocity = Vector3((target_x - ball_position.x) / flight_time, (0.18 - ball_position.y + 0.5 * 7.0 * flight_time * flight_time) / flight_time, (target_z - ball_position.z) / flight_time)
	avatar.hit()
	_tone(520 if side == 1 else 390, 0.09)
	message = "TEAL attacks" if side == 1 else "CORAL attacks"
	return true

func award(side: int, reason: String) -> void:
	if not rally:
		return
	scores[0 if side == 1 else 1] += 1
	rally = false
	serving_side = side
	last_touch = 0
	point_wait = 1.6
	message = ("TEAL" if side == 1 else "CORAL") + " point / " + reason
	_tone(780, 0.18)
	if scores[0 if side == 1 else 1] >= 7:
		winner = side
		message = ("TEAL" if side == 1 else "CORAL") + " wins! Host: New match."

func _physics_process(delta: float) -> void:
	if not authoritative():
		return
	point_wait = maxf(0, point_wait - delta)
	if demo.plugin != null and (not demo.placed or not demo.island.visible):
		return
	if training and winner == 0:
		if rally:
			var destination := predicted_landing() if last_touch == 1 else Vector3(0.7, 0, -2.4)
			var target := Vector2(clampf(destination.x, -2.6, 2.6), clampf(destination.z, -3.5, -0.6))
			bot.direction = (target - Vector2(bot.position.x, bot.position.z)).limit_length()
		else:
			bot.direction = Vector2.ZERO
		bot.running = true
		if rally and last_touch == 1 and ball_position.z < -0.45 and velocity.y < 1.0:
			strike(bot)
		elif not rally and serving_side == -1 and point_wait <= 0:
			strike(bot)
	if not rally:
		if winner == 0:
			if point_wait <= 0:
				message = ("TEAL" if serving_side == 1 else "CORAL") + " serve / HIT or close fist to start"
			var server_avatar: TerrainPlayer = demo.player
			if training and serving_side == -1:
				server_avatar = bot
			elif demo.session != null:
				for avatar in demo.session.avatars.values():
					if avatar.court_side == serving_side:
						server_avatar = avatar
			ball_position = server_avatar.position + Vector3(0, 1.25, -serving_side * 0.35)
		_render()
		return
	# Small fixed substeps prevent tunneling through the net at low FPS.
	var steps := maxi(1, ceili(delta / (1.0 / 120)))
	var step := delta / steps
	for i in range(steps):
		var previous := ball_position
		velocity.y -= 7.0 * step
		ball_position += velocity * step
		if previous.z * ball_position.z <= 0 and absf(ball_position.x) < 3.2 and ball_position.y < 1.53:
			ball_position.z = signf(previous.z) * 0.2
			velocity.z *= -0.35
			velocity.y *= 0.4
			message = "NET! Recovering ball..."
		if ball_position.y <= 0.18:
			if absf(ball_position.x) > 3 or absf(ball_position.z) > 4:
				award(-last_touch, "out of bounds")
			else:
				award(-1 if ball_position.z > 0 else 1, "ball grounded")
			break
		if absf(ball_position.x) > 6 or absf(ball_position.z) > 7:
			award(-last_touch, "out of bounds")
			break
	_render()

func _render() -> void:
	ball.position = ball_position
	shadow.position = Vector3(ball_position.x, 0.03, ball_position.z)
	shadow.scale = Vector3.ONE * clampf(1 - ball_position.y * 0.1, 0.4, 1)
	ball.rotate_y(0.04)
	landing.visible = rally
	if rally:
		landing.position = predicted_landing()

func predicted_landing() -> Vector3:
	var time_to_floor := (velocity.y + sqrt(maxf(0, velocity.y * velocity.y + 14 * (ball_position.y - 0.18)))) / 7.0
	return Vector3(ball_position.x + velocity.x * time_to_floor, 0.035, ball_position.z + velocity.z * time_to_floor)

func _tone(frequency: float, duration: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var samples := int(22050 * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	for i in range(samples):
		var value := sin(TAU * frequency * i / 22050.0) * (1.0 - float(i) / samples) * 12000
		bytes.encode_s16(i * 2, int(value))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 22050
	audio.data = bytes
	sound.stream = audio
	sound.play()

func _exit_tree() -> void:
	if sound != null:
		sound.stop()
		sound.stream = null

func _process(delta: float) -> void:
	trail_clock += delta
	if trail_clock > 0.045:
		trail_clock = 0
		for i in range(trail.size() - 1, 0, -1):
			trail[i].position = trail[i - 1].position
			trail[i].visible = rally
		trail[0].position = ball_position
		trail[0].visible = rally

func state_packet() -> Array:
	return [ball_position, velocity, scores, serving_side, last_touch, rally, winner, message, training, bot.position, bot.state, bot.rig.rotation.y]

func apply_packet(data: Array) -> void:
	var old_score := int(scores[0]) + int(scores[1])
	var old_touch := last_touch
	ball_position = data[0]
	velocity = data[1]
	scores = data[2]
	serving_side = data[3]
	last_touch = data[4]
	rally = data[5]
	winner = data[6]
	message = data[7]
	training = data[8]
	bot.visible = training
	bot.set_physics_process(false)
	bot.position = data[9]
	if bot.state != data[10]:
		bot.state = data[10]
		bot.animation.play(bot.state, 0.1)
	bot.rig.rotation.y = data[11]
	if old_score != int(scores[0]) + int(scores[1]):
		_tone(780, 0.18)
	elif old_touch != last_touch and rally:
		_tone(520 if last_touch == 1 else 390, 0.09)
	_render()
