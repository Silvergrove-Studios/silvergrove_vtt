class_name App
extends RefCounted
## What every mode of the application shares: preferences, the pack library
## and the theme choice. Created once by the shell (hexmap/shell/main.gd) and
## handed to whichever window is open. Holds no UI, so tools and tests can
## make one without a window.

signal theme_changed(name: String)

const NAME := "Hexmap"
const PREFS_PATH := "user://prefs.json"
const RECENT_MAX := 10

## Modes, in the order the home screen lists them.
const MODES := ["editor", "table", "player"]

var prefs := {"pack_dirs": [], "theme": "slate", "recent": []}
var packs := PackLibrary.new()
## Where preferences live; tests point this somewhere harmless.
var prefs_path := PREFS_PATH


func _init(p_prefs_path := PREFS_PATH) -> void:
	prefs_path = p_prefs_path
	load_prefs()
	packs.set_extra_dirs(PackedStringArray(prefs.pack_dirs))
	packs.reload()


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


## Which modes this build can run. The editor and the table need a desktop:
## docking panels, file dialogs, a keyboard. The player runs everywhere.
static func available_modes() -> PackedStringArray:
	if OS.has_feature("mobile") or OS.has_feature("web"):
		return PackedStringArray(["player"])
	return PackedStringArray(MODES)


static func mode_available(mode: String) -> bool:
	return available_modes().has(mode)


static func mode_label(mode: String) -> String:
	match mode:
		"editor": return "Editor"
		"table": return "Table"
		"player": return "Player"
	return mode


static func mode_blurb(mode: String) -> String:
	match mode:
		"editor": return "Draw maps: terrain, props, walls, lights. Export to VTTs and print."
		"table": return "Run an encounter on your maps: tokens, doors, lights, fog, turns."
		"player": return "Join a table as a player and see the map from your tokens' eyes."
	return ""


# ------------------------------------------------------------------- theme --

var theme_name: String:
	get: return str(prefs.theme)


func set_theme(name: String, persist := true) -> void:
	if not ThemeBuilder.VARIANTS.has(name):
		name = "slate"
	prefs.theme = name
	if persist:
		save_prefs()
	theme_changed.emit(name)


func build_theme() -> Theme:
	return ThemeBuilder.build(theme_name)


# ------------------------------------------------------------------- packs --

func set_pack_dirs(dirs: Array) -> void:
	prefs.pack_dirs = dirs
	save_prefs()
	packs.set_extra_dirs(PackedStringArray(dirs))
	packs.reload()


# ------------------------------------------------------------------ recent --

## Remember a document the user opened or saved; newest first.
func note_recent(path: String) -> void:
	var r: Array = prefs.get("recent", [])
	r.erase(path)
	r.push_front(path)
	if r.size() > RECENT_MAX:
		r.resize(RECENT_MAX)
	prefs.recent = r
	save_prefs()


func recent() -> Array:
	var out := []
	for p in prefs.get("recent", []):
		if FileAccess.file_exists(str(p)) or DirAccess.dir_exists_absolute(str(p)):
			out.append(str(p))
	return out


# ------------------------------------------------------------------- prefs --

func load_prefs() -> void:
	if not FileAccess.file_exists(prefs_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(prefs_path)) != OK:
		return
	if json.data is Dictionary:
		for k in json.data:
			prefs[k] = json.data[k]
	if not ThemeBuilder.VARIANTS.has(str(prefs.theme)):
		prefs.theme = "slate"


func save_prefs() -> void:
	var f := FileAccess.open(prefs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(prefs, "  "))
		f.close()
