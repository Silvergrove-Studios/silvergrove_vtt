extends SceneTree
## A table for the web screens to talk to: starts a campaign from a
## package, hosts it (the web side on its usual port, or the one given),
## writes where the DM's screen and the players' page are, and runs until
## its time is up or the stop file appears. For the web client's
## end-to-end tests and for looking at the web screens without clicking
## through the Table. No Bonjour: nothing is left announcing afterwards.
##
##   godot --headless --path . -s tools/web_host.gd -- <package> [--seconds N]
##       [--web-port P] [--ws-port P] [--info out.json] [--stop stop-file]
##       [--party]   two players, Ana and Ben, with a character each

class NoBonjour extends Bonjour:
	func available() -> bool:
		return false


var _ran := false
var _deadline := 0
var _stop_file := ""
var win: TableWindow


func _process(_d: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	if _deadline > 0 and Time.get_ticks_msec() > _deadline:
		print("web_host: time is up")
		_finish()
	elif _stop_file != "" and FileAccess.file_exists(_stop_file):
		print("web_host: asked to stop")
		DirAccess.remove_absolute(_stop_file)
		_finish()
	return false


func _finish() -> void:
	if win != null and win.host != null:
		win.host.stop()
	_deadline = 0
	_stop_file = ""
	quit(0)


func _arg(args: PackedStringArray, key: String, fallback := "") -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("web_host: which package?")
		quit(1)
		return
	var pkg := ProjectSettings.globalize_path(args[0]) if not args[0].begins_with("/") else args[0]
	_deadline = Time.get_ticks_msec() + int(_arg(args, "--seconds", "600")) * 1000
	_stop_file = _arg(args, "--stop")
	var info_path := _arg(args, "--info")
	var web_port := int(_arg(args, "--web-port", str(WebServer.DEFAULT_PORT)))
	App.no_auto_host = true
	App.no_browser = true
	var work := "user://web_host"
	if DirAccess.dir_exists_absolute(work):
		PluginHost._rm_rf(work)
	var app := App.new(work.path_join("prefs.json"))
	app.prefs.campaigns_dir = ProjectSettings.globalize_path(work.path_join("campaigns"))
	# started from where it is: nothing goes into the library of this computer's Hexmap
	var offered := pkg
	win = TableWindow.new()
	win.app = app
	win.bonjour = NoBonjour.new()
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(win)
	var info := CampaignPackage.read(offered)
	win._start_package(offered, info, str(info.get("name", "Web test")))
	for c in win.get_children():
		if c is AcceptDialog:
			c.hide()
	var ctx := win.ctx
	if args.has("--party") and ctx.host != null and ctx.host.plugins.has("srd5e"):
		ctx.commands.run({"t": "player.add", "player": {"id": "pl_ana", "name": "Ana", "color": "#4f9cf6"}}, "Ana joins")
		ctx.commands.run({"t": "player.add", "player": {"id": "pl_ben", "name": "Ben", "color": "#e0a040"}}, "Ben joins")
		ctx.host.dispatch("srd5e", "create_character", {"name": "Wren", "species": "halfling", "background": "criminal", "class": "rogue", "owner": "pl_ana",
			"abilities": {"str": 8, "dex": 15, "con": 14, "int": 10, "wis": 12, "cha": 13}, "gm": true})
		ctx.host.dispatch("srd5e", "create_character", {"name": "Brakka", "species": "dwarf", "background": "soldier", "class": "fighter", "owner": "pl_ben",
			"abilities": {"str": 15, "dex": 12, "con": 14, "int": 8, "wis": 13, "cha": 10}, "gm": true})
	win.host_port = int(_arg(args, "--ws-port", str(Protocol.DEFAULT_PORT)))
	win.web_port = web_port
	win._set_hosting(true)
	if win.host == null or win.host.web == null:
		push_error("web_host: could not host")
		quit(1)
		return
	var out := {"dm": win.dm_url(), "player": "http://localhost:%d/" % win.host.web.port, "web_port": win.host.web.port, "ws_port": win.host.port,
		"campaign": ctx.campaign.name if ctx.campaign != null else ""}
	print("web_host: ", JSON.stringify(out))
	if info_path != "":
		var f := FileAccess.open(info_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out))
		f.close()

