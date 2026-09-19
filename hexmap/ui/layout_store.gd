class_name LayoutStore
extends RefCounted
## The dock arrangement (a DockableLayout resource) as the user left it,
## saved per user and repaired on load so a panel added by a newer build
## always shows up somewhere.

const PANELS := ["Palette", "Layers", "Canvas", "Inspector", "View options"]


static func default_path() -> String:
	return "user://layout.tres"


## Palette + Layers tabbed on the left, canvas centre, Inspector + View
## options on the right.
static func default_layout() -> DockableLayout:
	var left := DockableLayoutPanel.new()
	left.names = PackedStringArray(["Palette", "Layers"])
	var center := DockableLayoutPanel.new()
	center.names = PackedStringArray(["Canvas"])
	var right := DockableLayoutPanel.new()
	right.names = PackedStringArray(["Inspector", "View options"])
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


static func save(layout: DockableLayout, path: String = "") -> Error:
	return ResourceSaver.save(layout.clone(), path if path != "" else default_path())


## Load the saved layout, or the default when there is none or it is
## unusable. Panels the saved layout does not mention are appended to the
## first leaf so nothing can disappear.
static func load_or_default(path: String = "") -> DockableLayout:
	var p := path if path != "" else default_path()
	var layout: DockableLayout = null
	if ResourceLoader.exists(p):
		var res = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is DockableLayout:
			layout = res
	if layout == null:
		return default_layout()
	return repair(layout)


## Make sure every panel name appears exactly once.
static func repair(layout: DockableLayout) -> DockableLayout:
	var names := layout.get_names()
	if names.is_empty():
		return default_layout()
	var seen := {}
	for n in names:
		seen[n] = true
	var missing := PackedStringArray()
	for n in PANELS:
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
