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


# ------------------------------------------------------------------ screen --

## How much to scale the UI on a phone or tablet: points, not pixels, but
## never so much that fewer than MIN_LOGICAL_WIDTH points fit across the
## narrower side — a column that needs 360 must still fit in portrait.
const MIN_LOGICAL_WIDTH := 360.0

static func ui_scale(dpi: float, screen_px: Vector2) -> float:
	var f := clampf(dpi / 160.0, 1.0, 4.0)
	var narrow := minf(screen_px.x, screen_px.y)
	if narrow > 0.0 and narrow / f < MIN_LOGICAL_WIDTH:
		f = maxf(1.0, narrow / MIN_LOGICAL_WIDTH)
	return f


## Safe-area insets (notch, rounded corners, gesture bar) in logical
## points for the given scale; zero on desktops.
static func safe_insets(scale: float) -> Dictionary:
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if not OS.has_feature("mobile"):
		return out
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size == Vector2i.ZERO or screen == Vector2i.ZERO:
		return out
	out.left = safe.position.x / scale
	out.top = safe.position.y / scale
	out.right = (screen.x - safe.end.x) / scale
	out.bottom = (screen.y - safe.end.y) / scale
	for k in out:
		out[k] = maxf(0.0, float(out[k]))
	return out


# ------------------------------------------------------------------- paths --

## A document path from the command line or the home screen, made absolute.
## Relative paths are tried against the shell's working directory (so
## `Hexmap -- examples/x.encounter` works from any folder), then the
## project, then the app's own bundled files (res://examples in a build).
static func resolve_path(arg: String) -> String:
	if arg == "" or arg.is_absolute_path() or arg.begins_with("res://") or arg.begins_with("user://"):
		return arg
	var candidates := []
	var cwd := OS.get_environment("PWD")
	if cwd != "":
		candidates.append(cwd.path_join(arg))
	candidates.append(ProjectSettings.globalize_path("res://").path_join(arg))
	candidates.append("res://".path_join(arg))
	for c in candidates:
		if FileAccess.file_exists(c) or DirAccess.dir_exists_absolute(c):
			return c
	return candidates[0]


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


## Documents that ship inside the app (a build carries the examples).
static func bundled(extension: String) -> Array:
	var out := []
	var d := DirAccess.open("res://examples")
	if d != null:
		for f in d.get_files():
			if f.ends_with(extension):
				out.append("res://examples".path_join(f))
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
