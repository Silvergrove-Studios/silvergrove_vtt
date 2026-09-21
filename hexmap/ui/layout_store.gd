class_name LayoutStore
extends RefCounted
## The dock arrangement (a DockableLayout resource) as the user left it,
## saved per user and repaired on load so a panel added by a newer build
## always shows up somewhere. The editor's layout is the default; the Table
## passes its own panel list, file and default builder.

const PANELS := ["Palette", "Layers", "Canvas", "Inspector", "View options"]
const TABLE_PANELS := ["Scenes", "Tokens", "Canvas", "Inspector", "Turns", "Rules", "Compendium", "Players", "Campaign"]


static func default_path() -> String:
	return "user://layout.tres"


static func table_path() -> String:
	return "user://table_layout.tres"


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


## The Table: Scenes over Tokens on the left, canvas in the middle,
## Inspector over Turns over Players on the right.
static func table_layout() -> DockableLayout:
	var left := _vsplit(_leaf("Scenes"), _leaf("Tokens"), 0.35)
	var right := _vsplit(_leaf("Inspector"), _vsplit(_tabs(["Turns", "Rules", "Compendium", "Campaign"]), _leaf("Players"), 0.65), 0.45)
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
static func load_or_default(path: String = "", panels: Array = PANELS, fallback: Callable = default_layout) -> DockableLayout:
	var p := path if path != "" else default_path()
	var layout: DockableLayout = null
	if ResourceLoader.exists(p):
		var res = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is DockableLayout:
			layout = res
	if layout == null:
		return fallback.call()
	return repair(layout, panels, fallback)


## Make sure every panel name appears exactly once.
static func repair(layout: DockableLayout, panels: Array = PANELS, fallback: Callable = default_layout) -> DockableLayout:
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
	return layout


## Names in the layout, for tests and the reset check.
static func names(layout: DockableLayout) -> PackedStringArray:
	return layout.get_names()
