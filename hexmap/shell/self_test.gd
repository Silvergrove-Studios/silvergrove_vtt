class_name SelfTest
extends Control
## The unit suite run inside a build — on a phone, in a simulator, in an
## exported desktop app — where `-s tests/run_tests.gd` cannot. Started by
## `--selftest` or by a `user://selftest` marker file (which is how a CI
## job reaches an app on an emulator: push the marker, launch, pull the
## results). Writes `user://selftest.txt` as it goes, screenshots the home
## and Player screens, and `user://selftest.done` last, holding the fail
## count, so a watcher knows when to look. Shows the log on screen too.

const LOG_PATH := "user://selftest.txt"
const DONE_PATH := "user://selftest.done"
const MARKER_PATH := "user://selftest"
## Holding "host:port": join that table instead of running the suite.
const JOIN_PATH := "user://selftest_join"

var app: App
var _log: FileAccess
var _text: RichTextLabel
var _lines := 0


static func requested(args: PackedStringArray) -> bool:
	return args.has("--selftest") or args.has("--selftest-join") or FileAccess.file_exists(MARKER_PATH) or FileAccess.file_exists(JOIN_PATH)


## The table to join, from `--selftest-join host:port` or the marker file.
static func join_target(args: PackedStringArray) -> String:
	var i := args.find("--selftest-join")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	if FileAccess.file_exists(JOIN_PATH):
		return FileAccess.get_file_as_string(JOIN_PATH).strip_edges()
	return ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if app == null:
		app = App.new()
	theme = app.build_theme()
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_text = RichTextLabel.new()
	_text.scroll_following = true
	_text.theme_type_variation = "MonoLabel"
	bg.add_child(_text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DONE_PATH))
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_run.call_deferred()


func _say(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()
	_lines += 1
	if _lines < 400:
		_text.append_text(line.xml_escape() + "\n")
	elif _lines == 400:
		_text.append_text("…\n")


func _run() -> void:
	_say("Hexmap self-test %s on %s (%s), Godot %s, scale %.2f, screen %s" % [App.build_stamp(), OS.get_name(), OS.get_model_name(), Engine.get_version_info().string, get_window().content_scale_factor, DisplayServer.screen_get_size()])
	_say("user dir: " + OS.get_user_data_dir())
	# Screenshots first: the frames the tests need are cheap now.
	await _shot("selftest_home.png", HomeScreen)
	await _shot("selftest_player.png", PlayerWindow)
	var suite := TestSuite.new(get_tree())
	suite.say = _say
	var t0 := Time.get_ticks_msec()
	var target := SelfTest.join_target(OS.get_cmdline_user_args())
	if target != "":
		var hp := Protocol.parse_address(target)
		_say("joining the table at %s:%d (this device: %s)" % [str(hp[0]), int(hp[1]), ", ".join(App.local_ipv4())])
		suite.join_remote(str(hp[0]), int(hp[1]))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(JOIN_PATH))
	else:
		await suite.run_all()
	_say("took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	for s in suite.skipped:
		_say("skipped: " + s)
	_say("RESULT %d checks, %d failed" % [suite.count, suite.fails])
	if _log != null:
		_log.close()
	var done := FileAccess.open(DONE_PATH, FileAccess.WRITE)
	if done != null:
		done.store_string(str(suite.fails))
		done.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MARKER_PATH))
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest") or args.has("--selftest-join"):
		get_tree().quit(1 if suite.fails > 0 else 0)


## Show a mode's window for a moment and save what the screen shows.
func _shot(file: String, window_class: Variant) -> void:
	var w: Control = window_class.new()
	w.app = app
	add_child(w)
	if w.has_signal("go_home"):
		pass
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("user://").path_join(file))
	_say("screenshot %s (%dx%d)" % [file, img.get_width(), img.get_height()])
	if w.has_method("_stop_browsing"):
		w._stop_browsing()
	remove_child(w)
	w.queue_free()
