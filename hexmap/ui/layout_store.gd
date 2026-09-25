class_name LayoutStore
extends RefCounted
## The dock arrangement (a DockableLayout resource) as the user left it,
## saved per user and repaired on load so a panel added by a newer build
## always shows up somewhere. The editor's layout is the default; the Table
## passes its own panel list, file and default builder.

const PANELS := ["Palette", "Layers", "Canvas", "Inspector", "View options"]
const TABLE_PANELS := ["Scenes", "Tokens", "Canvas", "Inspector", "Turns", "Rules", "Compendium", "Players", "Session", "Characters", "NPCs", "Notes", "Maps", "Party", "Reference"]
## What each of the Table's modes shows; every other pane is in the layout,
## hidden (View → Show all panes, or Prep, brings them).
const TABLE_MODE_PANELS := {
	"world": ["Party", "Canvas", "Reference"],
	"fight": ["Turns", "Tokens", "Canvas", "Reference", "Rules", "Inspector"],
}
const TABLE_MODES := ["world", "fight", "prep"]


static func default_path() -> String:
	return "user://layout.tres"


## Where a Table mode's arrangement is kept. (Before the modes, the Table
## had one layout, in table_layout.tres: it is left behind, and Prep starts
## from its new default.)
static func table_path(mode := "prep") -> String:
	return "user://table_layout_%s.tres" % mode


## Left column: Palette over Layers. Centre: canvas. Right column: Inspector
## over View options. Every pane alone, so only title bars show; grouping
## panes into tabs is the user's choice.
static func default_layout() -> DockableLayout:
	var left := _vsplit(_leaf("Palette"), _leaf("Layers"), 0.55)
	var center := _leaf("Canvas")
	var right := _vsplit(_leaf("Inspector"), _leaf("View options"), 0.85)
	var inner := DockableLayoutSplit.new()
	inner.direction = DockableLayoutSplit.Direction.HORIZONTAL
	inner.percent = 0.76
	inner.first = center
	inner.second = right
	var outer := DockableLayoutSplit.new()
	outer.direction = DockableLayoutSplit.Direction.HORIZONTAL
	outer.percent = 0.2
	outer.first = left
	outer.second = inner
	var layout := DockableLayout.new()
	layout.root = outer
	return layout


## A Table mode's layout: world (the default) or fight; prep is table_layout.
static func table_mode_layout(mode: String) -> DockableLayout:
	match mode:
		"world": return table_world_layout()
		"fight": return table_fight_layout()
	return table_layout()


## World: the party on the left, the map in the middle, the reference on the
## right — what a session is mostly spent with (playtest 1).
static func table_world_layout() -> DockableLayout:
	var shown: Array = TABLE_MODE_PANELS.world
	var hidden := TABLE_PANELS.filter(func(n: String) -> bool: return not shown.has(n))
	var inner := DockableLayoutSplit.new()
	inner.direction = DockableLayoutSplit.Direction.HORIZONTAL
	inner.percent = 0.64
	inner.first = _leaf("Canvas")
	inner.second = _tabs(["Reference"] + hidden)
	var outer := DockableLayoutSplit.new()
	outer.direction = DockableLayoutSplit.Direction.HORIZONTAL
	outer.percent = 0.24
	outer.first = _leaf("Party")
	outer.second = inner
	var layout := DockableLayout.new()
	layout.root = outer
	hide_tabs(layout, hidden)
	return layout


## Fight: turns over tokens on the left, the map, and on the right the
## reference (the selected creature's sheet), the rules' actions and prompts,
## and the token inspector.
static func table_fight_layout() -> DockableLayout:
	var shown: Array = TABLE_MODE_PANELS.fight
	var hidden := TABLE_PANELS.filter(func(n: String) -> bool: return not shown.has(n))
	var left := _vsplit(_leaf("Turns"), _leaf("Tokens"), 0.55)
	var inner := DockableLayoutSplit.new()
	inner.direction = DockableLayoutSplit.Direction.HORIZONTAL
	inner.percent = 0.68
	inner.first = _leaf("Canvas")
	inner.second = _tabs(["Reference", "Rules", "Inspector"] + hidden)
	var outer := DockableLayoutSplit.new()
	outer.direction = DockableLayoutSplit.Direction.HORIZONTAL
	outer.percent = 0.2
	outer.first = left
	outer.second = inner
	var layout := DockableLayout.new()
	layout.root = outer
	hide_tabs(layout, hidden)
	return layout


