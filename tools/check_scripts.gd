extends SceneTree
## godot --headless -s tools/check_scripts.gd — load every script so parse
## and compile errors surface without opening a window, and keep the
## platform-neutral modules free of desktop-only code.

## Modules that must run on every platform the Player runs on (phones and
## tablets included): no docking panels, no file dialogs, no menu bars, no
## editor state. The Editor and the Table are desktop-only and may use all of
## it.
const PORTABLE_DIRS := ["res://hexmap/core", "res://hexmap/render", "res://hexmap/encounter", "res://hexmap/net", "res://hexmap/player"]
const DESKTOP_ONLY := ["DockableContainer", "DockPane", "LayoutStore", "FileDialog", "NativeMenuMirror", "NativeMenu", "MenuBar", "PopupMenu",
	"EditorContext", "EditorWindow", "TableWindow", "Commands", "OS.execute", "OS.shell_open", "DisplayServer.global_menu"]


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
	bad += _check_portable()
	quit(1 if bad > 0 else 0)


func _check_portable() -> int:
	var bad := 0
	for dir in PORTABLE_DIRS:
		for path in _scripts(dir):
			var src := FileAccess.get_file_as_string(path)
			var lines := src.split("\n")
			for i in lines.size():
				var line := lines[i]
				var code := line.get_slice("#", 0) if not line.strip_edges().begins_with("##") else ""
				for token in DESKTOP_ONLY:
					if code.contains(token):
						print("FAIL %s:%d uses %s, which the Player cannot rely on" % [path, i + 1, token])
						bad += 1
	if bad == 0:
		print("ok   portable modules stay portable")
	return bad


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
