extends Node
## Server simulates every avatar; clients submit input, never positions.
const PORT := 7777
var demo: Node3D
var avatars: Dictionary = {}
var last_input: Dictionary = {}
var info := "Offline"
var elapsed := 0.0
var connecting_since := 0
var active := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_joined)
	multiplayer.peer_disconnected.connect(_left)
	multiplayer.connected_to_server.connect(func():
		connecting_since = 0
		info = "Connected to host"
		demo.player.set_physics_process(false))
	multiplayer.connection_failed.connect(func(): stop("Connection failed"))
	multiplayer.server_disconnected.connect(func(): stop("Host disconnected"))

func host() -> void:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 7)
	if error != OK:
		info = "Host failed: " + error_string(error)
		return
	multiplayer.multiplayer_peer = peer
	active = true
	avatars[1] = demo.player
	demo.player.court_side = 1
	demo.player.position = Vector3(-0.8, 0, 2.4)
	demo.game.reset_match()
	demo.game.set_roster(1)
	info = "Hosting UDP 7777"

func join(address: String) -> void:
	stop()
	if address.strip_edges().is_empty():
		info = "Enter host IP"
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), PORT)
	if error != OK:
		info = "Join failed: " + error_string(error)
		return
	multiplayer.multiplayer_peer = peer
	active = true
	connecting_since = Time.get_ticks_msec()
	info = "Connecting..."

func stop(message := "Offline") -> void:
	active = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	for avatar in avatars.values():
		if avatar != demo.player:
			avatar.queue_free()
	avatars.clear()
	last_input.clear()
	connecting_since = 0
	demo.player.set_physics_process(true)
	demo.player.court_side = 1
	demo.player.position = Vector3(-0.8, 0, 2.4)
	demo.player.vertical_speed = 0
	demo.player.grounded = true
	demo.player.jump_requested = false
	demo.player.direction = Vector2.ZERO
	demo.game.set_roster(1)
	demo.game.reset_match()
	info = message

func _spawn(id: int) -> TerrainPlayer:
	var avatar := TerrainPlayer.new()
	avatar.name = "Peer_%d" % id
	avatar.terrain = demo.terrain
	demo.island.add_child(avatar)
	var teal_count := 0
	var coral_count := 0
	for existing in avatars.values():
		if existing.court_side == 1:
			teal_count += 1
		else:
			coral_count += 1
	avatar.court_side = -1 if teal_count >= coral_count else 1
	avatar.position = Vector3((avatars.size() % 3 - 1) * 0.9, 0, avatar.court_side * 2.4)
	avatar.set_style(2 if avatar.court_side == -1 else 1, 1)
	avatars[id] = avatar
	return avatar

func _joined(id: int) -> void:
	if multiplayer.is_server():
		_spawn(id)
		last_input[id] = Time.get_ticks_msec()
		demo.game.set_roster(avatars.size())

func _left(id: int) -> void:
	if avatars.has(id) and avatars[id] != demo.player:
		avatars[id].queue_free()
	avatars.erase(id)
	last_input.erase(id)
	if active and multiplayer.is_server():
		demo.game.set_roster(avatars.size())

func submit(direction: Vector2, running: bool) -> void:
	if not active or multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	input_state.rpc_id(1, direction, running)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func input_state(direction: Vector2, running: bool) -> void:
	if not multiplayer.is_server() or not direction.is_finite():
		return
	var id := multiplayer.get_remote_sender_id()
	if avatars.has(id):
		avatars[id].direction = direction.limit_length()
		avatars[id].running = running
		last_input[id] = Time.get_ticks_msec()

func action(kind: String, value := 0) -> void:
	if not active or multiplayer.is_server():
		_apply_action(demo.player, kind, value)
	elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		avatar_action.rpc_id(1, kind, value)

@rpc("any_peer", "call_remote", "reliable", 2)
func avatar_action(kind: String, value: int) -> void:
	if multiplayer.is_server():
		var id := multiplayer.get_remote_sender_id()
		if avatars.has(id):
			_apply_action(avatars[id], kind, value)

func _apply_action(avatar: TerrainPlayer, kind: String, value: int) -> void:
	match kind:
		"hit": demo.game.strike(avatar)
		"new_match":
			if avatar == demo.player:
				demo.game.reset_match()
		"jump": avatar.jump_requested = true
		"wave": avatar.wave()
		"color": avatar.set_style(posmod(value, 4), avatar.size_index)
		"size": avatar.set_style(avatar.color_index, posmod(value, 3))
		"reset":
			avatar.position = Vector3(-0.8, 0, avatar.court_side * 2.4)
			avatar.vertical_speed = 0
			avatar.grounded = true

func _process(delta: float) -> void:
	if not active:
		return
	if connecting_since > 0 and Time.get_ticks_msec() - connecting_since > 10000:
		stop("Connection timed out: check IP / firewall")
		return
	if not multiplayer.is_server():
		return
	for id in last_input:
		if Time.get_ticks_msec() - int(last_input[id]) > 500:
			avatars[id].direction = Vector2.ZERO
			avatars[id].running = false
	elapsed += delta
	if elapsed < 0.05:
		return
	elapsed = 0
	var states: Dictionary = {}
	for id in avatars:
		var avatar: TerrainPlayer = avatars[id]
		states[id] = [avatar.position, avatar.rig.rotation.y, avatar.state, avatar.color_index, avatar.size_index, avatar.court_side]
	snapshot.rpc(states, demo.game.state_packet())
	info = "Hosting UDP 7777 | %d players" % avatars.size()

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func snapshot(states: Dictionary, match_state: Array) -> void:
	var local_id := multiplayer.get_unique_id()
	for id in avatars.keys():
		if not states.has(id):
			_left(id)
	for id in states:
		if not avatars.has(id):
			if id == local_id:
				avatars[id] = demo.player
			else:
				_spawn(id)
		var avatar: TerrainPlayer = avatars[id]
		avatar.set_physics_process(false)
		var data: Array = states[id]
		avatar.position = data[0]
		avatar.rig.rotation.y = data[1]
		if avatar.state != data[2]:
			avatar.state = data[2]
			avatar.animation.play(avatar.state, 0.1)
		avatar.set_style(data[3], data[4])
		avatar.court_side = data[5]
	demo.game.apply_packet(match_state)
	info = "Connected | %d players | YOU %d" % [states.size(), local_id]
