extends SceneTree
## godot --path . -s tools/player_smoke.gd -- <out_dir>
## Opens the Player on the example encounter as Ana, drives it and
## screenshots each state: a visual smoke test (needs a display).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "out/player"
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out)
	_run(out)


func _run(out: String) -> void:
	var main := PlayerWindow.new()
	main.app = App.new()
	root.add_child(main)
	await create_timer(0.4).timeout
	await _shot(out.path_join("01_join.png"))
	assert(main._files.item_count >= 1, "the example encounter is offered")
	main._choose_file(ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter"))
	await _shot(out.path_join("02_pick_player.png"))
	assert(main.screen == "pick" and main._players.item_count == 2, "two players to pick from")
	main._start(str(main._players.get_item_metadata(0)))
	await create_timer(0.5).timeout
	await _shot(out.path_join("03_as_ana.png"))
	assert(main.screen == "play" and main.session.player_name() == "Ana", "playing as Ana")
	assert(main.view.canvas.tokens_in_view().size() == 2, "sees the party, not the goblins")
	# The example is set up for ordered turns that have not begun, so a
	# move is refused; in free mode it goes through.
	var st := main.session.state
	var sid := main.session.scene_id()
	st.apply({"t": "turns.set", "changes": {"mode": "free"}})
	var fighter: Dictionary = main.session.my_tokens()[0]
	var from := Vision.token_pos(fighter)
	var g := main.view.canvas.map.grid
	var to := g.cell_center(g.world_to_axial(from) + Vector2i(1, 0))
	var mods := {"shift": false, "ctrl": false, "alt": false}
	main.tool.press(from, MOUSE_BUTTON_LEFT, mods)
	main.tool.drag(to, MOUSE_BUTTON_LEFT, mods)
	main.tool.release(to, MOUSE_BUTTON_LEFT, mods)
	assert(Vision.token_pos(st.token(sid, fighter.id)) == to, "the move went through")
	main._focus_token(fighter.id)
	main.view.set_zoom(0.5)
	await _shot(out.path_join("04_moved.png"))
	# Ordered turns, goblin's turn: her move is refused and she is told.
	st.apply({"t": "turns.set", "changes": {"mode": "ordered", "running": true, "turn": 2}})
	main.tool.press(to, MOUSE_BUTTON_LEFT, mods)
	main.tool.drag(from, MOUSE_BUTTON_LEFT, mods)
	main.tool.release(from, MOUSE_BUTTON_LEFT, mods)
	assert(Vision.token_pos(st.token(sid, fighter.id)) == to, "refused: still where she was")
	await _shot(out.path_join("05_not_your_turn.png"))
	print("player smoke done: ", out)
	quit(0)


func _shot(path: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path.get_file())
