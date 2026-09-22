class_name TableContext
extends RefCounted
## What every table tool and panel needs to see: the app, the running
## encounter (state + undoable commands), which scene is on the canvas, the
## canvas itself, what is selected, and what the token tool will place.
## Owned by TableWindow.

signal selection_changed
signal scene_changed
signal encounter_changed
## The campaign opened, saved, or a session started or ended.
signal campaign_changed
signal status(text: String)
## A pick on the map began or ended (`pick` is set or empty).
signal pick_changed

var app: App
var state: EncounterState
var history := EventLog.new()
var commands: EncounterCommands
## The rules engine over the state and the plugins loaded into it. Made
## fresh with every encounter; plugins come from `plugin_dirs`.
var kernel: RulesKernel
var host: PluginHost
var plugin_dirs: Array = ["user://plugins"]
## Set by the window: Callable(collection, id) opens the lookup popup on an entry.
var lookup: Callable = Callable()
## What loading plugins reported (for the status bar / log).
var plugin_log: PackedStringArray = []
## The campaign this session belongs to, when the encounter names one
## (loaded from beside it) or the DM opened one. Its plugin order and
## settings shape the plugins; sessions start from and bank into it.
var campaign: Campaign
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
## The pick in flight: {kind: token | cell | area, area: {shape, …},
## from: token id | "", label, on_done: Callable(target)}; empty when none.
var pick: Dictionary = {}


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
	# the campaign the file names, unless one is already open here
	if campaign == null or (str(e.campaign.get("id", "")) != "" and campaign.id != str(e.campaign.get("id", ""))):
		var err := []
		var found := Campaign.for_encounter(e, err)
		if found != null:
			campaign = found
		elif str(e.campaign.get("path", "")) != "":
			status.emit("campaign: " + "; ".join(PackedStringArray(err)))
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
	# the campaign's order and settings, when there is one
	var order := []
	if campaign != null:
		order = campaign.plugin_order()
		for pid in order:
			host.settings_overrides[pid] = campaign.plugin_settings(pid)
	for r in host.load_all(plugin_dirs, order):
		plugin_log.append("%s: %s" % [str(r.id), "loaded" if r.why == "" else r.why])
	# the table's own content, layered over what the plugins ship
	for line in kernel.comp.load_user_packs():
		plugin_log.append("pack " + line)
	kernel.pending.close_orphans()


## Drop every loaded plugin and load what is under plugin_dirs now (a
## ruleset just installed); the sheets derive again.
func reload_plugins() -> void:
	if host != null:
		for id in host.plugins.keys():
			host.unload(str(id))
	_load_plugins()
	kernel.rederive_all()
	kernel.pending.close_orphans()
	encounter_changed.emit()


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


## A file path as the live document should store it: relative to the
## campaign (or encounter) file when it has one, else as given.
func relative_path(p: String) -> String:
	var base := state.encounter.base_dir() if state != null else ""
	if base == "":
		return p
	if p.begins_with(base + "/"):
		return p.substr(base.length() + 1)
	return p


## The path the encounter's campaign reference should carry: relative to
## the encounter file when both are saved, else absolute.
func campaign_ref_path() -> String:
	if campaign == null or campaign.path == "":
		return ""
	var base := state.encounter.base_dir()
	if base != "" and campaign.path.begins_with(base + "/"):
		return campaign.path.substr(base.length() + 1)
	return campaign.path


# ---------------------------------------------------------------- campaign --

## Open a campaign as the live document: its runtime encounter (restored
## from the file, or built from it) becomes the encounter the kernel runs
## on. "" or why not.
func open_campaign(c: Campaign) -> String:
	campaign = c
	var e := c.runtime_encounter()
	set_encounter(e)
	var warn := state.resolve_maps()
	campaign_changed.emit()
	if not warn.is_empty():
		return "\n".join(warn)
	return ""


## Whether the live encounter is the open campaign's own runtime (as
## against an encounter file that merely names a campaign).
func campaign_is_live() -> bool:
	return campaign != null and state != null and str(state.encounter.campaign.get("id", "")) == campaign.id and state.encounter.path == campaign.path


## Capture the live state into the campaign and save it. "" or why.
func save_campaign(p_path := "") -> String:
	if campaign == null:
		return "no campaign is open"
	if p_path != "":
		campaign.path = p_path
		state.encounter.path = p_path
	if campaign.path == "":
		return "the campaign has no file yet"
	campaign.capture(state.encounter)
	var err := campaign.save()
	if err != OK:
		return "could not save the campaign (%s)" % error_string(err)
	state.encounter.dirty = false
	campaign_changed.emit()
	return ""


## Whether anything is unsaved: the live encounter or the campaign.
func campaign_dirty() -> bool:
	return (state != null and state.encounter.dirty) or (campaign != null and campaign.dirty)


## End the session on the live campaign: journal, recap, capture, save.
## The summary, or {error}.
func end_session(recap := "") -> Dictionary:
	if campaign == null:
		return {"error": "no campaign is open"}
	if not campaign_is_live():
		return bank_session()
	var summary := campaign.end_session(state.encounter, recap)
	var why := save_campaign()
	if why != "":
		summary.error = why
	campaign_changed.emit()
	return summary


## Start a session of the open campaign in this encounter. "" or why.
func start_session() -> String:
	if campaign == null:
		return "no campaign is open"
	var why := kernel.start_session(campaign, campaign_ref_path())
	if why == "":
		# the campaign's plugin order and settings may differ from what loaded
		encounter_changed.emit()
		campaign_changed.emit()
	return why


## Bank this session into the open campaign and save the campaign.
## The summary, or {error}.
func bank_session() -> Dictionary:
	if campaign == null:
		return {"error": "no campaign is open"}
	var rel := state.encounter.path
	if campaign.path != "" and rel.begins_with(campaign.path.get_base_dir() + "/"):
		rel = rel.substr(campaign.path.get_base_dir().length() + 1)
	var summary := campaign.bank(state.encounter, rel)
	if campaign.path != "":
		var err := campaign.save()
		if err != OK:
			summary.error = "could not save the campaign (%s)" % error_string(err)
	return summary


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


# ---------------------------------------------------------------- picks --

## Ask for a target on the map: the next press resolves it (see
## `resolve_pick`) and `on_done` receives the target — `"token:<id>"`, a
## `"q,r"` cell, or an area spec ready for `hm.map.template`. `spec`:
## {kind, area: {shape, radius | length, angle, width}, from: token id,
## label}.
func begin_pick(spec: Dictionary, on_done: Callable) -> void:
	pick = spec.duplicate(true)
	pick.on_done = on_done
	pick_changed.emit()
	say("%s: tap a %s on the map (Esc to cancel)" % [str(spec.get("label", "Pick")), str(spec.get("kind", "target"))])


func cancel_pick() -> void:
	if pick.is_empty():
		return
	pick = {}
	pick_changed.emit()
	say("Pick cancelled")


## The target a point on the map means for the pick in flight, or null
## when the point picks nothing (a token pick on empty ground).
func pick_target_at(p: Vector2) -> Variant:
	return MapQuery.pick_target(state, scene_id, pick, p, true)


## Resolve the pick with a press at `p`. False when nothing was picked.
func resolve_pick(p: Vector2) -> bool:
	if pick.is_empty():
		return false
	var target: Variant = pick_target_at(p)
	if target == null:
		say("Nothing to pick there")
		return false
	var done: Callable = pick.on_done
	pick = {}
	pick_changed.emit()
	if done.is_valid():
		done.call(target)
	return true
