extends SceneTree
## Walk the journey a new DM and a new player take, screenshotting each
## screen, for the UI audit (docs/ui-journey-audit.md). Drives the real
## windows the way a person would get there; it asserts nothing.
##
##   ./run.sh godot --path . --resolution 1440x900 -s tools/journey_shots.gd -- <out dir> <campaign package>

var _ran := false
var out := ""
var n := 0


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	OS.low_processor_usage_mode = false
	_run()
	return false


func shot(label: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	n += 1
	var path := out.path_join("%02d_%s.png" % [n, label])
	root.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


func clear() -> void:
	for c in root.get_children():
		if c is Control or c is Window:
			root.remove_child(c)
			c.free()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = str(args[0])
	var pkg := str(args[1])
	DirAccess.make_dir_recursive_absolute(out)
	App.no_auto_host = false
	var work := "user://journey_shots"
	if DirAccess.dir_exists_absolute(work):
		PluginHost._rm_rf(work)
	var app := App.new(work.path_join("prefs.json"))
	app.prefs.campaigns_dir = ProjectSettings.globalize_path(work.path_join("campaigns"))
	# 1. Home
	var home := HomeScreen.new()
	home.app = app
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(home)
	await shot("home")
	clear()
	# 2. the Table's first screen: the campaign picker
	var win := TableWindow.new()
	win.app = app
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(win)
	await shot("table_picker")
	# 3. starting the package: what the DM reads first
	var info := CampaignPackage.read(pkg)
	var whole := CampaignPackage.verify(pkg)
	win._confirm("Start '%s'?\n\n%s" % [str(info.name), TableWindow.package_summary(pkg, whole)], func() -> void: pass)
	await shot("package_summary")
	for c in win.get_children():
		if c is ConfirmationDialog:
			c.hide()
			c.queue_free()
	# 4. the campaign as it opens
	var r := CampaignPackage.instance(pkg, work.path_join("campaigns/Our Chapel"), "Our Chapel")
	win._open_campaign_path(str(r.path))
	await shot("campaign_open")
	# 5. the Maps pane, where the fight is
	win._show_maps_pane()
	await shot("maps_pane")
	# 6. the fight launched
	win.maps.launch(str(win.ctx.campaign.encounters[0].id))
	await shot("fight_launched")
	# 7. a player's first screen
	clear()
	var pw := PlayerWindow.new()
	pw.app = app
	pw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pw)
	await shot("player_first_screen")
	clear()
	print("%d shots in %s" % [n, out])
	quit(0)
