class_name App
extends RefCounted
## What every mode of the application shares: preferences, the pack library
## and the theme choice. Created once by the shell (hexmap/shell/main.gd) and
## handed to whichever window is open. Holds no UI, so tools and tests can
## make one without a window.

signal theme_changed(name: String)
signal ui_scale_changed(scale: float)

const NAME := "Hexmap"
const PREFS_PATH := "user://prefs.json"
const RECENT_MAX := 10

## Modes, in the order the home screen lists them.
const MODES := ["editor", "table", "player"]

var prefs := {"pack_dirs": [], "theme": "slate", "recent": [], "ui_scale": 1.0, "tables": []}
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


## What a CI build wrote about itself (res://build_info.json: commit, when,
## run number), or {} for a run from the project.
static func build_info() -> Dictionary:
	if not FileAccess.file_exists("res://build_info.json"):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
	return d if d is Dictionary else {}


## "1.1.0 · dev.42 · a1b2c3d · 2026-09-20 19:12 UTC", or "1.1.0 · local":
## enough to tell which build is on the screen.
static func build_stamp() -> String:
	var b := build_info()
	if b.is_empty():
		return "%s · local" % version()
	var parts := [version()]
	if b.has("run"):
		parts.append("dev.%d" % int(b.run))
	if b.has("commit"):
		parts.append(str(b.commit).left(7))
	if b.has("built"):
		parts.append(str(b.built))
	return " · ".join(PackedStringArray(parts))


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
		"table": return "Run a campaign: the party's sheets, NPCs, notes, maps; sessions and fights on your maps."
		"player": return "Join a table as a player and see the map from your tokens' eyes."
	return ""


# ------------------------------------------------------------------ screen --

## The user's UI size, on top of whatever the screen's density needs:
## 1.0 is the designed size, 1.3 is "a bit bigger", 2.0 is very large.
const UI_SCALES := [0.75, 0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

var ui_scale: float:
	get: return clampf(float(prefs.get("ui_scale", 1.0)), UI_SCALES[0], UI_SCALES[-1])


func set_ui_scale(scale: float, persist := true) -> void:
	prefs.ui_scale = clampf(scale, UI_SCALES[0], UI_SCALES[-1])
	if persist:
		save_prefs()
	ui_scale_changed.emit(ui_scale)


## The next step up or down from the current scale.
func step_ui_scale(up: bool) -> void:
	var cur := ui_scale
	var best: float = cur
	if up:
		for s in UI_SCALES:
			if s > cur + 0.001:
				best = s
				break
	else:
		for i in range(UI_SCALES.size() - 1, -1, -1):
			if UI_SCALES[i] < cur - 0.001:
				best = UI_SCALES[i]
				break
	set_ui_scale(best)


static func scale_label(scale: float) -> String:
	return "%d%%" % roundi(scale * 100.0)


## What the whole window is scaled by: the screen's density (phones, and
## desktops whose OS scales everything but the app) times the user's
## choice.
static func window_scale(user_scale: float) -> float:
	return base_scale() * user_scale


## The screen's own factor: density on phones; on desktops the OS scaling
## (2 on a Retina Mac, 1.5 on many Windows laptops), because Godot lays
## controls out in device pixels and would draw everything half size.
static func base_scale() -> float:
	if OS.has_feature("mobile"):
		return density_scale(DisplayServer.screen_get_dpi(), Vector2(DisplayServer.screen_get_size()))
	return clampf(DisplayServer.screen_get_scale(), 1.0, 3.0)

## How much to scale the UI on a phone or tablet: points, not pixels, but
## never so much that fewer than MIN_LOGICAL_WIDTH points fit across the
## narrower side — a column that needs 360 must still fit in portrait.
const MIN_LOGICAL_WIDTH := 360.0

static func density_scale(dpi: float, screen_px: Vector2) -> float:
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
	# Inside a build res:// is the pack and globalize_path gives nothing
	# usable, so the pack path comes before the project path.
	candidates.append("res://".path_join(arg))
	if not OS.has_feature("template"):
		candidates.append(ProjectSettings.globalize_path("res://").path_join(arg))
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


## Tables this device has joined: [{address, port, name}], newest first.
## The Player asks them directly, which reaches a table on another subnet
## when nothing else does.
func note_table(address: String, port: int, p_name: String) -> void:
	var t: Array = tables()
	t = t.filter(func(x) -> bool: return not (str(x.get("address", "")) == address and int(x.get("port", 0)) == port))
	t.push_front({"address": address, "port": port, "name": p_name})
	if t.size() > RECENT_MAX:
		t.resize(RECENT_MAX)
	prefs.tables = t
	save_prefs()


func tables() -> Array:
	return prefs.get("tables", []) if prefs.get("tables") is Array else []


## This device's own IPv4 addresses.
static func local_ipv4() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.is_valid_ip_address() and not s.contains(":") and not s.begins_with("127."):
			out.append(s)
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
	if not (prefs.get("ui_scale") is float or prefs.get("ui_scale") is int):
		prefs.ui_scale = 1.0


func save_prefs() -> void:
	var f := FileAccess.open(prefs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(prefs, "  "))
		f.close()
