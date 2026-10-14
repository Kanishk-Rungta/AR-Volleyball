extends SceneTree
var demo: Node
var client := false
var saw_remote := false
var saw_ball := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	client = "client" in OS.get_cmdline_user_args()
	demo = load("res://scenes/main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	if client:
		demo.session.join("127.0.0.1")
	else:
		demo.session.host()
	print("READY client=", client, " ticks=", Time.get_ticks_msec())
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < (12000 if client else 25000):
		await process_frame
		if client:
			demo.session.submit(Vector2(1, 0), true)
			if demo.session.avatars.size() == 2:
				saw_remote = true
				saw_ball = saw_ball or demo.game.rally
				assert(not demo.game.training and not demo.game.bot.visible)
				demo.session.action("color", 2)
				demo.session.action("size", 2)
				if demo.player.position.x > 1.0 and demo.player.color_index == 2 and demo.player.size_index == 2 and saw_ball:
					print("PASS: client receives host and own avatar, authoritative movement, color, scale, ball replication and AI replacement")
					demo.session.stop()
					quit(0)
					return
		else:
			if demo.session.avatars.size() == 2:
				if not saw_remote:
					demo.session.action("hit")
				saw_remote = true
			elif saw_remote:
				print("PASS: host spawned remote peer and removed it on disconnect")
				demo.session.stop()
				quit(0)
				return
	push_error("Network integration test timed out: " + demo.session.info)
	quit(1)