## Prep: every pane — the campaign's maps and encounters, its people and
## notes, the characters, the compendium — for building between sessions.
static func table_layout() -> DockableLayout:
	var left := _vsplit(_leaf("Scenes"), _leaf("Tokens"), 0.35)
	var right := _vsplit(_tabs(["Maps", "NPCs", "Notes", "Characters", "Session", "Party", "Players"]), _tabs(["Reference", "Compendium", "Inspector", "Turns", "Rules"]), 0.5)
	var inner := DockableLayoutSplit.new()
	inner.direction = DockableLayoutSplit.Direction.HORIZONTAL
	inner.percent = 0.76
	inner.first = _leaf("Canvas")
	inner.second = right
	var outer := DockableLayoutSplit.new()
	outer.direction = DockableLayoutSplit.Direction.HORIZONTAL
	outer.percent = 0.18
	outer.first = left
	outer.second = inner
	var layout := DockableLayout.new()
	layout.root = outer
	return layout


static func _leaf(p_name: String) -> DockableLayoutPanel:
	var l := DockableLayoutPanel.new()
	l.names = PackedStringArray([p_name])
	return l


## Several panels as tabs in one place.
static func _tabs(p_names: Array) -> DockableLayoutPanel:
	var l := DockableLayoutPanel.new()
	l.names = PackedStringArray(p_names)
	return l


static func _vsplit(a: DockableLayoutNode, b: DockableLayoutNode, percent: float) -> DockableLayoutSplit:
	var s := DockableLayoutSplit.new()
	s.direction = DockableLayoutSplit.Direction.VERTICAL
	s.percent = percent
	s.first = a
	s.second = b
	return s


static func save(layout: DockableLayout, path: String = "") -> Error:
	return ResourceSaver.save(layout.clone(), path if path != "" else default_path())


## Load the saved layout, or the default when there is none or it is
## unusable. Panels the saved layout does not mention are appended to the
## first leaf so nothing can disappear.
static func load_or_default(path: String = "", panels: Array = PANELS, fallback: Callable = default_layout, hide_new := false) -> DockableLayout:
	var p := path if path != "" else default_path()
	var layout: DockableLayout = null
	if ResourceLoader.exists(p):
		var res = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is DockableLayout:
			layout = res
	if layout == null:
		return fallback.call()
	return repair(layout, panels, fallback, hide_new)


## A Table mode's layout as the user left it, or the mode's default. A pane a
## newer build adds shows in Prep and stays hidden in World and Fight.
static func load_table_mode(mode: String) -> DockableLayout:
	return load_or_default(table_path(mode), TABLE_PANELS, func() -> DockableLayout: return table_mode_layout(mode), mode != "prep")


## Make sure every panel name appears exactly once (with `hide_new`, the
## ones added are hidden).
static func repair(layout: DockableLayout, panels: Array = PANELS, fallback: Callable = default_layout, hide_new := false) -> DockableLayout:
	var names := layout.get_names()
	if names.is_empty():
		return fallback.call()
	var seen := {}
	for n in names:
		seen[n] = true
	var missing := PackedStringArray()
	for n in panels:
		if not seen.has(n):
			missing.append(n)
	if not missing.is_empty():
		# update_nodes() drops unknown names and appends missing ones.
		var all := PackedStringArray(names)
		for n in missing:
			all.append(n)
		layout.update_nodes(all)
		if hide_new:
			hide_tabs(layout, Array(missing))
	return layout


## Mark tabs hidden. (The layout's own set_tab_hidden does nothing until a
## container has laid the layout out, so a fresh one is marked directly.)
static func hide_tabs(layout: DockableLayout, tabs: Array) -> void:
	var h: Dictionary = layout.hidden_tabs.duplicate()
	for n in tabs:
		h[str(n)] = true
	layout.hidden_tabs = h


## Names in the layout, for tests and the reset check.
static func names(layout: DockableLayout) -> PackedStringArray:
	return layout.get_names()
