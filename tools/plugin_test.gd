extends SceneTree
## godot --headless -s tools/plugin_test.gd -- <plugin dir> [more dirs]
## (`./run.sh plugintest <dir>`) — load a plugin into a scratch kernel and
## run its own `hm.test`s. Exit code 1 if any check fails or the plugin
## does not load. The same runs inside the app's self-test for the
## plugins shipped with it.

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: plugin_test.gd -- <plugin dir>")
		quit(2)
		return false
	var fails := 0
	for dir in args:
		fails += _run(App.resolve_path(str(dir)) if ClassDB.class_exists("App") else str(dir))
	quit(1 if fails > 0 else 0)
	return false


func _run(dir: String) -> int:
	if not PluginHost.available():
		print("no Lua runtime in this build; cannot test ", dir)
		return 1
	var st := EncounterState.new(Encounter.create("plugin test"))
	var host := PluginHost.new(RulesKernel.new(st))
	# a ruleset's tests read all of its content, whatever a campaign would choose
	host.all_packs = true
	host.plugin_failed.connect(func(id: String, where: String, msg: String) -> void: print("  %s: %s: %s" % [id, where, msg]))
	# dependencies from sibling directories first (a layered plugin is
	# tested over its base)
	var err := []
	var manifest := JsonDoc.parse(FileAccess.get_file_as_string(dir.path_join("manifest.json")), err)
	for dep in manifest.get("depends", []):
		var dw := host.load_dir(dir.get_base_dir().path_join(str(dep)))
		if dw != "":
			print("FAIL load dependency %s: %s" % [str(dep), dw])
			return 1
	var t0 := Time.get_ticks_msec()
	var why := host.load_dir(dir)
	var load_ms := Time.get_ticks_msec() - t0
	if why != "":
		print("FAIL load %s: %s" % [dir, why])
		return 1
	var id := str(manifest.get("id", host.plugins.keys()[0]))
	var entries := 0
	for coll in host.kernel.comp.collections():
		entries += host.kernel.comp.count(str(coll))
	print("-- %s (%s) loaded in %d ms, %d compendium entries" % [id, dir, load_ms, entries])
	t0 = Time.get_ticks_msec()
	var r := host.run_tests(id, func(line: String) -> void: print(line))
	print("%d checks, %d failed, %d ms" % [r.count, r.fails, Time.get_ticks_msec() - t0])
	return int(r.fails)
