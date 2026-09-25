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
	for i in 8:
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


func close_dialogs(win: Node) -> void:
	for c in win.get_children():
		if c is AcceptDialog:
			c.hide()
			c.queue_free()


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
	# the package where a download would be found (the library stands in for Downloads here)
	DirAccess.make_dir_recursive_absolute(App.packages_dir())
	var offered := App.packages_dir().path_join(pkg.get_file())
	JsonDoc.copy_file(pkg, offered)
	# 1. Home
	var home := HomeScreen.new()
	home.app = app
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(home)
	await shot("home")
	clear()
	# 2. the Table's first screen: continue, the adventures found, your campaigns
	var win := TableWindow.new()
	win.app = app
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(win)
	await shot("table_picker")
	# 3. starting the package: the pitch, the name, what is inside folded away
	win._from_package_dialog(offered)
	await shot("package_start")
	close_dialogs(win)
	# 4. the campaign as it opens: the World — the party, the road, the reference
	var info := CampaignPackage.read(offered)
	win._start_package(offered, info, "Our Chapel")
	close_dialogs(win)
	var ctx := win.ctx
	# a character, as a player makes one on the phone
	if ctx.host != null and ctx.host.plugins.has("srd5e"):
		ctx.commands.run({"t": "player.add", "player": {"id": "pl_ana", "name": "Ana", "color": "#4f9cf6"}}, "Ana joins")
		ctx.host.dispatch("srd5e", "create_character", {"name": "Wren", "species": "halfling", "background": "criminal", "class": "rogue", "owner": "pl_ana",
			"abilities": {"str": 8, "dex": 15, "con": 14, "int": 10, "wis": 12, "cha": 13}, "gm": true})
		ctx.host.dispatch("srd5e", "create_character", {"name": "Brakka", "species": "dwarf", "background": "soldier", "class": "fighter", "owner": "pl_ana",
			"abilities": {"str": 15, "dex": 12, "con": 14, "int": 8, "wis": 13, "cha": 10}, "gm": true})
	win.view.zoom_to_fit()
	await shot("world_open")
	# 5. Thornwick: its marker on the map opens its card
	var thornwick := ""
	var marta := ""
	for pl in ctx.campaign.places:
		if str(pl.get("name", "")) == "Thornwick":
			thornwick = str(pl.id)
	for aid in ctx.encounter().actors:
		if str(ctx.encounter().actors[aid].get("name", "")) == "Marta Vell":
			marta = str(aid)
	if thornwick != "":
		ctx.select_token(thornwick)
	await shot("world_place_card")
	# shown to everyone: its picture and description on the phones
	win.reference.share_current("all")
	var shown := {}
	for entry in ctx.encounter().log:
		if str(entry.get("kind", "")) == "handout":
			shown = entry
	var art_dir := ctx.campaign.base_dir().path_join("art")
	# 6. a person: what the DM knows and the DCs
	if marta != "":
		win.reference.open("actor:" + marta)
	await shot("world_person_card")
	# 7. a rule looked up mid-conversation
	win.reference._search.text = "charmed"
	win.reference.refresh_list()
	win.reference.open("entry:conditions/charmed")
	await shot("world_lookup")
	win.reference._search.text = ""
	win.reference.refresh_list()
	# 8. the chapel: the fight launched
	for pl in ctx.campaign.places:
		if str(pl.get("kind", "")) == "encounter":
			win.maps.go_to_place(str(pl.id))
	win.view.zoom_to_fit()
	await shot("fight")
	# 9. prep: every pane
	win.set_mode("prep")
	await shot("prep")
	win.set_mode("world")
	# 10. a player's first screen
	clear()
	var pw := PlayerWindow.new()
	pw.app = app
	pw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pw)
	await shot("player_first_screen")
	# 11. what the DM showed, on a phone-sized screen (the picture arrives with the table's art)
	app.packs.set_extra_dirs(PackedStringArray([art_dir]))
	app.packs.reload()
	root.get_window().size = Vector2i(420, 860)
	pw.show_handout(shown)
	await shot("player_shown")
	root.get_window().size = Vector2i(1440, 900)
	clear()
	DirAccess.remove_absolute(offered)
	print("%d shots in %s" % [n, out])
	quit(0)
