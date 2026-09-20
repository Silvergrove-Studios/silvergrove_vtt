extends TestCase
## App prefs, arguments and the home screen.


func test_app_prefs() -> void:
	var path := "user://test_prefs.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var app := App.new(path)
	check(app.theme_name == "slate", "fresh prefs → slate")
	check(app.recent().is_empty(), "fresh prefs → no recent files")
	var themed := []
	app.theme_changed.connect(func(n: String) -> void: themed.append(n))
	app.set_theme("forge")
	check(themed == ["forge"], "set_theme emits")
	app.set_theme("no-such-theme")
	check(app.theme_name == "slate", "unknown theme falls back to slate")
	var map_path := example("forest_road.hexmap")
	app.note_recent("/nowhere/gone.hexmap")
	app.note_recent(map_path)
	app.note_recent(map_path)
	check(app.recent() == [map_path], "recent: newest first, deduplicated, missing files dropped")
	for i in App.RECENT_MAX + 3:
		app.note_recent(example("forest_road.hexmap") if i % 2 == 0 else example("bog_crossing.hexmap"))
	check((app.prefs.recent as Array).size() <= App.RECENT_MAX, "recent list is capped")
	var again := App.new(path)
	check(again.theme_name == "slate" and again.recent().size() == 2, "prefs round-trip through the file")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	check(App.new(path).theme_name == "slate", "garbage prefs file → defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(App.mode_available("player"), "the player runs on every build")
	check(App.available_modes().size() == (1 if OS.has_feature("mobile") or OS.has_feature("web") else 3), "desktop builds get all modes")
	for m in App.MODES:
		check(App.mode_label(m) != m and App.mode_blurb(m) != "", "mode %s has a label and a blurb" % m)


func test_shell_args() -> void:
	var Main = load("res://hexmap/shell/main.gd")
	check(Main._mode_from_args(PackedStringArray([])) == ["", ""], "no args → home")
	check(Main._mode_from_args(PackedStringArray(["--theme", "forge"])) == ["", ""], "theme alone → home")
	check(Main._mode_from_args(PackedStringArray(["examples/x.hexmap"])) == ["editor", "examples/x.hexmap"], "a map → editor")
	check(Main._mode_from_args(PackedStringArray(["examples/x.hexmap", "--shot", "o.png"])) == ["editor", "examples/x.hexmap"], "map plus --shot → editor")
	check(Main._mode_from_args(PackedStringArray(["--editor"])) == ["editor", ""], "--editor → new map")
	check(Main._mode_from_args(PackedStringArray(["--editor", "--theme", "forge"])) == ["editor", ""], "--editor before a flag takes no argument")
	check(Main._mode_from_args(PackedStringArray(["a.encounter"])) == ["table", "a.encounter"], "an encounter → table")
	check(Main._mode_from_args(PackedStringArray(["--table", "a.encounter"])) == ["table", "a.encounter"], "--table with a file")
	check(Main._mode_from_args(PackedStringArray(["--player", "192.168.1.4:7777"])) == ["player", "192.168.1.4:7777"], "--player with an address")


func test_home_screen() -> void:
	var app := App.new("user://test_prefs_home.json")
	app.note_recent(example("forest_road.hexmap"))
	var home := HomeScreen.new()
	home.app = app
	root.add_child(home)
	var opened := []
	home.open_mode.connect(func(m: String, a: String) -> void: opened.append([m, a]))
	for m in App.MODES:
		var b: Button = home.find_child("Mode_" + m, true, false)
		check(b != null and b.disabled == not App.mode_available(m), "home has a %s button" % m)
		check(b.custom_minimum_size.y >= 44, "%s button is finger-sized" % m)
	(home.find_child("Mode_editor", true, false) as Button).pressed.emit()
	check(opened == [["editor", ""]], "mode button asks the shell for that mode")
	check(home._recent_box != null and home._recent_box.get_child_count() == 1, "recent files listed")
	(home._recent_box.get_child(0) as Button).pressed.emit()
	check(opened.size() == 2 and opened[1][0] == "editor" and opened[1][1].ends_with("forest_road.hexmap"), "recent map opens in the editor")
	home.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_home.json"))
