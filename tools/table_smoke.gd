extends SceneTree
## godot --path . -s tools/table_smoke.gd -- <out_dir>
## Opens the Table on the example encounter, drives it through a few turns
## of play and screenshots each state: a visual smoke test (needs a display).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "out/table"
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out)
	_run(out)


func _run(out: String) -> void:
	var main := TableWindow.new()
	main.app = App.new()
	root.add_child(main)
	await create_timer(0.5).timeout
	main._open_path(ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter"))
	await create_timer(0.5).timeout
	main.view.zoom_to_fit()
	await _shot(out.path_join("01_dm_view.png"))

	var ctx: TableContext = main.ctx
	var sid := ctx.scene_id
	var ana: Dictionary = ctx.encounter().players[0]
	# What Ana sees: fog, her fighter's vision, no goblins.
	main._set_viewpoint(str(ana.id))
	await _shot(out.path_join("02_as_ana.png"))
	assert(main.view.canvas.tokens_in_view().size() == 2, "Ana sees the two party tokens, not the hidden goblins")
	main._set_viewpoint("")

	# Open the west door with a click, walk the fighter in, see the reveal.
	var m := ctx.map()
	var g := m.grid
	var door: Dictionary = {}
	for w in m.level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			door = w
	var mid := (Vector2(door.points[0][0], door.points[0][1]) + Vector2(door.points[1][0], door.points[1][1])) / 2.0
	var mods := {"shift": false, "ctrl": false, "alt": false}
	main.view.tool.press(mid, MOUSE_BUTTON_LEFT, mods)
	main.view.tool.release(mid, MOUSE_BUTTON_LEFT, mods)
	assert(ctx.state.effective(sid, "walls", door).state == "open", "click opened the door")
	var fighter: Dictionary = ctx.state.tokens_owned_by(sid, str(ana.id))[0]
	var from := Vision.token_pos(fighter)
	var to := g.cell_center(g.offset_to_axial(6, 7))
	main.view.tool.press(from, MOUSE_BUTTON_LEFT, mods)
	main.view.tool.drag(to, MOUSE_BUTTON_LEFT, mods)
	main.view.tool.release(to, MOUSE_BUTTON_LEFT, mods)
	assert(ctx.state.token(sid, fighter.id).pos == [to.x, to.y], "drag moved the fighter into the nave")
	main.view.camera.position = to * main.view.canvas.ppx
	main.view.set_zoom(0.35)
	await _shot(out.path_join("03_door_open_moved.png"))
	main._set_viewpoint(str(ana.id))
	await _shot(out.path_join("04_as_ana_inside.png"))
	main._set_viewpoint("")

	# Reveal a goblin, start ordered turns, next turn: gold ring moves.
	var gob: Dictionary = ctx.state.tokens(sid)[2]
	ctx.commands.update_token(sid, gob.id, {"hidden": false})
	ctx.commands.start_turns(sid)
	ctx.commands.next_turn()
	ctx.select_token(gob.id)
	await _shot(out.path_join("05_ordered_turns.png"))
	# DM-picks mode: tick Ana's fighter.
	ctx.commands.set_turn_mode("dm")
	ctx.commands.toggle_active_token(fighter.id)
	await _shot(out.path_join("05b_dm_picks.png"))
	ctx.commands.set_turn_mode("ordered")

	# Place a token with the token tool, then the fog brush.
	main._select_tool("token")
	ctx.token_name = "Wolf"
	ctx.token_color = "#777777"
	ctx.token_hidden = false
	var spot := g.cell_center(g.offset_to_axial(8, 8))
	main.view.tool.move(spot)
	main.view.tool.press(spot, MOUSE_BUTTON_LEFT, mods)
	assert(ctx.state.tokens(sid).size() == 7, "token tool placed a wolf")
	main._select_tool("fog")
	ctx.fog_brush = 2
	var far := g.cell_center(g.offset_to_axial(18, 3))
	main.view.tool.move(far)
	main.view.tool.press(far, MOUSE_BUTTON_LEFT, mods)
	main.view.tool.release(far, MOUSE_BUTTON_LEFT, mods)
	main.view.zoom_to_fit()
	await _shot(out.path_join("06_wolf_and_fog_brush.png"))
	ctx.history.undo()
	ctx.history.undo()
	assert(ctx.state.tokens(sid).size() == 6, "undo removed the wolf again")

	# Crypt scene, then a theme switch persists through the same App.
	ctx.set_scene(str(ctx.encounter().scenes[1].id))
	await _shot(out.path_join("07_crypt.png"))
	main.app.set_theme("parchment")
	await create_timer(0.3).timeout
	await _shot(out.path_join("08_parchment.png"))
	main.app.set_theme("slate")
	print("table smoke done: ", out)
	quit(0)


func _shot(path: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path.get_file())
