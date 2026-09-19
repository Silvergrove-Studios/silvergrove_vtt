class_name LayersPanel
extends VBoxContainer
## Photoshop-style layers: every element on the level as a row, folders to
## group them, eye and lock toggles, drag-and-drop to reorder or regroup.
## Top of the list is drawn on top. Moving rows never moves anything on the
## canvas — only order and grouping change.

signal focus_requested(collection: String, id: String)

var ctx: EditorContext
var tree: LayerTreeControl
var _syncing := false
var _items: Dictionary = {}    # key -> TreeItem

const COL_NAME := 0
const COL_VIS := 1
const COL_LOCK := 2


class LayerTreeControl extends Tree:
	var panel: LayersPanel

	func _get_drag_data(_at: Vector2) -> Variant:
		var keys := panel._selected_keys()
		if keys.is_empty():
			return null
		var label := Label.new()
		label.text = "%d item%s" % [keys.size(), "" if keys.size() == 1 else "s"] if keys.size() > 1 else str(panel._items_name(keys[0]))
		set_drag_preview(label)
		return {"layer_keys": keys}

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary) or not data.has("layer_keys"):
			return false
		var item := get_item_at_position(at)
		if item == null:
			return true
		var key := str(item.get_metadata(0))
		for k in data.layer_keys:
			if k == key:
				return false
			# not into your own descendants
			var node := LayerTree.find(panel.ctx.level().tree, k)
			if LayerTree.is_folder(node) and not LayerTree.find(node.children, key).is_empty():
				return false
		return true

	func _drop_data(at: Vector2, data: Variant) -> void:
		panel._drop(at, data.layer_keys)


func _init(p_ctx: EditorContext) -> void:
	ctx = p_ctx
	custom_minimum_size = Vector2(290, 220)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Layers"
	title.theme_type_variation = "HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("group", "Group the selection into a new folder (Ctrl/Cmd+G)", _group_selection))
	head.add_child(_button("folder-plus", "New empty folder", func() -> void: _new_folder()))
	head.add_child(_button("trash", "Delete selected elements; folders are unwrapped", _delete_selected))
	add_child(head)
	tree = LayerTreeControl.new()
	tree.panel = self
	tree.columns = 3
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.allow_rmb_select = true
	tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM
	tree.set_column_expand(COL_NAME, true)
	tree.set_column_expand(COL_VIS, false)
	tree.set_column_expand(COL_LOCK, false)
	tree.set_column_custom_minimum_width(COL_VIS, 30)
	tree.set_column_custom_minimum_width(COL_LOCK, 30)
	tree.column_titles_visible = false
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_edited.connect(_on_item_edited)
	tree.button_clicked.connect(_on_button)
	tree.multi_selected.connect(_on_multi_selected)
	tree.item_collapsed.connect(_on_collapsed)
	tree.item_activated.connect(_on_activated)
	tree.nothing_selected.connect(func() -> void:
		if not _syncing:
			ctx.target_folder = ""
			ctx.clear_selection())
	add_child(tree)
	var hint := Label.new()
	hint.text = "Drag to reorder or into folders; top draws on top. Double-click renames or jumps to."
	hint.theme_type_variation = "DimLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	ctx.selection_changed.connect(_sync_selection)
	ctx.level_changed.connect(request_rebuild)


