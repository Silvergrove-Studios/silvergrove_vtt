class_name TokensPanel
extends VBoxContainer
## Every token on the scene: name, owner, an eye to hide it from the players.
## Selection syncs with the canvas both ways.

var ctx: TableContext
var tree: Tree
var _items: Dictionary = {}   # id -> TreeItem
var _syncing := false
var _actions: Array = []
var _eye: Texture2D
var _eye_off: Texture2D

const COL_NAME := 0
const COL_OWNER := 1
const COL_VIS := 2


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.columns = 3
	tree.set_column_expand(COL_NAME, true)
	tree.set_column_expand(COL_OWNER, false)
	tree.set_column_expand(COL_VIS, false)
	tree.set_column_custom_minimum_width(COL_OWNER, 70)
	tree.set_column_custom_minimum_width(COL_VIS, 28)
	tree.select_mode = Tree.SELECT_MULTI
	tree.multi_selected.connect(func(_i: TreeItem, _c: int, _s: bool) -> void: _push_selection.call_deferred())
	tree.button_clicked.connect(_on_button)
	tree.item_activated.connect(_focus)
	add_child(tree)
	var hint := Label.new()
	hint.text = "Click to select; double-click to find it on the map. H hides or reveals."
	hint.theme_type_variation = "DimLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var remove := Button.new()
	remove.set_meta("icon", "trash")
	remove.tooltip_text = "Remove the selected tokens"
	remove.theme_type_variation = "ToolButton"
	remove.pressed.connect(func() -> void:
		var ids := ctx.selected_token_ids()
		if not ids.is_empty():
			ctx.commands.remove_tokens(ctx.scene_id, ids))
	_actions = [remove]
	ctx.selection_changed.connect(_pull_selection)
	ctx.scene_changed.connect(refresh)
	ctx.encounter_changed.connect(refresh)


func header_actions() -> Array:
	return _actions


func bind() -> void:
	ctx.encounter().changed.connect(func(what: String, s: String) -> void:
		if what == "tokens" and s == ctx.scene_id:
			refresh())
	refresh()


func restyle(t: Dictionary) -> void:
	var text := ThemeBuilder.c(t, "text")
	_eye = UiIcons.get_icon("eye", 16, text, t.stroke)
	_eye_off = UiIcons.get_icon("eye-off", 16, ThemeBuilder.c(t, "text_dim"), t.stroke)
	refresh()


func refresh() -> void:
	_syncing = true
	tree.clear()
	_items.clear()
	var root := tree.create_item()
	if ctx.state != null:
		for tk in ctx.state.tokens(ctx.scene_id):
			var it := tree.create_item(root)
			it.set_text(COL_NAME, "%s  %s" % [str(tk.get("label", "")), str(tk.get("name", ""))])
			it.set_metadata(COL_NAME, str(tk.id))
			var owner := ""
			if tk.get("owner", null) != null:
				owner = str(ctx.encounter().player(str(tk.owner)).get("name", "?"))
			it.set_text(COL_OWNER, owner)
			it.set_custom_color(COL_OWNER, Color(str(tk.get("color", "#ffffff"))))
			var hidden := bool(tk.get("hidden", false))
			if _eye != null:
				it.add_button(COL_VIS, _eye_off if hidden else _eye, 0, false, "Hidden from players" if hidden else "Players can see it")
			if hidden:
				it.set_custom_color(COL_NAME, Color(0.6, 0.6, 0.6))
			_items[str(tk.id)] = it
			if ctx.is_token_selected(str(tk.id)):
				it.select(COL_NAME)
	_syncing = false


func _on_button(item: TreeItem, col: int, _id: int, _mb: int) -> void:
	if col != COL_VIS:
		return
	var id := str(item.get_metadata(COL_NAME))
	var tk := ctx.state.token(ctx.scene_id, id)
	ctx.commands.update_token(ctx.scene_id, id, {"hidden": not bool(tk.get("hidden", false))}, "Reveal" if bool(tk.get("hidden", false)) else "Hide")


func _push_selection() -> void:
	if _syncing:
		return
	var sel := []
	var it := tree.get_next_selected(null)
	while it != null:
		sel.append({"kind": "token", "id": str(it.get_metadata(COL_NAME))})
		it = tree.get_next_selected(it)
	_syncing = true
	ctx.set_selection(sel)
	_syncing = false


func _pull_selection() -> void:
	if _syncing:
		return
	_syncing = true
	tree.deselect_all()
	for id in ctx.selected_token_ids():
		if _items.has(id):
			(_items[id] as TreeItem).select(COL_NAME)
	_syncing = false


func _focus() -> void:
	var it := tree.get_selected()
	if it == null:
		return
	var id := str(it.get_metadata(COL_NAME))
	ctx.select_token(id)
	ctx.say("Selected %s" % str(ctx.state.token(ctx.scene_id, id).get("name", "")))
