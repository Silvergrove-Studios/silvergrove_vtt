extends SceneTree
## godot --headless -s tools/check_scripts.gd — load every script so parse
## and compile errors surface without opening a window.

func _init() -> void:
	var bad := 0
	for path in _scripts("res://hexmap") + _scripts("res://tools") + _scripts("res://tests"):
		var s = load(path)
		if s == null or not s.can_instantiate():
			# can_instantiate is false for scripts with compile errors
			print("FAIL ", path)
			bad += 1
		else:
			print("ok   ", path)
	quit(1 if bad > 0 else 0)

func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var p := dir + "/" + f
		if d.current_is_dir():
			out.append_array(_scripts(p))
		elif f.ends_with(".gd"):
			out.append(p)
		f = d.get_next()
	return out
