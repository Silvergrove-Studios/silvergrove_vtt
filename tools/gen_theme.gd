extends SceneTree
## godot --headless --editor --path . -s tools/gen_theme.gd — run the ThemeGen
## scripts under hexmap/ui/themes/ and write their .tres files. ThemeGen's
## generator is an EditorScript, so this needs the editor process.

func _init() -> void:
	var dir := DirAccess.open("res://hexmap/ui/themes")
	var bad := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var script = load("res://hexmap/ui/themes/" + f)
		var inst = script.new()
		if inst == null or not inst.has_method("_run"):
			print("skip ", f)
			continue
		print("generating from ", f)
		inst._run()
	quit(bad)
