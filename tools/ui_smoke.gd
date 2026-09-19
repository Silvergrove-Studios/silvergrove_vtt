extends SceneTree
## godot --path . -s tools/ui_smoke.gd -- <out_dir>
## Opens the editor on an example, drives a few UI states and screenshots
## each: a visual smoke test of the window (needs a display).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "out/ui"
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out)
	_run(out)


func _run(out: String) -> void:
	var main = load("res://hexmap/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	main._open_path(ProjectSettings.globalize_path("res://examples/forest_road.hexmap"))
	await create_timer(0.5).timeout
	main.view.zoom_to_fit()
	await _shot(out.path_join("01_open.png"))

	# Select a prop and show the inspector.
	var ctx: EditorContext = main.ctx
	var lvl := ctx.level()
	var prop: Dictionary = lvl.props[0]
	for p in lvl.props:
		if str(p.asset) == "woodland:campfire":
			prop = p
	ctx.select_one("props", prop.id)
	main._select_tool("select")
	main.view.set_zoom(0.6, main.view.size / 2.0)
	main.view.camera.position = Vector2(prop.pos[0], prop.pos[1]) * main.view.canvas.ppx
	await _shot(out.path_join("02_selected_prop.png"))

	# View → Theme drives the theme and persists it.
	var ids: PackedStringArray = main.theme_ids()
	main._on_menu(main.V_THEME_BASE + ids.find("forge"))
	await create_timer(0.3).timeout
	assert(main._prefs.theme == "forge", "theme menu sets the theme pref")
	assert(main.theme_menu.is_item_checked(ids.find("forge")), "theme menu shows the choice")
	await _shot(out.path_join("02b_theme_menu.png"))
	main._set_theme("slate")
	# Layout reset writes the layout file.
	main._reset_layout()
	await create_timer(2.5).timeout
	assert(FileAccess.file_exists(ProjectSettings.globalize_path("user://layout.tres")), "layout persisted")

	# Props palette + prop tool ghost.
	main.palette.current_tab = 1
	ctx.prop_ref = "woodland:oak_large"
	main._select_tool("prop")
	await _shot(out.path_join("03_prop_tool.png"))

	# Darkness preview with lights.
	main.view.canvas.darkness = 0.8
	main.view.canvas.refresh()
	main.view.zoom_to_fit()
	await _shot(out.path_join("04_darkness.png"))
	main.view.canvas.darkness = 0.0

	# Export dialog.
	main._export_pdf_dialog()
	await _shot(out.path_join("05_pdf_dialog.png"))
	for c in main.get_children():
		if c is ConfirmationDialog:
			c.hide()
			c.queue_free()

	# Second example, flat hexes, crypt level of the chapel.
	main._open_path(ProjectSettings.globalize_path("res://examples/ruined_chapel.hexmap"))
	await create_timer(0.3).timeout
	main.level_select.select(1)
	main._on_level_selected(1)
	main.view.zoom_to_fit()
	await _shot(out.path_join("06_crypt_level.png"))
	main._open_path(ProjectSettings.globalize_path("res://examples/bog_crossing.hexmap"))
	await create_timer(0.3).timeout
	main.view.zoom_to_fit()
	await _shot(out.path_join("07_flat_hexes.png"))
	print("ui smoke done: ", out)
	quit(0)


func _shot(path: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path.get_file())
