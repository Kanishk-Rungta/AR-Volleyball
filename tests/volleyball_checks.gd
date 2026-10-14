extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var demo = load("res://scenes/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	demo.player.set_physics_process(false)
	demo.game.set_physics_process(false)
	demo.game.set_roster(2)
	var game: Node3D = demo.game
	assert(demo.player.animation.has_animation("Hit"))
	assert(not game.bot.visible)
	assert(game.strike(demo.player), "Serving must start a rally")
	assert(game.rally and game.velocity.z < 0)
	assert(not game.strike(demo.player), "No repeat hit from same team")
	for i in range(180):
		game._physics_process(1.0 / 120)
	assert(not game.rally and game.scores[0] == 1, "Serve must clear net and score on coral floor")
	game.point_wait = 0
	game.last_hit_time = -10000
	assert(game.strike(demo.player))
	game.ball_position = Vector3(0, 0.8, 0.06)
	game.velocity = Vector3(0, 0, -3)
	game._physics_process(0.03)
	assert(game.velocity.z > 0, "Low shots must rebound from net")
	game.ball_position = Vector3(3.8, 0.19, -2)
	game.velocity = Vector3(0, -1, 0)
	game._physics_process(0.03)
	assert(game.scores[1] == 1, "An out ball must penalize last toucher")
	game.scores = [6, 1]
	game.rally = true
	game.award(1, "test")
	assert(game.winner == 1)
	game.reset_match()
	assert(game.scores == [0, 0] and game.winner == 0 and not game.rally)
	demo.player.direction = Vector2(0, -1)
	for i in range(180):
		demo.player._physics_process(1.0 / 60)
	assert(demo.player.position.z >= 0.5, "Teal cannot cross net")
	game.set_roster(1)
	assert(game.training and game.bot.visible)
	print("PASS: serve trajectory, net collision, scoring, out penalty, match win/reset, court bounds, AI roster")
	quit(0)
