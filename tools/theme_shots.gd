extends SceneTree
## godot --path . -s tools/theme_shots.gd -- <out_dir>
## One screenshot per theme variant, same map and state, for comparing looks.

func _init() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "out/themes"
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://hexmap/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.4).timeout
	main._open_path(ProjectSettings.globalize_path("res://examples/forest_road.hexmap"))
	await create_timer(0.4).timeout
	var ctx: EditorContext = main.ctx
	for p in ctx.level().props:
		if str(p.asset) == "woodland:campfire":
			ctx.select_one("props", p.id)
	main._select_tool("select")
	main.view.zoom_to_fit()
	for name in ThemeBuilder.names():
		main._set_theme(name)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out.path_join("theme_%s.png" % name))
		print("shot ", name)
	main._set_theme("slate")
	quit()
