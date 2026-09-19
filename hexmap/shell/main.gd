extends Control
## The application root. Owns the App (prefs, packs, theme) and exactly one
## window at a time: the home screen or one of the modes — Editor (author
## maps), Table (run encounters), Player (join a table). Modes are separate
## scenes under hexmap/<mode>/ that only share what is in core/, render/,
## encounter/, net/ and ui/.
##
## Command line (after `--`):
##   <file>.hexmap            open the editor on a map
##   <file>.encounter         open the table on an encounter
##   --editor [map]           the editor
##   --table [encounter]      the table
##   --player [address]       the player client
##   --theme <name>           theme for this run, not persisted
##   --shot <out.png>         (editor) screenshot and quit

var app := App.new()
var window: Control
var mode := ""


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := OS.get_cmdline_user_args()
	var ti := args.find("--theme")
	if ti >= 0 and ti + 1 < args.size():
		app.set_theme(args[ti + 1], false)
	var want := _mode_from_args(args)
	open_mode(want[0], want[1])
	var shot := args.find("--shot")
	if shot >= 0 and shot + 1 < args.size():
		_screenshot_and_quit(args[shot + 1])


## `--shot out.png`: render the window once and exit. Used by run.sh shot
## and by the docs.
func _screenshot_and_quit(path: String) -> void:
	await get_tree().create_timer(1.0).timeout
	if window != null and window.has_method("prepare_shot"):
		window.prepare_shot()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(path))
	print("screenshot: ", path)
	get_tree().quit()


## [mode, argument]. An empty mode is the home screen.
static func _mode_from_args(args: PackedStringArray) -> Array:
	for i in args.size():
		var a := args[i]
		var next := args[i + 1] if i + 1 < args.size() and not args[i + 1].begins_with("--") else ""
		match a:
			"--editor": return ["editor", next]
			"--table": return ["table", next]
			"--player": return ["player", next]
			"--home": return ["", ""]
		if a.begins_with("--"):
			continue
		if a.ends_with(".hexmap") or a.ends_with(".json"):
			return ["editor", a]
		if a.ends_with(".encounter"):
			return ["table", a]
	return ["", ""]


## Replace the current window with a mode's window (or the home screen when
## `p_mode` is empty). `arg` is a document path or address for the mode.
func open_mode(p_mode: String, arg := "") -> void:
	if p_mode != "" and not App.mode_available(p_mode):
		push_warning("mode '%s' is not available on this platform" % p_mode)
		p_mode = ""
	if window != null:
		window.queue_free()
		window = null
	mode = p_mode
	match p_mode:
		"editor": window = EditorWindow.new()
		"table": window = TableWindow.new()
		"player": window = PlayerWindow.new()
		_: window = HomeScreen.new()
	window.app = app
	if window.has_signal("go_home"):
		window.go_home.connect(func() -> void: open_mode(""))
	if window.has_signal("open_mode"):
		window.open_mode.connect(open_mode)
	add_child(window)
	if arg != "" and window.has_method("open_argument"):
		window.open_argument(arg)
	if p_mode == "":
		get_window().title = App.NAME


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if window != null and window.has_method("request_quit"):
			window.request_quit()
		else:
			get_tree().quit()