func _button(icon: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.set_meta("icon", icon)
	b.tooltip_text = tip
	b.theme_type_variation = "ToolButton"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	return b


var _tokens: Dictionary = ThemeBuilder.tokens("slate")
var _icons: Dictionary = {}

## Re-rasterise icons for the current theme's colours.
func restyle(t: Dictionary) -> void:
	_tokens = t
	var text := ThemeBuilder.c(t, "text")
	var dim := ThemeBuilder.c(t, "text_dim")
	var faint := Color(ThemeBuilder.c(t, "text_disabled"), 0.8)
	var size: int = t.icon - 2
	_icons = {
		"eye": UiIcons.get_icon("eye", size, dim, t.stroke), "eye-off": UiIcons.get_icon("eye-off", size, faint, t.stroke),
		"lock-open": UiIcons.get_icon("lock-open", size, faint, t.stroke), "lock": UiIcons.get_icon("lock", size, ThemeBuilder.c(t, "accent"), t.stroke),
		"folder": UiIcons.get_icon("folder", size, ThemeBuilder.c(t, "accent"), t.stroke),
		"wall": UiIcons.get_icon("brick-wall", size, text, t.stroke), "light": UiIcons.get_icon("lamp", size, text, t.stroke),
		"note": UiIcons.get_icon("sticky-note", size, text, t.stroke), "door": UiIcons.get_icon("door-open", size, text, t.stroke),
	}
	_folder_tex = null
	for b in find_children("*", "Button", true, false):
		if b.has_meta("icon"):
			(b as Button).icon = UiIcons.get_icon(str(b.get_meta("icon")), t.icon, text, t.stroke)
	request_rebuild()


var _rebuild_pending := false

func bind_map() -> void:
	ctx.map.changed.connect(func(what: String) -> void:
		if what in ["tree", "props", "walls", "lights", "notes", "levels"]:
			request_rebuild())
	rebuild()


## Rebuilding a Tree from inside one of its own signals (a checkbox toggle,
## a rename) is not allowed, and one edit often fires several changes, so
## rebuilds are coalesced and run after the current frame's input.
func request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	rebuild.call_deferred()


# --------------------------------------------------------------------- build --

func rebuild() -> void:
	_rebuild_pending = false
	if ctx.map == null:
		return
	_syncing = true
	tree.clear()
	_items.clear()
	var lvl := ctx.level()
	LayerTree.ensure(lvl)
	var root := tree.create_item()
	_build_children(root, lvl.tree)
	_syncing = false
	_sync_selection()


func _build_children(parent: TreeItem, children: Array) -> void:
	# Reversed: the last node draws on top and is listed first.
	for i in range(children.size() - 1, -1, -1):
		var n: Dictionary = children[i]
		var item := tree.create_item(parent)
		if LayerTree.is_folder(n):
			item.set_metadata(0, n.id)
			item.set_text(COL_NAME, str(n.name))
			item.set_icon(COL_NAME, _folder_icon())
			item.set_icon_max_width(COL_NAME, 18)
			item.set_editable(COL_NAME, true)
			item.collapsed = not bool(n.get("open", true))
			_build_children(item, n.children)
		else:
			var r := str(n.ref)
			item.set_metadata(0, r)
			item.set_text(COL_NAME, _items_name(r))
			item.set_icon(COL_NAME, _element_icon(r))
			item.set_icon_max_width(COL_NAME, 18)
			item.set_editable(COL_NAME, true)
		var vis := bool(n.get("visible", true))
		var locked := bool(n.get("locked", false))
		if not _icons.is_empty():
			item.add_button(COL_VIS, _icons["eye" if vis else "eye-off"], 0, false, "Hide / show")
			item.add_button(COL_LOCK, _icons["lock" if locked else "lock-open"], 1, false, "Lock / unlock")
		else:
			for col in [COL_VIS, COL_LOCK]:
				item.set_cell_mode(col, TreeItem.CELL_MODE_CHECK)
				item.set_editable(col, true)
			item.set_checked(COL_VIS, vis)
			item.set_checked(COL_LOCK, locked)
		if not vis:
			item.set_custom_color(COL_NAME, ThemeBuilder.c(_tokens, "text_disabled"))
		_items[str(item.get_metadata(0))] = item


func _items_name(key: String) -> String:
	var lvl := ctx.level()
	var node := LayerTree.find(lvl.tree, key)
	if LayerTree.is_folder(node):
		return str(node.name)
	var parts := LayerTree.split(key)
	if parts.size() != 2:
		return key
	var o := HexMap.find_in(lvl, parts[0], parts[1])
	if o.has("name") and str(o.name) != "":
		return str(o.name)
	match parts[0]:
		"props":
			var def := ctx.packs.prop(str(o.get("asset", "")))
			return str(def.get("name", o.get("asset", "Prop")))
		"walls":
			var door := str(o.get("door", "none"))
			if door != "none":
				return "Secret door" if door == "secret" else "Door"
			var b: Dictionary = o.get("blocks", {})
			if str(o.get("sight_mode", "normal")) == "limited":
				return "Terrain wall"
			if bool(b.get("move", true)) and not bool(b.get("sight", true)):
				return "Fence" if not bool(b.get("sound", false)) else "Window"
			if not bool(b.get("move", true)):
				return "Ethereal wall" if bool(b.get("sight", true)) else "Marker"
			return "Wall (%d pts)" % (o.get("points", []) as Array).size()
		"lights":
			return "Light %s/%s" % [PdfWriter.n(float(o.get("bright", 0))), PdfWriter.n(float(o.get("dim", 0)))]
		"notes":
			return "Note: %s" % str(o.get("title", ""))
	return key


var _folder_tex: Texture2D
func _folder_icon() -> Texture2D:
	if _icons.has("folder"):
		return _icons["folder"]
	if _folder_tex == null:
		var img := Image.create(18, 14, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		img.fill_rect(Rect2i(0, 2, 18, 12), Color(0.85, 0.75, 0.45))
		img.fill_rect(Rect2i(0, 0, 8, 3), Color(0.85, 0.75, 0.45))
		_folder_tex = ImageTexture.create_from_image(img)
	return _folder_tex


func _element_icon(r: String) -> Texture2D:
	var parts := LayerTree.split(r)
	var o := HexMap.find_in(ctx.level(), parts[0], parts[1])
	match parts[0]:
		"props":
			var def := ctx.packs.prop(str(o.get("asset", "")))
			return ctx.packs.prop_texture(str(o.get("asset", "")), 18.0 / maxf(0.2, float(def.get("size", [1])[0])))
		"walls":
			if _icons.is_empty():
				return ctx.packs.placeholder(MapCanvas.wall_color(o))
			return _icons["door"] if str(o.get("door", "none")) != "none" else _icons["wall"]
		"lights": return _icons.get("light", ctx.packs.placeholder(Color(str(o.get("color", "#ffb060")))))
		"notes": return _icons.get("note", ctx.packs.placeholder(Color("#f0d060")))
	return ctx.packs.placeholder(Color.GRAY)


# ----------------------------------------------------------------- selection --

func _selected_keys() -> Array:
	var out := []
	var item := tree.get_next_selected(null)
	while item != null:
		out.append(str(item.get_metadata(0)))
		item = tree.get_next_selected(item)
	# Model order (bottom first) so multi-moves keep their relative order.
	var order := LayerTree.order(ctx.level().tree)
	out.sort_custom(func(a, b) -> bool: return _sort_key(a, order) < _sort_key(b, order))
	return out


func _sort_key(key: String, order: Dictionary) -> int:
	if order.has(key):
		return order[key]
	var node := LayerTree.find(ctx.level().tree, key)
	var refs := LayerTree.refs_under(node)
	return order.get(refs[0], 0) if not refs.is_empty() else 0


func _on_multi_selected(_item: TreeItem, _col: int, _selected: bool) -> void:
	if _syncing:
		return
	# Coalesce: Tree fires once per item; apply after this frame.
	_apply_selection.call_deferred()


func _apply_selection() -> void:
	if _syncing:
		return
	var sel := []
	var folder := ""
	for key in _selected_keys():
		var node := LayerTree.find(ctx.level().tree, key)
		if node.is_empty():
			continue
		if LayerTree.is_folder(node):
			folder = node.id
		for r in LayerTree.refs_under(node):
			var parts := LayerTree.split(r)
			sel.append({"collection": parts[0], "id": parts[1]})
	ctx.target_folder = folder
	_syncing = true
	ctx.set_selection(sel)
	_syncing = false


func _sync_selection() -> void:
	if _syncing:
		return
	_syncing = true
	tree.deselect_all()
	var first: TreeItem = null
	for s in ctx.selection:
		if s.collection == "terrain":
			continue
		var item: TreeItem = _items.get(LayerTree.ref(s.collection, s.id))
		if item != null:
			item.select(COL_NAME)
			if first == null:
				first = item
			# Make it findable: open its folders.
			var p := item.get_parent()
			while p != null and p != tree.get_root():
				p.collapsed = false
				p = p.get_parent()
	if first != null:
		tree.scroll_to_item(first, true)
	_syncing = false


# ------------------------------------------------------------------- editing --

func _on_item_edited() -> void:
	var item := tree.get_edited()
	if item == null:
		return
	var key := str(item.get_metadata(0))
	var col := tree.get_edited_column()
	match col:
		COL_VIS:
			ctx.commands.tree_set(ctx.level_index, key, {"visible": item.is_checked(COL_VIS)}, "Toggle visibility")
		COL_LOCK:
			ctx.commands.tree_set(ctx.level_index, key, {"locked": item.is_checked(COL_LOCK)}, "Toggle lock")
		COL_NAME:
			var node := LayerTree.find(ctx.level().tree, key)
			var text := item.get_text(COL_NAME).strip_edges()
			if LayerTree.is_folder(node):
				if text != "":
					ctx.commands.tree_set(ctx.level_index, key, {"name": text}, "Rename folder")
			else:
				var parts := LayerTree.split(key)
				ctx.commands.update_object(ctx.level_index, parts[0], parts[1], {"name": text if text != "" else null}, "Rename")


func _on_button(item: TreeItem, column: int, id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	var key := str(item.get_metadata(0))
	var node := LayerTree.find(ctx.level().tree, key)
	if node.is_empty():
		return
	if id == 0:
		ctx.commands.tree_set(ctx.level_index, key, {"visible": not bool(node.get("visible", true))}, "Toggle visibility")
	elif id == 1:
		ctx.commands.tree_set(ctx.level_index, key, {"locked": not bool(node.get("locked", false))}, "Toggle lock")


func _on_collapsed(item: TreeItem) -> void:
	var node := LayerTree.find(ctx.level().tree, str(item.get_metadata(0)))
	if LayerTree.is_folder(node):
		node["open"] = not item.collapsed   # UI state, not undoable


func _on_activated() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	var key := str(item.get_metadata(0))
	var parts := LayerTree.split(key)
	if parts.size() == 2:
		focus_requested.emit(parts[0], parts[1])


func _new_folder() -> void:
	var keys := _selected_keys()
	var parent := ""
	var index := -1
	if keys.size() == 1:
		var node := LayerTree.find(ctx.level().tree, keys[0])
		if LayerTree.is_folder(node):
			parent = node.id
		else:
			var anc := LayerTree.ancestors(ctx.level().tree, keys[0])
			parent = anc[-1] if not anc.is_empty() else ""
			index = LayerTree.locate(ctx.level().tree, keys[0])[1] + 1
	var f := ctx.commands.tree_add_folder(ctx.level_index, "New folder", parent, index)
	_after_rebuild(func() -> void: _edit_name(f.id))


## Run something once the pending rebuild has happened.
func _after_rebuild(fn: Callable) -> void:
	request_rebuild()
	(func() -> void:
		if _rebuild_pending:
			rebuild()
		fn.call()).call_deferred()


func _edit_name(key: String) -> void:
	var item: TreeItem = _items.get(key)
	if item != null:
		item.select(COL_NAME)
		tree.edit_selected(true)


func _group_selection() -> void:
	var keys := _selected_keys()
	if keys.is_empty():
		return
	var t: Array = ctx.level().tree
	var anc := LayerTree.ancestors(t, keys[-1])
	var parent: String = anc[-1] if not anc.is_empty() else ""
	var index: int = LayerTree.locate(t, keys[-1])[1] + 1
	ctx.history.begin_group()
	var f := ctx.commands.tree_add_folder(ctx.level_index, "Group", parent, index)
	ctx.commands.tree_move_many(ctx.level_index, keys, f.id, -1)
	ctx.history.end_group("Group layers")
	_after_rebuild(func() -> void: _edit_name(f.id))


func _delete_selected() -> void:
	var keys := _selected_keys()
	if keys.is_empty():
		return
	var t: Array = ctx.level().tree
	var elements := []
	var folders := []
	for k in keys:
		var node := LayerTree.find(t, k)
		if LayerTree.is_folder(node):
			folders.append(k)
		else:
			var parts := LayerTree.split(k)
			elements.append({"collection": parts[0], "id": parts[1]})
	ctx.history.begin_group()
	ctx.commands.remove_objects(ctx.level_index, elements)
	for f in folders:
		ctx.commands.tree_remove_folder(ctx.level_index, f)
	ctx.history.end_group("Delete layers")
	ctx.clear_selection()


## Drop handling: translate the Tree's drop position (reversed display) into
## a model parent + index.
func _drop(at: Vector2, keys: Array) -> void:
	var item := tree.get_item_at_position(at)
	var section := tree.get_drop_section_at_position(at)
	var t: Array = ctx.level().tree
	var parent := ""
	var index := -1
	if item == null:
		parent = ""
		index = 0   # dropped below everything = bottom of the stack
	else:
		var key := str(item.get_metadata(0))
		var node := LayerTree.find(t, key)
		if section == 0 and LayerTree.is_folder(node):
			parent = node.id
			index = -1
		else:
			var anc := LayerTree.ancestors(t, key)
			parent = anc[-1] if not anc.is_empty() else ""
			var loc := LayerTree.locate(t, key)
			# Display is reversed: "above" in the list is "after" in the model.
			index = loc[1] + 1 if section <= 0 else loc[1]
	# Items already in this parent before the target index shift it; do the
	# moves one at a time from the top (model order preserved by tree_move_many).
	ctx.commands.tree_move_many(ctx.level_index, keys, parent, index)
