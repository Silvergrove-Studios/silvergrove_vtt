class_name TableContext
extends RefCounted
## What every table tool and panel needs to see: the app, the running
## encounter (state + undoable commands), which scene is on the canvas, the
## canvas itself, what is selected, and what the token tool will place.
## Owned by TableWindow.

signal selection_changed
signal scene_changed
signal encounter_changed
signal status(text: String)

var app: App
var state: EncounterState
var history := EventLog.new()
var commands: EncounterCommands
## The rules engine over the state and the plugins loaded into it. Made
## fresh with every encounter; plugins come from `plugin_dirs`.
var kernel: RulesKernel
var host: PluginHost
var plugin_dirs: Array = ["user://plugins"]
## What loading plugins reported (for the status bar / log).
var plugin_log: PackedStringArray = []
var canvas: MapCanvas
## View zoom (screen px per canvas px), kept current by TableView.
var zoom := 1.0
## The scene on the canvas (the DM may look at one the players don't see).
var scene_id := ""

## [{kind: "token", id} | {kind: "element", collection, id}]
var selection: Array = []

## Token tool picks.
var token_name := "Goblin"
var token_color := "#8a9a3a"
var token_size := 1
var token_hidden := true
var token_owner := ""
var token_vision := 6.0
var token_art := ""
var snap_tokens := true
## Fog brush radius in cells.
var fog_brush := 1


func set_encounter(e: Encounter) -> void:
	if state != null and state.encounter.changed.is_connected(_on_changed):
		state.encounter.changed.disconnect(_on_changed)
	state = EncounterState.new(e)
	state.encounter.changed.connect(_on_changed)
	history.clear()
	history.state = state
	kernel = RulesKernel.new(state, history)
	commands = EncounterCommands.new(state, history)
	commands.kernel = kernel
	_load_plugins()
	selection = []
	scene_id = e.active_scene_id
	if scene_id == "" and not e.scenes.is_empty():
		scene_id = str(e.scenes[0].id)
	encounter_changed.emit()


## Load every plugin found under plugin_dirs into a fresh host. Failures
## are logged, never fatal: the Table works with no rules at all.
func _load_plugins() -> void:
	host = null
	plugin_log = PackedStringArray()
	if not PluginHost.available():
		return
	host = PluginHost.new(kernel)
	host.plugin_failed.connect(func(id: String, where: String, msg: String) -> void:
		plugin_log.append("%s: %s: %s" % [id, where, msg])
		status.emit("%s: %s: %s" % [id, where, msg]))
	for m in PluginHost.discover(plugin_dirs):
		var why := host.load_dir(str(m.__dir))
		plugin_log.append("%s: %s" % [str(m.get("id", "?")), "loaded" if why == "" else why])
	# the table's own content, layered over what the plugins ship
	for line in kernel.comp.load_user_packs():
		plugin_log.append("pack " + line)
	kernel.pending.close_orphans()


func _on_changed(what: String, p_scene: String) -> void:
	if what == "scenes" and state.encounter.scene(scene_id).is_empty():
		scene_id = state.encounter.active_scene_id
		if scene_id == "" and not state.encounter.scenes.is_empty():
			scene_id = str(state.encounter.scenes[0].id)
		scene_changed.emit()
	if what == "tokens" and p_scene == scene_id:
		# Drop selections of tokens that are gone.
		var keep := []
		for s in selection:
			if s.kind != "token" or not state.token(scene_id, s.id).is_empty():
				keep.append(s)
		if keep.size() != selection.size():
			selection = keep
			selection_changed.emit()


func encounter() -> Encounter:
	return state.encounter


func scene() -> Dictionary:
	return state.encounter.scene(scene_id)


func map() -> HexMap:
	return state.map_for(scene_id)


func level() -> Dictionary:
	return state.effective_level(scene_id)


func set_scene(id: String) -> void:
	if id == scene_id:
		return
	scene_id = id
	selection = []
	selection_changed.emit()
	scene_changed.emit()


# ---------------------------------------------------------------- selection --

func set_selection(items: Array) -> void:
	selection = items
	selection_changed.emit()


func select_token(id: String) -> void:
	set_selection([{"kind": "token", "id": id}])


func select_element(collection: String, id: String) -> void:
	set_selection([{"kind": "element", "collection": collection, "id": id}])


func clear_selection() -> void:
	if not selection.is_empty():
		set_selection([])


func is_token_selected(id: String) -> bool:
	for s in selection:
		if s.kind == "token" and s.id == id:
			return true
	return false


func selected_token_ids() -> Array:
	var out := []
	for s in selection:
		if s.kind == "token":
			out.append(s.id)
	return out


## The one selected token, or {}.
func selected_token() -> Dictionary:
	var ids := selected_token_ids()
	if ids.size() != 1 or selection.size() != 1:
		return {}
	return state.token(scene_id, ids[0])


## The one selected map element (effective), or {}.
func selected_element() -> Dictionary:
	if selection.size() != 1 or selection[0].kind != "element":
		return {}
	var s: Dictionary = selection[0]
	var lvl := state.level_for(scene_id)
	var o := HexMap.find_in(lvl, s.collection, s.id)
	return state.effective(scene_id, s.collection, o) if not o.is_empty() else {}


func say(text: String) -> void:
	status.emit(text)


## A token from the tool picks, named uniquely within the scene.
func new_token(pos: Vector2) -> Dictionary:
	var base := token_name.strip_edges()
	if base == "":
		base = "Token"
	var n := 0
	for t in state.tokens(scene_id):
		if str(t.get("name", "")).begins_with(base):
			n += 1
	var p_name := base if n == 0 else "%s %d" % [base, n + 1]
	var label := base.left(1).to_upper() + (str(n + 1) if n > 0 else base.substr(1, 1).to_upper())
	var extra := {"label": label, "color": token_color, "size": token_size, "hidden": token_hidden, "vision": {"radius": token_vision}}
	if token_owner != "":
		extra["owner"] = token_owner
	if token_art != "":
		extra["art"] = token_art
	return Encounter.new_token(p_name, pos, extra)


func snapped(p: Vector2) -> Vector2:
	if not snap_tokens or map() == null:
		return p
	return map().grid.snap_to_center(p)
